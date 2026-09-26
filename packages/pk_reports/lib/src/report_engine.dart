import 'package:pk_domain/pk_domain.dart';

import 'builders.dart';
import 'period.dart';
import 'report_source.dart';
import 'report_table.dart';

/// The reports a shop can run.
enum ReportKind {
  profitAndLoss,
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
}

/// Runs a report: reads its rows from a [ReportSource] and builds the table.
final class ReportEngine {
  const ReportEngine(this.source);

  /// Whether [kind] is as of today rather than over a period.
  static bool isAsOfToday(ReportKind kind) =>
      kind == ReportKind.stockValue ||
      kind == ReportKind.receivables ||
      kind == ReportKind.payables ||
      kind == ReportKind.trialBalance ||
      kind == ReportKind.balanceSheet;

  final ReportSource source;

  Future<ReportTable> run(
    ReportKind kind, {
    required String firmId,
    required ReportPeriod period,
    required BusinessDate today,
  }) async => switch (kind) {
    ReportKind.profitAndLoss => profitAndLoss(
      period,
      await source.accountMovements(firmId, period),
    ),
    ReportKind.expenses => expensesByHead(
      period,
      await source.accountMovements(firmId, period),
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
    ReportKind.dayBook => dayBook(period, await source.dayBook(firmId, period)),
    ReportKind.stockValue => stockValue(
      today,
      await source.stockPositions(firmId),
      await source.inventoryInBooks(firmId),
    ),
  };
}
