import 'package:pk_domain/pk_domain.dart';

import 'builders.dart';
import 'business_reports.dart';
import 'collections_reports.dart'; // M54
import 'filters.dart';
import 'item_stock_reports.dart';
import 'mobile_reports.dart'; // M50
import 'money_owed_reports.dart';
import 'order_reports.dart';
import 'party_builders.dart';
import 'period.dart';
import 'pharmacy_reports.dart';
import 'report_source.dart';
import 'report_table.dart';
import 'transaction_builders.dart';

/// The reports a shop can run.
///
/// Adding one (M33 onward) is four things, and the compiler or a test holds
/// each of them to account: a value here, a builder that turns rows into a
/// table, a read on the [ReportSource] that fetches the rows, and a case in
/// [ReportEngine.run]. The app's report registry then gives it a name, a
/// group, an icon, a plan and the filters it takes, and a test fails until
/// every value here has exactly one entry there.
enum ReportKind {
  profitAndLoss,
  salesTax,
  tajirDost,
  salesByDay,
  salesByItem,
  expenses,
  cashBook,
  dayBook,

  /// As it stands now; the period is ignored.
  stockValue,

  /// Aged as of today; the period is ignored.
  receivables,

  /// Aged as of today; the period is ignored.
  payables,

  /// As of today; the period is ignored.
  trialBalance,

  /// As of today; the period is ignored.
  balanceSheet,

  /// As of today; the period is ignored.
  expiry,

  /// Every purchase bill in the period (M24).
  purchaseRegister,

  /// Every sale bill in the period, with what is paid and owed (M33).
  saleReport,

  /// Every purchase bill in the period, the same way (M33).
  purchaseReport,

  /// Every document and payment of every kind (M33).
  allTransactions,

  /// What each sale bill made over its cost (M33).
  billWiseProfit,

  /// Money in and out by what moved it, cash and bank (M33).
  cashflow,

  /// One party's account over the period (M33).
  partyStatement,

  /// Profit by customer (M33).
  partyProfitAndLoss,

  /// Every party with its balance each way; as of today (M33).
  allParties,

  /// What one party bought and sold, item by item (M33).
  partyItems,

  /// Sales and purchases by party (M33).
  salePurchaseByParty,

  /// Sales and purchases by party group (M33).
  salePurchaseByPartyGroup,

  // M34: item and stock. Those read as of a day take the `asOf` filter
  // where they declare it, and today otherwise.

  /// Every item's stock, prices and book value; as of a day (M34).
  stockSummary,

  /// Who bought and supplied one item (M34).
  itemByParty,

  /// Profit by item (M34).
  itemProfitAndLoss,

  /// Profit by item category (M34).
  categoryProfitAndLoss,

  /// What is at or below its floor, and how much to order; as of today
  /// (M34).
  lowStock,

  /// One item's stock, day by day (M34).
  itemDetail,

  /// Every item's opening, movements and closing, valued (M34).
  stockDetail,

  /// Sales and purchases by item category (M34).
  salePurchaseByCategory,

  /// Stock and its value by item category; as of a day (M34).
  stockSummaryByCategory,

  /// Every batch on the shelf; as of today (M34).
  itemBatches,

  /// Every serial or IMEI number, here or gone; as of today (M34).
  itemSerials,

  /// What came off each item's price (M34).
  itemDiscount,

  /// Goods moved between the shop floor, godowns and vans (M34).
  stockTransfers,

  /// Every production run (M34).
  productionRegister,

  /// Items banded by how they sell; as of today (M34).
  fastSlowStock,

  /// What is on the shelf by how long it has been there; as of a day (M34).
  stockAgeing,

  // M35: business status, staff and time, the Z report, taxes, expenses
  // and orders. Built in business_reports.dart.

  /// One day's sales, money, udhaar, expenses and drawer: the Z report.
  dailySummary,

  /// A bank or wallet account's deposits and withdrawals.
  bankStatement,

  /// Discount given and received, by party.
  discountByParty,

  /// Discount given, by whoever rang the bills.
  discountByCashier,

  /// Bills, sales, discounts, returns and voids by cashier.
  salesByCashier,

  /// The same by counter.
  salesByCounter,

  /// Sales and collections by payment mode, each tender its own line.
  paymentModes,

  /// Sales by the hour of the day.
  hourlySales,

  /// How long each customer takes to pay.
  paymentPerformance,

  /// Customers past due; as of today.
  defaulters,

  /// Voids, returns and edits, with who and why.
  changedBills,

  /// Output against input tax, by party.
  taxReport,

  /// Tax by rate and regime.
  taxRateReport,

  /// Sales by HS code.
  salesByHsCode,

  /// The sales register in FBR's Annex-C columns.
  annexC,

  /// The purchase register in FBR's Annex-A columns.
  annexA,

  /// Every expense voucher.
  expenseTransactions,

  /// Expenses by head, direct and indirect.
  expenseCategories,

  /// Expenses by what they were for.
  expenseItems,

  /// Quotations not yet billed; as of today.
  openQuotations,

  /// Challans not yet billed; as of today.
  openChallans,

  /// The items on both; as of today.
  openOrderItems,

  // M41: purchase and sale orders, in `order_reports.dart`.

  /// Purchase orders still to arrive; as of today.
  openPurchaseOrders,

  /// Sale orders still to go out, with their advances; as of today.
  openSaleOrders,

  /// The items on both, ordered, done and still to come; as of today.
  orderItemsDue,

  // M58: money owed both ways, built in money_owed_reports.dart.

  /// One loan's statement, or every loan the shop has taken on one page.
  loanStatement,

  /// Customers' udhaar by days past its due date; as of today.
  receivablesByDueDate,

  /// Udhaar written off or let go to settle, with who and why.
  badDebts,
  // M49: the pharmacy pack, in `pharmacy_reports.dart`.

  /// Every movement of every Schedule medicine, with its prescription.
  scheduleRegister,
  // M50: the mobile-shop pack, in `mobile_reports.dart`.

  /// Every used phone bought over the counter, with its seller's CNIC.
  usedPhonesRegister,

  /// Every phone sold on qist: paid, still to pay, overdue; as of today.
  qistInstalments,
  // M54: in `collections_reports.dart`.

  /// What each customer should pay this week: falling due and promised.
  expectedCollections,
}

/// Runs a report: reads its rows from a [ReportSource] and builds the table.
final class ReportEngine {
  const ReportEngine(this.source, {this.canSeeCosts = true});

  /// Whether [kind] is as of today rather than over a period.
  static bool isAsOfToday(ReportKind kind) =>
      kind == ReportKind.stockValue ||
      kind == ReportKind.receivables ||
      kind == ReportKind.payables ||
      kind == ReportKind.trialBalance ||
      kind == ReportKind.balanceSheet ||
      kind == ReportKind.expiry ||
      kind == ReportKind.allParties ||
      // M34: item and stock.
      kind == ReportKind.stockSummary ||
      kind == ReportKind.lowStock ||
      kind == ReportKind.stockSummaryByCategory ||
      kind == ReportKind.itemBatches ||
      kind == ReportKind.itemSerials ||
      kind == ReportKind.fastSlowStock ||
      kind == ReportKind.stockAgeing ||
      // M35
      businessReportsAsOfToday.contains(kind) ||
      // M58
      moneyOwedReportsAsOfToday.contains(kind) ||
      kind == ReportKind.qistInstalments || // M50
      collectionsReportKinds.contains(kind); // M54

  /// Whether [kind] is about what goods cost through and through: the cost
  /// of sales, a profit per bill, a shelf at cost. A role that may not see
  /// costs (a cashier, under the roles in `roles.dart`) is refused these
  /// here, at the one door every screen goes through, not only by a hidden
  /// tile. Any other report that carries a cost column, Sales by item, still
  /// runs for them, with the cost, profit and margin columns struck out.
  static bool showsCost(ReportKind kind) => switch (kind) {
    ReportKind.profitAndLoss ||
    ReportKind.stockValue ||
    ReportKind.trialBalance ||
    ReportKind.balanceSheet ||
    ReportKind.expiry ||
    ReportKind.billWiseProfit ||
    ReportKind.partyProfitAndLoss ||
    // M34: item and stock.
    ReportKind.itemProfitAndLoss ||
    ReportKind.categoryProfitAndLoss ||
    ReportKind.stockAgeing => true,
    _ => false,
  };

  final ReportSource source;

  /// Whether whoever is running reports may see what goods cost.
  final bool canSeeCosts;

  /// Builds [kind] for [period], narrowed by [filters]. The table says what
  /// it was narrowed by, so no export of it can be mistaken for the whole.
  Future<ReportTable> run(
    ReportKind kind, {
    required String firmId,
    required ReportPeriod period,
    required BusinessDate today,
    ReportFilters filters = ReportFilters.none,
  }) async {
    if (!canSeeCosts && showsCost(kind)) {
      throw const PermissionDenied(
        Permission.seeCosts,
        'This report shows what the goods cost, which this role does not see.',
      );
    }
    final table = await _build(kind, firmId, period, today, filters);
    final seen = canSeeCosts ? table : table.withoutCostColumns();
    return seen.withFilters(filters.describe());
  }

  /// What [filter] can be set to in this shop, matching [query]: the
  /// screen's pickers read through here, behind the same permission as the
  /// reports themselves.
  Future<List<ReportChoice>> choices(
    String firmId,
    ReportFilter filter, {
    String query = '',
    int limit = 50,
  }) => source.choices(firmId, filter, query: query, limit: limit);

  /// The headline figures of [kind] for the period before [period], to set
  /// beside this period's as "vs last month" (M33). Empty for a report that
  /// is as of today, which has no period before it.
  Future<List<ReportFigure>> previousSummary(
    ReportKind kind, {
    required String firmId,
    required ReportPeriod period,
    required BusinessDate today,
    ReportFilters filters = ReportFilters.none,
  }) async {
    if (isAsOfToday(kind) || kind == ReportKind.partyStatement) return const [];
    final before = await run(
      kind,
      firmId: firmId,
      period: period.previous,
      today: today,
      filters: filters,
    );
    return before.summary;
  }

  Future<ReportTable> _build(
    ReportKind kind,
    String firmId,
    ReportPeriod period,
    BusinessDate today,
    ReportFilters filters,
  ) async => switch (kind) {
    ReportKind.profitAndLoss => profitAndLoss(
      period,
      await source.accountMovements(firmId, period),
      stock: await source.stockFigures(firmId, period),
    ),
    ReportKind.expenses => expensesByHead(
      period,
      await source.accountMovements(firmId, period),
    ),
    ReportKind.salesTax => salesTaxSummary(
      period,
      await source.taxLines(firmId, period),
    ),
    ReportKind.tajirDost => tajirDost(
      period,
      await source.monthlyTurnover(firmId, period),
    ),
    ReportKind.salesByDay => salesByDay(
      period,
      await source.dailySales(firmId, period),
    ),
    ReportKind.receivables => receivablesByAge(
      today,
      await source.receivables(firmId, today),
    ),
    ReportKind.trialBalance => trialBalance(
      today,
      await source.accountBalances(firmId, today),
    ),
    ReportKind.balanceSheet => balanceSheet(
      today,
      await source.accountBalances(firmId, today),
    ),
    ReportKind.expiry => expiryReport(
      today,
      await source.batchesWithExpiry(firmId),
    ),
    ReportKind.payables => payablesByAge(
      today,
      await source.payables(firmId, today),
    ),
    ReportKind.salesByItem => salesByItem(
      period,
      await source.itemSales(firmId, period),
    ),
    ReportKind.cashBook => cashBook(
      period,
      await source.cashBefore(firmId, period.from),
      await source.cashMovements(firmId, period),
    ),
    ReportKind.dayBook => dayBook(
      period,
      await source.dayBook(firmId, period, filters: filters),
    ),
    ReportKind.purchaseRegister => purchaseRegister(
      period,
      await source.purchaseRegister(firmId, period),
    ),
    ReportKind.stockValue => stockValue(
      today,
      await source.stockPositions(firmId),
      await source.inventoryInBooks(firmId),
    ),
    ReportKind.saleReport => saleReport(
      period,
      await source.bills(
        firmId,
        period,
        docTypes: const {TransactionType.sale},
        filters: filters,
      ),
    ),
    ReportKind.purchaseReport => purchaseReport(
      period,
      await source.bills(
        firmId,
        period,
        docTypes: const {TransactionType.purchase},
        filters: filters,
      ),
    ),
    ReportKind.billWiseProfit => billWiseProfit(
      period,
      await source.bills(
        firmId,
        period,
        docTypes: const {TransactionType.sale, TransactionType.saleReturn},
        filters: filters,
      ),
    ),
    ReportKind.allTransactions => allTransactions(
      period,
      await source.transactions(firmId, period, filters: filters),
    ),
    ReportKind.cashflow => cashflow(
      period,
      await source.moneyBefore(firmId, period.from),
      await source.moneyFlows(firmId, period),
    ),
    ReportKind.partyStatement => partyStatementReport(
      period: period,
      ledgers: filters.partyId == null
          ? null
          : await source.partyLedgers(firmId, filters.partyId!),
    ),
    ReportKind.partyProfitAndLoss => partyProfitAndLoss(
      period,
      await source.partyTrade(firmId, period, filters: filters),
    ),
    ReportKind.allParties => allParties(
      today,
      await source.partyBalances(firmId, filters: filters),
      withBalanceOnly: filters.withBalanceOnly,
    ),
    ReportKind.partyItems => partyItemsReport(
      period,
      await source.partyItems(firmId, period, filters: filters),
      partyName: filters.partyId == null ? null : filters.partyName,
    ),
    ReportKind.salePurchaseByParty => salePurchaseByParty(
      period,
      await source.partyTrade(firmId, period, filters: filters),
    ),
    ReportKind.salePurchaseByPartyGroup => salePurchaseByPartyGroup(
      period,
      await source.partyTrade(firmId, period, filters: filters),
    ),
    // M34: item and stock.
    ReportKind.stockSummary ||
    ReportKind.itemByParty ||
    ReportKind.itemProfitAndLoss ||
    ReportKind.categoryProfitAndLoss ||
    ReportKind.lowStock ||
    ReportKind.itemDetail ||
    ReportKind.stockDetail ||
    ReportKind.salePurchaseByCategory ||
    ReportKind.stockSummaryByCategory ||
    ReportKind.itemBatches ||
    ReportKind.itemSerials ||
    ReportKind.itemDiscount ||
    ReportKind.stockTransfers ||
    ReportKind.productionRegister ||
    ReportKind.fastSlowStock ||
    ReportKind.stockAgeing => buildItemStockReport(
      source,
      kind,
      firmId,
      period,
      filters.asOf ?? today,
      filters,
    ),
    ReportKind.dailySummary ||
    ReportKind.bankStatement ||
    ReportKind.discountByParty ||
    ReportKind.discountByCashier ||
    ReportKind.salesByCashier ||
    ReportKind.salesByCounter ||
    ReportKind.paymentModes ||
    ReportKind.hourlySales ||
    ReportKind.paymentPerformance ||
    ReportKind.defaulters ||
    ReportKind.changedBills ||
    ReportKind.taxReport ||
    ReportKind.taxRateReport ||
    ReportKind.salesByHsCode ||
    ReportKind.annexC ||
    ReportKind.annexA ||
    ReportKind.expenseTransactions ||
    ReportKind.expenseCategories ||
    ReportKind.expenseItems ||
    ReportKind.openQuotations ||
    ReportKind.openChallans ||
    ReportKind.openOrderItems => buildBusinessReport(
      kind,
      source: source,
      firmId: firmId,
      period: period,
      today: today,
      filters: filters,
      canSeeCosts: canSeeCosts,
    ),
    // M41
    ReportKind.openPurchaseOrders ||
    ReportKind.openSaleOrders ||
    ReportKind.orderItemsDue => buildOrderDocumentReport(
      kind,
      source: source,
      firmId: firmId,
      today: today,
      filters: filters,
    ),
    // M58: money owed both ways.
    ReportKind.loanStatement ||
    ReportKind.receivablesByDueDate ||
    ReportKind.badDebts => buildMoneyOwedReport(
      kind,
      source: source,
      firmId: firmId,
      period: period,
      today: today,
      filters: filters,
    ),
    // M49
    ReportKind.scheduleRegister => buildPharmacyReport(
      kind,
      source: source,
      firmId: firmId,
      period: period,
      filters: filters,
    ),
    // M50
    ReportKind.usedPhonesRegister ||
    ReportKind.qistInstalments => buildMobileReport(
      kind,
      source: source,
      firmId: firmId,
      period: period,
      today: today,
      filters: filters,
    ),
    // M54
    ReportKind.expectedCollections => buildCollectionsReport(
      kind,
      source: source,
      firmId: firmId,
      today: today,
      filters: filters,
    ),
  };
}
