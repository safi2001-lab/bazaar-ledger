/// Purchase orders and sale orders (M41): what the shop has asked a
/// supplier to send, and what a customer has asked the shop to keep for
/// them.
///
/// Both are promises on paper, and neither is the books. A purchase order
/// is the list the order-booker writes in his diary on Tuesday, sent to the
/// mill on WhatsApp so the delivery on Friday can be checked against it; a
/// sale order is the wholesale customer's "do bori cheeni aur ek carton
/// ghee Jumme ko bhej dena". No stock moves, no money is owed, no entry is
/// posted: a document and its lines, numbered, and nothing else. The
/// delivery that arrives against a purchase order, and the bill or challan
/// made from a sale order, are the documents that reach the books, each
/// linked back `converted_from` as a bill made from a quotation is (M25).
///
/// What has come in or gone out against an order is never stored on it. It
/// is read off the documents linked to it, so a delivery entered twice and
/// one of them cancelled, or a bill voided after it was made from the
/// order, can never leave an order saying something the books do not.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';
import '../time/clock.dart';

/// Which side of the counter an order is on.
enum OrderKind {
  /// What the shop has asked a supplier for.
  purchase('purchase_order'),

  /// What a customer has asked the shop for.
  sale('sale_order');

  const OrderKind(this.docType);

  /// The `documents.doc_type` it is kept as.
  final String docType;

  /// The kind [docType] is, or null for a document that is not an order.
  static OrderKind? ofDocType(String docType) {
    for (final k in values) {
      if (k.docType == docType) return k;
    }
    return null;
  }

  /// The words the due date is written into the terms with, in English, as
  /// a quotation writes "Prices valid until": the printed paper says it, and
  /// the date is read back off it, so the paper and the list cannot differ.
  String get dueWords => switch (this) {
    OrderKind.purchase => 'Expected by',
    OrderKind.sale => 'Promised for',
  };
}

/// Why an order cannot be written, in words.
final class OrderRefused implements Exception {
  const OrderRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// One line of an order as the shopkeeper wrote it.
final class OrderLineDraft {
  const OrderLineDraft({
    required this.itemId,
    required this.itemName,
    required this.qty,
    required this.baseQty,
    required this.unitId,
    required this.unitCode,
    required this.rate,
  });

  final String itemId;
  final String itemName;

  /// As ordered: bori, carton, dozen, whatever the supplier or the customer
  /// counts in.
  final Qty qty;

  /// The same quantity in the item's own unit, which is what a delivery and
  /// a bill against the order are counted in.
  final Qty baseQty;

  final String unitId;
  final String unitCode;

  /// Per [unitCode]. On a purchase order, the rate the supplier quoted,
  /// which the delivery is checked against; on a sale order, the price the
  /// customer was promised, which the bill made from it is rung at.
  final Rate rate;

  Money get lineTotal => rate.amountFor(qty);

  OrderLineDraft withQty(Qty qty, Qty baseQty) => OrderLineDraft(
    itemId: itemId,
    itemName: itemName,
    qty: qty,
    baseQty: baseQty,
    unitId: unitId,
    unitCode: unitCode,
    rate: rate,
  );
}

/// An order as the shopkeeper wrote it.
final class OrderDraft {
  const OrderDraft({
    required this.kind,
    required this.partyId,
    required this.lines,
    this.partyName,
    this.dueDate,
    this.notes,
  });

  final OrderKind kind;

  /// The supplier, or the customer. Always somebody: an order nobody placed
  /// and nobody is to fill is a list, and the shortage list is for that.
  final String partyId;
  final String? partyName;

  final List<OrderLineDraft> lines;

  /// When the goods are expected in, or promised out.
  final BusinessDate? dueDate;

  final String? notes;

  Money get total => Money.sum([for (final l in lines) l.lineTotal]);
}

/// Everything one order writes: a document and its lines.
final class OrderPosting {
  const OrderPosting({
    required this.document,
    required this.lines,
    required this.auditSummary,
  });

  final DocumentPosting document;
  final List<DocumentLinePosting> lines;
  final String auditSummary;
}

/// Builds an order from what the shopkeeper wrote.
final class OrderBuilder {
  const OrderBuilder();

  OrderPosting build({
    required ActorContext actor,
    required OrderDraft draft,
    required AllocatedNumber number,
  }) {
    if (draft.partyId.trim().isEmpty) {
      throw OrderRefused(
        draft.kind == OrderKind.purchase
            ? 'A purchase order needs a supplier.'
            : 'A sale order needs a customer.',
      );
    }
    if (draft.lines.isEmpty) {
      throw const OrderRefused('An order needs at least one item.');
    }
    for (final l in draft.lines) {
      if (!l.qty.isPositive || !l.baseQty.isPositive) {
        throw OrderRefused('${l.itemName}: how many is ordered?');
      }
      if (l.rate.inMilliPaisa < 0) {
        throw OrderRefused('${l.itemName}: a rate cannot be below nothing.');
      }
    }
    final due = draft.dueDate;
    final today = actor.businessDate;
    if (due != null && due.value.compareTo(today.value) < 0) {
      throw OrderRefused(
        '${draft.kind.dueWords} ${due.value} is a day already gone.',
      );
    }
    final total = draft.total;
    final notes = draft.notes?.trim();

    return OrderPosting(
      document: DocumentPosting(
        docType: draft.kind.docType,
        docNo: number.formatted,
        docSeries: number.series,
        docSeq: number.sequence,
        fiscalYear: today.fiscalYear,
        docDateUtcMillis: actor.epochMillis,
        docDateLocal: today.value,
        partyId: draft.partyId,
        partyNameSnapshot: draft.partyName,
        subtotal: total,
        lineDiscount: Money.zero,
        billDiscount: Money.zero,
        taxable: total,
        tax: Money.zero,
        furtherTax: Money.zero,
        withholding: Money.zero,
        extraCharges: Money.zero,
        roundOff: Money.zero,
        total: total,
        // Nothing is paid and nothing is owed on an order. A balance here
        // would be udhaar on goods that have not moved; an advance against
        // a sale order is a receipt on the khata, as it always was.
        paid: Money.zero,
        balance: Money.zero,
        cost: Money.zero,
        roundingMode: 'half_up',
        taxRuleVersion: '',
        cashThresholdBreached: false,
        notes: notes == null || notes.isEmpty ? null : notes,
        terms: due == null ? null : orderTerms(draft.kind, due),
      ),
      lines: [
        for (var i = 0; i < draft.lines.length; i++)
          () {
            final l = draft.lines[i];
            final amount = l.lineTotal;
            return DocumentLinePosting(
              lineNo: i + 1,
              itemId: l.itemId,
              itemNameSnapshot: l.itemName,
              qty: l.qty,
              baseQty: l.baseQty,
              unitId: l.unitId,
              unitCodeSnapshot: l.unitCode,
              rate: l.rate,
              gross: amount,
              discount: Money.zero,
              taxable: amount,
              tax: Money.zero,
              lineTotal: amount,
              cost: Money.zero,
              discountBp: 0,
              isFreeItem: false,
              taxes: const [],
            );
          }(),
      ],
      auditSummary:
          '${draft.kind == OrderKind.purchase ? 'Purchase order' : 'Sale order'} '
          '${number.formatted} for ${draft.partyName ?? 'a party'}, '
          '${draft.lines.length} line(s), ${total.amountOnly}'
          '${due == null ? '' : ', ${draft.kind.dueWords.toLowerCase()} ${due.value}'}',
    );
  }
}

/// The terms line an order's due date is written into.
String orderTerms(OrderKind kind, BusinessDate due) =>
    '${kind.dueWords} ${due.value}';

/// The due date [terms] carries, as [orderTerms] wrote it.
BusinessDate? orderDueDate(String? terms) {
  final match = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(terms ?? '');
  return match == null ? null : BusinessDate.tryParse(match.group(1)!);
}

/// Where an order stands.
enum OrderStatus {
  /// Nothing has come in, or gone out, against it yet.
  open,

  /// Some of it has.
  part,

  /// All of it has.
  done,

  /// Cancelled before anything came of it.
  cancelled,

  /// Cancelled after part of it came: what arrived stands, the rest will
  /// not be sent.
  closed;

  /// Whether goods are still to come in, or go out, against it.
  bool get isStanding => this == open || this == part;
}

/// Where an order with [lines] stands, cancelled or not.
OrderStatus orderStatusOf({
  required bool isVoid,
  required List<OrderLineProgress> lines,
}) {
  final any = lines.any((l) => l.done.isPositive);
  if (isVoid) return any ? OrderStatus.closed : OrderStatus.cancelled;
  if (lines.isNotEmpty && lines.every((l) => l.isDone)) {
    return OrderStatus.done;
  }
  return any ? OrderStatus.part : OrderStatus.open;
}

/// One line of an order, with how much of it has come in or gone out.
final class OrderLineProgress {
  const OrderLineProgress({
    required this.lineNo,
    required this.itemId,
    required this.itemName,
    required this.qty,
    required this.baseQty,
    required this.unitId,
    required this.unitCode,
    required this.baseUnitCode,
    required this.rate,
    required this.done,
    this.baseUnitId = '',
  });

  final int lineNo;
  final String itemId;
  final String itemName;

  /// As ordered, in [unitCode].
  final Qty qty;

  /// As ordered, in the item's own unit, [baseUnitCode].
  final Qty baseQty;
  final String unitId;
  final String unitCode;
  final String baseUnitId;
  final String baseUnitCode;
  final Rate rate;

  /// Received (a purchase order) or delivered (a sale order) against this
  /// line, in the item's own unit.
  final Qty done;

  /// Still to come, in the item's own unit. Never below nothing: a supplier
  /// who sent more than was asked for has filled the line, not overfilled
  /// the order.
  Qty get pendingBase => done >= baseQty ? Qty.zero : baseQty - done;

  bool get isDone => done >= baseQty;

  /// What is still to come, in the unit it was ordered in, when that comes
  /// out exact; otherwise null, and the item's own unit is the one to use.
  ///
  /// Two cartons of twelve with seven pieces in is seventeen pieces still to
  /// come, which is not a whole number of cartons and is not rounded into
  /// one.
  Qty? get pendingInOrderUnit {
    final pending = pendingBase;
    if (pending == baseQty) return qty;
    if (pending.isZero) return Qty.zero;
    if (unitCode == baseUnitCode || qty == baseQty) return pending;
    final scaled = pending.inThousandths * qty.inThousandths;
    if (scaled % baseQty.inThousandths != 0) return null;
    return Qty.raw(scaled ~/ baseQty.inThousandths);
  }

  /// [rate] per the item's own unit, as near as a milli-paisa goes: what a
  /// line still to come in the item's own unit is priced at.
  Rate get baseRate => qty == baseQty
      ? rate
      : Rate.raw(
          divideRounded(
            rate.inMilliPaisa * qty.inThousandths,
            baseQty.inThousandths,
            RoundingMode.halfUp,
          ),
        );

  /// What is still to come is worth, at the order's rate.
  Money get pendingValue => switch (pendingInOrderUnit) {
    final q? => rate.amountFor(q),
    null => baseRate.amountFor(pendingBase),
  };
}

/// Spreads what came in against an order over its lines, item by item, in
/// line order: an order with the same item on two lines fills the first
/// before the second, as a shopkeeper ticking a list would.
///
/// [ordered] is each line as ordered; [doneByItem] what the linked
/// documents carried of each item, in its own unit.
List<OrderLineProgress> spreadDone(
  List<OrderLineProgress> ordered,
  Map<String, Qty> doneByItem,
) {
  final left = {...doneByItem};
  return [
    for (final l in ordered)
      () {
        final have = left[l.itemId] ?? Qty.zero;
        // The last line of an item takes whatever is left, so an over-
        // delivery shows on the order rather than vanishing.
        final isLast = !ordered
            .skipWhile((o) => o.lineNo != l.lineNo)
            .skip(1)
            .any((o) => o.itemId == l.itemId);
        final take = isLast || have <= l.baseQty ? have : l.baseQty;
        left[l.itemId] = have - take;
        return OrderLineProgress(
          lineNo: l.lineNo,
          itemId: l.itemId,
          itemName: l.itemName,
          qty: l.qty,
          baseQty: l.baseQty,
          unitId: l.unitId,
          unitCode: l.unitCode,
          baseUnitId: l.baseUnitId,
          baseUnitCode: l.baseUnitCode,
          rate: l.rate,
          done: take.isNegative ? Qty.zero : take,
        );
      }(),
  ];
}

/// One order, as a list shows it.
final class OrderRow {
  const OrderRow({
    required this.id,
    required this.kind,
    required this.docNo,
    required this.date,
    required this.partyId,
    required this.partyName,
    required this.total,
    required this.status,
    required this.lineCount,
    this.dueDate,
    this.advance = Money.zero,
  });

  final String id;
  final OrderKind kind;
  final String docNo;
  final BusinessDate date;
  final String partyId;
  final String partyName;
  final Money total;
  final OrderStatus status;
  final int lineCount;

  /// When it is expected in, or promised out.
  final BusinessDate? dueDate;

  /// Taken from the customer against a sale order, and still standing.
  final Money advance;

  /// Whether it is past its day with goods still to come.
  bool isLateOn(BusinessDate today) =>
      status.isStanding &&
      dueDate != null &&
      dueDate!.value.compareTo(today.value) < 0;
}

/// A document that came of an order: a delivery against a purchase order,
/// a bill or a challan made from a sale order.
final class OrderFollowUp {
  const OrderFollowUp({
    required this.documentId,
    required this.docType,
    required this.docNo,
    required this.date,
    required this.total,
  });

  final String documentId;
  final String docType;
  final String docNo;
  final BusinessDate date;
  final Money total;
}

/// One order, opened: its lines and how far each has got, and what came of
/// it.
final class OrderView {
  const OrderView({
    required this.row,
    required this.lines,
    required this.followUps,
    this.notes,
  });

  final OrderRow row;
  final List<OrderLineProgress> lines;
  final List<OrderFollowUp> followUps;
  final String? notes;

  Money get pendingValue => Money.sum([for (final l in lines) l.pendingValue]);
}

/// Whether a delivery's [rate] is not the rate [ordered] on the purchase
/// order (M41): the supplier's bill and the order disagree, and it is
/// caught at the door rather than in the month's margins.
bool rateDiffers(Rate rate, Rate? ordered) =>
    ordered != null && rate != ordered;
