part of '../drift_report_source.dart';

/// The reads behind the staff and time reports and the Z report (M35).
///
/// Every bill carries who made it (`created_by`) and where
/// (`origin_device_id`), and every payment who took it, so each of these is
/// a GROUP BY over rows the counter already writes.
mixin _StaffQueries implements StaffReportSource {
  AppDatabase get _db;

  /// A tender is money taken when it is cleared, or a cheque not yet
  /// presented. A void payment was handed back, a bounced cheque never was
  /// money; neither is counted anywhere in these reports.
  static const _taken = "IN ('cleared', 'pending')";

  @override
  Future<List<StaffSales>> staffSales(
    String firmId,
    ReportPeriod period, {
    required StaffGrouping by,
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId, period);
    final byUser = filters.userId == null
        ? ''
        : 'AND d.created_by = ${q.text(filters.userId!)}';
    final key = by == StaffGrouping.user
        ? 'd.created_by'
        : 'd.origin_device_id';
    final who = by == StaffGrouping.user
        ? 'LEFT JOIN users w ON w.id = s.key'
        : 'LEFT JOIN devices w ON w.id = s.key';
    final name = by == StaffGrouping.user ? 'w.name' : 'w.label';
    final detail = by == StaffGrouping.user ? 'w.role' : 'w.doc_prefix';
    const sale = "d.doc_type = 'sale_invoice' AND d.status = 'posted'";
    const off = '(d.line_discount_paisa + d.bill_discount_paisa)';
    // Rides idx_documents_list for the period's sale bills and returns,
    // voided ones included: a void is counted for whoever rang the bill.
    final rows = await _db
        .customSelect(
          '''
          SELECT s.*, $name AS name, $detail AS detail
          FROM (
            SELECT $key AS key,
                   SUM(CASE WHEN $sale THEN 1 ELSE 0 END) AS bills,
                   SUM(CASE WHEN $sale THEN d.total_paisa ELSE 0 END) AS sales,
                   SUM(CASE WHEN $sale THEN d.subtotal_paisa ELSE 0 END)
                     AS before_discount,
                   SUM(CASE WHEN $sale THEN $off ELSE 0 END) AS discount,
                   SUM(CASE WHEN $sale AND $off > 0 THEN 1 ELSE 0 END)
                     AS discounted,
                   SUM(CASE WHEN d.doc_type = 'sale_return'
                             AND d.status = 'posted' THEN 1 ELSE 0 END)
                     AS returns,
                   SUM(CASE WHEN d.doc_type = 'sale_return'
                             AND d.status = 'posted'
                            THEN d.total_paisa ELSE 0 END) AS returned,
                   SUM(CASE WHEN d.doc_type = 'sale_invoice'
                             AND d.status = 'void' THEN 1 ELSE 0 END)
                     AS voids,
                   SUM(CASE WHEN d.doc_type = 'sale_invoice'
                             AND d.status = 'void'
                            THEN d.total_paisa ELSE 0 END) AS voided
            FROM documents d
            WHERE d.firm_id = ?1
              AND d.doc_type IN ('sale_invoice', 'sale_return')
              AND d.status IN ('posted', 'void')
              AND d.deleted_at_utc IS NULL
              AND d.doc_date_local BETWEEN ?2 AND ?3
              $byUser
            GROUP BY $key
          ) s
          $who
          ''',
          variables: q.variables,
          readsFrom: {_db.documents, _db.users, _db.devices},
        )
        .get();
    return [
      for (final r in rows)
        StaffSales(
          id: r.read<String>('key'),
          name: r.readNullable<String>('name') ?? r.read<String>('key'),
          detail: _blank(r.readNullable<String>('detail')),
          bills: r.read<int>('bills'),
          sales: Money.paisa(r.read<int>('sales')),
          salesBeforeDiscount: Money.paisa(r.read<int>('before_discount')),
          discount: Money.paisa(r.read<int>('discount')),
          discountedBills: r.read<int>('discounted'),
          returns: r.read<int>('returns'),
          returnsValue: Money.paisa(r.read<int>('returned')),
          voids: r.read<int>('voids'),
          voidsValue: Money.paisa(r.read<int>('voided')),
        ),
    ];
  }

  @override
  Future<List<TenderTotal>> tenders(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    // Each payment row is one tender: the sale writer writes a split
    // bill's cash and its JazzCash as two payments, each allocated to the
    // bill as `exact`, which is how a tender at the counter is told from a
    // receipt on a khata. Rides idx_payments_daybook.
    final q = _Params(firmId, period);
    final byUser = filters.userId == null
        ? ''
        : 'AND pm.created_by = ${q.text(filters.userId!)}';
    final rows = await _db
        .customSelect(
          '''
          SELECT t.mode,
                 SUM(t.at_counter) AS counter_count,
                 SUM(CASE WHEN t.at_counter = 1 THEN t.amount_paisa ELSE 0 END)
                   AS counter,
                 SUM(1 - t.at_counter) AS khata_count,
                 SUM(CASE WHEN t.at_counter = 0 THEN t.amount_paisa ELSE 0 END)
                   AS khata
          FROM (
            SELECT pm.mode, pm.amount_paisa,
                   EXISTS (
                     SELECT 1 FROM payment_allocations a
                     WHERE a.payment_id = pm.id
                       AND a.allocation_mode = 'exact'
                       AND a.deleted_at_utc IS NULL
                   ) AS at_counter
            FROM payments pm
            WHERE pm.firm_id = ?1
              AND pm.direction = 'in'
              AND pm.status $_taken
              AND pm.deleted_at_utc IS NULL
              AND pm.payment_date_local BETWEEN ?2 AND ?3
              $byUser
          ) t
          GROUP BY t.mode
          ''',
          variables: q.variables,
          readsFrom: {_db.payments, _db.paymentAllocations},
        )
        .get();
    return [
      for (final r in rows)
        TenderTotal(
          mode: r.read<String>('mode'),
          counterCount: r.read<int>('counter_count'),
          counter: Money.paisa(r.read<int>('counter')),
          khataCount: r.read<int>('khata_count'),
          khata: Money.paisa(r.read<int>('khata')),
        ),
    ];
  }

  @override
  Future<UdhaarGiven> udhaarGiven(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    // What each bill left owing when it was rung up: its total less the
    // tenders taken with it. Not its balance today, which later payments
    // and returns have moved; the night's figure must not change by
    // morning.
    final q = _Params(firmId, period);
    final byUser = filters.userId == null
        ? ''
        : 'AND d.created_by = ${q.text(filters.userId!)}';
    final row = await _db
        .customSelect(
          '''
          SELECT COUNT(*) AS bills, COALESCE(SUM(owing), 0) AS amount
          FROM (
            SELECT d.total_paisa - COALESCE((
                     SELECT SUM(a.amount_paisa) FROM payment_allocations a
                     JOIN payments pm ON pm.id = a.payment_id
                     WHERE a.document_id = d.id
                       AND a.allocation_mode = 'exact'
                       AND a.deleted_at_utc IS NULL
                       AND pm.deleted_at_utc IS NULL
                       AND pm.status $_taken
                   ), 0) AS owing
            FROM documents d
            WHERE d.firm_id = ?1
              AND d.doc_type = 'sale_invoice'
              AND d.status = 'posted'
              AND d.deleted_at_utc IS NULL
              AND d.doc_date_local BETWEEN ?2 AND ?3
              $byUser
          )
          WHERE owing > 0
          ''',
          variables: q.variables,
          readsFrom: {_db.documents, _db.payments, _db.paymentAllocations},
        )
        .getSingle();
    return UdhaarGiven(
      bills: row.read<int>('bills'),
      amount: Money.paisa(row.read<int>('amount')),
    );
  }

  @override
  Future<List<HourSales>> hourlySales(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    // The hour is the bill's own instant, `doc_date_utc`, moved to Pakistan
    // time by a fixed five hours: PKT has kept no daylight saving since
    // 2009 (see `pakistanStandardTime`), so this is exact, and it does not
    // depend on whatever time zone the phone was set to. The day is still
    // the bill's business date, `doc_date_local`, so a bill at 11:30 at
    // night is in the 23:00 hour of the day it was made.
    final q = _Params(firmId, period);
    final byUser = filters.userId == null
        ? ''
        : 'AND d.created_by = ${q.text(filters.userId!)}';
    final offset = pakistanStandardTime.inSeconds;
    final rows = await _db
        .customSelect(
          '''
          -- SQLite divides an INTEGER by an INTEGER as integers: no float.
          SELECT ((d.doc_date_utc / 1000 + $offset) % 86400) / 3600 AS hour, -- arch_check: allow no_floating_point_money — integer division in SQLite
                 COUNT(*) AS bills, SUM(d.total_paisa) AS sales
          FROM documents d
          WHERE d.firm_id = ?1
            AND d.doc_type = 'sale_invoice'
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
            AND d.doc_date_local BETWEEN ?2 AND ?3
            $byUser
          GROUP BY hour
          ORDER BY hour
          ''',
          variables: q.variables,
          readsFrom: {_db.documents},
        )
        .get();
    return [
      for (final r in rows)
        HourSales(
          hour: r.read<int>('hour'),
          bills: r.read<int>('bills'),
          sales: Money.paisa(r.read<int>('sales')),
        ),
    ];
  }

  @override
  Future<DayFigures> dayFigures(String firmId, ReportPeriod period) async {
    final q = _Params(firmId, period);
    const sale = "d.doc_type = 'sale_invoice'";
    const back = "d.doc_type = 'sale_return'";
    final sums = await _db
        .customSelect(
          '''
          SELECT
            SUM(CASE WHEN $sale THEN 1 ELSE 0 END) AS bills,
            COALESCE(SUM(CASE WHEN $sale THEN d.total_paisa END), 0) AS sales,
            SUM(CASE WHEN $back THEN 1 ELSE 0 END) AS returns,
            COALESCE(SUM(CASE WHEN $back THEN d.total_paisa END), 0)
              AS returned,
            COALESCE(SUM(CASE WHEN $sale
                         THEN d.line_discount_paisa + d.bill_discount_paisa
                         END), 0) AS discount,
            COALESCE(SUM(CASE WHEN $sale THEN d.taxable_paisa END), 0)
              AS sales_taxable,
            COALESCE(SUM(CASE WHEN $sale THEN d.cost_paisa END), 0)
              AS sales_cost,
            COALESCE(SUM(CASE WHEN $back THEN d.taxable_paisa END), 0)
              AS returns_taxable,
            COALESCE(SUM(CASE WHEN $back THEN d.cost_paisa END), 0)
              AS returns_cost,
            SUM(CASE WHEN d.doc_type = 'expense' THEN 1 ELSE 0 END)
              AS expenses,
            COALESCE(SUM(CASE WHEN d.doc_type = 'expense'
                              THEN d.total_paisa END), 0) AS expensed,
            (SELECT COUNT(*) FROM document_lines l
              JOIN documents s ON s.id = l.document_id
              WHERE s.firm_id = ?1 AND s.doc_type = 'sale_invoice'
                AND s.status = 'posted' AND s.deleted_at_utc IS NULL
                AND l.deleted_at_utc IS NULL
                AND s.doc_date_local BETWEEN ?2 AND ?3) AS lines_sold
          FROM documents d
          WHERE d.firm_id = ?1
            AND d.doc_type IN ('sale_invoice', 'sale_return', 'expense')
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
            AND d.doc_date_local BETWEEN ?2 AND ?3
          ''',
          variables: q.variables,
          readsFrom: {_db.documents, _db.documentLines},
        )
        .getSingle();
    return DayFigures(
      bills: sums.readNullable<int>('bills') ?? 0,
      sales: Money.paisa(sums.read<int>('sales')),
      returns: sums.readNullable<int>('returns') ?? 0,
      returnsValue: Money.paisa(sums.read<int>('returned')),
      discount: Money.paisa(sums.read<int>('discount')),
      linesSold: sums.read<int>('lines_sold'),
      salesTaxable: Money.paisa(sums.read<int>('sales_taxable')),
      salesCost: Money.paisa(sums.read<int>('sales_cost')),
      returnsTaxable: Money.paisa(sums.read<int>('returns_taxable')),
      returnsCost: Money.paisa(sums.read<int>('returns_cost')),
      expenses: sums.readNullable<int>('expenses') ?? 0,
      expensesValue: Money.paisa(sums.read<int>('expensed')),
      tenders: await tenders(firmId, period),
      udhaar: await udhaarGiven(firmId, period),
      counts: await _drawerCounts(firmId, period),
    );
  }

  /// The day closes (M9) made in [period], from the audit line each one
  /// writes. A close has no business-date column of its own: it is dated
  /// by the instant it was made, and the period's days are turned into
  /// instants on Pakistan time to find it.
  Future<List<DrawerCount>> _drawerCounts(
    String firmId,
    ReportPeriod period,
  ) async {
    final (from, to) = _instants(period);
    final rows = await _db
        .customSelect(
          '''
          SELECT a.at_utc, a.after_json, u.name AS who
          FROM audit_log a
          JOIN users u ON u.id = a.created_by
          WHERE a.firm_id = ?1 AND a.action_code = 'DAY_CLOSED'
            AND a.at_utc >= ?2 AND a.at_utc < ?3
            AND a.deleted_at_utc IS NULL
          ORDER BY a.at_utc, a.id
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<int>(from),
            Variable<int>(to),
          ],
          readsFrom: {_db.auditLog, _db.users},
        )
        .get();
    return [
      for (final r in rows)
        if (_counted(r.readNullable<String>('after_json')) case (
          final expected,
          final counted,
        ))
          DrawerCount(
            time: _clock(r.read<int>('at_utc')),
            expected: expected,
            counted: counted,
            closedBy: r.read<String>('who'),
          ),
    ];
  }

  @override
  Future<List<ChangeRecord>> changes(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    // From the audit log, which every void, return and edit writes inside
    // the transaction that makes it: who did it and when are the log's own
    // envelope, never a column anyone could leave out. Rides
    // idx_audit_action.
    final (from, to) = _instants(period);
    final variables = <Variable<Object>>[
      Variable<String>(firmId),
      Variable<int>(from),
      Variable<int>(to),
    ];
    var byUser = '';
    if (filters.userId != null) {
      variables.add(Variable<String>(filters.userId!));
      byUser = 'AND a.created_by = ?${variables.length}';
    }
    final codes = changeActions.map((c) => "'$c'").join(', ');
    final rows = await _db
        .customSelect(
          '''
          SELECT a.at_utc, a.action_code, a.entity_table, a.entity_id,
                 a.summary, a.after_json, u.name AS who,
                 COALESCE(d.total_paisa, a.amount_paisa) AS amount_paisa,
                 d.doc_no, d.doc_type, d.void_reason, d.notes,
                 pm.payment_no,
                 COALESCE(d.party_name_snapshot, dp.name, pp.name, ep.name)
                   AS party
          FROM audit_log a
          JOIN users u ON u.id = a.created_by
          LEFT JOIN documents d
            ON a.entity_table = 'documents' AND d.id = a.entity_id
          LEFT JOIN parties dp ON dp.id = d.party_id
          LEFT JOIN payments pm
            ON a.entity_table = 'payments' AND pm.id = a.entity_id
          LEFT JOIN parties pp ON pp.id = pm.party_id
          LEFT JOIN parties ep
            ON a.entity_table = 'parties' AND ep.id = a.entity_id
          WHERE a.firm_id = ?1
            AND a.action_code IN ($codes)
            AND a.at_utc >= ?2 AND a.at_utc < ?3
            AND a.deleted_at_utc IS NULL
            $byUser
          ORDER BY a.at_utc, a.id
          ''',
          variables: variables,
          readsFrom: {
            _db.auditLog,
            _db.users,
            _db.documents,
            _db.parties,
            _db.payments,
          },
        )
        .get();
    return [for (final r in rows) _change(r)];
  }

  static ChangeRecord _change(QueryRow r) {
    final action = r.read<String>('action_code');
    final after = _json(r.readNullable<String>('after_json'));
    final isReturn = action == 'SALE_RETURNED' || action == 'PURCHASE_RETURNED';
    final atUtc = r.read<int>('at_utc');
    return ChangeRecord(
      date: BusinessDate.fromUtc(
        DateTime.fromMillisecondsSinceEpoch(atUtc, isUtc: true),
      ),
      time: _clock(atUtc),
      action: action,
      who: r.read<String>('who'),
      summary: r.readNullable<String>('summary') ?? action,
      reference:
          r.readNullable<String>('doc_no') ??
          r.readNullable<String>('payment_no') ??
          _string(after['no']),
      party: _blank(r.readNullable<String>('party')),
      amount: switch (r.readNullable<int>('amount_paisa')) {
        final int p => Money.paisa(p),
        null => null,
      },
      reason: _blank(
        r.readNullable<String>('void_reason') ??
            _string(after['reason']) ??
            (isReturn ? r.readNullable<String>('notes') : null),
      ),
      documentId: r.read<String>('entity_table') == 'documents'
          ? r.read<String>('entity_id')
          : null,
      docType: r.readNullable<String>('doc_type'),
    );
  }

  /// [period]'s first and last day as the instants that bound them on
  /// Pakistan time: from midnight of the first day to midnight after the
  /// last, as epoch milliseconds.
  static (int, int) _instants(ReportPeriod period) {
    int midnight(BusinessDate d) => DateTime.utc(
      d.year,
      d.month,
      d.day,
    ).subtract(pakistanStandardTime).millisecondsSinceEpoch;
    return (midnight(period.from), midnight(period.to.addDays(1)));
  }

  /// `21:40`, Pakistan time.
  static String _clock(int millisUtc) {
    final local = DateTime.fromMillisecondsSinceEpoch(
      millisUtc,
      isUtc: true,
    ).add(pakistanStandardTime);
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static (Money, Money)? _counted(String? afterJson) {
    final after = _json(afterJson);
    final expected = after['expected_paisa'];
    final counted = after['counted_paisa'];
    if (expected is! int || counted is! int) return null;
    return (Money.paisa(expected), Money.paisa(counted));
  }

  static Map<String, Object?> _json(String? text) {
    if (text == null || text.isEmpty) return const {};
    try {
      final value = jsonDecode(text);
      return value is Map<String, Object?> ? value : const {};
    } on FormatException {
      return const {};
    }
  }

  static String? _string(Object? value) => value is String ? value : null;
}
