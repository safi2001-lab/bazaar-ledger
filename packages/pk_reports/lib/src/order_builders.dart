import 'package:pk_domain/pk_domain.dart';

import 'business_builders.dart';
import 'filters.dart';
import 'order_source.dart';
import 'period.dart';
import 'report_table.dart';

/// The order reports (M35). The market's apps keep sale and purchase
/// orders; this shop's orders are its quotations and its delivery challans,
/// so what is still open is a quotation nobody has billed or sent, and a
/// challan whose goods have gone and whose bill has not.

/// Every quotation still open on [today], oldest first: what the shop has
/// offered and not yet sold, with how long it has waited and whether it has
/// run past the date it was good until.
ReportTable openQuotations(BusinessDate today, List<OpenOrder> orders) {
  final rows = _oldestFirst(orders, TransactionType.quotation);
  final expired = rows
      .where(
        (o) => o.validUntil != null && calendarDays(o.validUntil!, today) > 0,
      )
      .length;
  final value = Money.sum(rows.map((o) => o.total));
  return ReportTable(
    id: 'open_quotations',
    title: 'Open quotations',
    period: ReportPeriod.day(today),
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Number', CellKind.text),
      ReportColumn('Party', CellKind.text),
      ReportColumn('Lines', CellKind.count),
      ReportColumn('Value', CellKind.money),
      ReportColumn('Days open', CellKind.count),
      ReportColumn('Good until', CellKind.text),
      ReportColumn('Status', CellKind.text),
    ],
    rows: [
      for (final o in rows)
        ReportRow(
          [
            o.date.value,
            o.docNo,
            o.party,
            o.lines,
            o.total,
            calendarDays(o.date, today),
            o.validUntil?.value ?? '',
            o.validUntil == null
                ? ''
                : calendarDays(o.validUntil!, today) > 0
                ? 'Expired'
                : 'Valid',
          ],
          link: ReportLink.document(
            o.documentId,
            label: o.docNo,
            docType: o.docType,
          ),
        ),
      ReportRow([
        'Total',
        rows.length == 1 ? '1 quotation' : '${rows.length} quotations',
        null,
        rows.fold<int>(0, (n, o) => n + o.lines),
        value,
        null,
        null,
        expired == 0 ? null : '$expired expired',
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('Open quotations', rows.length),
      ReportFigure('Value', value),
      ReportFigure.count('Expired', expired),
    ],
    notes: const [_openQuotationNote],
  );
}

/// Every delivery challan not yet billed on [today], oldest first: goods
/// that have left the shop and are on nobody's khata yet (M25).
ReportTable openChallans(BusinessDate today, List<OpenOrder> orders) {
  final rows = _oldestFirst(orders, TransactionType.challan);
  final value = Money.sum(rows.map((o) => o.total));
  return ReportTable(
    id: 'open_challans',
    title: 'Challans not yet billed',
    period: ReportPeriod.day(today),
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Number', CellKind.text),
      ReportColumn('Party', CellKind.text),
      ReportColumn('Lines', CellKind.count),
      ReportColumn('Value', CellKind.money),
      ReportColumn('Days out', CellKind.count),
    ],
    rows: [
      for (final o in rows)
        ReportRow(
          [
            o.date.value,
            o.docNo,
            o.party,
            o.lines,
            o.total,
            calendarDays(o.date, today),
          ],
          link: ReportLink.document(
            o.documentId,
            label: o.docNo,
            docType: o.docType,
          ),
        ),
      ReportRow([
        'Total',
        rows.length == 1 ? '1 challan' : '${rows.length} challans',
        null,
        rows.fold<int>(0, (n, o) => n + o.lines),
        value,
        null,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('Not billed', rows.length),
      ReportFigure('Value', value),
    ],
    notes: const [_openChallanNote],
  );
}

List<OpenOrder> _oldestFirst(List<OpenOrder> orders, String docType) =>
    orders.where((o) => o.docType == docType).toList()..sort((a, b) {
      final byDate = a.date.value.compareTo(b.date.value);
      return byDate != 0 ? byDate : a.docNo.compareTo(b.docNo);
    });

/// The items on every open quotation and unbilled challan on [today], the
/// most valuable first: what customers have been offered, and what has
/// gone out on trust.
ReportTable openOrderItems(BusinessDate today, List<OpenOrderItem> items) {
  final rows = items.toList()
    ..sort((a, b) {
      final byValue = b.value.compareTo(a.value);
      return byValue != 0 ? byValue : a.itemName.compareTo(b.itemName);
    });
  final value = Money.sum(rows.map((i) => i.value));
  return ReportTable(
    id: 'open_order_items',
    title: 'Quotation and challan items',
    period: ReportPeriod.day(today),
    columns: const [
      ReportColumn('Item', CellKind.text),
      ReportColumn('On', CellKind.text),
      ReportColumn('Qty', CellKind.qty),
      ReportColumn('Unit', CellKind.text),
      ReportColumn('Value', CellKind.money),
      ReportColumn('Documents', CellKind.count),
    ],
    rows: [
      for (final i in rows)
        ReportRow([
          i.itemName,
          i.docType == TransactionType.challan ? 'Challans' : 'Quotations',
          i.qty,
          i.unitCode,
          i.value,
          i.documents,
        ]),
      ReportRow([
        'Total',
        null,
        null,
        null,
        value,
        null,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure(
        'On quotations',
        Money.sum([
          for (final i in rows)
            if (i.docType == TransactionType.quotation) i.value,
        ]),
      ),
      ReportFigure(
        'On challans',
        Money.sum([
          for (final i in rows)
            if (i.docType == TransactionType.challan) i.value,
        ]),
      ),
    ],
    notes: const [_orderItemsNote],
  );
}

const _openQuotationNote =
    'Open is a quotation that stands and has not been made into a bill or '
    'sent on a challan.';

const _openChallanNote =
    'The goods on these have left the shelf and are in the books as goods '
    'on challan; nobody owes for them until they are billed.';

const _orderItemsNote =
    'Quantities are in each item\'s base unit; values before tax and after '
    'every discount.';

// ---------------------------------------------------------------------------
// Purchase orders and sale orders (M41)
// ---------------------------------------------------------------------------

/// Every purchase order still standing on [today], oldest first: what the
/// shop has asked suppliers for and not yet received, with how long each
/// has waited, what has come in of it, and whether it is past the day it
/// was expected.
ReportTable openPurchaseOrders(BusinessDate today, List<StandingOrder> rows) =>
    _standing(
      today,
      _oldestFirstOrders(rows, TransactionType.purchaseOrder),
      id: 'open_purchase_orders',
      title: 'Open purchase orders',
      party: 'Supplier',
      done: 'Received',
      due: 'Expected',
      started: 'Part received',
      noun: ('purchase order', 'purchase orders'),
      note:
          'Open is a purchase order not cancelled with something still to '
          'arrive. Received is the order\'s value less what is still to '
          'come, at the order\'s rates; a delivery counts once it is entered '
          'against the order.',
    );

/// Every sale order still standing on [today], oldest first: what
/// customers have asked for and not yet been billed or sent, with the
/// advance each paid.
ReportTable openSaleOrders(BusinessDate today, List<StandingOrder> rows) =>
    _standing(
      today,
      _oldestFirstOrders(rows, TransactionType.saleOrder),
      id: 'open_sale_orders',
      title: 'Open sale orders',
      party: 'Customer',
      done: 'Delivered',
      due: 'Promised',
      started: 'Part delivered',
      noun: ('sale order', 'sale orders'),
      withAdvance: true,
      note:
          'Open is a sale order not cancelled with something still to go '
          'out. Delivered is what has gone on bills and challans made from '
          'it, at the order\'s rates. Advance is the money taken against it, '
          'held on the customer\'s khata until the bill takes it.',
    );

List<StandingOrder> _oldestFirstOrders(
  List<StandingOrder> rows,
  String docType,
) => rows.where((o) => o.docType == docType).toList()
  ..sort((a, b) {
    final byDate = a.date.value.compareTo(b.date.value);
    return byDate != 0 ? byDate : a.docNo.compareTo(b.docNo);
  });

ReportTable _standing(
  BusinessDate today,
  List<StandingOrder> rows, {
  required String id,
  required String title,
  required String party,
  required String done,
  required String due,
  required String started,
  required (String, String) noun,
  required String note,
  bool withAdvance = false,
}) {
  bool late(StandingOrder o) =>
      o.dueDate != null && calendarDays(o.dueDate!, today) > 0;
  final value = Money.sum(rows.map((o) => o.total));
  final pending = Money.sum(rows.map((o) => o.pendingValue));
  final advance = Money.sum(rows.map((o) => o.advance));
  final lateCount = rows.where(late).length;
  return ReportTable(
    id: id,
    title: title,
    period: ReportPeriod.day(today),
    columns: [
      const ReportColumn('Date', CellKind.text),
      const ReportColumn('Number', CellKind.text),
      ReportColumn(party, CellKind.text),
      const ReportColumn('Lines', CellKind.count),
      const ReportColumn('Value', CellKind.money),
      ReportColumn(done, CellKind.money),
      const ReportColumn('Still to come', CellKind.money),
      if (withAdvance) const ReportColumn('Advance', CellKind.money),
      const ReportColumn('Days open', CellKind.count),
      ReportColumn(due, CellKind.text),
      const ReportColumn('Status', CellKind.text),
    ],
    rows: [
      for (final o in rows)
        ReportRow(
          [
            o.date.value,
            o.docNo,
            o.party,
            o.lines,
            o.total,
            o.total - o.pendingValue,
            o.pendingValue,
            if (withAdvance) o.advance,
            calendarDays(o.date, today),
            o.dueDate?.value ?? '',
            late(o)
                ? 'Late'
                : o.started
                ? started
                : 'Open',
          ],
          link: ReportLink.document(
            o.documentId,
            label: o.docNo,
            docType: o.docType,
          ),
        ),
      ReportRow([
        'Total',
        rows.length == 1 ? '1 ${noun.$1}' : '${rows.length} ${noun.$2}',
        null,
        rows.fold<int>(0, (n, o) => n + o.lines),
        value,
        value - pending,
        pending,
        if (withAdvance) advance,
        null,
        null,
        lateCount == 0 ? null : '$lateCount late',
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('Open', rows.length),
      ReportFigure('Still to come', pending),
      if (withAdvance) ReportFigure('Advance held', advance),
      ReportFigure.count('Late', lateCount),
    ],
    notes: [note],
  );
}

/// The items on every standing purchase and sale order on [today]: how
/// much was ordered, how much has come in or gone out, and how much is
/// still to, the most still to come first.
ReportTable orderItemsDue(BusinessDate today, List<StandingOrderItem> items) {
  final rows = items.toList()
    ..sort((a, b) {
      final byKind = a.docType.compareTo(b.docType);
      if (byKind != 0) return byKind;
      final byValue = b.pendingValue.compareTo(a.pendingValue);
      return byValue != 0 ? byValue : a.itemName.compareTo(b.itemName);
    });
  Money on(String docType) => Money.sum([
    for (final i in rows)
      if (i.docType == docType) i.pendingValue,
  ]);
  return ReportTable(
    id: 'order_items_due',
    title: 'Items on open orders',
    period: ReportPeriod.day(today),
    columns: const [
      ReportColumn('Item', CellKind.text),
      ReportColumn('On', CellKind.text),
      ReportColumn('Ordered', CellKind.qty),
      ReportColumn('Received / delivered', CellKind.qty),
      ReportColumn('Still to come', CellKind.qty),
      ReportColumn('Unit', CellKind.text),
      ReportColumn('Value still to come', CellKind.money),
      ReportColumn('Orders', CellKind.count),
    ],
    rows: [
      for (final i in rows)
        ReportRow([
          i.itemName,
          i.docType == TransactionType.purchaseOrder
              ? 'Purchase orders'
              : 'Sale orders',
          i.ordered,
          i.done,
          i.pending,
          i.unitCode,
          i.pendingValue,
          i.orders,
        ]),
      ReportRow([
        'Total',
        null,
        null,
        null,
        null,
        null,
        Money.sum(rows.map((i) => i.pendingValue)),
        null,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('To arrive', on(TransactionType.purchaseOrder)),
      ReportFigure('To deliver', on(TransactionType.saleOrder)),
    ],
    notes: const [_orderItemsDueNote],
  );
}

const _orderItemsDueNote =
    'Quantities are in each item\'s base unit, at the rates on the orders. '
    'Only orders not cancelled and with something still to come are '
    'counted.';
