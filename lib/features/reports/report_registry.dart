import 'package:flutter/material.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../l10n/app_strings.dart';

/// Every report the hub lists, and everything the app needs to know about
/// each: where it sits, what it is called, what it opens with, which plan
/// it needs and what it can be narrowed by (M33).
///
/// One entry per [ReportKind], and a test fails until there is exactly one.
/// Adding a report, from M34 on, is:
///
///   1. a value in `ReportKind` (packages/pk_reports/lib/src/report_engine.dart);
///   2. a builder that turns rows into a `ReportTable`, beside the others
///      for its group in pk_reports, with its own row types and a read on
///      the group's source interface (`TransactionReportSource`,
///      `PartyReportSource`, or a new one added to `ReportSource`);
///   3. that read in SQL, in the group's part file under
///      packages/pk_data/lib/src/read/reports/, narrowed by
///      `_documentWhere` where it reads documents;
///   4. a case in `ReportEngine._build`, which the compiler insists on;
///   5. one entry in the group's list below, with its name and hint in both
///      ARB files.
///
/// A report that reads well drawn (M46) declares how in [ReportEntry.chart]:
/// a trend over days or hours, the top ten as bars, or parts of a whole as
/// a ring, naming the table's own columns. Its screen then offers Table or
/// Chart, and the chart is read off the finished table, so it cannot
/// disagree with it.
///
/// A report about what goods cost through and through also goes into
/// `ReportEngine.showsCost`, which closes it to a role that may not see
/// costs; a cost column in an ordinary report is a `ReportColumn` marked
/// `isCost`, which the engine strikes out for them instead. Headline tiles
/// are the builder's `summary`, and a row that is a bill or a party carries
/// a `ReportLink` so a tap opens it.
///
/// The groups follow the shop apps this market already knows, in their
/// order. A group with nothing in it is not shown, so a group whose
/// reports are still to come (business status, orders, loans) is declared
/// here and appears the day its first entry does.
enum ReportGroup {
  transaction,
  party,
  itemStock,
  businessStatus,
  taxes,
  expense,
  orders,
  loans,
  // M49
  pharmacy,
  // M50
  mobile,
  // M65
  staff,
}

/// A group's heading, as the shop reads it.
String reportGroupName(AppStrings s, ReportGroup group) => switch (group) {
  ReportGroup.transaction => s.reportGroupTransaction,
  ReportGroup.party => s.reportGroupParty,
  ReportGroup.itemStock => s.reportGroupItemStock,
  ReportGroup.businessStatus => s.reportGroupBusiness,
  ReportGroup.taxes => s.reportGroupTaxes,
  ReportGroup.expense => s.reportGroupExpense,
  ReportGroup.orders => s.reportGroupOrders,
  ReportGroup.loans => s.reportGroupLoans,
  ReportGroup.pharmacy => s.reportGroupPharmacy, // M49
  ReportGroup.mobile => s.reportGroupMobile, // M50
  ReportGroup.staff => s.reportGroupStaff, // M65
};

/// One report in the hub.
final class ReportEntry {
  const ReportEntry({
    required this.kind,
    required this.group,
    required this.name,
    required this.hint,
    required this.icon,
    this.plan,
    this.filters = const {},
    this.defaultPreset = DatePreset.thisMonth,
    this.chart,
  });

  final ReportKind kind;
  final ReportGroup group;
  final String Function(AppStrings s) name;

  /// One line under the name: what the report answers.
  final String Function(AppStrings s) hint;
  final IconData icon;

  /// The paid feature that opens it, or null for a report every plan has.
  /// The premium reports map onto the one feature the plans already sell
  /// for the books, rather than a tier of their own.
  final PlanFeature? plan;

  /// What it can be narrowed by, offered as chips on its screen and passed
  /// to the engine; anything else is dropped before it is run.
  final Set<ReportFilter> filters;

  /// The period it opens on the first time; after that, the last one the
  /// shopkeeper chose for it.
  final DatePreset defaultPreset;

  /// How it is drawn when the shopkeeper turns it into a chart (M46), or
  /// null for a report that reads only as a table.
  final ChartSpec? chart;

  /// Whether it is about what goods cost, and so closed to a role that may
  /// not see costs.
  bool get showsCost => ReportEngine.showsCost(kind);

  /// Whether it is as of now rather than over a period.
  bool get isAsOfToday => ReportEngine.isAsOfToday(kind);
}

const _billFilters = {
  ReportFilter.party,
  ReportFilter.partyGroup,
  ReportFilter.paymentStatus,
  ReportFilter.paymentMode,
  ReportFilter.user,
  ReportFilter.item,
  ReportFilter.itemCategory,
};

/// The transaction reports, in the order the market's apps list them, then
/// the ones they do not have.
final _transactionReports = [
  ReportEntry(
    kind: ReportKind.saleReport,
    group: ReportGroup.transaction,
    name: (s) => s.reportSale,
    hint: (s) => s.reportSaleHint,
    icon: Icons.receipt_long_outlined,
    filters: _billFilters,
    // M46: the bills summed by day, every day of the period drawn.
    chart: const ChartSpec.trend(label: 'Date', value: 'Total', everyDay: true),
  ),
  ReportEntry(
    kind: ReportKind.purchaseReport,
    group: ReportGroup.transaction,
    name: (s) => s.reportPurchase,
    hint: (s) => s.reportPurchaseHint,
    icon: Icons.shopping_cart_outlined,
    filters: _billFilters.difference({ReportFilter.partyGroup}),
  ),
  ReportEntry(
    kind: ReportKind.dayBook,
    group: ReportGroup.transaction,
    name: (s) => s.reportDayBook,
    hint: (s) => s.reportDayBookHint,
    icon: Icons.menu_book_outlined,
    filters: const {ReportFilter.user},
    defaultPreset: DatePreset.today,
  ),
  ReportEntry(
    kind: ReportKind.allTransactions,
    group: ReportGroup.transaction,
    name: (s) => s.reportAllTransactions,
    hint: (s) => s.reportAllTransactionsHint,
    icon: Icons.list_alt_outlined,
    filters: const {
      ReportFilter.transactionType,
      ReportFilter.party,
      ReportFilter.partyGroup,
      ReportFilter.paymentMode,
      ReportFilter.user,
    },
  ),
  ReportEntry(
    kind: ReportKind.billWiseProfit,
    group: ReportGroup.transaction,
    name: (s) => s.reportBillWiseProfit,
    hint: (s) => s.reportBillWiseProfitHint,
    icon: Icons.request_quote_outlined,
    plan: PlanFeature.accountingReports,
    filters: const {
      ReportFilter.party,
      ReportFilter.partyGroup,
      ReportFilter.user,
      ReportFilter.item,
      ReportFilter.itemCategory,
    },
  ),
  ReportEntry(
    kind: ReportKind.profitAndLoss,
    group: ReportGroup.transaction,
    name: (s) => s.reportProfitAndLoss,
    hint: (s) => s.reportProfitAndLossHint,
    icon: Icons.trending_up,
    plan: PlanFeature.accountingReports,
  ),
  ReportEntry(
    kind: ReportKind.cashflow,
    group: ReportGroup.transaction,
    name: (s) => s.reportCashflow,
    hint: (s) => s.reportCashflowHint,
    icon: Icons.swap_vert,
  ),
  ReportEntry(
    kind: ReportKind.balanceSheet,
    group: ReportGroup.transaction,
    name: (s) => s.reportBalanceSheet,
    hint: (s) => s.reportBalanceSheetHint,
    icon: Icons.account_balance_outlined,
    plan: PlanFeature.accountingReports,
  ),
  ReportEntry(
    kind: ReportKind.cashBook,
    group: ReportGroup.transaction,
    name: (s) => s.reportCashBook,
    hint: (s) => s.reportCashBookHint,
    icon: Icons.point_of_sale_outlined,
    defaultPreset: DatePreset.today,
  ),
  ReportEntry(
    kind: ReportKind.salesByDay,
    group: ReportGroup.transaction,
    name: (s) => s.reportSalesByDay,
    hint: (s) => s.reportSalesByDayHint,
    icon: Icons.calendar_month_outlined,
    chart: const ChartSpec.trend(label: 'Date', value: 'Sales', everyDay: true),
  ),
  ReportEntry(
    kind: ReportKind.trialBalance,
    group: ReportGroup.transaction,
    name: (s) => s.reportTrialBalance,
    hint: (s) => s.reportTrialBalanceHint,
    icon: Icons.balance_outlined,
    plan: PlanFeature.accountingReports,
  ),
  // M67: beside the statements it is read off, on the same plan.
  ReportEntry(
    kind: ReportKind.ratioAnalysis,
    group: ReportGroup.transaction,
    name: (s) => s.reportRatioAnalysis,
    hint: (s) => s.reportRatioAnalysisHint,
    icon: Icons.analytics_outlined,
    plan: PlanFeature.accountingReports,
  ),
];

/// The party reports, then the ageing the market's apps keep elsewhere.
final _partyReports = [
  ReportEntry(
    kind: ReportKind.partyStatement,
    group: ReportGroup.party,
    name: (s) => s.reportPartyStatement,
    hint: (s) => s.reportPartyStatementHint,
    icon: Icons.description_outlined,
    filters: const {ReportFilter.party},
  ),
  ReportEntry(
    kind: ReportKind.partyProfitAndLoss,
    group: ReportGroup.party,
    name: (s) => s.reportPartyProfit,
    hint: (s) => s.reportPartyProfitHint,
    icon: Icons.leaderboard_outlined,
    plan: PlanFeature.accountingReports,
    filters: const {ReportFilter.partyGroup, ReportFilter.user},
  ),
  ReportEntry(
    kind: ReportKind.allParties,
    group: ReportGroup.party,
    name: (s) => s.reportAllParties,
    hint: (s) => s.reportAllPartiesHint,
    icon: Icons.people_alt_outlined,
    filters: const {ReportFilter.partyGroup, ReportFilter.withBalance},
  ),
  ReportEntry(
    kind: ReportKind.partyItems,
    group: ReportGroup.party,
    name: (s) => s.reportPartyItems,
    hint: (s) => s.reportPartyItemsHint,
    icon: Icons.category_outlined,
    filters: const {
      ReportFilter.party,
      ReportFilter.item,
      ReportFilter.itemCategory,
    },
  ),
  ReportEntry(
    kind: ReportKind.salePurchaseByParty,
    group: ReportGroup.party,
    name: (s) => s.reportSalePurchaseByParty,
    hint: (s) => s.reportSalePurchaseByPartyHint,
    icon: Icons.compare_arrows,
    filters: const {ReportFilter.partyGroup, ReportFilter.user},
    chart: const ChartSpec.ranked(label: 'Party', value: 'Sales'),
  ),
  ReportEntry(
    kind: ReportKind.salePurchaseByPartyGroup,
    group: ReportGroup.party,
    name: (s) => s.reportSalePurchaseByGroup,
    hint: (s) => s.reportSalePurchaseByGroupHint,
    icon: Icons.group_work_outlined,
    filters: const {ReportFilter.user},
  ),
  ReportEntry(
    kind: ReportKind.receivables,
    group: ReportGroup.party,
    name: (s) => s.reportReceivables,
    hint: (s) => s.reportReceivablesHint,
    icon: Icons.hourglass_bottom_outlined,
    // M67: the shop's own buckets, drawn as a ring of them.
    chart: const ChartSpec.ringOfBuckets(),
  ),
  ReportEntry(
    kind: ReportKind.payables,
    group: ReportGroup.party,
    name: (s) => s.reportPayables,
    hint: (s) => s.reportPayablesHint,
    icon: Icons.local_shipping_outlined,
    chart: const ChartSpec.ringOfBuckets(), // M67
  ),
  // M58: the udhaar pack's (M38, M44), beside the bill-age one.
  ReportEntry(
    kind: ReportKind.receivablesByDueDate,
    group: ReportGroup.party,
    name: (s) => s.reportReceivablesByDue,
    hint: (s) => s.reportReceivablesByDueHint,
    icon: Icons.event_note_outlined,
    filters: const {ReportFilter.partyGroup},
    // M67: the ring follows the buckets the shop set.
    chart: const ChartSpec.ringOfBuckets(),
  ),
  // M54: the week ahead, beside the late — what falls due (M38, M50) and
  // what was promised (M38), per customer.
  ReportEntry(
    kind: ReportKind.expectedCollections,
    group: ReportGroup.party,
    name: (s) => s.reportExpectedCollections,
    hint: (s) => s.reportExpectedCollectionsHint,
    icon: Icons.event_available_outlined,
    filters: const {ReportFilter.party, ReportFilter.partyGroup},
  ),
  // M66: each customer's loyalty points — earned, used, lapsed, held —
  // and what the points used took off (Vyapar's "Total Loyalty Points
  // Rewarded" and "Total Discount Redeemed").
  ReportEntry(
    kind: ReportKind.loyaltyPoints,
    group: ReportGroup.party,
    name: (s) => s.reportLoyalty,
    hint: (s) => s.reportLoyaltyHint,
    icon: Icons.stars_outlined,
    filters: const {ReportFilter.party, ReportFilter.partyGroup},
  ),
  ReportEntry(
    kind: ReportKind.badDebts,
    group: ReportGroup.party,
    name: (s) => s.reportBadDebts,
    hint: (s) => s.reportBadDebtsHint,
    icon: Icons.money_off_csred_outlined,
    defaultPreset: DatePreset.thisFiscalYear,
  ),
];

/// Item and stock (M34): Vyapar's item and stock reports in its order, the
/// two it does not have (fast, slow and dead stock, and stock ageing), then
/// the three the books have had since M8 and M11.
///
/// Stock value stays beside the new Stock summary rather than being folded
/// into it: it is the owner's check of the shelf at today's average cost
/// against the books, closed to a role that may not see costs, where the
/// stock summary is the shop's list, open to the counter without its cost
/// columns. The premium ones ride the features the plans already sell:
/// batches and serials on tracking, transfers on godowns, production on
/// manufacturing, and profit on the books.
const _stockFilters = {
  ReportFilter.itemCategory,
  ReportFilter.location,
  ReportFilter.inStockOnly,
  ReportFilter.asOf,
  ReportFilter.valuation, // M67
};

const _tradeFilters = {ReportFilter.item, ReportFilter.itemCategory};

final _itemStockReports = [
  ReportEntry(
    kind: ReportKind.stockSummary,
    group: ReportGroup.itemStock,
    name: (s) => s.reportStockSummary,
    hint: (s) => s.reportStockSummaryHint,
    icon: Icons.inventory_outlined,
    filters: _stockFilters,
  ),
  ReportEntry(
    kind: ReportKind.itemByParty,
    group: ReportGroup.itemStock,
    name: (s) => s.reportItemByParty,
    hint: (s) => s.reportItemByPartyHint,
    icon: Icons.person_pin_outlined,
    filters: const {ReportFilter.item},
  ),
  ReportEntry(
    kind: ReportKind.itemProfitAndLoss,
    group: ReportGroup.itemStock,
    name: (s) => s.reportItemProfit,
    hint: (s) => s.reportItemProfitHint,
    icon: Icons.stacked_line_chart,
    plan: PlanFeature.accountingReports,
    filters: _tradeFilters,
  ),
  ReportEntry(
    kind: ReportKind.categoryProfitAndLoss,
    group: ReportGroup.itemStock,
    name: (s) => s.reportCategoryProfit,
    hint: (s) => s.reportCategoryProfitHint,
    icon: Icons.donut_small_outlined,
    plan: PlanFeature.accountingReports,
    filters: const {ReportFilter.itemCategory},
  ),
  ReportEntry(
    kind: ReportKind.lowStock,
    group: ReportGroup.itemStock,
    name: (s) => s.reportLowStock,
    hint: (s) => s.reportLowStockHint,
    icon: Icons.production_quantity_limits,
    filters: const {
      ReportFilter.itemCategory,
      ReportFilter.salesDays,
      ReportFilter.coverDays,
    },
  ),
  ReportEntry(
    kind: ReportKind.itemDetail,
    group: ReportGroup.itemStock,
    name: (s) => s.reportItemDetail,
    hint: (s) => s.reportItemDetailHint,
    icon: Icons.timeline,
    filters: const {ReportFilter.item, ReportFilter.location},
  ),
  ReportEntry(
    kind: ReportKind.stockDetail,
    group: ReportGroup.itemStock,
    name: (s) => s.reportStockDetail,
    hint: (s) => s.reportStockDetailHint,
    icon: Icons.table_rows_outlined,
    filters: const {
      ReportFilter.item,
      ReportFilter.itemCategory,
      ReportFilter.location,
    },
  ),
  ReportEntry(
    kind: ReportKind.salePurchaseByCategory,
    group: ReportGroup.itemStock,
    name: (s) => s.reportSalePurchaseByCategory,
    hint: (s) => s.reportSalePurchaseByCategoryHint,
    icon: Icons.category_outlined,
    filters: const {ReportFilter.itemCategory},
  ),
  ReportEntry(
    kind: ReportKind.stockSummaryByCategory,
    group: ReportGroup.itemStock,
    name: (s) => s.reportStockByCategory,
    hint: (s) => s.reportStockByCategoryHint,
    icon: Icons.view_module_outlined,
    filters: const {
      ReportFilter.location,
      ReportFilter.asOf,
      ReportFilter.valuation, // M67
    },
  ),
  ReportEntry(
    kind: ReportKind.itemBatches,
    group: ReportGroup.itemStock,
    name: (s) => s.reportBatches,
    hint: (s) => s.reportBatchesHint,
    icon: Icons.medication_outlined,
    plan: PlanFeature.tracking,
    filters: const {
      ReportFilter.item,
      ReportFilter.itemCategory,
      ReportFilter.location,
    },
  ),
  ReportEntry(
    kind: ReportKind.itemSerials,
    group: ReportGroup.itemStock,
    name: (s) => s.reportSerials,
    hint: (s) => s.reportSerialsHint,
    icon: Icons.qr_code_2,
    plan: PlanFeature.tracking,
    filters: const {ReportFilter.serial, ReportFilter.item},
  ),
  ReportEntry(
    kind: ReportKind.itemDiscount,
    group: ReportGroup.itemStock,
    name: (s) => s.reportItemDiscount,
    hint: (s) => s.reportItemDiscountHint,
    icon: Icons.local_offer_outlined,
    filters: _tradeFilters,
  ),
  ReportEntry(
    kind: ReportKind.stockTransfers,
    group: ReportGroup.itemStock,
    name: (s) => s.reportStockTransfers,
    hint: (s) => s.reportStockTransfersHint,
    icon: Icons.move_down,
    plan: PlanFeature.godowns,
    filters: const {ReportFilter.item, ReportFilter.location},
  ),
  ReportEntry(
    kind: ReportKind.productionRegister,
    group: ReportGroup.itemStock,
    name: (s) => s.reportProduction,
    hint: (s) => s.reportProductionHint,
    icon: Icons.precision_manufacturing_outlined,
    plan: PlanFeature.manufacturing,
    filters: const {ReportFilter.item},
  ),
  ReportEntry(
    kind: ReportKind.fastSlowStock,
    group: ReportGroup.itemStock,
    name: (s) => s.reportFastSlow,
    hint: (s) => s.reportFastSlowHint,
    icon: Icons.speed,
    filters: const {
      ReportFilter.itemCategory,
      ReportFilter.salesDays,
      ReportFilter.fastAt,
      ReportFilter.slowBelow,
    },
  ),
  ReportEntry(
    kind: ReportKind.stockAgeing,
    group: ReportGroup.itemStock,
    name: (s) => s.reportStockAgeing,
    hint: (s) => s.reportStockAgeingHint,
    icon: Icons.hourglass_empty,
    filters: const {ReportFilter.itemCategory, ReportFilter.asOf},
  ),
  // M67: Zoho's ABC classes, beside the fast and slow stock; the ring is
  // the three classes' sales.
  ReportEntry(
    kind: ReportKind.abcClassification,
    group: ReportGroup.itemStock,
    name: (s) => s.reportAbc,
    hint: (s) => s.reportAbcHint,
    icon: Icons.sort_by_alpha,
    filters: const {
      ReportFilter.itemCategory,
      ReportFilter.abcBasis,
      ReportFilter.abcBands,
    },
    defaultPreset: DatePreset.thisFiscalYear,
    chart: const ChartSpec.ring(label: 'Class', value: 'Sales'),
  ),
  ReportEntry(
    kind: ReportKind.salesByItem,
    group: ReportGroup.itemStock,
    name: (s) => s.reportSalesByItem,
    hint: (s) => s.reportSalesByItemHint,
    icon: Icons.shopping_basket_outlined,
    chart: const ChartSpec.ranked(label: 'Item', value: 'Sales'),
  ),
  ReportEntry(
    kind: ReportKind.stockValue,
    group: ReportGroup.itemStock,
    name: (s) => s.reportStockValue,
    hint: (s) => s.reportStockValueHint,
    icon: Icons.inventory_2_outlined,
  ),
  ReportEntry(
    kind: ReportKind.expiry,
    group: ReportGroup.itemStock,
    name: (s) => s.reportExpiry,
    hint: (s) => s.reportExpiryHint,
    icon: Icons.event_busy_outlined,
  ),
];

/// Business status (M35): the night's Z report first, then the bank, the
/// discounts, the staff and the hours, and how customers pay. Everything
/// after the bank and the discounts is beyond what the market's apps have.
final _businessStatusReports = [
  // M67: Dhyan dein, everything odd today, before the day's figures.
  ReportEntry(
    kind: ReportKind.needsAttention,
    group: ReportGroup.businessStatus,
    name: (s) => s.reportNeedsAttention,
    hint: (s) => s.reportNeedsAttentionHint,
    icon: Icons.notification_important_outlined,
    filters: const {ReportFilter.lateDays},
    defaultPreset: DatePreset.today,
  ),
  ReportEntry(
    kind: ReportKind.dailySummary,
    group: ReportGroup.businessStatus,
    name: (s) => s.reportDailySummary,
    hint: (s) => s.reportDailySummaryHint,
    icon: Icons.summarize_outlined,
    defaultPreset: DatePreset.today,
  ),
  ReportEntry(
    kind: ReportKind.bankStatement,
    group: ReportGroup.businessStatus,
    name: (s) => s.reportBankStatement,
    hint: (s) => s.reportBankStatementHint,
    icon: Icons.account_balance_wallet_outlined,
    filters: const {ReportFilter.moneyAccount},
  ),
  ReportEntry(
    kind: ReportKind.discountByParty,
    group: ReportGroup.businessStatus,
    name: (s) => s.reportDiscount,
    hint: (s) => s.reportDiscountHint,
    icon: Icons.sell_outlined,
    filters: const {ReportFilter.partyGroup},
  ),
  ReportEntry(
    kind: ReportKind.discountByCashier,
    group: ReportGroup.businessStatus,
    name: (s) => s.reportDiscountByCashier,
    hint: (s) => s.reportDiscountByCashierHint,
    icon: Icons.badge_outlined,
  ),
  ReportEntry(
    kind: ReportKind.salesByCashier,
    group: ReportGroup.businessStatus,
    name: (s) => s.reportSalesByCashier,
    hint: (s) => s.reportSalesByCashierHint,
    icon: Icons.person_outline,
  ),
  ReportEntry(
    kind: ReportKind.salesByCounter,
    group: ReportGroup.businessStatus,
    name: (s) => s.reportSalesByCounter,
    hint: (s) => s.reportSalesByCounterHint,
    icon: Icons.devices_outlined,
    filters: const {ReportFilter.user},
  ),
  ReportEntry(
    kind: ReportKind.paymentModes,
    group: ReportGroup.businessStatus,
    name: (s) => s.reportPaymentModes,
    hint: (s) => s.reportPaymentModesHint,
    icon: Icons.payments_outlined,
    filters: const {ReportFilter.user},
    defaultPreset: DatePreset.today,
    // How the sales were paid, udhaar included: the slices are the sales.
    chart: const ChartSpec.ring(label: 'Paid by', value: 'Sales paid by it'),
  ),
  ReportEntry(
    kind: ReportKind.hourlySales,
    group: ReportGroup.businessStatus,
    name: (s) => s.reportHourlySales,
    hint: (s) => s.reportHourlySalesHint,
    icon: Icons.schedule_outlined,
    filters: const {ReportFilter.user},
    chart: const ChartSpec.trend(label: 'Hour', value: 'Sales'),
  ),
  ReportEntry(
    kind: ReportKind.paymentPerformance,
    group: ReportGroup.businessStatus,
    name: (s) => s.reportPaymentPerformance,
    hint: (s) => s.reportPaymentPerformanceHint,
    icon: Icons.timer_outlined,
    filters: const {ReportFilter.partyGroup},
    defaultPreset: DatePreset.thisFiscalYear,
  ),
  ReportEntry(
    kind: ReportKind.defaulters,
    group: ReportGroup.businessStatus,
    name: (s) => s.reportDefaulters,
    hint: (s) => s.reportDefaultersHint,
    icon: Icons.warning_amber_outlined,
    filters: const {ReportFilter.partyGroup},
  ),
  ReportEntry(
    kind: ReportKind.changedBills,
    group: ReportGroup.businessStatus,
    name: (s) => s.reportChangedBills,
    hint: (s) => s.reportChangedBillsHint,
    icon: Icons.edit_note_outlined,
    // M58: "above Rs X", the changes worth an owner's evening.
    filters: const {ReportFilter.user, ReportFilter.minAmount},
  ),
];

/// Taxes (M35 adds the tax and tax-rate reports).
final _taxReports = [
  ReportEntry(
    kind: ReportKind.salesTax,
    group: ReportGroup.taxes,
    name: (s) => s.reportSalesTax,
    hint: (s) => s.reportSalesTaxHint,
    icon: Icons.receipt_outlined,
    plan: PlanFeature.accountingReports,
  ),
  ReportEntry(
    kind: ReportKind.tajirDost,
    group: ReportGroup.taxes,
    name: (s) => s.reportTajirDost,
    hint: (s) => s.reportTajirDostHint,
    icon: Icons.percent,
    plan: PlanFeature.accountingReports,
  ),
  ReportEntry(
    kind: ReportKind.purchaseRegister,
    group: ReportGroup.taxes,
    name: (s) => s.reportPurchaseRegister,
    hint: (s) => s.reportPurchaseRegisterHint,
    icon: Icons.inventory_outlined,
    plan: PlanFeature.accountingReports,
  ),
  // M35: the GST reports of the market's apps, mapped onto Pakistan's.
  ReportEntry(
    kind: ReportKind.taxReport,
    group: ReportGroup.taxes,
    name: (s) => s.reportTaxReport,
    hint: (s) => s.reportTaxReportHint,
    icon: Icons.request_page_outlined,
    plan: PlanFeature.accountingReports,
    filters: const {ReportFilter.party, ReportFilter.partyGroup},
  ),
  ReportEntry(
    kind: ReportKind.taxRateReport,
    group: ReportGroup.taxes,
    name: (s) => s.reportTaxRate,
    hint: (s) => s.reportTaxRateHint,
    icon: Icons.pie_chart_outline,
    plan: PlanFeature.accountingReports,
  ),
  ReportEntry(
    kind: ReportKind.salesByHsCode,
    group: ReportGroup.taxes,
    name: (s) => s.reportSalesByHsCode,
    hint: (s) => s.reportSalesByHsCodeHint,
    icon: Icons.tag,
    plan: PlanFeature.accountingReports,
  ),
  // The return is filed for the month gone, so the annexures open on it.
  ReportEntry(
    kind: ReportKind.annexC,
    group: ReportGroup.taxes,
    name: (s) => s.reportAnnexC,
    hint: (s) => s.reportAnnexCHint,
    icon: Icons.upload_file_outlined,
    plan: PlanFeature.accountingReports,
    defaultPreset: DatePreset.lastMonth,
  ),
  ReportEntry(
    kind: ReportKind.annexA,
    group: ReportGroup.taxes,
    name: (s) => s.reportAnnexA,
    hint: (s) => s.reportAnnexAHint,
    icon: Icons.file_present_outlined,
    plan: PlanFeature.accountingReports,
    defaultPreset: DatePreset.lastMonth,
  ),
];

/// Expense: the heads from the books, then every voucher, the heads
/// direct and indirect, and what the money went on (M35).
final _expenseReports = [
  ReportEntry(
    kind: ReportKind.expenses,
    group: ReportGroup.expense,
    name: (s) => s.reportExpenses,
    hint: (s) => s.reportExpensesHint,
    icon: Icons.money_off_outlined,
    chart: const ChartSpec.ranked(label: 'Head', value: 'Amount'),
  ),
  ReportEntry(
    kind: ReportKind.expenseTransactions,
    group: ReportGroup.expense,
    name: (s) => s.reportExpenseTransactions,
    hint: (s) => s.reportExpenseTransactionsHint,
    icon: Icons.list_outlined,
    filters: const {
      ReportFilter.expenseHead,
      ReportFilter.user,
      ReportFilter.paymentMode,
    },
  ),
  ReportEntry(
    kind: ReportKind.expenseCategories,
    group: ReportGroup.expense,
    name: (s) => s.reportExpenseCategories,
    hint: (s) => s.reportExpenseCategoriesHint,
    icon: Icons.donut_small_outlined,
    filters: const {ReportFilter.user},
    chart: const ChartSpec.ranked(label: 'Head', value: 'Amount'),
  ),
  ReportEntry(
    kind: ReportKind.expenseItems,
    group: ReportGroup.expense,
    name: (s) => s.reportExpenseItems,
    hint: (s) => s.reportExpenseItemsHint,
    icon: Icons.shopping_bag_outlined,
    filters: const {ReportFilter.expenseHead},
  ),
];

/// Orders (M35): this shop's are its quotations and challans. Sale and
/// purchase orders as documents (M41) join here, as more doc types on the
/// same reads.
final _orderReports = [
  ReportEntry(
    kind: ReportKind.openQuotations,
    group: ReportGroup.orders,
    name: (s) => s.reportOpenQuotations,
    hint: (s) => s.reportOpenQuotationsHint,
    icon: Icons.format_quote_outlined,
    filters: const {ReportFilter.party},
  ),
  ReportEntry(
    kind: ReportKind.openChallans,
    group: ReportGroup.orders,
    name: (s) => s.reportOpenChallans,
    hint: (s) => s.reportOpenChallansHint,
    icon: Icons.move_to_inbox_outlined,
    filters: const {ReportFilter.party},
  ),
  ReportEntry(
    kind: ReportKind.openOrderItems,
    group: ReportGroup.orders,
    name: (s) => s.reportOpenOrderItems,
    hint: (s) => s.reportOpenOrderItemsHint,
    icon: Icons.checklist_outlined,
  ),
  // M41: purchase and sale orders as documents.
  ReportEntry(
    kind: ReportKind.openPurchaseOrders,
    group: ReportGroup.orders,
    name: (s) => s.reportOpenPurchaseOrders,
    hint: (s) => s.reportOpenPurchaseOrdersHint,
    icon: Icons.assignment_outlined,
    filters: const {ReportFilter.party},
  ),
  ReportEntry(
    kind: ReportKind.openSaleOrders,
    group: ReportGroup.orders,
    name: (s) => s.reportOpenSaleOrders,
    hint: (s) => s.reportOpenSaleOrdersHint,
    icon: Icons.shopping_bag_outlined,
    filters: const {ReportFilter.party},
  ),
  ReportEntry(
    kind: ReportKind.orderItemsDue,
    group: ReportGroup.orders,
    name: (s) => s.reportOrderItemsDue,
    hint: (s) => s.reportOrderItemsDueHint,
    icon: Icons.inventory_outlined,
  ),
];

/// Loan accounts (M58, over M48's loans): every loan on one page, or one
/// loan's statement when narrowed to it. Not behind a plan, as the loan's
/// own statement is not: a shop whose plan lapsed still owes the bank.
final _loanReports = [
  ReportEntry(
    kind: ReportKind.loanStatement,
    group: ReportGroup.loans,
    name: (s) => s.reportLoanStatement,
    hint: (s) => s.reportLoanStatementHint,
    icon: Icons.account_balance_outlined,
    filters: const {ReportFilter.loan},
    defaultPreset: DatePreset.thisFiscalYear,
  ),
];

/// M50: a mobile shop's register of used phones bought, for the police and
/// the market association, and its phones sold on qist.
final _mobileReports = [
  ReportEntry(
    kind: ReportKind.usedPhonesRegister,
    group: ReportGroup.mobile,
    name: (s) => s.reportUsedPhones,
    hint: (s) => s.reportUsedPhonesHint,
    icon: Icons.phonelink_lock_outlined,
  ),
  ReportEntry(
    kind: ReportKind.qistInstalments,
    group: ReportGroup.mobile,
    name: (s) => s.reportQistInstalments,
    hint: (s) => s.reportQistInstalmentsHint,
    icon: Icons.calendar_month_outlined,
    filters: const {ReportFilter.party},
  ),
];

/// M49: the pharmacy's register, for the inspector.
final _pharmacyReports = [
  ReportEntry(
    kind: ReportKind.scheduleRegister,
    group: ReportGroup.pharmacy,
    name: (s) => s.reportScheduleRegister,
    hint: (s) => s.reportScheduleRegisterHint,
    icon: Icons.medication_outlined,
    filters: const {ReportFilter.item},
  ),
];

/// M65: the staff book's register in totals, the salary register, and what
/// each man still owes of his advances.
final _staffBookReports = [
  ReportEntry(
    kind: ReportKind.staffAttendance,
    group: ReportGroup.staff,
    name: (s) => s.reportStaffAttendance,
    hint: (s) => s.reportStaffAttendanceHint,
    icon: Icons.fact_check_outlined,
  ),
  ReportEntry(
    kind: ReportKind.salaryRegister,
    group: ReportGroup.staff,
    name: (s) => s.reportSalaryRegister,
    hint: (s) => s.reportSalaryRegisterHint,
    icon: Icons.account_balance_wallet_outlined,
  ),
  ReportEntry(
    kind: ReportKind.staffAdvances,
    group: ReportGroup.staff,
    name: (s) => s.reportStaffAdvances,
    hint: (s) => s.reportStaffAdvancesHint,
    icon: Icons.payments_outlined,
  ),
];

/// Every report, group by group, in the order the hub lists them.
final List<ReportEntry> reportRegistry = List.unmodifiable([
  ..._transactionReports,
  ..._partyReports,
  ..._itemStockReports,
  ..._businessStatusReports,
  ..._taxReports,
  ..._expenseReports,
  ..._orderReports,
  ..._loanReports,
  ..._pharmacyReports, // M49
  ..._mobileReports, // M50
  ..._staffBookReports, // M65
]);

final Map<ReportKind, ReportEntry> _byKind = {
  for (final e in reportRegistry) e.kind: e,
};

/// The entry for [kind]. Every kind has one; a test says so.
ReportEntry reportEntry(ReportKind kind) =>
    _byKind[kind] ?? (throw StateError('$kind is not in the report registry.'));

/// A report's name as the shop reads it.
String reportName(AppStrings s, ReportKind kind) => reportEntry(kind).name(s);

/// The books and tax reports a paid plan opens (M21); the day's sales,
/// cash, stock and khatas are free.
bool isAccountingReport(ReportKind kind) =>
    reportEntry(kind).plan == PlanFeature.accountingReports;
