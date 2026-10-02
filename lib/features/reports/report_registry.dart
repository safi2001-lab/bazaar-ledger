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
  ),
  ReportEntry(
    kind: ReportKind.trialBalance,
    group: ReportGroup.transaction,
    name: (s) => s.reportTrialBalance,
    hint: (s) => s.reportTrialBalanceHint,
    icon: Icons.balance_outlined,
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
  ),
  ReportEntry(
    kind: ReportKind.payables,
    group: ReportGroup.party,
    name: (s) => s.reportPayables,
    hint: (s) => s.reportPayablesHint,
    icon: Icons.local_shipping_outlined,
  ),
];

/// Item and stock (M34 fills this group out).
final _itemStockReports = [
  ReportEntry(
    kind: ReportKind.salesByItem,
    group: ReportGroup.itemStock,
    name: (s) => s.reportSalesByItem,
    hint: (s) => s.reportSalesByItemHint,
    icon: Icons.shopping_basket_outlined,
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

/// Business status: bank statement and discounts (M35).
final _businessStatusReports = <ReportEntry>[];

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
];

/// Expense (M35 adds the expense transaction, category and item reports).
final _expenseReports = [
  ReportEntry(
    kind: ReportKind.expenses,
    group: ReportGroup.expense,
    name: (s) => s.reportExpenses,
    hint: (s) => s.reportExpensesHint,
    icon: Icons.money_off_outlined,
  ),
];

/// Sale and purchase orders (M35).
final _orderReports = <ReportEntry>[];

/// Loan accounts (M35).
final _loanReports = <ReportEntry>[];

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
