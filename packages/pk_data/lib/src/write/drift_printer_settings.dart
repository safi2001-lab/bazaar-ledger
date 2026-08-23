import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';
import 'tx_runner.dart';

/// The printer a counter uses, and the record of what it has printed.
///
/// Both live in the database rather than in a file or in memory, and for the
/// same reason: a shopkeeper is entitled to ask "how many times was this bill
/// printed", and a reprint count in a scratch file next to the till is not
/// evidence. Going through [TxRunner] also means the choice is audited and
/// reaches the sync outbox like every other decision about the shop.
final class DriftPrinterSettings implements PrinterSettingsStore, PrintJobLog {
  DriftPrinterSettings(this._db, this._runner);

  final AppDatabase _db;

  /// Asked for the runner each time rather than holding one.
  ///
  /// The bootstrap rebuilds its TxRunner once first run registers this device,
  /// because the HLC clock's node id is final and a clock built before the
  /// device existed stamps every row `...-unregistered`. Anything that cached
  /// the old runner would keep writing through the placeholder for the rest of
  /// the session. A supplier cannot go stale.
  final TxRunner Function() _runner;

  /// Namespaced per device.
  ///
  /// `idx_settings_key` is UNIQUE on (firm_id, setting_key), and the counter
  /// has the USB printer while the back office has the LAN one. An
  /// unnamespaced `printer` key would let the two tills overwrite each other's
  /// choice forever once M13 starts carrying the settings table between them.
  static String _key(String deviceId) => 'printer.$deviceId';

  // -------------------------------------------------------------------------
  // PrinterSettingsStore
  // -------------------------------------------------------------------------

  @override
  Future<PrinterSettings?> forDevice(String firmId, String deviceId) async {
    final row = await _db
        .customSelect(
          'SELECT setting_value FROM settings '
          'WHERE firm_id = ? AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(firmId),
            Variable<String>(_key(deviceId)),
          ],
        )
        .getSingleOrNull();
    if (row == null) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(row.read<String>('setting_value'));
    } on FormatException {
      // A settings row somebody edited by hand, or one written by a build that
      // stored something else under this key. Reported as "no printer chosen"
      // rather than as an error: the setup screen then offers to choose one,
      // which is the action that fixes it.
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    return PrinterSettings.fromJson(decoded);
  }

  @override
  Future<void> save(ActorContext actor, PrinterSettings settings) async {
    await _runner().run(actor, (tx) async {
      final key = _key(actor.deviceId);
      final existing = await tx.select(
        'SELECT id FROM settings '
        'WHERE firm_id = ? AND setting_key = ? AND deleted_at_utc IS NULL',
        [actor.firmId, key],
      );
      final value = jsonEncode(settings.toJson());

      if (existing.isEmpty) {
        await tx.insert('settings', {
          'setting_key': key,
          'setting_value': value,
          'value_type': 'json',
        });
      } else {
        await tx.update('settings', existing.single.read<String>('id'), {
          'setting_value': value,
        });
      }

      tx.audit(
        action: 'PRINTER_CONFIGURED',
        entityTable: 'settings',
        entityId: key,
        summary:
            'Printer set to ${settings.name} '
            '(${settings.transportKind}, ${settings.columns} columns)',
      );
    });
  }

  @override
  Future<void> clear(ActorContext actor) async {
    await _runner().run(actor, (tx) async {
      final key = _key(actor.deviceId);
      final existing = await tx.select(
        'SELECT id FROM settings '
        'WHERE firm_id = ? AND setting_key = ? AND deleted_at_utc IS NULL',
        [actor.firmId, key],
      );
      if (existing.isEmpty) return;

      await tx.softDelete('settings', existing.single.read<String>('id'));
      tx.audit(
        action: 'PRINTER_FORGOTTEN',
        entityTable: 'settings',
        entityId: key,
      );
    });
  }

  // -------------------------------------------------------------------------
  // PrintJobLog
  // -------------------------------------------------------------------------

  @override
  Future<PrintJobRecord?> byKey(String firmId, String jobKey) async {
    final row = await _db
        .customSelect(
          'SELECT job_key, document_id, status, bytes_written, byte_count, '
          'copy_index, failure_reason FROM print_jobs '
          'WHERE firm_id = ? AND job_key = ? AND deleted_at_utc IS NULL',
          variables: [Variable<String>(firmId), Variable<String>(jobKey)],
        )
        .getSingleOrNull();
    return row == null ? null : _record(row);
  }

  @override
  Future<void> begin(
    ActorContext actor, {
    required String jobKey,
    required String transportKind,
    required String targetAddress,
    required int columnsUsed,
    required int copyIndex,
    required int byteCount,
    required String payloadSha256,
    String? documentId,
  }) async {
    // Its own transaction, committed before the first byte leaves. That
    // ordering IS the mechanism: a row still saying `sending` at next launch
    // is how the app knows that it does not know.
    await _runner().run(actor, (tx) async {
      await tx.insert('print_jobs', {
        'job_key': jobKey,
        'document_id': documentId,
        'transport_kind': transportKind,
        'target_address': targetAddress,
        'columns_used': columnsUsed,
        'copy_index': copyIndex,
        'byte_count': byteCount,
        'payload_sha256': payloadSha256,
        'status': 'sending',
        'bytes_written': 0,
        'started_at_utc': actor.epochMillis,
      });
    });
  }

  @override
  Future<void> finish(
    ActorContext actor, {
    required String jobKey,
    required PrintJobStatus status,
    required int bytesWritten,
    String? failureReason,
  }) async {
    if (status == PrintJobStatus.sending) {
      throw ArgumentError.value(
        status,
        'status',
        'a job cannot finish as `sending`; that value means nobody knows',
      );
    }
    await _runner().run(actor, (tx) async {
      final existing = await tx.select(
        'SELECT id FROM print_jobs '
        'WHERE firm_id = ? AND job_key = ? AND deleted_at_utc IS NULL',
        [actor.firmId, jobKey],
      );
      if (existing.isEmpty) {
        throw StateError(
          'No print job $jobKey to finish. begin() must be committed before '
          'a byte is sent, or a process kill mid-print leaves no trace and '
          'the next reprint is a second receipt.',
        );
      }
      await tx.update('print_jobs', existing.single.read<String>('id'), {
        'status': status.name,
        'bytes_written': bytesWritten,
        'failure_reason': failureReason,
        'finished_at_utc': actor.epochMillis,
      });
    });
  }

  @override
  Future<List<PrintJobRecord>> forDocument(
    String firmId,
    String documentId,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT job_key, document_id, status, bytes_written, byte_count, '
          'copy_index, failure_reason FROM print_jobs '
          'WHERE firm_id = ? AND document_id = ? AND deleted_at_utc IS NULL '
          'ORDER BY started_at_utc DESC, id DESC',
          variables: [Variable<String>(firmId), Variable<String>(documentId)],
        )
        .get();
    return [for (final row in rows) _record(row)];
  }

  PrintJobRecord _record(QueryRow row) => PrintJobRecord(
    jobKey: row.read<String>('job_key'),
    documentId: row.readNullable<String>('document_id'),
    status: PrintJobStatus.values.firstWhere(
      (s) => s.name == row.read<String>('status'),
      // Unreachable through the CHECK constraint, but a value nobody
      // recognises must never read as `printed`.
      orElse: () => PrintJobStatus.partial,
    ),
    bytesWritten: row.read<int>('bytes_written'),
    byteCount: row.read<int>('byte_count'),
    copyIndex: row.read<int>('copy_index'),
    failureReason: row.readNullable<String>('failure_reason'),
  );
}
