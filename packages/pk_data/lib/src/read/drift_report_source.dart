import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';

import '../db/app_database.dart';
import 'drift_app_queries.dart';

part 'reports/item_stock_queries.dart';
part 'reports/party_queries.dart';
part 'reports/sql_filters.dart';
part 'reports/transaction_queries.dart';

/// The drift implementation of [ReportSource].
///
/// Every figure is summed by SQLite over the period's rows, on the business
/// date column the rows were written with, so a report on a year of a busy
/// shop is a handful of indexed aggregates and never a table read into Dart.
///
/// Since M33 each group of reports keeps its queries in its own part file,
/// as a mixin over the same database: the transaction reports in
/// `reports/transaction_queries.dart`, the party reports in
/// `reports/party_queries.dart`. A later group adds its own part and one
/// more name to the `with` clause, and the filters every group narrows by
/// are written once, in `reports/sql_filters.dart`.
final class DriftReportSource
    with _TransactionQueries, _PartyQueries, _ItemStockQueries
    implements ReportSource {
  const DriftReportSource(this._db);

  @override
  final AppDatabase _db;

  /// The accounts that hold the drawer: Cash in Hand, and whatever account
  /// each cash tender posts into, which a shop with two drawers may have
  /// split out.
  ///
  /// Written once, in `reports/sql_filters.dart`, where the cash flow reads
  /// the same drawer (M33).
  static const _cashAccounts = _drawerAccounts;

  @override
  Future<List<AccountMovement>> accountMovements(
    String firmId,
    ReportPeriod period,
  ) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT a.code, a.name, a.account_type, a.system_key, a.is_direct,
                 SUM(jl.debit_paisa) AS debit, SUM(jl.credit_paisa) AS credit
          FROM journal_lines jl
          JOIN journal_entries je ON je.id = jl.journal_entry_id
          JOIN accounts a ON a.id = jl.account_id
          WHERE je.firm_id = ?1
            AND je.entry_date_local BETWEEN ?2 AND ?3
            AND je.deleted_at_utc IS NULL
            AND jl.deleted_at_utc IS NULL
            -- A year's closing entry (M26) moves its profit into the owner's
            -- equity; it is not itself income or spending, and counting it
            -- would show every closed year as having made nothing.
            AND je.source_type <> 'year_close'
          GROUP BY a.id
          ORDER BY a.code
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(period.from.value),
            Variable<String>(period.to.value),
          ],
          readsFrom: {_db.journalLines, _db.journalEntries, _db.accounts},
        )
        .get();
    return [
      for (final r in rows)
        AccountMovement(
          code: r.read<String>('code'),
          name: r.read<String>('name'),
          type: r.read<String>('account_type'),
          systemKey: r.readNullable<String>('system_key'),
          isDirect: r.read<int>('is_direct') == 1,
          debit: Money.paisa(r.read<int>('debit')),
          credit: Money.paisa(r.read<int>('credit')),
        ),
    ];
  }

  @override
  Future<List<AccountMovement>> accountBalances(
    String firmId,
    BusinessDate asOf,
  ) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT a.code, a.name, a.account_type, a.system_key, a.is_direct,
                 SUM(jl.debit_paisa) AS debit, SUM(jl.credit_paisa) AS credit
          FROM journal_lines jl
          JOIN journal_entries je ON je.id = jl.journal_entry_id
          JOIN accounts a ON a.id = jl.account_id
          WHERE je.firm_id = ?1
            AND je.entry_date_local <= ?2
            AND je.deleted_at_utc IS NULL
            AND jl.deleted_at_utc IS NULL
          GROUP BY a.id
          ORDER BY a.code
          ''',
          variables: [Variable<String>(firmId), Variable<String>(asOf.value)],
          readsFrom: {_db.journalLines, _db.journalEntries, _db.accounts},
        )
        .get();
    return [
      for (final r in rows)
        AccountMovement(
          code: r.read<String>('code'),
          name: r.read<String>('name'),
          type: r.read<String>('account_type'),
          systemKey: r.readNullable<String>('system_key'),
          isDirect: r.read<int>('is_direct') == 1,
          debit: Money.paisa(r.read<int>('debit')),
          credit: Money.paisa(r.read<int>('credit')),
        ),
    ];
  }

  @override
  Future<Money> cashBefore(String firmId, BusinessDate day) async {
    final row = await _db
        .customSelect(
          '''
          SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS cash
          FROM journal_lines jl
          JOIN journal_entries je ON je.id = jl.journal_entry_id
          WHERE je.firm_id = ?1
            AND je.entry_date_local < ?2
            AND je.deleted_at_utc IS NULL
            AND jl.deleted_at_utc IS NULL
            AND jl.account_id IN ($_cashAccounts)
          ''',
          variables: [Variable<String>(firmId), Variable<String>(day.value)],
          readsFrom: {
            _db.journalLines,
            _db.journalEntries,
            _db.accounts,
            _db.paymentAccounts,
          },
        )
        .getSingle();
    return Money.paisa(row.read<int>('cash'));
  }

  @override
  Future<List<CashMovement>> cashMovements(
    String firmId,
    ReportPeriod period,
  ) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT je.entry_date_local, je.entry_no, je.narration,
                 SUM(jl.debit_paisa) AS money_in,
                 SUM(jl.credit_paisa) AS money_out
          FROM journal_lines jl
          JOIN journal_entries je ON je.id = jl.journal_entry_id
          WHERE je.firm_id = ?1
            AND je.entry_date_local BETWEEN ?2 AND ?3
            AND je.deleted_at_utc IS NULL
            AND jl.deleted_at_utc IS NULL
            AND jl.account_id IN ($_cashAccounts)
          GROUP BY je.id
          ORDER BY je.entry_date_local, je.created_at_utc, je.id
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(period.from.value),
            Variable<String>(period.to.value),
          ],
          readsFrom: {
            _db.journalLines,
            _db.journalEntries,
            _db.accounts,
            _db.paymentAccounts,
          },
        )
        .get();
    return [
      for (final r in rows)
        CashMovement(
          date: BusinessDate(r.read<String>('entry_date_local')),
          entryNo: r.read<String>('entry_no'),
          narration: r.readNullable<String>('narration') ?? '',
          moneyIn: Money.paisa(r.read<int>('money_in')),
          moneyOut: Money.paisa(r.read<int>('money_out')),
        ),
    ];
  }

  @override
  Future<List<DayBookEntry>> dayBook(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    // One row per journal entry, as before, now with the paper behind it and
    // the money it moved (M33). The money is read off the entry's own lines
    // against the drawer, the banks and the wallets, so a sale on udhaar
    // moves nothing and a cheque moves money only when it clears. The party
    // is the bill's, or for a receipt, whose entry names no document, the
    // party on its receivable or payable line.
    final q = _Params(firmId, period);
    final byUser = filters.userId == null
        ? ''
        : 'AND je.created_by = ${q.text(filters.userId!)}';
    final rows = await _db
        .customSelect(
          '''
          WITH money AS ($_moneyAccounts)
          SELECT je.id, je.entry_date_local, je.entry_no, je.source_type,
                 je.narration, je.total_debit_paisa, je.document_id,
                 d.doc_type, d.doc_no, d.total_paisa AS doc_total,
                 COALESCE(d.party_name_snapshot, dp.name, (
                   SELECT pp.name FROM journal_lines pl
                   JOIN parties pp ON pp.id = pl.party_id
                   WHERE pl.journal_entry_id = je.id
                     AND pl.deleted_at_utc IS NULL
                   LIMIT 1
                 )) AS party,
                 COALESCE((
                   SELECT SUM(jl.debit_paisa) FROM journal_lines jl
                   WHERE jl.journal_entry_id = je.id
                     AND jl.deleted_at_utc IS NULL
                     AND jl.account_id IN (SELECT id FROM money)
                 ), 0) AS money_in,
                 COALESCE((
                   SELECT SUM(jl.credit_paisa) FROM journal_lines jl
                   WHERE jl.journal_entry_id = je.id
                     AND jl.deleted_at_utc IS NULL
                     AND jl.account_id IN (SELECT id FROM money)
                 ), 0) AS money_out
          FROM journal_entries je
          LEFT JOIN documents d ON d.id = je.document_id
          LEFT JOIN parties dp ON dp.id = d.party_id
          WHERE je.firm_id = ?1
            AND je.entry_date_local BETWEEN ?2 AND ?3
            AND je.deleted_at_utc IS NULL
            $byUser
          ORDER BY je.entry_date_local, je.created_at_utc, je.id
          ''',
          variables: q.variables,
          readsFrom: {
            _db.journalEntries,
            _db.journalLines,
            _db.documents,
            _db.parties,
            _db.accounts,
            _db.paymentAccounts,
          },
        )
        .get();
    return [
      for (final r in rows)
        DayBookEntry(
          date: BusinessDate(r.read<String>('entry_date_local')),
          entryNo: r.read<String>('entry_no'),
          sourceType: r.read<String>('source_type'),
          narration: r.readNullable<String>('narration') ?? '',
          amount: Money.paisa(
            r.readNullable<int>('doc_total') ??
                r.read<int>('total_debit_paisa'),
          ),
          reference: r.readNullable<String>('doc_no'),
          party: r.readNullable<String>('party'),
          moneyIn: Money.paisa(r.read<int>('money_in')),
          moneyOut: Money.paisa(r.read<int>('money_out')),
          documentId: r.readNullable<String>('document_id'),
          docType: r.readNullable<String>('doc_type'),
        ),
    ];
  }

  @override
  Future<List<ItemSales>> itemSales(String firmId, ReportPeriod period) async {
    // Posted bills and posted returns only: a void bill sold nothing, and a
    // quotation or a challan is not a sale until its bill is made.
    final rows = await _db
        .customSelect(
          '''
          SELECT i.name, u.code AS unit_code,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN dl.base_qty_thousandths ELSE 0 END) AS sold,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN dl.base_qty_thousandths ELSE 0 END) AS returned,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN dl.taxable_paisa ELSE 0 END) AS sales,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN dl.taxable_paisa ELSE 0 END) AS returns,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN dl.cost_paisa ELSE 0 END) AS cost,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN dl.cost_paisa ELSE 0 END) AS returned_cost
          FROM document_lines dl
          JOIN documents d ON d.id = dl.document_id
          JOIN items i ON i.id = dl.item_id
          JOIN units u ON u.id = i.base_unit_id
          WHERE d.firm_id = ?1
            AND d.doc_type IN ('sale_invoice', 'sale_return')
            AND d.status = 'posted'
            AND d.doc_date_local BETWEEN ?2 AND ?3
            AND d.deleted_at_utc IS NULL
            AND dl.deleted_at_utc IS NULL
          GROUP BY i.id
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(period.from.value),
            Variable<String>(period.to.value),
          ],
          readsFrom: {_db.documentLines, _db.documents, _db.items, _db.units},
        )
        .get();
    return [
      for (final r in rows)
        ItemSales(
          itemName: r.read<String>('name'),
          unitCode: r.read<String>('unit_code'),
          qtySold: Qty.raw(r.read<int>('sold')),
          qtyReturned: Qty.raw(r.read<int>('returned')),
          salesValue: Money.paisa(r.read<int>('sales')),
          returnsValue: Money.paisa(r.read<int>('returns')),
          cost: Money.paisa(r.read<int>('cost')),
          returnedCost: Money.paisa(r.read<int>('returned_cost')),
        ),
    ];
  }

  @override
  Future<List<StockPosition>> stockPositions(String firmId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT i.name, u.code AS unit_code, i.avg_cost_milli_paisa,
                 COALESCE((SELECT SUM(s.qty_delta_thousandths)
                             FROM stock_ledger s
                            WHERE s.item_id = i.id
                              AND s.deleted_at_utc IS NULL), 0) AS qty
          FROM items i
          JOIN units u ON u.id = i.base_unit_id
          WHERE i.firm_id = ?1
            AND i.track_stock = 1
            AND i.deleted_at_utc IS NULL
          ORDER BY i.name_search
          ''',
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.items, _db.units, _db.stockLedger},
        )
        .get();
    return [
      for (final r in rows)
        StockPosition(
          itemName: r.read<String>('name'),
          unitCode: r.read<String>('unit_code'),
          qty: Qty.raw(r.read<int>('qty')),
          averageCost: Rate.raw(r.read<int>('avg_cost_milli_paisa')),
        ),
    ];
  }

  @override
  Future<Money> inventoryInBooks(String firmId) async {
    final row = await _db
        .customSelect(
          '''
          SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS books
          FROM journal_lines jl
          JOIN accounts a ON a.id = jl.account_id
          WHERE a.firm_id = ?1 AND a.system_key = 'inventory'
            AND jl.deleted_at_utc IS NULL
          ''',
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.journalLines, _db.accounts},
        )
        .getSingle();
    return Money.paisa(row.read<int>('books'));
  }

  @override
  Future<List<DaySales>> dailySales(String firmId, ReportPeriod period) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT doc_date_local,
                 SUM(CASE WHEN doc_type = 'sale_invoice' THEN 1 ELSE 0 END)
                   AS bills,
                 SUM(CASE WHEN doc_type = 'sale_invoice'
                          THEN total_paisa ELSE 0 END) AS sales,
                 SUM(CASE WHEN doc_type = 'sale_return'
                          THEN total_paisa ELSE 0 END) AS returns,
                 SUM(CASE WHEN doc_type = 'sale_invoice'
                          THEN paid_paisa ELSE 0 END) AS received,
                 SUM(CASE WHEN doc_type = 'sale_invoice'
                          THEN total_paisa - paid_paisa ELSE 0 END)
                   AS on_udhaar
          FROM documents
          WHERE firm_id = ?1
            AND doc_type IN ('sale_invoice', 'sale_return')
            AND status = 'posted'
            AND doc_date_local BETWEEN ?2 AND ?3
            AND deleted_at_utc IS NULL
          GROUP BY doc_date_local
          ORDER BY doc_date_local
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(period.from.value),
            Variable<String>(period.to.value),
          ],
          readsFrom: {_db.documents},
        )
        .get();
    return [
      for (final r in rows)
        DaySales(
          date: BusinessDate(r.read<String>('doc_date_local')),
          bills: r.read<int>('bills'),
          sales: Money.paisa(r.read<int>('sales')),
          returns: Money.paisa(r.read<int>('returns')),
          received: Money.paisa(r.read<int>('received')),
          onUdhaar: Money.paisa(r.read<int>('on_udhaar')),
        ),
    ];
  }

  @override
  Future<List<PartyReceivable>> receivables(
    String firmId,
    BusinessDate asOf,
  ) async {
    // The same three parts as the khata's balance -- opening, open bills and
    // charges, less advances -- with the open part split by age on the
    // business date, so each row's total is the figure on that khata.
    final rows = await _db
        .customSelect(
          '''
          SELECT p.name, p.opening_balance_paisa AS opening,
                 COALESCE(SUM(CASE WHEN a.days <= 30 THEN a.owed END), 0)
                   AS d30,
                 COALESCE(SUM(CASE WHEN a.days BETWEEN 31 AND 60
                                   THEN a.owed END), 0) AS d60,
                 COALESCE(SUM(CASE WHEN a.days BETWEEN 61 AND 90
                                   THEN a.owed END), 0) AS d90,
                 COALESCE(SUM(CASE WHEN a.days > 90 THEN a.owed END), 0)
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
            SELECT d.party_id,
                   CAST(julianday(?2) - julianday(d.doc_date_local)
                        AS INTEGER) AS days,
                   d.balance_paisa AS owed
            FROM documents d
            WHERE d.firm_id = ?1
              AND d.doc_type IN ('sale_invoice', 'other_income')
              AND d.status = 'posted'
              AND d.balance_paisa <> 0
              AND d.deleted_at_utc IS NULL
          ) a ON a.party_id = p.id
          WHERE p.firm_id = ?1
            AND p.party_type IN ('customer', 'both')
            AND p.deleted_at_utc IS NULL
          GROUP BY p.id
          ''',
          variables: [Variable<String>(firmId), Variable<String>(asOf.value)],
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
        PartyReceivable(
          name: r.read<String>('name'),
          opening: Money.paisa(r.read<int>('opening')),
          upTo30: Money.paisa(r.read<int>('d30')),
          upTo60: Money.paisa(r.read<int>('d60')),
          upTo90: Money.paisa(r.read<int>('d90')),
          over90: Money.paisa(r.read<int>('over90')),
          advance: Money.paisa(r.read<int>('advance')),
        ),
    ];
  }

  @override
  Future<List<PartyReceivable>> payables(
    String firmId,
    BusinessDate asOf,
  ) async {
    // The khata's payable figure -- deliveries and expenses left on account
    // -- split by age. A supplier's khata has no opening balance or advance
    // of its own yet, so those columns stay empty.
    final rows = await _db
        .customSelect(
          '''
          SELECT p.name,
                 SUM(CASE WHEN a.days <= 30 THEN a.owed ELSE 0 END) AS d30,
                 SUM(CASE WHEN a.days BETWEEN 31 AND 60
                          THEN a.owed ELSE 0 END) AS d60,
                 SUM(CASE WHEN a.days BETWEEN 61 AND 90
                          THEN a.owed ELSE 0 END) AS d90,
                 SUM(CASE WHEN a.days > 90 THEN a.owed ELSE 0 END) AS over90
          FROM (
            SELECT d.party_id,
                   CAST(julianday(?2) - julianday(d.doc_date_local)
                        AS INTEGER) AS days,
                   d.balance_paisa AS owed
            FROM documents d
            WHERE d.firm_id = ?1
              AND d.doc_type IN ('purchase_bill', 'expense')
              AND d.status = 'posted'
              AND d.balance_paisa <> 0
              AND d.party_id IS NOT NULL
              AND d.deleted_at_utc IS NULL
          ) a
          JOIN parties p ON p.id = a.party_id
          WHERE p.deleted_at_utc IS NULL
          GROUP BY p.id
          ''',
          variables: [Variable<String>(firmId), Variable<String>(asOf.value)],
          readsFrom: {_db.parties, _db.documents},
        )
        .get();
    return [
      for (final r in rows)
        PartyReceivable(
          name: r.read<String>('name'),
          opening: Money.zero,
          upTo30: Money.paisa(r.read<int>('d30')),
          upTo60: Money.paisa(r.read<int>('d60')),
          upTo90: Money.paisa(r.read<int>('d90')),
          over90: Money.paisa(r.read<int>('over90')),
          advance: Money.zero,
        ),
    ];
  }

  @override
  Future<List<LotOnHand>> batchesWithExpiry(String firmId) async {
    final lots = await DriftAppQueries(_db).lotsOnHand(firmId);
    return [
      for (final l in lots)
        if (l.expiry != null) l,
    ];
  }

  @override
  Future<List<TaxLine>> taxLines(String firmId, ReportPeriod period) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT t.tax_code, t.tax_kind, t.rate_bp,
                 d.doc_type = 'sale_return' AS is_return,
                 SUM(t.base_paisa) AS base, SUM(t.amount_paisa) AS amount
          FROM document_line_taxes t
          JOIN documents d ON d.id = t.document_id
          WHERE d.firm_id = ?1
            AND d.doc_type IN ('sale_invoice', 'sale_return')
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
            AND d.doc_date_local BETWEEN ?2 AND ?3
          GROUP BY t.tax_code, t.tax_kind, t.rate_bp, is_return
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(period.from.value),
            Variable<String>(period.to.value),
          ],
          readsFrom: {_db.documentLineTaxes, _db.documents},
        )
        .get();
    return [
      for (final r in rows)
        TaxLine(
          code: r.read<String>('tax_code'),
          kind: r.read<String>('tax_kind'),
          rateBp: r.read<int>('rate_bp'),
          base: Money.paisa(r.read<int>('base')),
          amount: Money.paisa(r.read<int>('amount')),
          isReturn: r.read<int>('is_return') == 1,
        ),
    ];
  }

  @override
  Future<Map<String, Money>> monthlyTurnover(
    String firmId,
    ReportPeriod period,
  ) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT substr(doc_date_local, 1, 7) AS month,
                 SUM(total_paisa) AS turnover
          FROM documents
          WHERE firm_id = ?1 AND doc_type = 'sale_invoice'
            AND status = 'posted' AND deleted_at_utc IS NULL
            AND doc_date_local BETWEEN ?2 AND ?3
          GROUP BY month
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(period.from.value),
            Variable<String>(period.to.value),
          ],
          readsFrom: {_db.documents},
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('month'): Money.paisa(r.read<int>('turnover')),
    };
  }

  @override
  Future<List<PurchaseRegisterLine>> purchaseRegister(
    String firmId,
    ReportPeriod period,
  ) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT d.doc_date_local, d.doc_no, d.doc_type,
                 COALESCE(d.party_name_snapshot, p.name) AS supplier,
                 COALESCE(d.party_ntn_snapshot, p.ntn) AS ntn,
                 d.supplier_bill_no, d.taxable_paisa, d.tax_paisa,
                 d.further_tax_paisa, d.total_paisa, d.balance_paisa
          FROM documents d
          LEFT JOIN parties p ON p.id = d.party_id
          WHERE d.firm_id = ?1
            AND d.doc_type IN ('purchase_bill', 'purchase_return')
            AND d.status = 'posted'
            AND d.doc_date_local BETWEEN ?2 AND ?3
            AND d.deleted_at_utc IS NULL
          ORDER BY d.doc_date_local, d.doc_seq, d.id
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(period.from.value),
            Variable<String>(period.to.value),
          ],
          readsFrom: {_db.documents, _db.parties},
        )
        .get();
    return [
      for (final r in rows)
        PurchaseRegisterLine(
          date: BusinessDate(r.read<String>('doc_date_local')),
          docNo: r.read<String>('doc_no'),
          supplier: r.readNullable<String>('supplier') ?? '',
          supplierBillNo: r.readNullable<String>('supplier_bill_no'),
          supplierNtn: r.readNullable<String>('ntn'),
          taxable: Money.paisa(r.read<int>('taxable_paisa')),
          tax: Money.paisa(
            r.read<int>('tax_paisa') + r.read<int>('further_tax_paisa'),
          ),
          total: Money.paisa(r.read<int>('total_paisa')),
          owed: r.read<String>('doc_type') == 'purchase_return'
              ? Money.zero
              : Money.paisa(r.read<int>('balance_paisa')),
          isReturn: r.read<String>('doc_type') == 'purchase_return',
        ),
    ];
  }

  @override
  Future<List<ReportChoice>> choices(
    String firmId,
    ReportFilter filter, {
    String query = '',
    int limit = 50,
  }) async {
    // What a filter can be set to (M33), each a short indexed read: items
    // by idx_items_firm_name, categories by idx_items_category, groups by
    // the parties of the firm, staff by idx_users_firm. The fixed lists (a
    // transaction type, a payment mode, a payment status) are the screen's
    // own, in the shop's language.
    final term = query.trim().toLowerCase();
    final like = '%$term%';
    Future<List<QueryRow>> select(String sql) => _db
        .customSelect(
          sql,
          variables: [
            Variable<String>(firmId),
            Variable<String>(term),
            Variable<String>(like),
            Variable<int>(limit),
          ],
          readsFrom: {_db.items, _db.parties, _db.users},
        )
        .get();

    switch (filter) {
      case ReportFilter.item:
        final rows = await select('''
          SELECT id, name, code FROM items
          WHERE firm_id = ?1 AND deleted_at_utc IS NULL
            AND (?2 = '' OR name_search LIKE ?3 OR LOWER(code) LIKE ?3)
          ORDER BY name_search
          LIMIT ?4
          ''');
        return [
          for (final r in rows)
            ReportChoice(
              id: r.read<String>('id'),
              label: r.read<String>('name'),
              detail: r.readNullable<String>('code'),
            ),
        ];
      case ReportFilter.itemCategory:
        final rows = await select('''
          SELECT DISTINCT TRIM(category) AS name FROM items
          WHERE firm_id = ?1 AND deleted_at_utc IS NULL
            AND category IS NOT NULL AND TRIM(category) <> ''
            AND (?2 = '' OR LOWER(category) LIKE ?3)
          ORDER BY LOWER(TRIM(category))
          LIMIT ?4
          ''');
        return [
          for (final r in rows)
            ReportChoice(
              id: r.read<String>('name'),
              label: r.read<String>('name'),
            ),
        ];
      case ReportFilter.partyGroup:
        final rows = await select('''
          SELECT DISTINCT TRIM(party_group) AS name FROM parties
          WHERE firm_id = ?1 AND deleted_at_utc IS NULL
            AND party_group IS NOT NULL AND TRIM(party_group) <> ''
            AND (?2 = '' OR LOWER(party_group) LIKE ?3)
          ORDER BY LOWER(TRIM(party_group))
          LIMIT ?4
          ''');
        return [
          // Every shop has the parties nobody put in a group, and until a
          // group is used anywhere they are all of them.
          if (term.isEmpty ||
              ReportFilters.ungrouped.toLowerCase().contains(term))
            const ReportChoice(
              id: ReportFilters.ungrouped,
              label: ReportFilters.ungrouped,
            ),
          for (final r in rows)
            ReportChoice(
              id: r.read<String>('name'),
              label: r.read<String>('name'),
            ),
        ];
      case ReportFilter.user:
        final rows = await select('''
          SELECT id, name, role FROM users
          WHERE firm_id = ?1 AND deleted_at_utc IS NULL
            AND (?2 = '' OR LOWER(name) LIKE ?3)
          ORDER BY LOWER(name)
          LIMIT ?4
          ''');
        return [
          for (final r in rows)
            ReportChoice(
              id: r.read<String>('id'),
              label: r.read<String>('name'),
              detail: r.read<String>('role'),
            ),
        ];
      case ReportFilter.party:
        final rows = await select('''
          SELECT id, name, phone FROM parties
          WHERE firm_id = ?1 AND deleted_at_utc IS NULL AND is_active = 1
            AND (?2 = '' OR name_search LIKE ?3 OR phone LIKE ?3)
          ORDER BY name_search
          LIMIT ?4
          ''');
        return [
          for (final r in rows)
            ReportChoice(
              id: r.read<String>('id'),
              label: r.read<String>('name'),
              detail: r.readNullable<String>('phone'),
            ),
        ];
      // M34: the places goods are kept; the other stock filters are the
      // screen's own, a date, a number of days or a typed serial.
      case ReportFilter.location:
        return _placeChoices(firmId, term);
      case ReportFilter.transactionType ||
          ReportFilter.paymentMode ||
          ReportFilter.paymentStatus ||
          ReportFilter.withBalance ||
          ReportFilter.inStockOnly ||
          ReportFilter.asOf ||
          ReportFilter.salesDays ||
          ReportFilter.coverDays ||
          ReportFilter.fastAt ||
          ReportFilter.slowBelow ||
          ReportFilter.serial:
        return const [];
    }
  }
}
