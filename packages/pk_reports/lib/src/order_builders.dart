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
