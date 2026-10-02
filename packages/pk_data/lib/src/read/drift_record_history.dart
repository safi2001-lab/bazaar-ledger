import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';

/// One record's history, read from what the books already keep (M42).
///
/// Nothing is written for the history's sake. The audit log has carried
/// who, when, which device and what since M0, inside the transaction of the
/// act itself; a print leaves its print job; a return its link; a payment
/// its allocation. This joins them, so the timeline cannot leave out
/// anything that happened — and cannot show anything that did not.
final class DriftRecordHistory implements RecordHistoryReads {
  const DriftRecordHistory(this._db);

  final AppDatabase _db;

  /// The corrections that tie an old entry to the one that replaced it
  /// (M31). The new entry is the row's subject; the old one is named in its
  /// `before_json`.
  static const _corrections = [
    'PAYMENT_EDITED',
    'CHARGE_EDITED',
    'EXPENSE_EDITED',
  ];

  /// Keys in an audit row's before and after that tie records together or
  /// say why, rather than being a field that changed.
  static const _notFields = {
    'id',
    'no',
    'reason',
    'dates',
    'closed_through',
    'approved_by',
    'approved_by_name',
    'for',
  };

  @override
  Future<List<HistoryEvent>> historyOf(String firmId, RecordRef record) async {
    final events = <HistoryEvent>[
      ...await _auditOn(firmId, record.table, [record.id]),
      ...await _replaced(firmId, record),
    ];
    switch (record.table) {
      case 'documents':
        events
          ..addAll(await _prints(firmId, record.id))
          ..addAll(await _links(firmId, record.id))
          ..addAll(await _paymentsOn(firmId, record.id))
          ..addAll(
            await _auditOn(
              firmId,
              'journal_entries',
              await _entriesOf(firmId, 'document_id', record.id),
            ),
          );
      case 'payments':
        events
          ..addAll(await _billsSettled(firmId, record.id))
          ..addAll(
            await _auditOn(
              firmId,
              'journal_entries',
              await _entriesOf(firmId, 'payment_id', record.id),
            ),
          );
      case 'items':
        events.addAll(await _itemExtras(firmId, record.id));
    }
    // By time, and within one instant in the order read: everything one
    // transaction wrote shares its instant, and the bill reads before the
    // money taken with it. `List.sort` does not promise to keep that order,
    // so the position breaks the tie.
    final ordered = [for (var i = 0; i < events.length; i++) (i, events[i])]
      ..sort((a, b) {
        final byTime = a.$2.atUtcMillis.compareTo(b.$2.atUtcMillis);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
    return [for (final (_, e) in ordered) e];
  }

  // ---------------------------------------------------------------------
  // The audit log
  // ---------------------------------------------------------------------

  static const _auditColumns = '''
    a.at_utc, a.action_code, a.entity_table, a.entity_id, a.summary,
    a.before_json, a.after_json, a.amount_paisa,
    u.name AS who, dv.label AS device,
    d.void_reason AS void_reason, pm.notes AS payment_notes
  ''';

  static const _auditJoins = '''
    FROM audit_log a
    JOIN users u ON u.id = a.created_by
    LEFT JOIN devices dv ON dv.id = a.origin_device_id
    LEFT JOIN documents d
      ON a.entity_table = 'documents' AND d.id = a.entity_id
    LEFT JOIN payments pm
      ON a.entity_table = 'payments' AND pm.id = a.entity_id
  ''';

  /// Every audit row whose subject is one of [ids] in [table]. Rides
  /// idx_audit_entity.
  Future<List<HistoryEvent>> _auditOn(
    String firmId,
    String table,
    List<String> ids, {
    RecordRef? linked,
    String? linkedLabel,
  }) async {
    if (ids.isEmpty) return const [];
    final rows = await _db
        .customSelect(
          'SELECT $_auditColumns $_auditJoins '
          'WHERE a.firm_id = ? AND a.entity_table = ? '
          'AND a.entity_id IN (${List.filled(ids.length, '?').join(', ')}) '
          'AND a.deleted_at_utc IS NULL',
          variables: [
            Variable<String>(firmId),
            Variable<String>(table),
            for (final id in ids) Variable<String>(id),
          ],
        )
        .get();
    return [
      for (final r in rows)
        _fromAudit(r, linked: linked, linkedLabel: linkedLabel),
    ];
  }

  /// The correction that replaced [record], when one did: the M31 row is
  /// written on the replacement and names this one in its before.
  Future<List<HistoryEvent>> _replaced(String firmId, RecordRef record) async {
    if (record.table != 'payments' && record.table != 'documents') {
      return const [];
    }
    final rows = await _db
        .customSelect(
          'SELECT $_auditColumns $_auditJoins '
          'WHERE a.firm_id = ? '
          'AND a.action_code IN (${_corrections.map((c) => "'$c'").join(', ')}) '
          "AND json_extract(a.before_json, '\$.id') = ? "
          'AND a.deleted_at_utc IS NULL',
          variables: [Variable<String>(firmId), Variable<String>(record.id)],
        )
        .get();
    // Seen from the entry that was replaced, the row points on to its
    // replacement, which is the row's own subject.
    return [for (final r in rows) _fromAudit(r, onward: true)];
  }

  HistoryEvent _fromAudit(
    QueryRow r, {
    RecordRef? linked,
    String? linkedLabel,
    bool onward = false,
  }) {
    final action = r.read<String>('action_code');
    final before = _json(r.readNullable<String>('before_json'));
    final after = _json(r.readNullable<String>('after_json'));
    final table = r.read<String>('entity_table');
    final subject = r.read<String>('entity_id');

    // A correction points both ways: from the replacement back to what it
    // replaced, and from the replaced entry on to its replacement.
    var link = linked;
    var label = linkedLabel;
    if (_corrections.contains(action) && link == null) {
      final oldId = before['id'];
      if (onward) {
        link = RecordRef(table, subject);
        label = _text(after['no']);
      } else if (oldId is String && oldId != subject) {
        link = RecordRef(table, oldId);
        label = _text(before['no']);
      }
    }

    return HistoryEvent(
      atUtcMillis: r.read<int>('at_utc'),
      kind: kindOf(action),
      actionCode: action,
      who: r.read<String>('who'),
      device: r.readNullable<String>('device'),
      summary: r.readNullable<String>('summary'),
      amount: switch (r.readNullable<int>('amount_paisa')) {
        final int p => Money.paisa(p),
        null => null,
      },
      // A cancel keeps its reason on the bill; a write-off or a settlement
      // discount (M44) in its payment's note.
      reason:
          _text(after['reason']) ??
          switch (action) {
            'DOCUMENT_VOIDED' => _text(r.readNullable<String>('void_reason')),
            'BAD_DEBT_WRITTEN_OFF' || 'SETTLEMENT_DISCOUNT_GIVEN' => _text(
              r.readNullable<String>('payment_notes'),
            ),
            _ => null,
          },
      changes: [
        for (final key in before.keys)
          if (!_notFields.contains(key) && before[key] != after[key])
            FieldChange(key, before[key], after[key]),
      ],
      linked: link,
      linkedLabel: label,
    );
  }

  /// What kind of thing an audit code records.
  static HistoryKind kindOf(String action) => switch (action) {
    'DOCUMENT_VOIDED' ||
    'PAYMENT_VOIDED' ||
    'ITEM_ARCHIVED' ||
    'PARTY_ARCHIVED' ||
    'LOAN_ENTRY_CANCELLED' => HistoryKind.cancelled,
    'SALE_RETURNED' || 'PURCHASE_RETURNED' => HistoryKind.returned,
    'PAYMENT_EDITED' ||
    'CHARGE_EDITED' ||
    'EXPENSE_EDITED' ||
    'OPENING_BALANCE_CORRECTED' => HistoryKind.corrected,
    closedBooksOverrideAction || dataLockPinAction => HistoryKind.approved,
    'BAD_DEBT_WRITTEN_OFF' ||
    'SETTLEMENT_DISCOUNT_GIVEN' ||
    'PAYMENT_RECEIVED' ||
    'PAYMENT_MADE' => HistoryKind.paid,
    _
        when action.endsWith('_POSTED') ||
            action.endsWith('_CREATED') ||
            action.endsWith('_RECORDED') ||
            action.endsWith('_ISSUED') ||
            action == 'GOODS_TAKEN_HOME' =>
      HistoryKind.created,
    _
        when action.endsWith('_UPDATED') ||
            action.endsWith('_RESTORED') ||
            action.endsWith('_SET') ||
            action.startsWith('STOCK_') ||
            action.startsWith('ATTACHMENT_') ||
            action.startsWith('CHEQUE_') =>
      HistoryKind.changed,
    _ => HistoryKind.other,
  };

  // ---------------------------------------------------------------------
  // A bill's other traces
  // ---------------------------------------------------------------------

  /// Every print of the bill, tried or done, on whichever counter.
  Future<List<HistoryEvent>> _prints(String firmId, String documentId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT pj.started_at_utc, pj.status, pj.copy_index, pj.columns_used,
                 pj.failure_reason, u.name AS who, dv.label AS device
          FROM print_jobs pj
          JOIN users u ON u.id = pj.created_by
          LEFT JOIN devices dv ON dv.id = pj.origin_device_id
          WHERE pj.firm_id = ? AND pj.document_id = ?
            AND pj.deleted_at_utc IS NULL
          ''',
          variables: [Variable<String>(firmId), Variable<String>(documentId)],
        )
        .get();
    return [
      for (final r in rows)
        HistoryEvent(
          atUtcMillis: r.read<int>('started_at_utc'),
          kind: HistoryKind.printed,
          actionCode: switch (r.read<String>('status')) {
            'printed' => 'PRINTED',
            'failed' => 'PRINT_FAILED',
            'partial' => 'PRINT_PARTIAL',
            _ => 'PRINT_UNKNOWN',
          },
          who: r.read<String>('who'),
          device: r.readNullable<String>('device'),
          summary:
              'Copy ${r.read<int>('copy_index')}, '
              '${r.read<int>('columns_used')} columns',
          reason: _text(r.readNullable<String>('failure_reason')),
        ),
    ];
  }

  /// Returns against the bill, the bill it was made from, and the bill it
  /// became: each link both ways, with the other paper's number.
  Future<List<HistoryEvent>> _links(String firmId, String documentId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT l.created_at_utc, l.link_type, l.amount_paisa,
                 l.from_document_id = ?2 AS outward,
                 other.id AS other_id, other.doc_no AS other_no,
                 other.total_paisa AS other_total, other.status AS other_status,
                 u.name AS who, dv.label AS device
          FROM doc_links l
          JOIN documents other
            ON other.id = CASE WHEN l.from_document_id = ?2
                               THEN l.to_document_id ELSE l.from_document_id END
          JOIN users u ON u.id = l.created_by
          LEFT JOIN devices dv ON dv.id = l.origin_device_id
          WHERE l.firm_id = ?1
            AND (l.from_document_id = ?2 OR l.to_document_id = ?2)
            AND l.deleted_at_utc IS NULL
          ''',
          variables: [Variable<String>(firmId), Variable<String>(documentId)],
        )
        .get();
    return [
      for (final r in rows)
        _fromLink(
          type: r.read<String>('link_type'),
          outward: r.read<int>('outward') == 1,
          at: r.read<int>('created_at_utc'),
          who: r.read<String>('who'),
          device: r.readNullable<String>('device'),
          otherId: r.read<String>('other_id'),
          otherNo: r.read<String>('other_no'),
          total: Money.paisa(r.read<int>('other_total')),
          otherVoid: r.read<String>('other_status') == 'void',
        ),
    ];
  }

  static HistoryEvent _fromLink({
    required String type,
    required bool outward,
    required int at,
    required String who,
    required String? device,
    required String otherId,
    required String otherNo,
    required Money total,
    required bool otherVoid,
  }) {
    // Outward is this paper's link to a later one: goods back against it,
    // or the bill it became. Inward is the paper this one came from.
    final action = switch ((type, outward)) {
      ('returns', true) => 'RETURNED_AGAINST',
      ('returns', false) => 'RETURN_OF',
      ('converted_from', true) => 'CONVERTED_TO',
      ('converted_from', false) => 'CONVERTED_FROM',
      _ => 'LINKED',
    };
    return HistoryEvent(
      atUtcMillis: at,
      kind: switch (action) {
        'RETURNED_AGAINST' => HistoryKind.returned,
        'CONVERTED_FROM' || 'RETURN_OF' => HistoryKind.created,
        _ => HistoryKind.changed,
      },
      actionCode: action,
      who: who,
      device: device,
      summary: otherVoid ? '$otherNo (cancelled since)' : otherNo,
      amount: total,
      linked: RecordRef.document(otherId),
      linkedLabel: otherNo,
    );
  }

  /// Money that went against the bill: the tender at the counter, each
  /// receipt that settled part of it, a discount or a write-off (M44), and
  /// whatever later happened to each of those payments — a receipt
  /// cancelled reopens the bill, and the bill's history says so.
  Future<List<HistoryEvent>> _paymentsOn(
    String firmId,
    String documentId,
  ) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT pa.created_at_utc, pa.amount_paisa, pa.allocation_mode,
                 p.id AS payment_id, p.payment_no, p.mode,
                 u.name AS who, dv.label AS device
          FROM payment_allocations pa
          JOIN payments p ON p.id = pa.payment_id
          JOIN users u ON u.id = pa.created_by
          LEFT JOIN devices dv ON dv.id = pa.origin_device_id
          WHERE pa.firm_id = ? AND pa.document_id = ?
          ''',
          variables: [Variable<String>(firmId), Variable<String>(documentId)],
        )
        .get();
    final events = <HistoryEvent>[];
    final later = <String, String>{};
    for (final r in rows) {
      final paymentId = r.read<String>('payment_id');
      final no = r.read<String>('payment_no');
      later[paymentId] = no;
      events.add(
        HistoryEvent(
          atUtcMillis: r.read<int>('created_at_utc'),
          kind: HistoryKind.paid,
          actionCode: r.read<String>('mode') == 'adjustment'
              ? 'LET_GO_AGAINST'
              : r.read<String>('allocation_mode') == 'exact'
              ? 'PAID_AT_COUNTER'
              : 'PAID_AGAINST',
          who: r.read<String>('who'),
          device: r.readNullable<String>('device'),
          summary: no,
          amount: Money.paisa(r.read<int>('amount_paisa')),
          linked: RecordRef.payment(paymentId),
          linkedLabel: no,
        ),
      );
    }
    // The payments' own later lives: cancelled, corrected, a cheque moved.
    // Their making is already the line above.
    for (final e in later.entries) {
      for (final event in await _auditOn(
        firmId,
        'payments',
        [e.key],
        linked: RecordRef.payment(e.key),
        linkedLabel: e.value,
      )) {
        if (event.kind != HistoryKind.paid) events.add(event);
      }
    }
    return events;
  }

  /// The bills a payment went against, each a tap away.
  Future<List<HistoryEvent>> _billsSettled(
    String firmId,
    String paymentId,
  ) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT pa.created_at_utc, pa.amount_paisa, pa.deleted_at_utc,
                 d.id AS document_id, d.doc_no,
                 u.name AS who, dv.label AS device
          FROM payment_allocations pa
          JOIN documents d ON d.id = pa.document_id
          JOIN users u ON u.id = pa.created_by
          LEFT JOIN devices dv ON dv.id = pa.origin_device_id
          WHERE pa.firm_id = ? AND pa.payment_id = ?
          ''',
          variables: [Variable<String>(firmId), Variable<String>(paymentId)],
        )
        .get();
    return [
      for (final r in rows)
        HistoryEvent(
          atUtcMillis: r.read<int>('created_at_utc'),
          kind: HistoryKind.paid,
          actionCode: r.readNullable<int>('deleted_at_utc') == null
              ? 'SETTLED_BILL'
              : 'SETTLED_BILL_RELEASED',
          who: r.read<String>('who'),
          device: r.readNullable<String>('device'),
          summary: r.read<String>('doc_no'),
          amount: Money.paisa(r.read<int>('amount_paisa')),
          linked: RecordRef.document(r.read<String>('document_id')),
          linkedLabel: r.read<String>('doc_no'),
        ),
    ];
  }

  Future<List<String>> _entriesOf(
    String firmId,
    String column,
    String id,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT id FROM journal_entries WHERE firm_id = ? AND $column = ?',
          variables: [Variable<String>(firmId), Variable<String>(id)],
        )
        .get();
    return [for (final r in rows) r.read<String>('id')];
  }

  // ---------------------------------------------------------------------
  // An item's other traces
  // ---------------------------------------------------------------------

  /// Stock adjusted or written off by hand, and its picture changed. Each
  /// is audited on its own row, not on the item.
  Future<List<HistoryEvent>> _itemExtras(String firmId, String itemId) async {
    final adjusted = await _db
        .customSelect(
          'SELECT id FROM stock_ledger WHERE firm_id = ? AND item_id = ? '
          "AND txn_type IN ('adjustment', 'wastage')",
          variables: [Variable<String>(firmId), Variable<String>(itemId)],
        )
        .get();
    final pictures = await _db
        .customSelect(
          "SELECT id FROM attachments WHERE firm_id = ? AND owner_table = 'items' "
          'AND owner_id = ?',
          variables: [Variable<String>(firmId), Variable<String>(itemId)],
        )
        .get();
    return [
      ...await _auditOn(firmId, 'stock_ledger', [
        for (final r in adjusted) r.read<String>('id'),
      ]),
      ...await _auditOn(firmId, 'attachments', [
        for (final r in pictures) r.read<String>('id'),
      ]),
    ];
  }

  // ---------------------------------------------------------------------
  // Closed books
  // ---------------------------------------------------------------------

  @override
  Future<List<LateArrival>> lateArrivals(String firmId) async {
    // An entry taken in from another device (this device's own rows are
    // either made before the closing or let in with the owner's PIN, which
    // is audited), dated inside books that were already closed when it
    // arrived: some BOOKS_CLOSED row at or before its arrival covered its
    // date. A journal entry is listed only when no bill or payment speaks
    // for it.
    final rows = await _db
        .customSelect(
          '''
          SELECT * FROM (
            SELECT c.entity_table, c.entity_id, c.synced_at_utc,
                   COALESCE(dv.label, c.origin_device_id) AS device,
                   COALESCE(d.doc_no, p.payment_no, je.entry_no) AS number,
                   COALESCE(d.doc_date_local, p.payment_date_local,
                            je.entry_date_local) AS date_local,
                   COALESCE(d.total_paisa, p.amount_paisa,
                            je.total_debit_paisa) AS amount_paisa
            FROM change_log c
            LEFT JOIN devices dv ON dv.id = c.origin_device_id
            LEFT JOIN documents d
              ON c.entity_table = 'documents' AND d.id = c.entity_id
             AND d.doc_type NOT IN ('quotation', 'proforma', 'sale_order',
                                    'purchase_order')
            LEFT JOIN payments p
              ON c.entity_table = 'payments' AND p.id = c.entity_id
             -- Money taken at the counter goes with its bill, which is
             -- listed already.
             AND NOT EXISTS (
               SELECT 1 FROM payment_allocations pa
               WHERE pa.payment_id = p.id AND pa.allocation_mode = 'exact')
            LEFT JOIN journal_entries je
              ON c.entity_table = 'journal_entries' AND je.id = c.entity_id
             AND je.document_id IS NULL AND je.payment_id IS NULL
            WHERE c.firm_id = ?1 AND c.op = 'insert'
              AND c.synced_at_utc IS NOT NULL
              AND c.entity_table IN ('documents', 'payments', 'journal_entries')
              AND c.origin_device_id NOT IN (
                SELECT id FROM devices WHERE is_this_device = 1)
          ) arrived
          WHERE arrived.date_local IS NOT NULL
            AND EXISTS (
              SELECT 1 FROM audit_log a
              WHERE a.firm_id = ?1 AND a.action_code = ?2
                AND a.at_utc <= arrived.synced_at_utc
                AND json_extract(a.after_json, '\$.closed_through')
                    >= arrived.date_local)
          ORDER BY arrived.synced_at_utc DESC
          ''',
          variables: [
            Variable<String>(firmId),
            const Variable<String>(booksClosedAction),
          ],
        )
        .get();
    return [
      for (final r in rows)
        LateArrival(
          record: RecordRef(
            r.read<String>('entity_table'),
            r.read<String>('entity_id'),
          ),
          number: r.read<String>('number'),
          dateLocal: r.read<String>('date_local'),
          arrivedAtUtcMillis: r.read<int>('synced_at_utc'),
          device: r.read<String>('device'),
          amount: switch (r.readNullable<int>('amount_paisa')) {
            final int p => Money.paisa(p),
            null => null,
          },
        ),
    ];
  }

  @override
  Future<String?> lastDayClosed(String firmId) async {
    final row = await _db
        .customSelect(
          'SELECT MAX(at_utc) AS at FROM audit_log '
          "WHERE firm_id = ? AND action_code = 'DAY_CLOSED'",
          variables: [Variable<String>(firmId)],
        )
        .getSingle();
    final at = row.readNullable<int>('at');
    return at == null
        ? null
        : BusinessDate.fromUtc(
            DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
          ).value;
  }

  // ---------------------------------------------------------------------

  static Map<String, Object?> _json(String? text) {
    if (text == null || text.isEmpty) return const {};
    final decoded = jsonDecode(text);
    return decoded is Map<String, Object?> ? decoded : const {};
  }

  static String? _text(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}
