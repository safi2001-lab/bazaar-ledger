import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_sync/pk_sync.dart';

import '../db/app_database.dart';

/// One firm's books as a sync peer: its outbox served to other devices, and
/// theirs merged in.
///
/// The one place besides the write path that writes rows, and it does not
/// invent any: every row it writes was written first on another device,
/// through that device's TxRunner, with that device's envelope, and arrives
/// here as the outbox entry that write left. The entry is kept, under its
/// own device and sequence, so the merge is recorded like any write and a
/// third device can be handed it in turn.
///
/// The merge rule is last writer wins per row, by HLC: a change is applied
/// when it is newer than the row as this device has it, and skipped when it
/// is older, which gives the same answer on every device whatever order the
/// changes arrive in. The ledgers are append-only, so a sale, a payment or a
/// stock movement is never merged away: both counters' rows are kept, and
/// the stock balances they stamp are rebuilt from the whole ledger after.
final class DriftSyncStore implements SyncPeer {
  DriftSyncStore(
    this._db, {
    required this.firmId,
    this.mergeClock,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AppDatabase _db;
  final String firmId;

  /// Folds the newest remote timestamp into this device's clock, so what it
  /// writes next sorts after what it has just taken in. Throws when the peer
  /// is implausibly far ahead.
  final Hlc Function(Hlc remote)? mergeClock;

  final DateTime Function() _now;

  /// Columns that are true of one handset and never of the copy a peer holds.
  static const _localOnly = {
    'devices': {'is_this_device', 'change_seq', 'last_seen_at_utc'},
  };

  final Map<String, Set<String>> _columns = {};

  /// Rows whose `name_search` is worked out here, from their name (M56).
  ///
  /// The column is derived, so the copy that arrives is not trusted to be
  /// the copy this build would write. A counter still on an older build
  /// sends the old key — the plain name alone — and an item it adds would
  /// otherwise be found here by its exact spelling only. Working the key
  /// out on arrival means a merged row is found exactly as one made on this
  /// phone, whatever sent it.
  static const _respelled = {'items', 'parties'};

  static Map<String, Object?> _respell(String table, Map<String, Object?> row) {
    if (!_respelled.contains(table)) return row;
    final name = row['name'];
    var out = name is String
        ? {...row, 'name_search': nameSearchColumn(name)}
        : row;
    // M49: a medicine's salt key is derived the same way, from the salt and
    // strength the change carries — the catalogue writer always sends the
    // two together.
    if (table == 'items' && row.containsKey('generic_name')) {
      out = {
        ...out,
        'generic_search': genericSearchColumn(
          row['generic_name'] as String?,
          row['strength'] as String?,
        ),
      };
    }
    return out;
  }

  @override
  Future<VersionVector> vector() async {
    final rows = await _db
        .customSelect(
          'SELECT origin_device_id, MAX(seq) AS seq FROM change_log '
          'WHERE firm_id = ? GROUP BY origin_device_id',
          variables: [Variable<String>(firmId)],
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('origin_device_id'): r.read<int>('seq'),
    };
  }

  /// Tables whose rows stay on the phone that wrote them (M60).
  ///
  /// Pictures — an item's photograph, the shop's logo and QR, the parchis
  /// photographed onto entries — are kept inline as blobs, and this wire is
  /// JSON. Until M60 a picture's row went out as a list of numbers that no
  /// device could take in: SQLite refused a list where a blob belongs, the
  /// whole merge rolled back, and from the first picture on, that counter
  /// could not sync at all. Sending files is its own piece of work (a size
  /// budget, resuming, a shop's whole gallery on the first join), and not
  /// one to slip in here; until it is done, a picture stays on the phone it
  /// was added on and travels in that phone's backups, and everything else
  /// syncs as before. The audit row saying a picture was added still goes.
  static const _keptHere = {'attachments'};

  @override
  Future<List<SyncChange>> changesSince(VersionVector known) async {
    final held = List.filled(
      known.length,
      '(origin_device_id = ? AND seq <= ?)',
    );
    final rows = await _db
        .customSelect(
          'SELECT * FROM change_log WHERE firm_id = ? '
          "AND entity_table NOT IN ('${_keptHere.join("', '")}') "
          '${held.isEmpty ? '' : 'AND NOT (${held.join(' OR ')}) '}'
          'ORDER BY origin_device_id, seq',
          variables: [
            Variable<String>(firmId),
            for (final e in known.entries) ...[
              Variable<String>(e.key),
              Variable<int>(e.value),
            ],
          ],
        )
        .get();
    return [
      for (final r in rows)
        SyncChange({
          for (final e in r.data.entries)
            if (e.key != 'sync_state' && e.key != 'synced_at_utc')
              e.key: e.value,
        }),
    ];
  }

  @override
  Future<ApplyResult> apply(List<SyncChange> changes) async {
    if (changes.isEmpty) return ApplyResult.none;
    for (final c in changes) {
      if (c.row['firm_id'] != firmId) {
        throw const SyncRefused(
          'That device keeps the books of a different shop.',
        );
      }
    }
    // Newest last, so a row settles on the newest write whatever order the
    // changes came in.
    final ordered = [...changes]
      ..sort((a, b) {
        final byHlc = _entityHlc(a).compareTo(_entityHlc(b));
        if (byHlc != 0) return byHlc;
        final byDevice = a.originDeviceId.compareTo(b.originDeviceId);
        return byDevice != 0 ? byDevice : a.seq.compareTo(b.seq);
      });
    final newest = Hlc(_entityHlc(ordered.last));
    try {
      mergeClock?.call(newest);
    } on HlcDriftException catch (e) {
      throw SyncRefused(e.toString());
    }

    var applied = 0;
    var skipped = 0;
    var conflicts = 0;
    await _db.transaction(() async {
      var stockMoved = false;
      for (final change in ordered) {
        // A counter still on an older build sends its pictures; they are
        // left where they were made, rather than stopping every sync.
        if (_keptHere.contains(change.row['entity_table'])) {
          skipped++;
          continue;
        }
        final held = await _db
            .customSelect(
              'SELECT 1 FROM change_log WHERE origin_device_id = ? AND seq = ?',
              variables: [
                Variable<String>(change.originDeviceId),
                Variable<int>(change.seq),
              ],
            )
            .getSingleOrNull();
        if (held != null) {
          skipped++;
          continue;
        }
        final outcome = await _merge(change);
        switch (outcome) {
          case _Outcome.applied:
            applied++;
          case _Outcome.older:
            skipped++;
          case _Outcome.conflict:
            conflicts++;
        }
        if (change.row['entity_table'] == 'stock_ledger') stockMoved = true;
        await _keep(change, conflict: outcome == _Outcome.conflict);
      }
      // Each counter stamped its running balance knowing only its own rows.
      if (stockMoved) await _db.rebuildStockBalances();
    });
    return ApplyResult(
      applied: applied,
      skipped: skipped,
      conflicts: conflicts,
    );
  }

  /// Marks [deviceId] as this handset, once its own row has arrived from the
  /// master it joined.
  Future<void> adoptThisDevice(String deviceId) async {
    await _db.customStatement(
      // Local-only: the column is never carried between devices.
      'UPDATE devices SET is_this_device = 1 WHERE id = ? AND firm_id = ?',
      [deviceId, firmId],
    );
  }

  /// The changes this device took in that clashed with a row it already had.
  Future<int> conflictCount() async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS n FROM change_log '
          "WHERE firm_id = ? AND sync_state = 'conflict'",
          variables: [Variable<String>(firmId)],
        )
        .getSingle();
    return row.read<int>('n');
  }

  /// Each clash still to be looked at (M29): what clashed, by the name a
  /// shopkeeper knows it by. The row itself is already kept under a marked
  /// code or number; this is the list of what to put right.
  Future<List<({String changeId, String table, String label})>>
  clashes() async {
    final rows = await _db
        .customSelect(
          '''
          SELECT c.id, c.entity_table,
                 CASE c.entity_table
                   WHEN 'items' THEN (SELECT name || COALESCE(' · ' || barcode, '')
                                      FROM items WHERE id = c.entity_id)
                   WHEN 'parties' THEN (SELECT name FROM parties
                                        WHERE id = c.entity_id)
                   WHEN 'documents' THEN (SELECT doc_no FROM documents
                                          WHERE id = c.entity_id)
                 END AS label
          FROM change_log c
          WHERE c.firm_id = ? AND c.sync_state = 'conflict'
          ORDER BY c.created_at_utc, c.id
          ''',
          variables: [Variable<String>(firmId)],
        )
        .get();
    return [
      for (final r in rows)
        (
          changeId: r.read<String>('id'),
          table: r.read<String>('entity_table'),
          label:
              r.readNullable<String>('label') ?? r.read<String>('entity_table'),
        ),
    ];
  }

  /// Marks a clash as looked at. The change log's state is this device's
  /// own and never travels, so this is a local note, not a change.
  Future<void> resolveClash(String changeId) => _db.customStatement(
    "UPDATE change_log SET sync_state = 'acked' "
    "WHERE id = ? AND firm_id = ? AND sync_state = 'conflict'",
    [changeId, firmId],
  );

  static String _entityHlc(SyncChange c) => c.row['entity_hlc']! as String;

  Future<_Outcome> _merge(SyncChange change) async {
    final table = change.row['entity_table']! as String;
    final columns = await _columnsOf(table);
    final entityId = change.row['entity_id']! as String;
    final hlc = _entityHlc(change);
    final decoded = jsonDecode(change.row['payload_json']! as String);
    if (decoded is! Map<String, Object?>) {
      throw const SyncRefused('A change arrived that this build cannot read.');
    }
    final localOnly = _localOnly[table] ?? const <String>{};
    final payload = {
      for (final e in decoded.entries)
        if (!localOnly.contains(e.key)) e.key: e.value,
    };
    final unknown = payload.keys.where((k) => !columns.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw SyncRefused(
        'The other device has a newer build of the app ($table.${unknown.first} '
        'is new here). Update this phone and sync again.',
      );
    }

    final existing = await _db
        .customSelect(
          'SELECT hlc, rev FROM $table WHERE id = ?',
          variables: [Variable<String>(entityId)],
        )
        .getSingleOrNull();
    final op = change.row['op']! as String;

    if (existing == null) {
      if (op != 'insert') return _Outcome.conflict;
      return _insert(table, payload, change.originDeviceId);
    }
    if (hlc.compareTo(existing.read<String>('hlc')) <= 0) {
      return _Outcome.older;
    }
    final rev = change.row['entity_rev']! as int;
    final values = <String, Object?>{
      for (final e in _respell(table, payload).entries)
        if (e.key != 'id') e.key: e.value,
      'hlc': hlc,
      'rev': rev > existing.read<int>('rev') ? rev : existing.read<int>('rev'),
      if (op != 'insert') ...{
        'updated_at_utc': change.row['at_utc'],
        'updated_by': change.row['created_by'],
      },
    };
    await _db.customStatement(
      'UPDATE $table SET ${values.keys.map((k) => '$k = ?').join(', ')} '
      'WHERE id = ?',
      [...values.values, entityId],
    );
    return _Outcome.applied;
  }

  /// Inserts a row another device made. When it clashes with one this
  /// device made under the same code or number, the newcomer is kept under
  /// a marked name rather than lost, and counted as a conflict.
  Future<_Outcome> _insert(
    String table,
    Map<String, Object?> row,
    String origin,
  ) async {
    Future<void> write(Map<String, Object?> row) {
      // Keyed after any renaming below, so a name that came in marked is
      // found by the name it is kept under.
      final r = _respell(table, row);
      return _db.customStatement(
        'INSERT INTO $table (${r.keys.join(', ')}) '
        'VALUES (${List.filled(r.length, '?').join(', ')})',
        [...r.values],
      );
    }

    try {
      await write(row);
      return _Outcome.applied;
    } on Object catch (e) {
      final clash = RegExp(
        r'UNIQUE constraint failed: ([\w., ]+)',
      ).firstMatch('$e');
      if (clash == null) rethrow;
      final mark = '~${origin.substring(origin.length - 4)}';
      final renamed = {...row};
      var marked = false;
      for (final column in clash.group(1)!.split(',')) {
        final name = column.trim().split('.').last;
        final value = renamed[name];
        if (value is String && name != 'firm_id' && !name.endsWith('_id')) {
          renamed[name] = '$value$mark';
          marked = true;
        }
      }
      // A clash on ids alone has nothing to carry a mark: two counters that
      // each gave the same item a carton while apart (M53) clash on the
      // item and the two units, and renaming nothing wrote the same row
      // into the same clash again — the whole merge failed, and every sync
      // after it, on that one change. Such a newcomer is kept struck out
      // instead, as a clash to look at: the index counts live rows only, so
      // it goes in, the counter's own carton stands, and the merge moves on.
      if (!marked && row.containsKey('deleted_at_utc')) {
        renamed['deleted_at_utc'] = _now().toUtc().millisecondsSinceEpoch;
      }
      await write(renamed);
      return _Outcome.conflict;
    }
  }

  Future<void> _keep(SyncChange change, {required bool conflict}) async {
    final row = {
      ...change.row,
      'sync_state': conflict ? 'conflict' : 'acked',
      'synced_at_utc': _now().toUtc().millisecondsSinceEpoch,
    };
    final columns = await _columnsOf('change_log');
    final known = {
      for (final e in row.entries)
        if (columns.contains(e.key)) e.key: e.value,
    };
    await _db.customStatement(
      'INSERT INTO change_log (${known.keys.join(', ')}) '
      'VALUES (${List.filled(known.length, '?').join(', ')})',
      [...known.values],
    );
  }

  Future<Set<String>> _columnsOf(String table) async {
    final cached = _columns[table];
    if (cached != null) return cached;
    if (!RegExp(r'^[a-z_]+$').hasMatch(table)) {
      throw SyncRefused('A change named a table this build does not keep.');
    }
    final rows = await _db.customSelect('PRAGMA table_info($table)').get();
    if (rows.isEmpty) {
      throw SyncRefused(
        'The other device keeps $table, which this build does not. Update '
        'this phone and sync again.',
      );
    }
    return _columns[table] = {for (final r in rows) r.read<String>('name')};
  }
}

enum _Outcome { applied, older, conflict }
