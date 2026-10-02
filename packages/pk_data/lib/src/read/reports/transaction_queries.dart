part of '../drift_report_source.dart';

/// The reads behind the transaction reports (M33): bills, every
/// transaction, the money that moved, and the stock a trading account
/// needs. Each is one statement over the period's rows, on the business
/// date the rows were written with, riding the indexes the counter's own
/// lists use.
mixin _TransactionQueries implements TransactionReportSource {
  AppDatabase get _db;

  @override
  Future<List<BillRow>> bills(
    String firmId,
    ReportPeriod period, {
    required Set<String> docTypes,
    ReportFilters filters = ReportFilters.none,
  }) async {
    if (docTypes.isEmpty) return const [];
    final q = _Params(firmId, period);
    final types = [for (final t in docTypes) q.text(t)].join(', ');
    final where = _documentWhere(filters, q);
    // Rides idx_documents_list (firm_id, doc_type, doc_date_local, id): a
    // year of a busy shop's bills is a range read, never a table scan. How
    // each bill was paid is the distinct modes of the payments allocated to
    // it, by idx_alloc_doc.
    final rows = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_date_local, d.doc_no, d.doc_type, d.party_id,
                 COALESCE(d.party_name_snapshot, p.name, '') AS party,
                 d.taxable_paisa, d.tax_paisa + d.further_tax_paisa AS tax,
                 d.total_paisa, d.paid_paisa, d.balance_paisa, d.cost_paisa,
                 u.name AS entered_by,
                 (SELECT GROUP_CONCAT(DISTINCT pm.mode)
                    FROM payment_allocations pa
                    JOIN payments pm ON pm.id = pa.payment_id
                   WHERE pa.document_id = d.id
                     AND pa.deleted_at_utc IS NULL
                     AND pm.deleted_at_utc IS NULL
                     AND pm.status <> 'void') AS modes
          FROM documents d
          LEFT JOIN parties p ON p.id = d.party_id
          LEFT JOIN users u ON u.id = d.created_by
          WHERE d.firm_id = ?1
            AND d.doc_type IN ($types)
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
            AND d.doc_date_local BETWEEN ?2 AND ?3
            $where
          ORDER BY d.doc_date_local, d.doc_seq, d.id
          ''',
          variables: q.variables,
          readsFrom: {
            _db.documents,
            _db.parties,
            _db.users,
            _db.paymentAllocations,
            _db.payments,
            _db.documentLines,
            _db.items,
          },
        )
        .get();
    return [
      for (final r in rows)
        BillRow(
          documentId: r.read<String>('id'),
          date: BusinessDate(r.read<String>('doc_date_local')),
          docNo: r.read<String>('doc_no'),
          docType: r.read<String>('doc_type'),
          partyId: r.readNullable<String>('party_id'),
          party: r.read<String>('party'),
          taxable: Money.paisa(r.read<int>('taxable_paisa')),
          tax: Money.paisa(r.read<int>('tax')),
          total: Money.paisa(r.read<int>('total_paisa')),
          paid: Money.paisa(r.read<int>('paid_paisa')),
          balance: Money.paisa(r.read<int>('balance_paisa')),
          cost: Money.paisa(r.read<int>('cost_paisa')),
          modes: _modes(r.readNullable<String>('modes')),
          enteredBy: r.readNullable<String>('entered_by'),
        ),
    ];
  }

  /// In the order a filter offers them, each once.
  static List<String> _modes(String? concatenated) {
    if (concatenated == null || concatenated.isEmpty) return const [];
    final found = concatenated.split(',').toSet();
    return [
      for (final m in PaymentMode.all)
        if (found.contains(m)) m,
      ...found.where((m) => !PaymentMode.all.contains(m)),
    ];
  }

  @override
  Future<List<TransactionRow>> transactions(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId, period);
    final type = filters.transactionType;
    final documents = type == null || !TransactionType.isPayment(type);
    final payments = type == null || TransactionType.isPayment(type);

    final docWhere = StringBuffer(_documentWhere(filters, q));
    if (type != null && documents) {
      docWhere.write(' AND d.doc_type = ${q.text(type)}');
    }

    // A payment taken with a bill at the counter is part of that bill:
    // DriftSaleWriter allocates it to the bill as `exact`, which is the same
    // mark the void writer tells a tender from a later receipt by. Anything
    // else is a payment the shop took or made on its own, and is listed.
    final payWhere = StringBuffer();
    if (filters.partyId != null) {
      payWhere.write(' AND pm.party_id = ${q.text(filters.partyId!)}');
    }
    if (filters.userId != null) {
      payWhere.write(' AND pm.created_by = ${q.text(filters.userId!)}');
    }
    if (filters.paymentMode != null) {
      payWhere.write(' AND pm.mode = ${q.text(filters.paymentMode!)}');
    }
    if (filters.partyGroup != null) {
      payWhere.write(
        filters.partyGroup == ReportFilters.ungrouped
            ? ' AND pm.party_id IS NOT NULL'
                  " AND COALESCE(TRIM(pp.party_group), '') = ''"
            : ' AND TRIM(pp.party_group) = '
                  '${q.text(filters.partyGroup!.trim())}',
      );
    }
    if (type == TransactionType.paymentIn) {
      payWhere.write(" AND pm.direction = 'in'");
    } else if (type == TransactionType.paymentOut) {
      payWhere.write(" AND pm.direction = 'out'");
    }
    // A filter a payment cannot meet leaves the payments out altogether.
    final paymentsApply =
        payments &&
        filters.itemId == null &&
        filters.category == null &&
        filters.paymentStatus == null;

    final rows = await _db
        .customSelect(
          '''
          SELECT * FROM (
            SELECT d.id AS id, d.doc_type AS type,
                   d.doc_date_local AS date_local, d.doc_no AS number,
                   d.party_id AS party_id,
                   COALESCE(d.party_name_snapshot, p.name, '') AS party,
                   d.total_paisa AS total, d.paid_paisa AS paid,
                   d.balance_paisa AS balance, d.status AS status,
                   d.created_at_utc AS recorded
            FROM documents d
            LEFT JOIN parties p ON p.id = d.party_id
            WHERE ${documents ? '1' : '0'}
              AND d.firm_id = ?1
              AND d.status IN ('posted', 'void')
              AND d.deleted_at_utc IS NULL
              AND d.doc_date_local BETWEEN ?2 AND ?3
              $docWhere

            UNION ALL

            SELECT pm.id AS id,
                   CASE pm.direction WHEN 'in' THEN 'payment_in'
                        ELSE 'payment_out' END AS type,
                   pm.payment_date_local AS date_local,
                   pm.payment_no AS number,
                   pm.party_id AS party_id,
                   COALESCE(pp.name, '') AS party,
                   pm.amount_paisa AS total, pm.amount_paisa AS paid,
                   0 AS balance, pm.status AS status,
                   pm.created_at_utc AS recorded
            FROM payments pm
            LEFT JOIN parties pp ON pp.id = pm.party_id
            WHERE ${paymentsApply ? '1' : '0'}
              AND pm.firm_id = ?1
              AND pm.deleted_at_utc IS NULL
              AND pm.payment_date_local BETWEEN ?2 AND ?3
              AND NOT EXISTS (
                SELECT 1 FROM payment_allocations ta
                WHERE ta.payment_id = pm.id
                  AND ta.allocation_mode = 'exact'
                  AND ta.deleted_at_utc IS NULL
              )
              $payWhere
          )
          ORDER BY date_local, recorded, id
          ''',
          variables: q.variables,
          readsFrom: {
            _db.documents,
            _db.parties,
            _db.payments,
            _db.paymentAllocations,
            _db.documentLines,
            _db.items,
          },
        )
        .get();
    return [
      for (final r in rows)
        TransactionRow(
          id: r.read<String>('id'),
          date: BusinessDate(r.read<String>('date_local')),
          number: r.read<String>('number'),
          type: r.read<String>('type'),
          partyId: r.readNullable<String>('party_id'),
          party: r.read<String>('party'),
          total: Money.paisa(r.read<int>('total')),
          paid: Money.paisa(r.read<int>('paid')),
          balance: Money.paisa(r.read<int>('balance')),
          status: r.read<String>('status'),
        ),
    ];
  }

  @override
  Future<List<MoneyFlow>> moneyFlows(String firmId, ReportPeriod period) async {
    // Every line against a money account in the period, summed by what
    // moved it and by drawer or bank. Rides idx_je_date for the period's
    // entries and idx_jl_seq for their lines.
    final rows = await _db
        .customSelect(
          '''
          WITH money AS ($_moneyAccounts), drawer AS ($_drawerAccounts)
          SELECT je.source_type AS kind,
                 jl.account_id IN (SELECT id FROM drawer) AS in_cash,
                 SUM(jl.debit_paisa) AS money_in,
                 SUM(jl.credit_paisa) AS money_out
          FROM journal_entries je
          JOIN journal_lines jl ON jl.journal_entry_id = je.id
          WHERE je.firm_id = ?1
            AND je.entry_date_local BETWEEN ?2 AND ?3
            AND je.deleted_at_utc IS NULL
            AND jl.deleted_at_utc IS NULL
            AND jl.account_id IN (SELECT id FROM money)
          GROUP BY kind, in_cash
          ''',
          variables: _Params(firmId, period).variables,
          readsFrom: {
            _db.journalEntries,
            _db.journalLines,
            _db.accounts,
            _db.paymentAccounts,
          },
        )
        .get();
    return [
      for (final r in rows)
        MoneyFlow(
          kind: r.read<String>('kind'),
          inCash: r.read<int>('in_cash') == 1,
          moneyIn: Money.paisa(r.read<int>('money_in')),
          moneyOut: Money.paisa(r.read<int>('money_out')),
        ),
    ];
  }

  @override
  Future<MoneyBalance> moneyBefore(String firmId, BusinessDate day) async {
    final rows = await _db
        .customSelect(
          '''
          WITH money AS ($_moneyAccounts), drawer AS ($_drawerAccounts)
          SELECT jl.account_id IN (SELECT id FROM drawer) AS in_cash,
                 SUM(jl.debit_paisa - jl.credit_paisa) AS balance
          FROM journal_lines jl
          JOIN journal_entries je ON je.id = jl.journal_entry_id
          WHERE jl.firm_id = ?1
            AND jl.account_id IN (SELECT id FROM money)
            AND jl.deleted_at_utc IS NULL
            AND je.deleted_at_utc IS NULL
            AND je.entry_date_local < ?2
          GROUP BY in_cash
          ''',
          variables: [Variable<String>(firmId), Variable<String>(day.value)],
          readsFrom: {
            _db.journalEntries,
            _db.journalLines,
            _db.accounts,
            _db.paymentAccounts,
          },
        )
        .get();
    var cash = Money.zero;
    var bank = Money.zero;
    for (final r in rows) {
      final balance = Money.paisa(r.read<int>('balance'));
      if (r.read<int>('in_cash') == 1) {
        cash = balance;
      } else {
        bank = balance;
      }
    }
    return MoneyBalance(cash: cash, bank: bank);
  }

  @override
  Future<StockFigures> stockFigures(String firmId, ReportPeriod period) async {
    // The Inventory account before the period and at its end, and what the
    // period's deliveries and returns to suppliers moved through it, read
    // by the document behind each entry so that a cancelled delivery nets
    // itself out. Rides idx_jl_firm_account.
    final row = await _db
        .customSelect(
          '''
          SELECT
            COALESCE(SUM(CASE WHEN je.entry_date_local < ?2
                              THEN jl.debit_paisa - jl.credit_paisa END), 0)
              AS opening,
            COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS closing,
            COALESCE(SUM(CASE WHEN je.entry_date_local >= ?2
                               AND d.doc_type = 'purchase_bill'
                              THEN jl.debit_paisa - jl.credit_paisa END), 0)
              AS purchases,
            COALESCE(SUM(CASE WHEN je.entry_date_local >= ?2
                               AND d.doc_type = 'purchase_return'
                              THEN jl.credit_paisa - jl.debit_paisa END), 0)
              AS purchase_returns
          FROM journal_lines jl
          JOIN accounts a ON a.id = jl.account_id
          JOIN journal_entries je ON je.id = jl.journal_entry_id
          LEFT JOIN documents d ON d.id = je.document_id
          WHERE jl.firm_id = ?1
            AND a.system_key = 'inventory'
            AND jl.deleted_at_utc IS NULL
            AND je.deleted_at_utc IS NULL
            AND je.entry_date_local <= ?3
          ''',
          variables: _Params(firmId, period).variables,
          readsFrom: {
            _db.journalLines,
            _db.journalEntries,
            _db.accounts,
            _db.documents,
          },
        )
        .getSingle();
    return StockFigures(
      opening: Money.paisa(row.read<int>('opening')),
      purchases: Money.paisa(row.read<int>('purchases')),
      purchaseReturns: Money.paisa(row.read<int>('purchase_returns')),
      closing: Money.paisa(row.read<int>('closing')),
    );
  }
}
