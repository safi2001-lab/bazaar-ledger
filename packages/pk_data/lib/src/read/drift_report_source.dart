import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';

import '../db/app_database.dart';

/// The drift implementation of [ReportSource].
///
/// Every figure is summed by SQLite over the period's rows, on the business
/// date column the rows were written with, so a report on a year of a busy
/// shop is a handful of indexed aggregates and never a table read into Dart.
final class DriftReportSource implements ReportSource {
  const DriftReportSource(this._db);

  final AppDatabase _db;

  /// The accounts that hold the drawer: Cash in Hand, and whatever account
  /// each cash tender posts into, which a shop with two drawers may have
  /// split out.
  static const _cashAccounts = '''
    SELECT id FROM accounts WHERE firm_id = ?1 AND system_key = 'cash_in_hand'
    UNION
    SELECT ledger_account_id FROM payment_accounts
     WHERE firm_id = ?1 AND mode_label = 'cash'
  ''';

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
  Future<List<DayBookEntry>> dayBook(String firmId, ReportPeriod period) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT entry_date_local, entry_no, source_type, narration,
                 total_debit_paisa
          FROM journal_entries
          WHERE firm_id = ?1
            AND entry_date_local BETWEEN ?2 AND ?3
            AND deleted_at_utc IS NULL
          ORDER BY entry_date_local, created_at_utc, id
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(period.from.value),
            Variable<String>(period.to.value),
          ],
          readsFrom: {_db.journalEntries},
        )
        .get();
    return [
      for (final r in rows)
        DayBookEntry(
          date: BusinessDate(r.read<String>('entry_date_local')),
          entryNo: r.read<String>('entry_no'),
          sourceType: r.read<String>('source_type'),
          narration: r.readNullable<String>('narration') ?? '',
          amount: Money.paisa(r.read<int>('total_debit_paisa')),
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
}
