import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'order_builders.dart';
import 'report_engine.dart';
import 'report_source.dart';
import 'report_table.dart';

/// The purchase and sale order reports (M41), beside M35's quotations and
/// challans in the Orders group.
///
/// Kept here, out of `ReportEngine._build`, so the engine carries them as
/// one case and the reports other milestones add beside them touch a
/// different line of it. All three are as of today: an order is open or it
/// is not, whatever month it was placed in.
const orderDocumentReportKinds = {
  ReportKind.openPurchaseOrders,
  ReportKind.openSaleOrders,
  ReportKind.orderItemsDue,
};

/// Builds [kind], one of [orderDocumentReportKinds], from [source].
Future<ReportTable> buildOrderDocumentReport(
  ReportKind kind, {
  required ReportSource source,
  required String firmId,
  required BusinessDate today,
  required ReportFilters filters,
}) async => switch (kind) {
  ReportKind.openPurchaseOrders => openPurchaseOrders(
    today,
    await source.standingOrders(
      firmId,
      docType: TransactionType.purchaseOrder,
      filters: filters,
    ),
  ),
  ReportKind.openSaleOrders => openSaleOrders(
    today,
    await source.standingOrders(
      firmId,
      docType: TransactionType.saleOrder,
      filters: filters,
    ),
  ),
  ReportKind.orderItemsDue => orderItemsDue(
    today,
    await source.standingOrderItems(firmId, filters: filters),
  ),
  _ => throw ArgumentError.value(kind, 'kind', 'is not an M41 report'),
};
