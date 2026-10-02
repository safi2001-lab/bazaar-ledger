part of '../drift_report_source.dart';

/// The reads behind the business status reports (M35): the bank statement,
/// the discounts, and how customers pay. Each is summed by SQLite over the
/// period's rows on the business date they were written with.
mixin _BusinessQueries implements BusinessReportSource {
  AppDatabase get _db;

  @override
  Future<List<BankStatementAccount>> bankStatements(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    // The accounts first: the one asked for, or every bank and wallet in
    // the chart (the drawer has the Cash Book). "Per bank account" is per
    // ledger account: the books post every bank tender to the account its
    // payment account names, and JazzCash and EasyPaisa share the chart's
    // Mobile wallets unless the shop gave one its own account (M26).
    final q = _Params(firmId);
    final which = filters.accountId == null
        ? 'AND a.id NOT IN (SELECT id FROM drawer)'
        : 'AND a.id = ${q.text(filters.accountId!)}';
    final accounts = await _db
        .customSelect(
          '''
          WITH money AS ($_moneyAccounts), drawer AS ($_drawerAccounts)
          SELECT a.id, a.name, a.system_key,
                 a.id IN (SELECT id FROM drawer) AS is_drawer,
                 (SELECT pa.account_kind FROM payment_accounts pa
                   WHERE pa.ledger_account_id = a.id AND pa.firm_id = ?1
                     AND pa.deleted_at_utc IS NULL
                   ORDER BY pa.is_default DESC LIMIT 1) AS kind
          FROM accounts a
          WHERE a.firm_id = ?1
            AND a.deleted_at_utc IS NULL
            AND a.id IN (SELECT id FROM money)
            $which
          ORDER BY a.code
          ''',
          variables: q.variables,
          readsFrom: {_db.accounts, _db.paymentAccounts},
        )
        .get();

    final statements = <BankStatementAccount>[];
    for (final a in accounts) {
      final id = a.read<String>('id');
      final opening = await _accountBefore(firmId, id, period.from);
      final lines = await _accountLines(firmId, id, period);
      // Without a filter, an account the shop has never used is left out:
      // a statement of nothing for the chart's every wallet is noise.
      if (filters.accountId == null && opening.isZero && lines.isEmpty) {
        continue;
      }
      final systemKey = a.readNullable<String>('system_key');
      statements.add(
        BankStatementAccount(
          accountId: id,
          name: a.read<String>('name'),
          kind: a.read<int>('is_drawer') == 1
              ? 'cash'
              : a.readNullable<String>('kind') ??
                    (systemKey == 'wallet' ? 'wallet' : 'bank'),
          opening: opening,
          lines: lines,
        ),
      );
    }
    return statements;
  }

  /// What the books held in [accountId] before [day].
  Future<Money> _accountBefore(
    String firmId,
    String accountId,
    BusinessDate day,
  ) async {
    final row = await _db
        .customSelect(
          '''
          SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS balance
          FROM journal_lines jl
          JOIN journal_entries je ON je.id = jl.journal_entry_id
          WHERE jl.firm_id = ?1 AND jl.account_id = ?2
            AND jl.deleted_at_utc IS NULL AND je.deleted_at_utc IS NULL
            AND je.entry_date_local < ?3
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(accountId),
            Variable<String>(day.value),
          ],
          readsFrom: {_db.journalLines, _db.journalEntries},
        )
        .getSingle();
    return Money.paisa(row.read<int>('balance'));
  }

  /// Every line against [accountId] in [period], in the order it was
  /// recorded, with the paper and the party behind it. Rides
  /// idx_jl_firm_account.
  Future<List<BankLine>> _accountLines(
    String firmId,
    String accountId,
    ReportPeriod period,
  ) async {
    final q = _Params(firmId, period);
    final account = q.text(accountId);
    final rows = await _db
        .customSelect(
          '''
          SELECT je.entry_date_local, je.entry_no, je.source_type,
                 je.narration, jl.debit_paisa, jl.credit_paisa,
                 je.document_id, d.doc_type, d.doc_no, pm.payment_no,
                 COALESCE(d.party_name_snapshot, dp.name, pp.name, (
                   SELECT op.name FROM journal_lines ol
                   JOIN parties op ON op.id = ol.party_id
                   WHERE ol.journal_entry_id = je.id
                     AND ol.deleted_at_utc IS NULL
                   LIMIT 1
                 )) AS party
          FROM journal_lines jl
          JOIN journal_entries je ON je.id = jl.journal_entry_id
          LEFT JOIN documents d ON d.id = je.document_id
          LEFT JOIN parties dp ON dp.id = d.party_id
          LEFT JOIN payments pm ON pm.id = je.payment_id
          LEFT JOIN parties pp ON pp.id = pm.party_id
          WHERE jl.firm_id = ?1 AND jl.account_id = $account
            AND jl.deleted_at_utc IS NULL AND je.deleted_at_utc IS NULL
            AND je.entry_date_local BETWEEN ?2 AND ?3
          ORDER BY je.entry_date_local, je.created_at_utc, je.id, jl.line_no
          ''',
          variables: q.variables,
          readsFrom: {
            _db.journalLines,
            _db.journalEntries,
            _db.documents,
            _db.parties,
            _db.payments,
          },
        )
        .get();
    return [
      for (final r in rows)
        BankLine(
          date: BusinessDate(r.read<String>('entry_date_local')),
          description:
              _blank(r.readNullable<String>('narration')) ??
              _entryKind(r.read<String>('source_type')),
          reference:
              r.readNullable<String>('doc_no') ??
              r.readNullable<String>('payment_no') ??
              r.read<String>('entry_no'),
          party: _blank(r.readNullable<String>('party')),
          deposit: Money.paisa(r.read<int>('debit_paisa')),
          withdrawal: Money.paisa(r.read<int>('credit_paisa')),
          documentId: r.readNullable<String>('document_id'),
          docType: r.readNullable<String>('doc_type'),
        ),
    ];
  }

  @override
  Future<List<PartyDiscount>> discountsByParty(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    // Discount is the bill's own line and bill discounts as it stored them;
    // what the bill came to before them is its subtotal, the lines at
    // their full rates. Rides idx_documents_list.
    final q = _Params(firmId, period);
    final where = _documentWhere(filters, q);
    const off = '(d.line_discount_paisa + d.bill_discount_paisa)';
    final rows = await _db
        .customSelect(
          '''
          SELECT d.party_id,
                 COALESCE(p.name, MAX(d.party_name_snapshot)) AS name,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice' AND $off > 0
                          THEN 1 ELSE 0 END) AS sale_bills,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice' AND $off > 0
                          THEN d.subtotal_paisa ELSE 0 END) AS sale_before,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN $off ELSE 0 END) AS given,
                 SUM(CASE WHEN d.doc_type = 'purchase_bill' AND $off > 0
                          THEN 1 ELSE 0 END) AS purchase_bills,
                 SUM(CASE WHEN d.doc_type = 'purchase_bill' AND $off > 0
                          THEN d.subtotal_paisa ELSE 0 END) AS purchase_before,
                 SUM(CASE WHEN d.doc_type = 'purchase_bill'
                          THEN $off ELSE 0 END) AS received
          FROM documents d
          LEFT JOIN parties p ON p.id = d.party_id
          WHERE d.firm_id = ?1
            AND d.doc_type IN ('sale_invoice', 'purchase_bill')
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
            AND d.doc_date_local BETWEEN ?2 AND ?3
            $where
          GROUP BY d.party_id
          ''',
          variables: q.variables,
          readsFrom: {
            _db.documents,
            _db.parties,
            _db.paymentAllocations,
            _db.payments,
            _db.documentLines,
            _db.items,
          },
        )
        .get();
    return [
      for (final r in rows)
        PartyDiscount(
          partyId: r.readNullable<String>('party_id'),
          name: r.readNullable<String>('party_id') == null
              ? _walkIns
              : r.readNullable<String>('name') ?? '',
          saleBills: r.read<int>('sale_bills'),
          salesBeforeDiscount: Money.paisa(r.read<int>('sale_before')),
          discountGiven: Money.paisa(r.read<int>('given')),
          purchaseBills: r.read<int>('purchase_bills'),
          purchasesBeforeDiscount: Money.paisa(r.read<int>('purchase_before')),
          discountReceived: Money.paisa(r.read<int>('received')),
        ),
    ];
  }

  @override
  Future<List<PaymentRecord>> paymentRecords(
    String firmId,
    ReportPeriod period,
    BusinessDate today, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    // One row per bill first: what was paid with it at the counter, the
    // last payment and the last return against it since, and the
    // customer's credit days; then summed per customer. A bill paid in full
    // at the counter was never udhaar and is left out. A tender is money
    // when it is cleared or a cheque still pending, as everywhere else.
    final q = _Params(firmId, period);
    final asOf = q.text(today.value);
    final where = _documentWhere(filters, q);
    final rows = await _db
        .customSelect(
          '''
          WITH bill AS (
            SELECT d.id, d.party_id, d.doc_date_local, d.total_paisa,
                   d.balance_paisa,
                   COALESCE(p.credit_days, $defaultCreditDays) AS terms,
                   COALESCE((
                     SELECT SUM(a.amount_paisa) FROM payment_allocations a
                     JOIN payments pm ON pm.id = a.payment_id
                     WHERE a.document_id = d.id
                       AND a.allocation_mode = 'exact'
                       AND a.deleted_at_utc IS NULL
                       AND pm.deleted_at_utc IS NULL
                       AND pm.status IN ('cleared', 'pending')
                   ), 0) AS at_counter,
                   MAX(
                     COALESCE((
                       SELECT MAX(pm.payment_date_local)
                       FROM payment_allocations a
                       JOIN payments pm ON pm.id = a.payment_id
                       WHERE a.document_id = d.id
                         AND a.deleted_at_utc IS NULL
                         AND pm.deleted_at_utc IS NULL
                         AND pm.status IN ('cleared', 'pending')
                     ), d.doc_date_local),
                     COALESCE((
                       SELECT MAX(r.doc_date_local) FROM doc_links l
                       JOIN documents r ON r.id = l.to_document_id
                       WHERE l.from_document_id = d.id
                         AND l.link_type = 'returns'
                         AND l.deleted_at_utc IS NULL
                         AND r.status = 'posted'
                     ), d.doc_date_local)
                   ) AS cleared_on
            FROM documents d
            JOIN parties p ON p.id = d.party_id
            WHERE d.firm_id = ?1
              AND d.doc_type = 'sale_invoice'
              AND d.status = 'posted'
              AND d.deleted_at_utc IS NULL
              AND d.doc_date_local BETWEEN ?2 AND ?3
              $where
          ),
          udhaar AS (
            SELECT *,
                   CAST(julianday(cleared_on) - julianday(doc_date_local)
                        AS INTEGER) AS days,
                   CAST(julianday($asOf) - julianday(doc_date_local)
                        AS INTEGER) AS age
            FROM bill
            WHERE total_paisa > at_counter
          )
          SELECT p.id, p.name, p.phone, MAX(u.terms) AS terms,
                 COUNT(*) AS udhaar_bills,
                 SUM(CASE WHEN u.balance_paisa <= 0 THEN 1 ELSE 0 END)
                   AS settled,
                 SUM(CASE WHEN u.balance_paisa <= 0 THEN u.days ELSE 0 END)
                   AS days,
                 SUM(CASE WHEN u.balance_paisa <= 0 AND u.days > u.terms
                          THEN 1 ELSE 0 END) AS late,
                 SUM(CASE WHEN u.balance_paisa > 0 AND u.age > u.terms
                          THEN 1 ELSE 0 END) AS overdue_bills,
                 SUM(CASE WHEN u.balance_paisa > 0 AND u.age > u.terms
                          THEN u.balance_paisa ELSE 0 END) AS overdue,
                 SUM(CASE WHEN u.balance_paisa > 0
                          THEN u.balance_paisa ELSE 0 END) AS open
          FROM udhaar u
          JOIN parties p ON p.id = u.party_id
          GROUP BY p.id
          ''',
          variables: q.variables,
          readsFrom: {
            _db.documents,
            _db.parties,
            _db.paymentAllocations,
            _db.payments,
            _db.docLinks,
          },
        )
        .get();
    return [
      for (final r in rows)
        PaymentRecord(
          partyId: r.read<String>('id'),
          name: r.read<String>('name'),
          phone: r.readNullable<String>('phone'),
          creditDays: r.read<int>('terms'),
          udhaarBills: r.read<int>('udhaar_bills'),
          settledBills: r.read<int>('settled'),
          daysToSettle: r.read<int>('days'),
          paidLate: r.read<int>('late'),
          overdueBills: r.read<int>('overdue_bills'),
          overdue: Money.paisa(r.read<int>('overdue')),
          open: Money.paisa(r.read<int>('open')),
        ),
    ];
  }

  @override
  Future<List<DefaulterRow>> defaulters(
    String firmId,
    BusinessDate today, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    // Every bill and charge still open, aged on the business date against
    // the customer's credit days. Rides idx_documents_open_balance.
    final q = _Params(firmId);
    final asOf = q.text(today.value);
    final where = _documentWhere(filters, q);
    final due =
        'julianday($asOf) - julianday(d.doc_date_local) > '
        'COALESCE(p.credit_days, $defaultCreditDays)';
    final rows = await _db
        .customSelect(
          '''
          SELECT p.id, p.name, p.phone, p.credit_limit_paisa,
                 COALESCE(p.credit_days, $defaultCreditDays) AS terms,
                 SUM(d.balance_paisa) AS open,
                 SUM(CASE WHEN $due THEN d.balance_paisa ELSE 0 END)
                   AS overdue,
                 SUM(CASE WHEN $due THEN 1 ELSE 0 END) AS overdue_bills,
                 MIN(CASE WHEN $due THEN d.doc_date_local END) AS oldest,
                 (SELECT MAX(pm.payment_date_local) FROM payments pm
                   WHERE pm.party_id = p.id AND pm.direction = 'in'
                     AND pm.status IN ('cleared', 'pending')
                     AND pm.deleted_at_utc IS NULL) AS last_paid
          FROM documents d
          JOIN parties p ON p.id = d.party_id
          WHERE d.firm_id = ?1
            AND d.doc_type IN ('sale_invoice', 'other_income')
            AND d.status = 'posted'
            AND d.balance_paisa > 0
            AND d.deleted_at_utc IS NULL
            AND p.deleted_at_utc IS NULL
            $where
          GROUP BY p.id
          HAVING overdue > 0
          ''',
          variables: q.variables,
          readsFrom: {_db.documents, _db.parties, _db.payments},
        )
        .get();
    return [
      for (final r in rows)
        DefaulterRow(
          partyId: r.read<String>('id'),
          name: r.read<String>('name'),
          phone: r.readNullable<String>('phone'),
          creditDays: r.read<int>('terms'),
          open: Money.paisa(r.read<int>('open')),
          overdue: Money.paisa(r.read<int>('overdue')),
          overdueBills: r.read<int>('overdue_bills'),
          oldestBill: BusinessDate(r.read<String>('oldest')),
          creditLimit: switch (r.readNullable<int>('credit_limit_paisa')) {
            final int p => Money.paisa(p),
            null => null,
          },
          lastPayment: switch (r.readNullable<String>('last_paid')) {
            final String d => BusinessDate(d),
            null => null,
          },
        ),
    ];
  }

  /// What a money-account or expense-head filter can be set to (M35).
  Future<List<ReportChoice>> _accountChoices(
    String firmId,
    ReportFilter filter, {
    required String term,
    required int limit,
  }) async {
    final like = '%$term%';
    final which = filter == ReportFilter.moneyAccount
        ? 'a.id IN (SELECT id FROM money)'
        : "a.account_type = 'expense' AND COALESCE(a.system_key, '') NOT IN "
              "('cogs', 'purchase_returns', 'discount_received')";
    final rows = await _db
        .customSelect(
          '''
          WITH money AS ($_moneyAccounts)
          SELECT a.id, a.name, a.code,
                 (SELECT GROUP_CONCAT(pa.name, ', ') FROM payment_accounts pa
                   WHERE pa.ledger_account_id = a.id AND pa.firm_id = ?1
                     AND pa.deleted_at_utc IS NULL) AS tenders
          FROM accounts a
          WHERE a.firm_id = ?1 AND a.deleted_at_utc IS NULL AND $which
            AND (?2 = '' OR LOWER(a.name) LIKE ?3)
          ORDER BY a.code
          LIMIT ?4
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(term),
            Variable<String>(like),
            Variable<int>(limit),
          ],
          readsFrom: {_db.accounts, _db.paymentAccounts},
        )
        .get();
    return [
      for (final r in rows)
        ReportChoice(
          id: r.read<String>('id'),
          label: r.read<String>('name'),
          detail:
              _blank(r.readNullable<String>('tenders')) ??
              r.read<String>('code'),
        ),
    ];
  }
}

/// The walk-in customers, one row between them.
const _walkIns = 'Walk-in customers';

/// [s], or null when it is empty or only spaces.
String? _blank(String? s) => s == null || s.trim().isEmpty ? null : s.trim();

/// A journal entry's kind, as a statement line reads when it has no words
/// of its own.
String _entryKind(String sourceType) => switch (sourceType) {
  'sale' => 'Sale',
  'sale_return' => 'Sale return',
  'purchase' => 'Purchase',
  'purchase_return' => 'Purchase return',
  'payment' => 'Payment',
  'expense' => 'Expense',
  // A charge on a khata moves no money, so money into an account under
  // other income is the shop's own (M47, M58).
  'other_income' => 'Other income',
  'opening' => 'Opening balance',
  'adjustment' => 'Adjustment',
  'reversal' => 'Cancelled entry',
  'manual' => 'Journal voucher',
  _ => sourceType,
};
