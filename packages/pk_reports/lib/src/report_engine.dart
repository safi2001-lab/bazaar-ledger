import 'package:pk_domain/pk_domain.dart';

import 'builders.dart';
import 'period.dart';
import 'report_source.dart';
import 'report_table.dart';

/// The reports a shop can run.
enum ReportKind {
  profitAndLoss,
  salesByItem,
  expenses,
  cashBook,
  dayBook,

  /// As it stands now; the period is ignored.
  stockValue,
}

/// Runs a report: reads its rows from a [ReportSource] and builds the table.
final class ReportEngine {
  const ReportEngine(this.source);

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
