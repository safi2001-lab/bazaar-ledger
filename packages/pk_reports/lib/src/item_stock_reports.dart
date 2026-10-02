import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'item_stock_builders.dart';
import 'item_stock_source.dart';
import 'period.dart';
import 'report_engine.dart';
import 'report_table.dart';

/// Reads and builds one of the item and stock reports (M34).
///
/// Kept beside the builders rather than written out case by case in
/// `ReportEngine._build`, so the engine's switch carries the group as one
/// arm and the next group's reports land beside it without touching these.
///
/// [asOf] is the day a report that stands as of a day is read for: the
/// `asOf` filter when the report declares it and the shop chose one, and
/// today otherwise.
Future<ReportTable> buildItemStockReport(
  ItemStockReportSource source,
  ReportKind kind,
  String firmId,
  ReportPeriod period,
  BusinessDate asOf,
  ReportFilters filters,
) async {
  // The whole shop, not a part of it: only then is a stock total the
  // books' Inventory, and only then does a report set the two side by side.
  final whole =
      filters.itemId == null &&
      filters.category == null &&
      filters.location == null &&
      !filters.inStockOnly;
  return switch (kind) {
    ReportKind.stockSummary => stockSummary(
      asOf,
      await source.stockLines(firmId, asOf, filters: filters),
      inBooks: whole ? await source.inventoryAsOf(firmId, asOf) : null,
    ),
    ReportKind.stockSummaryByCategory => stockSummaryByCategory(
      asOf,
      await source.stockLines(firmId, asOf, filters: filters),
    ),
    ReportKind.stockDetail => stockDetail(
      period,
      await source.stockFlows(firmId, period, filters: filters),
      openingInBooks: whole
          ? await source.inventoryAsOf(firmId, period.from.addDays(-1))
          : null,
      closingInBooks: whole
          ? await source.inventoryAsOf(firmId, period.to)
          : null,
    ),
    ReportKind.itemDetail => itemDetail(
      period,
      filters.itemId == null
          ? null
          : await source.itemHistory(firmId, period, filters: filters),
    ),
    ReportKind.itemByParty => itemByParty(
      period,
      filters.itemId == null
          ? const []
          : await source.itemParties(firmId, period, filters: filters),
      itemName: filters.itemId == null
          ? null
          : filters.itemName ?? filters.itemId,
    ),
    ReportKind.itemProfitAndLoss => itemProfitAndLoss(
      period,
      await source.itemTrade(firmId, period, filters: filters),
    ),
    ReportKind.categoryProfitAndLoss => categoryProfitAndLoss(
      period,
      await source.itemTrade(firmId, period, filters: filters),
    ),
    ReportKind.salePurchaseByCategory => salePurchaseByCategory(
      period,
      await source.itemTrade(firmId, period, filters: filters),
    ),
    ReportKind.itemDiscount => itemDiscount(
      period,
      await source.itemTrade(firmId, period, filters: filters),
    ),
    ReportKind.lowStock => lowStockSummary(
      asOf,
      await source.lowStock(
        firmId,
        asOf,
        salesDays: filters.salesDays ?? StockDefaults.lowStockDays,
        filters: filters,
      ),
      salesDays: filters.salesDays ?? StockDefaults.lowStockDays,
      coverDays: filters.coverDays ?? StockDefaults.coverDays,
    ),
    ReportKind.itemBatches => batchReport(
      asOf,
      await source.batches(firmId, filters: filters),
    ),
    ReportKind.itemSerials => serialReport(
      asOf,
      await source.serials(firmId, filters: filters),
    ),
    ReportKind.stockTransfers => stockTransferReport(
      period,
      await source.stockTransfers(firmId, period, filters: filters),
    ),
    ReportKind.productionRegister => productionRegister(
      period,
      await source.productionRuns(firmId, period, filters: filters),
    ),
    ReportKind.fastSlowStock => fastSlowStock(
      asOf,
      await source.itemSelling(
        firmId,
        asOf,
        salesDays: filters.salesDays ?? StockDefaults.movementDays,
        filters: filters,
      ),
      salesDays: filters.salesDays ?? StockDefaults.movementDays,
      fastAt: filters.fastAt ?? StockDefaults.fastAt,
      slowBelow: filters.slowBelow ?? StockDefaults.slowBelow,
    ),
    ReportKind.stockAgeing => stockAgeing(
      asOf,
      await source.stockAgeing(firmId, asOf, filters: filters),
    ),
    _ => throw ArgumentError.value(kind, 'kind', 'is not an item report'),
  };
}
