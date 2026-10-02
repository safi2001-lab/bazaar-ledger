import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';

/// A quotation or challan nobody has billed yet (M35).
///
/// The order reports of the market's apps are about sale and purchase
/// orders; this shop's orders are its quotations and its delivery challans
/// (M25), so those are what is open. A sale or purchase order document
/// (M41) is one more doc type on the same read.
final class OpenOrder {
  const OpenOrder({
    required this.documentId,
    required this.docType,
    required this.docNo,
    required this.date,
    required this.party,
    required this.total,
    required this.lines,
    this.partyId,
    this.validUntil,
  });

  final String documentId;

  /// `quotation` or `delivery_challan`.
  final String docType;
  final String docNo;
  final BusinessDate date;
  final String? partyId;

  /// The name on it, or empty for a walk-in.
  final String party;
  final Money total;
  final int lines;

  /// The date a quotation was good until, as its terms say.
  final BusinessDate? validUntil;
}

/// One item on the open quotations or challans, summed (M35).
final class OpenOrderItem {
  const OpenOrderItem({
    required this.itemName,
    required this.unitCode,
    required this.docType,
    required this.qty,
    required this.value,
    required this.documents,
  });

  final String itemName;

  /// The base unit the quantity is counted in.
  final String unitCode;

  /// `quotation` or `delivery_challan`.
  final String docType;
  final Qty qty;

  /// Before tax, after every discount.
  final Money value;

  /// How many open documents carry it.
  final int documents;
}

/// Where the order reports read from (M35).
abstract interface class OrderReportSource {
  /// Every posted document of [docTypes] not yet billed, oldest first.
  Future<List<OpenOrder>> openOrders(
    String firmId, {
    required Set<String> docTypes,
    ReportFilters filters = ReportFilters.none,
  });

  /// The items on those documents, by item and document type.
  Future<List<OpenOrderItem>> openOrderItems(
    String firmId, {
    required Set<String> docTypes,
    ReportFilters filters = ReportFilters.none,
  });

  /// Every purchase or sale order of [docType] still standing — not
  /// cancelled, with something still to come — oldest first (M41).
  Future<List<StandingOrder>> standingOrders(
    String firmId, {
    required String docType,
    ReportFilters filters = ReportFilters.none,
  });

  /// The items on every standing order of both kinds (M41).
  Future<List<StandingOrderItem>> standingOrderItems(
    String firmId, {
    ReportFilters filters = ReportFilters.none,
  });
}

/// A purchase order or a sale order still standing (M41): not cancelled,
/// and with something still to come in or go out.
final class StandingOrder {
  const StandingOrder({
    required this.documentId,
    required this.docType,
    required this.docNo,
    required this.date,
    required this.party,
    required this.total,
    required this.lines,
    required this.linesDone,
    required this.pendingValue,
    required this.started,
    this.partyId,
    this.dueDate,
    this.advance = Money.zero,
  });

  final String documentId;

  /// `purchase_order` or `sale_order`.
  final String docType;
  final String docNo;
  final BusinessDate date;
  final String? partyId;
  final String party;

  /// What it was placed for, at the order's rates.
  final Money total;
  final int lines;

  /// Lines that have come in, or gone out, in full.
  final int linesDone;

  /// What is still to come, at the order's rates.
  final Money pendingValue;

  /// Whether anything has come of it yet.
  final bool started;

  /// When it is expected in, or promised out.
  final BusinessDate? dueDate;

  /// Taken from the customer against a sale order.
  final Money advance;
}

/// One item on the standing orders, by item and kind of order (M41).
final class StandingOrderItem {
  const StandingOrderItem({
    required this.itemName,
    required this.unitCode,
    required this.docType,
    required this.ordered,
    required this.done,
    required this.pending,
    required this.pendingValue,
    required this.orders,
  });

  final String itemName;

  /// The item's own unit, which every quantity here is in.
  final String unitCode;

  /// `purchase_order` or `sale_order`.
  final String docType;
  final Qty ordered;

  /// Received on deliveries, or delivered on bills and challans.
  final Qty done;
  final Qty pending;
  final Money pendingValue;

  /// How many standing orders carry it.
  final int orders;
}
