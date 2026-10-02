part of '../drift_report_source.dart';

/// The reads behind the party reports (M33): trade by party, every party's
/// balance, a party's items, and a party's ledgers.
mixin _PartyQueries implements PartyReportSource {
  AppDatabase get _db;

  @override
  Future<List<PartyTrade>> partyTrade(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId, period);
    final where = _documentWhere(filters, q);
    // One pass over the period's bills and returns both ways, grouped by
    // party: idx_documents_list for the range, the party by its key.
    final rows = await _db
        .customSelect(
          '''
          SELECT d.party_id, p.name, p.party_group,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN d.total_paisa ELSE 0 END) AS sales,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN d.total_paisa ELSE 0 END) AS sale_returns,
                 SUM(CASE WHEN d.doc_type = 'purchase_bill'
                          THEN d.total_paisa ELSE 0 END) AS purchases,
                 SUM(CASE WHEN d.doc_type = 'purchase_return'
                          THEN d.total_paisa ELSE 0 END) AS purchase_returns,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN d.taxable_paisa ELSE 0 END) AS sales_taxable,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN d.taxable_paisa ELSE 0 END) AS returns_taxable,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN d.cost_paisa ELSE 0 END) AS cost,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN d.cost_paisa ELSE 0 END) AS returned_cost
          FROM documents d
          LEFT JOIN parties p ON p.id = d.party_id
          WHERE d.firm_id = ?1
            AND d.doc_type IN ('sale_invoice', 'sale_return',
                               'purchase_bill', 'purchase_return')
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
        PartyTrade(
          partyId: r.readNullable<String>('party_id'),
          name: r.readNullable<String>('name') ?? 'Walk-in customers',
          group: r.readNullable<String>('party_group'),
          sales: Money.paisa(r.read<int>('sales')),
          saleReturns: Money.paisa(r.read<int>('sale_returns')),
          purchases: Money.paisa(r.read<int>('purchases')),
          purchaseReturns: Money.paisa(r.read<int>('purchase_returns')),
          salesTaxable: Money.paisa(r.read<int>('sales_taxable')),
          returnsTaxable: Money.paisa(r.read<int>('returns_taxable')),
          cost: Money.paisa(r.read<int>('cost')),
          returnedCost: Money.paisa(r.read<int>('returned_cost')),
        ),
    ];
  }

  @override
  Future<List<PartyBalanceRow>> partyBalances(
    String firmId, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId);
    final where = StringBuffer();
    if (filters.partyId != null) {
      where.write(' AND p.id = ${q.text(filters.partyId!)}');
    }
    if (filters.partyGroup != null) {
      where.write(
        filters.partyGroup == ReportFilters.ungrouped
            ? " AND COALESCE(TRIM(p.party_group), '') = ''"
            : ' AND TRIM(p.party_group) = ${q.text(filters.partyGroup!.trim())}',
      );
    }
    // The khata's balance, by the same three parts the khata adds up
    // (DriftAppQueries' party select): the opening, the bills and charges
    // still open, less what the shop is holding for them. Written out again
    // here because that select is the khata screen's own, and a test ties
    // the two to the paisa for every party. Each part rides
    // idx_documents_party or idx_jl_party.
    final rows = await _db
        .customSelect(
          '''
          SELECT * FROM (
            SELECT p.id, p.name, p.party_type, p.phone, p.party_group,
                   p.credit_limit_paisa,
                   p.opening_balance_paisa
                     + COALESCE((
                         SELECT SUM(d.balance_paisa) FROM documents d
                         WHERE d.party_id = p.id
                           AND d.firm_id = p.firm_id
                           AND d.doc_type IN ('sale_invoice', 'other_income')
                           AND d.status = 'posted'
                           AND d.deleted_at_utc IS NULL
                       ), 0)
                     - COALESCE((
                         SELECT SUM(jl.credit_paisa - jl.debit_paisa)
                         FROM journal_lines jl
                         JOIN accounts a ON a.id = jl.account_id
                         WHERE jl.party_id = p.id
                           AND jl.firm_id = p.firm_id
                           AND a.system_key = 'customer_advances'
                           AND jl.deleted_at_utc IS NULL
                       ), 0) AS receivable,
                   COALESCE((
                       SELECT SUM(d.balance_paisa) FROM documents d
                       WHERE d.party_id = p.id
                         AND d.firm_id = p.firm_id
                         AND d.doc_type IN ('purchase_bill', 'expense')
                         AND d.status = 'posted'
                         AND d.deleted_at_utc IS NULL
                     ), 0) AS payable
            FROM parties p
            WHERE p.firm_id = ?1
              AND p.deleted_at_utc IS NULL
              AND p.is_active = 1
              $where
          )
          ${filters.withBalanceOnly ? 'WHERE receivable <> 0 OR payable <> 0' : ''}
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
        PartyBalanceRow(
          partyId: r.read<String>('id'),
          name: r.read<String>('name'),
          partyType: r.read<String>('party_type'),
          phone: _blank(r.readNullable<String>('phone')),
          group: _blank(r.readNullable<String>('party_group')),
          receivable: Money.paisa(r.read<int>('receivable')),
          payable: Money.paisa(r.read<int>('payable')),
          creditLimit: r.readNullable<int>('credit_limit_paisa') == null
              ? null
              : Money.paisa(r.read<int>('credit_limit_paisa')),
        ),
    ];
  }

  static String? _blank(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();

  @override
  Future<List<PartyItemTrade>> partyItems(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId, period);
    final where = StringBuffer();
    if (filters.partyId != null) {
      where.write(' AND d.party_id = ${q.text(filters.partyId!)}');
    }
    if (filters.itemId != null) {
      where.write(' AND dl.item_id = ${q.text(filters.itemId!)}');
    }
    if (filters.category != null) {
      where.write(
        ' AND TRIM(i.category) = ${q.text(filters.category!.trim())}',
      );
    }
    // Lines of the party's bills and returns both ways, by item. With a
    // party, idx_documents_party finds their documents; without, the
    // period's range on idx_documents_list.
    final rows = await _db
        .customSelect(
          '''
          SELECT COALESCE(i.name, dl.item_name_snapshot) AS name,
                 COALESCE(u.code, dl.unit_code_snapshot) AS unit_code,
                 SUM(CASE d.doc_type
                       WHEN 'sale_invoice' THEN dl.base_qty_thousandths
                       WHEN 'sale_return' THEN -dl.base_qty_thousandths
                       ELSE 0 END) AS sold,
                 SUM(CASE d.doc_type
                       WHEN 'sale_invoice' THEN dl.taxable_paisa
                       WHEN 'sale_return' THEN -dl.taxable_paisa
                       ELSE 0 END) AS sale_amount,
                 SUM(CASE d.doc_type
                       WHEN 'purchase_bill' THEN dl.base_qty_thousandths
                       WHEN 'purchase_return' THEN -dl.base_qty_thousandths
                       ELSE 0 END) AS bought,
                 -- A delivery's lines keep their total and no taxable
                 -- figure of their own, so before tax is total less tax,
                 -- which is the same thing on a return's lines.
                 SUM(CASE d.doc_type
                       WHEN 'purchase_bill'
                         THEN dl.line_total_paisa - dl.tax_paisa
                       WHEN 'purchase_return'
                         THEN -(dl.line_total_paisa - dl.tax_paisa)
                       ELSE 0 END) AS purchase_amount
          FROM documents d
          JOIN document_lines dl ON dl.document_id = d.id
          LEFT JOIN items i ON i.id = dl.item_id
          LEFT JOIN units u ON u.id = i.base_unit_id
          WHERE d.firm_id = ?1
            AND d.doc_type IN ('sale_invoice', 'sale_return',
                               'purchase_bill', 'purchase_return')
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
            AND dl.deleted_at_utc IS NULL
            AND d.doc_date_local BETWEEN ?2 AND ?3
            $where
          GROUP BY COALESCE(dl.item_id, dl.item_name_snapshot)
          ''',
          variables: q.variables,
          readsFrom: {_db.documents, _db.documentLines, _db.items, _db.units},
        )
        .get();
    return [
      for (final r in rows)
        PartyItemTrade(
          itemName: r.read<String>('name'),
          unitCode: r.read<String>('unit_code'),
          qtySold: Qty.raw(r.read<int>('sold')),
          saleAmount: Money.paisa(r.read<int>('sale_amount')),
          qtyPurchased: Qty.raw(r.read<int>('bought')),
          purchaseAmount: Money.paisa(r.read<int>('purchase_amount')),
        ),
    ];
  }

  @override
  Future<PartyLedgers?> partyLedgers(String firmId, String partyId) async {
    final party = await _db
        .customSelect(
          'SELECT name, party_type FROM parties '
          'WHERE id = ?1 AND firm_id = ?2 AND deleted_at_utc IS NULL',
          variables: [Variable<String>(partyId), Variable<String>(firmId)],
          readsFrom: {_db.parties},
        )
        .getSingleOrNull();
    if (party == null) return null;
    return PartyLedgers(
      name: party.read<String>('name'),
      partyType: party.read<String>('party_type'),
      receivable: await _customerLedger(firmId, partyId),
      // The supplier side is the khata's own ledger (M8, M24), unchanged: it
      // already reads every delivery, expense and return off the payable
      // line each posted, so its running figure is what the khata shows.
      payable: await DriftAppQueries(
        _db,
      ).payablesLedger(firmId, partyId, limit: _wholeLedger),
    );
  }

  /// Far more entries than one party will ever have: the statement needs
  /// the whole ledger to know what was owed before the period.
  static const _wholeLedger = 1 << 30;

  /// What a customer owes, entry by entry, oldest first, with the balance
  /// after each (M33).
  ///
  /// The khata's own ledger (DriftAppQueries.partyLedger, M24) and one
  /// thing more: goods the customer brought back. A return that came off
  /// a bill, or was kept as an advance, takes that much off what they owe,
  /// and a statement without it ran ahead of the khata's balance by exactly
  /// the return. What was handed back over the counter there and then moved
  /// nothing on the khata, so only the rest is listed: the total less the
  /// refund. The khata's list is the khata screen's to change; this one
  /// lands on the khata's balance to the paisa, and a test says so.
  Future<List<LedgerEntry>> _customerLedger(
    String firmId,
    String partyId,
  ) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT id, kind, reference, date_local, amount_paisa FROM (
            SELECT d.id AS id,
                   CASE d.doc_type WHEN 'other_income' THEN 'charge'
                        ELSE 'sale' END AS kind,
                   CASE d.doc_type WHEN 'other_income'
                        THEN d.doc_no || ' · ' || COALESCE(d.notes, '')
                        ELSE d.doc_no END AS reference,
                   d.doc_date_local AS date_local,
                   d.total_paisa AS amount_paisa,
                   d.created_at_utc AS recorded
            FROM documents d
            WHERE d.firm_id = ?1 AND d.party_id = ?2
              AND d.doc_type IN ('sale_invoice', 'other_income')
              AND d.status NOT IN ('void', 'draft')
              AND d.deleted_at_utc IS NULL

            UNION ALL

            SELECT d.id AS id,
                   'return' AS kind,
                   d.doc_no AS reference,
                   d.doc_date_local AS date_local,
                   -(d.total_paisa - d.paid_paisa) AS amount_paisa,
                   d.created_at_utc AS recorded
            FROM documents d
            WHERE d.firm_id = ?1 AND d.party_id = ?2
              AND d.doc_type = 'sale_return'
              AND d.status NOT IN ('void', 'draft')
              AND d.deleted_at_utc IS NULL
              AND d.total_paisa <> d.paid_paisa

            UNION ALL

            SELECT p.id AS id,
                   'payment' AS kind,
                   p.payment_no AS reference,
                   p.payment_date_local AS date_local,
                   -p.amount_paisa AS amount_paisa,
                   p.created_at_utc AS recorded
            FROM payments p
            WHERE p.firm_id = ?1 AND p.party_id = ?2
              AND p.direction = 'in'
              AND p.status <> 'void'
              AND p.deleted_at_utc IS NULL

            UNION ALL

            SELECT je.id AS id,
                   'bounce' AS kind,
                   p.payment_no AS reference,
                   je.entry_date_local AS date_local,
                   p.amount_paisa AS amount_paisa,
                   je.created_at_utc AS recorded
            FROM journal_entries je
            JOIN payments p ON p.id = je.payment_id
            WHERE p.firm_id = ?1 AND p.party_id = ?2
              AND p.direction = 'in'
              AND p.status = 'bounced'
              AND je.source_type = 'reversal'
              AND je.deleted_at_utc IS NULL

            UNION ALL

            SELECT pa.id AS id,
                   'opening' AS kind,
                   'Opening balance' AS reference,
                   COALESCE(pa.opening_balance_as_of_local,
                            (SELECT MIN(d0.doc_date_local) FROM documents d0
                             WHERE d0.party_id = pa.id),
                            '2000-01-01') AS date_local,
                   pa.opening_balance_paisa AS amount_paisa,
                   pa.created_at_utc AS recorded
            FROM parties pa
            WHERE pa.firm_id = ?1 AND pa.id = ?2
              AND pa.opening_balance_paisa <> 0
              AND pa.deleted_at_utc IS NULL
          )
          ORDER BY date_local, recorded, id
          ''',
          variables: [Variable<String>(firmId), Variable<String>(partyId)],
          readsFrom: {
            _db.documents,
            _db.payments,
            _db.journalEntries,
            _db.parties,
          },
        )
        .get();
    var running = Money.zero;
    return [
      for (final r in rows)
        () {
          final amount = Money.paisa(r.read<int>('amount_paisa'));
          running += amount;
          return LedgerEntry(
            id: r.read<String>('id'),
            kind: r.read<String>('kind'),
            reference: r.read<String>('reference'),
            dateLocal: r.read<String>('date_local'),
            amount: amount,
            balanceAfter: running,
          );
        }(),
    ];
  }
}
