import 'package:pk_domain/pk_domain.dart';

import 'business_builders.dart';
import 'expense_builders.dart';
import 'filters.dart';
import 'order_builders.dart';
import 'period.dart';
import 'report_engine.dart';
import 'report_source.dart';
import 'report_table.dart';
import 'staff_builders.dart';
import 'staff_source.dart';
import 'tax_builders.dart';

/// The reports M35 added: business status, staff and time, the night's Z
/// report, taxes, expenses and orders.
///
/// Kept here, out of `ReportEngine._build`, so that the engine's switch
/// carries them as one case and every other group adding reports beside
/// them touches a different line of it. The engine still refuses a cost
/// report before anything is read and strikes cost columns after; the one
/// cost figure among these, the Z report's gross profit, is left off by the
/// builder for a role that may not see it, because a two-column summary
/// has no cost column to strike.
const businessReportKinds = {
  ReportKind.dailySummary,
  ReportKind.bankStatement,
  ReportKind.discountByParty,
  ReportKind.discountByCashier,
  ReportKind.salesByCashier,
  ReportKind.salesByCounter,
  ReportKind.paymentModes,
  ReportKind.hourlySales,
  ReportKind.paymentPerformance,
  ReportKind.defaulters,
  ReportKind.changedBills,
  ReportKind.taxReport,
  ReportKind.taxRateReport,
  ReportKind.salesByHsCode,
  ReportKind.annexC,
  ReportKind.annexA,
  ReportKind.expenseTransactions,
  ReportKind.expenseCategories,
  ReportKind.expenseItems,
  ReportKind.openQuotations,
  ReportKind.openChallans,
  ReportKind.openOrderItems,
};

/// The M35 kinds that are as of today rather than over a period.
const businessReportsAsOfToday = {
  ReportKind.defaulters,
  ReportKind.openQuotations,
  ReportKind.openChallans,
  ReportKind.openOrderItems,
};

/// The documents the order reports count as open orders. A sale order and
/// a purchase order (M41) join this set when they exist as documents.
const _orderDocTypes = {TransactionType.quotation, TransactionType.challan};

/// Builds [kind], one of [businessReportKinds], from [source].
Future<ReportTable> buildBusinessReport(
  ReportKind kind, {
  required ReportSource source,
  required String firmId,
  required ReportPeriod period,
  required BusinessDate today,
  required ReportFilters filters,
  required bool canSeeCosts,
}) async => switch (kind) {
  ReportKind.dailySummary => dailySummary(
    period,
    await source.dayFigures(firmId, period),
    showProfit: canSeeCosts,
  ),
  ReportKind.bankStatement => bankStatement(
    period,
    await source.bankStatements(firmId, period, filters: filters),
  ),
  ReportKind.discountByParty => discountByParty(
    period,
    await source.discountsByParty(firmId, period, filters: filters),
  ),
  ReportKind.discountByCashier => discountByCashier(
    period,
    await source.staffSales(
      firmId,
      period,
      by: StaffGrouping.user,
      filters: filters,
    ),
  ),
  ReportKind.salesByCashier => salesByStaff(
    period,
    await source.staffSales(
      firmId,
      period,
      by: StaffGrouping.user,
      filters: filters,
    ),
    by: StaffGrouping.user,
  ),
  ReportKind.salesByCounter => salesByStaff(
    period,
    await source.staffSales(
      firmId,
      period,
      by: StaffGrouping.device,
      filters: filters,
    ),
    by: StaffGrouping.device,
  ),
  ReportKind.paymentModes => paymentModeSummary(
    period,
    await source.tenders(firmId, period, filters: filters),
    await source.udhaarGiven(firmId, period, filters: filters),
  ),
  ReportKind.hourlySales => hourlySales(
    period,
    await source.hourlySales(firmId, period, filters: filters),
  ),
  ReportKind.paymentPerformance => paymentPerformance(
    period,
    today,
    await source.paymentRecords(firmId, period, today, filters: filters),
  ),
  ReportKind.defaulters => defaulterList(
    today,
    await source.defaulters(firmId, today, filters: filters),
  ),
  ReportKind.changedBills => changedBills(
    period,
    await source.changes(firmId, period, filters: filters),
  ),
  ReportKind.taxReport => taxReport(
    period,
    await source.partyTax(firmId, period, filters: filters),
  ),
  ReportKind.taxRateReport => taxRateReport(
    period,
    await source.rateTax(firmId, period),
  ),
  ReportKind.salesByHsCode => salesByHsCode(
    period,
    await source.hsCodeSales(firmId, period),
  ),
  ReportKind.annexC => annexC(
    period,
    await source.annexLines(firmId, period, purchases: false),
  ),
  ReportKind.annexA => annexA(
    period,
    await source.annexLines(firmId, period, purchases: true),
  ),
  ReportKind.expenseTransactions => expenseTransactions(
    period,
    await source.expenseVouchers(firmId, period, filters: filters),
  ),
  ReportKind.expenseCategories => expenseCategories(
    period,
    await source.expenseVouchers(firmId, period, filters: filters),
  ),
  ReportKind.expenseItems => expenseItems(
    period,
    await source.expenseVouchers(firmId, period, filters: filters),
  ),
  ReportKind.openQuotations => openQuotations(
    today,
    await source.openOrders(
      firmId,
      docTypes: const {TransactionType.quotation},
      filters: filters,
    ),
  ),
  ReportKind.openChallans => openChallans(
    today,
    await source.openOrders(
      firmId,
      docTypes: const {TransactionType.challan},
      filters: filters,
    ),
  ),
  ReportKind.openOrderItems => openOrderItems(
    today,
    await source.openOrderItems(
      firmId,
      docTypes: _orderDocTypes,
      filters: filters,
    ),
  ),
  _ => throw ArgumentError.value(kind, 'kind', 'is not an M35 report'),
};
