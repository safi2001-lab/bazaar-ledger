part of '../drift_report_source.dart';

/// The reads behind the udhaar reports in the hub (M58), on the udhaar
/// pack's own terms (M38, M44).
///
/// A bill's due date is the pack's `dueOnSql`, and an open bill the rows
/// its `dueAging` reads — a sale or a charge on a khata, posted, with
/// something left on it — so this report's buckets add up to that figure,
/// and a test holds them to it. The opening balance and the advance are
/// read as Udhaar by age (M8) reads them, so each customer's owed is the
/// khata's balance. What was let go is the pack's own `allowances`.
mixin _UdhaarReportQueries implements UdhaarReportSource {
  AppDatabase get _db;

  @override
  Future<List<DueAgeingRow>> dueAgeing(
    String firmId,
    BusinessDate asOf, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId);
    final day = q.text(asOf.value);
    final group = switch (filters.partyGroup) {
      null => '',
      ReportFilters.ungrouped => " AND COALESCE(TRIM(p.party_group), '') = ''",
      final g => ' AND TRIM(p.party_group) = ${q.text(g.trim())}',
    };
    // Each open bill's days past due, bucketed by the database: a
    // wholesaler's ten thousand open bills are summed in SQLite, never read
    // into the phone. Rides idx_documents_open_balance for the bills and the
    // party's own lines for the advance.
    final rows = await _db
        .customSelect(
          '''
          SELECT p.id, p.name,
                 CASE WHEN p.party_type IN ('customer', 'both')
                      THEN p.opening_balance_paisa ELSE 0 END AS opening,
                 COALESCE(SUM(CASE WHEN b.late <= 0 THEN b.owed END), 0)
                   AS not_due,
                 COALESCE(SUM(CASE WHEN b.late BETWEEN 1 AND 30
                                   THEN b.owed END), 0) AS d30,
                 COALESCE(SUM(CASE WHEN b.late BETWEEN 31 AND 60
                                   THEN b.owed END), 0) AS d60,
                 COALESCE(SUM(CASE WHEN b.late BETWEEN 61 AND 90
                                   THEN b.owed END), 0) AS d90,
                 COALESCE(SUM(CASE WHEN b.late > 90 THEN b.owed END), 0)
                   AS over90,
                 COALESCE((
                   SELECT SUM(jl.credit_paisa - jl.debit_paisa)
                   FROM journal_lines jl
                   JOIN accounts acc ON acc.id = jl.account_id
                   WHERE jl.party_id = p.id
                     AND jl.firm_id = p.firm_id
                     AND acc.system_key = 'customer_advances'
                     AND jl.deleted_at_utc IS NULL
                 ), 0) AS advance
          FROM parties p
          LEFT JOIN (
            SELECT d.party_id AS party_id, d.balance_paisa AS owed,
                   CAST(julianday($day) - julianday($dueOnSql) AS INTEGER)
                     AS late
            FROM documents d
            JOIN parties p ON p.id = d.party_id
            WHERE d.firm_id = ?1
              AND d.doc_type IN ('sale_invoice', 'other_income')
              AND d.balance_paisa > 0
              AND d.status NOT IN ('void', 'draft')
              AND d.deleted_at_utc IS NULL
          ) b ON b.party_id = p.id
          WHERE p.firm_id = ?1
            AND ((p.party_type IN ('customer', 'both')
                  AND p.deleted_at_utc IS NULL)
                 OR b.party_id IS NOT NULL)
            $group
          GROUP BY p.id
          ''',
          variables: q.variables,
          readsFrom: {
            _db.parties,
            _db.documents,
            _db.journalLines,
            _db.accounts,
          },
        )
        .get();
    return [
      for (final r in rows)
        DueAgeingRow(
          partyId: r.read<String>('id'),
          name: r.read<String>('name'),
          opening: Money.paisa(r.read<int>('opening')),
          notYetDue: Money.paisa(r.read<int>('not_due')),
          upTo30: Money.paisa(r.read<int>('d30')),
          upTo60: Money.paisa(r.read<int>('d60')),
          upTo90: Money.paisa(r.read<int>('d90')),
          over90: Money.paisa(r.read<int>('over90')),
          advance: Money.paisa(r.read<int>('advance')),
        ),
    ];
  }

  @override
  Future<List<AllowanceRow>> allowances(
    String firmId,
    ReportPeriod period, {
    required AllowanceKind kind,
  }) => DriftUdhaarQueries(_db).allowances(
    firmId,
    kind: kind,
    fromDateLocal: period.from.value,
    toDateLocal: period.to.value,
  );
}
