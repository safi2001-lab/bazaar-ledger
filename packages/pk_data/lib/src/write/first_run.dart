import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';
import 'tx_runner.dart';

/// What first run produced, so the caller can build an [ActorContext].
final class FirstRunResult {
  const FirstRunResult({
    required this.firmId,
    required this.ownerUserId,
    required this.deviceId,
    required this.cashAccountId,
    required this.cashPaymentAccountId,
  });

  final String firmId;
  final String ownerUserId;
  final String deviceId;
  final String cashAccountId;
  final String cashPaymentAccountId;
}

/// Creates everything a brand-new shop needs before it can ring up a sale.
///
/// The first three rows — the firm, the owner and this device — are written
/// with raw SQL rather than through [TxRunner]. This is the one place in the
/// application where that is correct, and it is worth being explicit about
/// why: [Tx] stamps `created_by` and `origin_device_id` from an
/// [ActorContext], and at this instant no user row and no device row exist for
/// a context to name. Everything after those three goes through the normal
/// write path, audit trail and outbox included.
///
/// All of it is one transaction. A shopkeeper who force-kills the app halfway
/// through setup gets a clean database and the wizard again, never a firm with
/// no chart of accounts.
final class FirstRunSeeder {
  FirstRunSeeder({
    required this.database,
    required this.ids,
    required this.clock,
  });

  final AppDatabase database;
  final IdGenerator ids;
  final Clock clock;

  Future<FirstRunResult> seed({
    required String shopName,
    required String ownerName,
    required String deviceLabel,
    required String platform,
    String city = '',
    String province = 'punjab',
    String businessKind = 'general',
    bool allowSecondFirm = false,
  }) async {
    final firmId = ids.next();
    final userId = ids.next();
    final deviceId = ids.next();
    final now = clock.nowUtc();
    final millis = now.millisecondsSinceEpoch;

    final hlcClock = HlcClock(deviceId: deviceId, clock: clock);
    final actor = ActorContext(
      firmId: firmId,
      userId: userId,
      deviceId: deviceId,
      startedAtUtc: now,
    );

    late String cashAccountId;
    late String cashPaymentAccountId;

    await database.transaction(() async {
      // Checked inside the transaction, not before it. Outside, two callers
      // racing first run both see an empty table and both seed a shop.
      // Multi-firm is M10. Until then a second firm in one database is a
      // bug, except in the tests that prove the isolation between them holds
      // — which is the one place it has to be possible on purpose.
      final existing = allowSecondFirm
          ? const <QueryRow>[]
          : await database.customSelect('SELECT id FROM firms LIMIT 1').get();
      if (existing.isNotEmpty) {
        throw StateError(
          'This database already has a firm. First run must not be repeated — '
          'it would create a second chart of accounts and a second set of '
          'numbering sequences.',
        );
      }

      // --- The bootstrap trio, raw. -------------------------------------
      // One timestamp per row, as TxRunner mints one per write. Sharing a
      // single value across the three left three outbox entries with
      // byte-identical `entity_hlc`, which is an unbreakable tie for any
      // future merge that orders by it.
      final firmHlc = hlcClock.next().value;
      final deviceHlc = hlcClock.next().value;
      final userHlc = hlcClock.next().value;

      await database.customStatement(
        'INSERT INTO firms ($_env, name, city, province, business_kind) '
        'VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, 1, ?, ?, ?, ?)',
        [
          firmId, firmId, millis, millis, userId, userId, deviceId,
          firmHlc, //
          shopName, city, province, businessKind,
        ],
      );
      await database.customStatement(
        'INSERT INTO devices ($_env, label, platform, device_role, '
        'is_this_device) '
        'VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, 1, ?, ?, ?, ?)',
        [
          deviceId, firmId, millis, millis, userId, userId, deviceId,
          deviceHlc, //
          deviceLabel, platform, 'master', 1,
        ],
      );
      await database.customStatement(
        'INSERT INTO users ($_env, name, role, can_see_purchase_price, '
        'can_see_margin, max_discount_bp) '
        'VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, 1, ?, ?, ?, ?, ?)',
        [
          userId, firmId, millis, millis, userId, userId, deviceId,
          userHlc, //
          ownerName, 'owner', 1, 1, 10000,
        ],
      );

      // The three rows above skipped TxRunner, so they also skipped the
      // outbox. Left there, a counter joining over LAN in M13 would never
      // receive the firm, the owner or the master device — and would sync
      // rows whose foreign keys point at nothing. The outbox entries are
      // written by hand here, in the same transaction, for the same reason
      // the inserts are: at this instant there is no actor for TxRunner to
      // demand.
      // The envelope every one of these rows was actually written with. A
      // payload has to be something a peer can turn straight back into an
      // INSERT, and every envelope column is NOT NULL — so a payload carrying
      // only the business columns is a row the receiving counter cannot
      // construct. TxRunner records the whole row for exactly this reason,
      // and these three have to match it.
      Map<String, Object?> envelope(String id, String hlc) => {
            'id': id,
            'firm_id': firmId,
            'created_at_utc': millis,
            'updated_at_utc': millis,
            'created_by': userId,
            'updated_by': userId,
            'deleted_at_utc': null,
            'origin_device_id': deviceId,
            'hlc': hlc,
            'rev': 1,
          };

      var bootstrapSeq = 0;
      for (final row in <(String, String, Map<String, Object?>)>[
        (
          'firms',
          firmId,
          {
            ...envelope(firmId, firmHlc),
            'name': shopName,
            'city': city,
            'province': province,
            'business_kind': businessKind,
          },
        ),
        (
          'devices',
          deviceId,
          {
            ...envelope(deviceId, deviceHlc),
            'label': deviceLabel,
            'platform': platform,
            'device_role': 'master',
            // `is_this_device` is deliberately absent. It is true of this
            // handset and false of every peer that receives the row, so
            // shipping it would tell each counter it is the master.
          },
        ),
        (
          'users',
          userId,
          {
            ...envelope(userId, userHlc),
            'name': ownerName,
            'role': 'owner',
            'can_see_purchase_price': 1,
            'can_see_margin': 1,
            'max_discount_bp': 10000,
          },
        ),
      ]) {
        bootstrapSeq++;
        await database.customStatement(
          'INSERT INTO change_log ($_env, seq, entity_table, entity_id, op, '
          'payload_json, entity_hlc, entity_rev, at_utc) '
          'VALUES (?, ?, ?, ?, ?, ?, NULL, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            ids.next(), firmId, millis, millis, userId, userId, deviceId,
            // The outbox row's own timestamp and the timestamp of the row it
            // describes are the same thing here: both were written in this
            // transaction, by this device, for this entity.
            row.$3['hlc']! as String, //
            bootstrapSeq, row.$1, row.$2, 'insert', jsonEncode(row.$3),
            row.$3['hlc']! as String, 1, millis,
          ],
        );
      }
      await database.customStatement(
        'UPDATE devices SET change_seq = ? WHERE id = ?',
        [bootstrapSeq, deviceId],
      );

      // --- Everything else through the one write path. -------------------
      final runner =
          TxRunner(database: database, ids: ids, hlc: hlcClock);
      await runner.run(actor, (tx) async {
        final accountIdsByCode = <String, String>{};
        // Two passes: parents must exist before children can reference them.
        for (final spec in defaultChartOfAccounts.where(
          (a) => a.parentCode == null,
        )) {
          accountIdsByCode[spec.code] = await _insertAccount(tx, spec, null);
        }
        for (final spec in defaultChartOfAccounts.where(
          (a) => a.parentCode != null,
        )) {
          accountIdsByCode[spec.code] = await _insertAccount(
            tx,
            spec,
            accountIdsByCode[spec.parentCode],
          );
        }

        final unitIdsByCode = <String, String>{};
        for (final unit in defaultUnits) {
          unitIdsByCode[unit.code] = await tx.insert('units', {
            'code': unit.code,
            'name_en': unit.nameEn,
            'name_ur': unit.nameUr,
            'kind': unit.kind.name,
            'is_base': unit.isBase ? 1 : 0,
            'decimals': unit.decimals,
          });
        }
        for (final conversion in defaultUnitConversions) {
          await tx.insert('unit_conversions', {
            'from_unit_id': unitIdsByCode[conversion.fromCode],
            'to_unit_id': unitIdsByCode[conversion.toCode],
            'factor_thousandths': conversion.factorThousandths,
          });
        }

        cashAccountId = accountIdsByCode['1010']!;
        cashPaymentAccountId = await tx.insert('payment_accounts', {
          'name': 'Golak',
          'account_kind': 'cash',
          'mode_label': 'cash',
          'ledger_account_id': cashAccountId,
          'is_default': 1,
        });

        // Invoice numbering for this device, this fiscal year. INV-2627-0001.
        await tx.insert('numbering_sequences', {
          'doc_type': 'sale_invoice',
          'device_id': deviceId,
          'fiscal_year': actor.businessDate.fiscalYear,
          'prefix': 'INV',
          'pad_width': 4,
          'next_value': 1,
        });
        await tx.insert('numbering_sequences', {
          'doc_type': 'payment_in',
          'device_id': deviceId,
          'fiscal_year': actor.businessDate.fiscalYear,
          'prefix': 'RCV',
          'pad_width': 4,
          'next_value': 1,
        });
        await tx.insert('numbering_sequences', {
          'doc_type': 'journal_entry',
          'device_id': deviceId,
          'fiscal_year': actor.businessDate.fiscalYear,
          'prefix': 'JV',
          'pad_width': 5,
          'next_value': 1,
        });

        tx.audit(
          action: 'FIRM_CREATED',
          entityTable: 'firms',
          entityId: firmId,
          summary: '$shopName set up by $ownerName on $deviceLabel',
        );
      });
    });

    return FirstRunResult(
      firmId: firmId,
      ownerUserId: userId,
      deviceId: deviceId,
      cashAccountId: cashAccountId,
      cashPaymentAccountId: cashPaymentAccountId,
    );
  }

  Future<String> _insertAccount(
    Tx tx,
    AccountSpec spec,
    String? parentId,
  ) =>
      tx.insert('accounts', {
        'code': spec.code,
        'name': spec.nameEn,
        'account_type': spec.type.name,
        'normal_side': spec.normalSide.name,
        'system_key': spec.systemKey,
        'parent_id': parentId,
        'is_direct': spec.isDirect ? 1 : 0,
      });
}

const String _env = 'id, firm_id, created_at_utc, updated_at_utc, created_by, '
    'updated_by, deleted_at_utc, origin_device_id, hlc, rev';

/// Convenience for callers that already have a database and want a runner and
/// a context wired to whatever first run produced.
extension FirstRunWiring on FirstRunResult {
  ActorContext actorAt(DateTime instant) => ActorContext(
        firmId: firmId,
        userId: ownerUserId,
        deviceId: deviceId,
        startedAtUtc: instant,
      );
}

/// Rebuilds this device's HLC from the outbox on startup.
///
/// The highest timestamp this device ever issued is already recorded in
/// `change_log`, which the single write path guarantees is complete. There is
/// therefore no separate counter to persist, keep in step, or lose in a power
/// cut — the thing that would be hardest to get right is simply not there.
Future<HlcClock> resumeHlcClock(
  AppDatabase database, {
  required String deviceId,
  required Clock clock,
}) async {
  final row = await database
      .customSelect(
        'SELECT MAX(hlc) AS last_hlc FROM change_log WHERE origin_device_id = ?',
        variables: [Variable<String>(deviceId)],
      )
      .getSingleOrNull();
  final raw = row?.readNullable<String>('last_hlc');
  return HlcClock(
    deviceId: deviceId,
    clock: clock,
    lastSeen: raw == null ? null : Hlc.tryParse(raw),
  );
}
