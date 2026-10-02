import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';
import 'drift_app_queries.dart';

/// A bill's due date, in SQL: its business date plus its customer's credit
/// days, or the shop's usual month when they have none (M38).
///
/// The same arithmetic as `dueDateOf` in pk_domain, and a test pins the two
/// together at the boundaries. Worked out on read, never stored, so a
/// customer given longer terms has every open bill move with them — which is
/// what the party form tells the shopkeeper before they save.
///
/// `d` is the bill and `p` its party. A negative term (only a hand-edited
/// row could hold one) is read as zero rather than as a date in the past.
const dueOnSql =
    "date(d.doc_date_local, '+' || "
    'MAX(COALESCE(p.credit_days, $shopUsualCreditDays), 0) || '
    "' days')";

/// A bill a customer still owes on: a sale or a charge put on the khata,
/// posted, not cancelled, with something left on it. The same rows the
/// payment writer settles (`_DriftPaymentWriteContext.openBillsFor`).
const _openBill = '''
  d.doc_type IN ('sale_invoice', 'other_income')
  AND d.balance_paisa > 0
  AND d.status NOT IN ('void', 'draft')
  AND d.deleted_at_utc IS NULL
''';

/// The drift implementation of [UdhaarQueries].
///
/// Days late are counted on business dates with julianday, never on an
/// epoch, for the reason the bill-age report gives (M3): PKT is UTC+5, and a
/// bill raised in the evening is a day older under UTC arithmetic.
final class DriftUdhaarQueries implements UdhaarQueries {
  const DriftUdhaarQueries(this._db);

  final AppDatabase _db;

  @override
  Future<List<BillDue>> billsDue(
    String firmId,
    String partyId, {
    required String asOfDateLocal,
  }) async {
    // In the order the payment writer settles them, so the bill the khata
    // shows first is the one the next receipt clears first.
    final rows = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_no, d.doc_type, d.doc_date_local,
                 d.balance_paisa, $dueOnSql AS due_on,
                 CAST(julianday(?3) - julianday($dueOnSql) AS INTEGER) AS late
          FROM documents d
          JOIN parties p ON p.id = d.party_id
          WHERE d.firm_id = ?1 AND d.party_id = ?2 AND $_openBill
          ORDER BY d.doc_date_local, d.doc_seq, d.id
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(partyId),
            Variable<String>(asOfDateLocal),
          ],
          readsFrom: {_db.documents, _db.parties},
        )
        .get();
    return [
      for (final r in rows)
        BillDue(
          documentId: r.read<String>('id'),
          docNo: r.read<String>('doc_no'),
          docType: r.read<String>('doc_type'),
          billDateLocal: r.read<String>('doc_date_local'),
          dueDateLocal: r.read<String>('due_on'),
          outstanding: Money.paisa(r.read<int>('balance_paisa')),
          daysOverdue: r.read<int>('late'),
        ),
    ];
  }

  @override
  Future<DueAging> dueAging(
    String firmId, {
    required String asOfDateLocal,
  }) async {
    // Bucketed by the database, one row per distinct lateness, rather than
    // every open bill pulled into Dart: a wholesaler has tens of thousands.
    final rows = await _db
        .customSelect(
          '''
          SELECT CAST(julianday(?2) - julianday($dueOnSql) AS INTEGER) AS late,
                 SUM(d.balance_paisa) AS owed
          FROM documents d
          JOIN parties p ON p.id = d.party_id
          WHERE d.firm_id = ?1 AND $_openBill
          GROUP BY late
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(asOfDateLocal),
          ],
          readsFrom: {_db.documents, _db.parties},
        )
        .get();
    return ageByDueDate([
      for (final r in rows)
        BillDue(
          documentId: '',
          docNo: '',
          docType: '',
          billDateLocal: '',
          dueDateLocal: '',
          outstanding: Money.paisa(r.read<int>('owed')),
          daysOverdue: r.read<int>('late'),
        ),
    ]);
  }

  @override
  Future<List<DueParty>> dueParties(
    String firmId, {
    required String asOfDateLocal,
  }) async {
    // One query: each customer's open bills summed by lateness, joined to
    // the one SELECT the whole app reads a customer's balance from — so a
    // customer in credit overall (an advance larger than their open bills)
    // is dropped here exactly as the khata would show them, and the list
    // never knocks on the door of somebody the shop owes.
    final rows = await _db
        .customSelect(
          '''
          WITH due AS (
            SELECT d.party_id AS party_id, d.balance_paisa AS owed,
                   $dueOnSql AS due_on
            FROM documents d
            JOIN parties p ON p.id = d.party_id
            WHERE d.firm_id = ?1 AND $_openBill
              AND p.deleted_at_utc IS NULL AND p.is_active = 1
          ),
          per_party AS (
            SELECT party_id,
                   COUNT(*) AS open_bills,
                   MIN(due_on) AS oldest_due,
                   SUM(CASE WHEN due_on < ?2 THEN owed ELSE 0 END) AS overdue,
                   SUM(CASE WHEN due_on = ?2 THEN owed ELSE 0 END) AS due_today
            FROM due
            GROUP BY party_id
          )
          SELECT ps.*, pp.open_bills, pp.oldest_due, pp.overdue,
                 pp.due_today,
                 CAST(julianday(?2) - julianday(pp.oldest_due) AS INTEGER)
                   AS late
          FROM per_party pp
          JOIN (${DriftAppQueries.partySelectSql} WHERE p.firm_id = ?1) ps
            ON ps.id = pp.party_id
          WHERE ps.balance_paisa > 0
          ORDER BY late DESC, ps.name
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(asOfDateLocal),
          ],
          readsFrom: {
            _db.documents,
            _db.parties,
            _db.journalLines,
            _db.accounts,
            _db.payments,
          },
        )
        .get();

    final latest = _latestByParty(await _promises(firmId));
    final prefs = await _allPrefs(firmId);
    final reminded = await _lastReminded(firmId);
    final listed = <String>{};
    final parties = <DueParty>[];
    for (final r in rows) {
      final party = DriftAppQueries.partyFromRow(r);
      listed.add(party.id);
      parties.add(
        DueParty(
          party: party,
          openBills: r.read<int>('open_bills'),
          oldestDueLocal: r.read<String>('oldest_due'),
          daysOverdue: r.read<int>('late'),
          overdue: Money.paisa(r.read<int>('overdue')),
          dueToday: Money.paisa(r.read<int>('due_today')),
          promise: latest[party.id],
          prefs: prefs[party.id] ?? ReminderPrefs.standard,
          lastRemindedAt: reminded[party.id],
        ),
      );
    }

    // A customer whose only debt is an opening balance has no bill to fall
    // due, but a promise from them is still a promise: listed, after the
    // rest, while it is live and they still owe.
    final queries = DriftAppQueries(_db);
    for (final promise in latest.values) {
      if (listed.contains(promise.partyId)) continue;
      if (!promise.standingOn(asOfDateLocal).isLive) continue;
      final party = await queries.partyById(firmId, promise.partyId);
      if (party == null || !party.balance.isPositive) continue;
      parties.add(
        DueParty(
          party: party,
          openBills: 0,
          daysOverdue: 0,
          overdue: Money.zero,
          dueToday: Money.zero,
          promise: promise,
          prefs: prefs[party.id] ?? ReminderPrefs.standard,
          lastRemindedAt: reminded[party.id],
        ),
      );
    }
    return parties;
  }

  @override
  Future<List<PaymentPromise>> promisesOf(String firmId, String partyId) async {
    final all = await _promises(firmId, partyId: partyId);
    return all.reversed.toList();
  }

  @override
  Future<UdhaarToday> udhaarToday(
    String firmId, {
    required String asOfDateLocal,
  }) async {
    final parties = await dueParties(firmId, asOfDateLocal: asOfDateLocal);
    var dueCount = 0;
    var overdueCount = 0;
    var promisedCount = 0;
    var due = Money.zero;
    var overdue = Money.zero;
    var promised = Money.zero;
    for (final p in parties) {
      if (p.hasDueToday) {
        dueCount++;
        due += p.dueToday;
      }
      if (p.isOverdue) {
        overdueCount++;
        overdue += p.overdue;
      }
      final promise = p.promise;
      if (promise != null &&
          promise.standingOn(asOfDateLocal) == PromiseStanding.dueToday) {
        promisedCount++;
        // What they said they would bring, less what has come already; a
        // promise with no amount is counted at what they owe.
        final said = promise.amount;
        promised += said == null
            ? p.party.balance
            : (said - promise.paidSince).isPositive
            ? said - promise.paidSince
            : Money.zero;
      }
    }
    return UdhaarToday(
      dueTodayCount: dueCount,
      dueToday: due,
      overdueCount: overdueCount,
      overdue: overdue,
      promisedTodayCount: promisedCount,
      promisedToday: promised,
    );
  }

  // -------------------------------------------------------------------------
  // Reminders (M39)
  // -------------------------------------------------------------------------

  @override
  Future<String?> customReminderTemplate(
    String firmId,
    ReminderLanguage language,
  ) async {
    final row = await _db
        .customSelect(
          'SELECT setting_value FROM settings '
          'WHERE firm_id = ? AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(firmId),
            Variable<String>(reminderTemplateKey(language)),
          ],
          readsFrom: {_db.settings},
        )
        .getSingleOrNull();
    final text = row?.read<String>('setting_value') ?? '';
    // Empty is how "back to the shop's words" is kept.
    return text.trim().isEmpty ? null : text;
  }

  @override
  Future<ReminderPrefs> reminderPrefs(String firmId, String partyId) async {
    final row = await _db
        .customSelect(
          'SELECT setting_value FROM settings '
          'WHERE firm_id = ? AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(firmId),
            Variable<String>(reminderPrefsKey(partyId)),
          ],
          readsFrom: {_db.settings},
        )
        .getSingleOrNull();
    return _prefs(row?.read<String>('setting_value'));
  }

  @override
  Future<List<ReminderSent>> remindersSent(
    String firmId,
    String partyId, {
    int limit = 20,
  }) async {
    // The log is the audit trail: one REMINDER_SENT row per reminder, on
    // the customer's own entity, so it rides idx_audit_entity and carries
    // who (created_by) and when (at_utc) the way every audited act does.
    final rows = await _db
        .customSelect(
          '''
          SELECT a.at_utc, a.after_json, COALESCE(u.name, '') AS by_name
          FROM audit_log a
          LEFT JOIN users u ON u.id = a.created_by
          WHERE a.entity_table = 'parties' AND a.entity_id = ?1
            AND a.firm_id = ?2 AND a.action_code = 'REMINDER_SENT'
          ORDER BY a.at_utc DESC, a.id DESC
          LIMIT ?3
          ''',
          variables: [
            Variable<String>(partyId),
            Variable<String>(firmId),
            Variable<int>(limit),
          ],
          readsFrom: {_db.auditLog, _db.users},
        )
        .get();
    return [
      for (final r in rows)
        () {
          final after = _json(r.readNullable<String>('after_json'));
          return ReminderSent(
            partyId: partyId,
            atUtc: DateTime.fromMillisecondsSinceEpoch(
              r.read<int>('at_utc'),
              isUtc: true,
            ),
            byName: r.read<String>('by_name'),
            channel: ReminderChannel.parse(after['channel'] as String?),
            language: ReminderLanguage.parse(after['language'] as String?),
          );
        }(),
    ];
  }

  // -------------------------------------------------------------------------
  // Udhaar let go (M44)
  // -------------------------------------------------------------------------

  @override
  Future<List<AllowanceRow>> allowances(
    String firmId, {
    required AllowanceKind kind,
    String? fromDateLocal,
    String? toDateLocal,
  }) async {
    // Known by their number series (`WO-`, `SD-`), which no other payment
    // is numbered in, and by the mode the schema keeps for exactly this.
    final rows = await _db
        .customSelect(
          '''
          SELECT p.id, p.payment_no, p.party_id, p.payment_date_local,
                 p.amount_paisa, p.status,
                 COALESCE(p.notes, '') AS notes,
                 COALESCE(pa.name, '') AS party_name,
                 COALESCE(u.name, '') AS by_name
          FROM payments p
          LEFT JOIN parties pa ON pa.id = p.party_id
          LEFT JOIN users u ON u.id = p.created_by
          WHERE p.firm_id = ?1 AND p.mode = 'adjustment'
            AND p.direction = 'in'
            AND p.payment_no LIKE ?2
            AND p.deleted_at_utc IS NULL
            AND (?3 IS NULL OR p.payment_date_local >= ?3)
            AND (?4 IS NULL OR p.payment_date_local <= ?4)
          ORDER BY p.payment_date_local DESC, p.payment_no DESC
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>('${kind.prefix}-%'),
            Variable<String>(fromDateLocal),
            Variable<String>(toDateLocal),
          ],
          readsFrom: {_db.payments, _db.parties, _db.users},
        )
        .get();
    return [
      for (final r in rows)
        AllowanceRow(
          paymentId: r.read<String>('id'),
          paymentNo: r.read<String>('payment_no'),
          kind: kind,
          partyId: r.readNullable<String>('party_id') ?? '',
          partyName: r.read<String>('party_name'),
          dateLocal: r.read<String>('payment_date_local'),
          amount: Money.paisa(r.read<int>('amount_paisa')),
          reason: r.read<String>('notes'),
          byName: r.read<String>('by_name'),
          cancelled: r.read<String>('status') == 'void',
        ),
    ];
  }

  /// Every customer's reminder settings, by key range on the settings
  /// index: `reminder.party.` up to `reminder.party/`.
  Future<Map<String, ReminderPrefs>> _allPrefs(String firmId) async {
    const prefix = 'reminder.party.';
    final rows = await _db
        .customSelect(
          'SELECT setting_key, setting_value FROM settings '
          'WHERE firm_id = ?1 AND setting_key >= ?2 AND setting_key < ?3 '
          '  AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(firmId),
            Variable<String>(prefix),
            Variable<String>('reminder.party/'),
          ],
          readsFrom: {_db.settings},
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('setting_key').substring(prefix.length): _prefs(
          r.read<String>('setting_value'),
        ),
    };
  }

  /// When each customer was last reminded, from the log.
  Future<Map<String, DateTime>> _lastReminded(String firmId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT entity_id, MAX(at_utc) AS at
          FROM audit_log
          WHERE firm_id = ?1 AND action_code = 'REMINDER_SENT'
          GROUP BY entity_id
          ''',
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.auditLog},
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('entity_id'): DateTime.fromMillisecondsSinceEpoch(
          r.read<int>('at'),
          isUtc: true,
        ),
    };
  }

  static ReminderPrefs _prefs(String? text) {
    final json = _json(text);
    return json.isEmpty ? ReminderPrefs.standard : ReminderPrefs.fromJson(json);
  }

  static Map<String, Object?> _json(String? text) {
    if (text == null || text.isEmpty) return const {};
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, Object?> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  // -------------------------------------------------------------------------
  // Promises
  // -------------------------------------------------------------------------

  /// Every promise in the shop (or one customer's), oldest first, each told
  /// what has come in since it was made and when the next one was made.
  ///
  /// Read by key range, not LIKE, so it rides `idx_settings_key`: every key
  /// from `promise.` up to (not including) `promise/`, the next character.
  Future<List<PaymentPromise>> _promises(
    String firmId, {
    String? partyId,
  }) async {
    final from = partyId == null
        ? promiseKeyPrefix
        : '$promiseKeyPrefix$partyId.';
    final to = '${from.substring(0, from.length - 1)}/';
    final rows = await _db
        .customSelect(
          '''
          SELECT s.id, s.setting_value, s.created_at_utc,
                 COALESCE(u.name, '') AS made_by
          FROM settings s
          LEFT JOIN users u ON u.id = s.created_by
          WHERE s.firm_id = ?1
            AND s.setting_key >= ?2 AND s.setting_key < ?3
            AND s.deleted_at_utc IS NULL
          ORDER BY s.created_at_utc, s.id
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(from),
            Variable<String>(to),
          ],
          readsFrom: {_db.settings, _db.users},
        )
        .get();

    final raw = <({String id, Map<String, Object?> json, String by})>[];
    for (final r in rows) {
      final Object? decoded;
      try {
        decoded = jsonDecode(r.read<String>('setting_value'));
      } on FormatException {
        // A row somebody edited by hand. Left out rather than shown wrong.
        continue;
      }
      if (decoded is! Map<String, Object?>) continue;
      raw.add((
        id: r.read<String>('id'),
        json: decoded,
        by: r.read<String>('made_by'),
      ));
    }
    if (raw.isEmpty) return const [];

    // Who made them, by name, for the home screen's list.
    final ids = {for (final p in raw) p.json['party_id'] as String? ?? ''};
    final names = {
      for (final r
          in await _db
              .customSelect(
                'SELECT id, name FROM parties WHERE firm_id = ? AND id IN '
                '(${List.filled(ids.length, '?').join(', ')})',
                variables: [
                  Variable<String>(firmId),
                  for (final id in ids) Variable<String>(id),
                ],
                readsFrom: {_db.parties},
              )
              .get())
        r.read<String>('id'): r.read<String>('name'),
    };

    // What came in, from the earliest promise on, for the customers who
    // made them. Receipts only: not a write-off or a settlement discount
    // (M44), not money taken at the counter for a new bill (its allocation
    // is `exact`), not a cheque the bank sent back — none of those is the
    // customer paying what they promised.
    final earliest = raw
        .map((p) => p.json['made_on'] as String? ?? '')
        .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    final paid = await _db
        .customSelect(
          '''
          SELECT p.party_id, p.payment_date_local, p.amount_paisa
          FROM payments p
          WHERE p.firm_id = ?1
            AND p.direction = 'in'
            AND p.status NOT IN ('void', 'bounced')
            AND p.mode <> 'adjustment'
            AND p.deleted_at_utc IS NULL
            AND p.payment_date_local >= ?2
            AND (?3 IS NULL OR p.party_id = ?3)
            AND NOT EXISTS (
              SELECT 1 FROM payment_allocations a
              WHERE a.payment_id = p.id AND a.allocation_mode = 'exact'
                AND a.deleted_at_utc IS NULL)
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(earliest),
            Variable<String>(partyId),
          ],
          readsFrom: {_db.payments, _db.paymentAllocations},
        )
        .get();
    final receipts = <String, List<(String, Money)>>{};
    for (final r in paid) {
      final id = r.readNullable<String>('party_id');
      if (id == null) continue;
      (receipts[id] ??= []).add((
        r.read<String>('payment_date_local'),
        Money.paisa(r.read<int>('amount_paisa')),
      ));
    }

    // Oldest first per customer, so each knows the day the next was made.
    final byParty = <String, List<int>>{};
    for (var i = 0; i < raw.length; i++) {
      final party = raw[i].json['party_id'] as String? ?? '';
      (byParty[party] ??= []).add(i);
    }
    final superseded = <int, String>{};
    for (final indexes in byParty.values) {
      indexes.sort((a, b) {
        final byDay = (raw[a].json['made_on'] as String? ?? '').compareTo(
          raw[b].json['made_on'] as String? ?? '',
        );
        return byDay != 0 ? byDay : a.compareTo(b);
      });
      final standing = [
        for (final i in indexes)
          if (raw[i].json['withdrawn_on'] == null) i,
      ];
      for (var k = 0; k + 1 < standing.length; k++) {
        superseded[standing[k]] =
            raw[standing[k + 1]].json['made_on'] as String? ?? '';
      }
    }

    return [
      for (var i = 0; i < raw.length; i++)
        () {
          final json = raw[i].json;
          final party = json['party_id'] as String? ?? '';
          final madeOn = json['made_on'] as String? ?? '';
          final until = json['for'] as String? ?? '';
          return PaymentPromise.fromJson(
            raw[i].id,
            json,
            madeBy: raw[i].by,
            partyName: names[party] ?? '',
            supersededOn: superseded[i],
            paidSince: Money.sum([
              for (final (day, amount)
                  in receipts[party] ?? const <(String, Money)>[])
                if (day.compareTo(madeOn) >= 0 && day.compareTo(until) <= 0)
                  amount,
            ]),
          );
        }(),
    ];
  }

  /// Each customer's most recent promise that has not been withdrawn.
  static Map<String, PaymentPromise> _latestByParty(
    List<PaymentPromise> promises,
  ) {
    final latest = <String, PaymentPromise>{};
    for (final p in promises) {
      if (p.isWithdrawn) continue;
      final held = latest[p.partyId];
      // Oldest first already; a later one on the same day is the newer.
      if (held == null || p.madeOn.compareTo(held.madeOn) >= 0) {
        latest[p.partyId] = p;
      }
    }
    return latest;
  }
}
