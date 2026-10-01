/// A delivery challan: goods sent to a customer before the bill.
///
/// A wholesaler's van leaves at nine with forty cartons for a retailer who
/// is billed at the end of the week, or once his own customer has paid him.
/// The driver carries a challan, the retailer signs it, and the goods are
/// gone from the godown the moment the van leaves. Nothing is owed yet: the
/// price may still be argued, and some cartons may come back.
///
/// So a challan moves stock and nothing else a customer can see. In the
/// books the goods leave Inventory at what they cost and wait in Goods on
/// Challan, which is still the shop's own asset; the bill made from the
/// challan later takes them from there to Cost of Goods Sold, without
/// moving any stock a second time.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../sales/sale_calculator.dart';
import '../sales/sale_draft.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';

/// Why a challan cannot be written, or billed, in words.
final class ChallanRefused implements Exception {
  const ChallanRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Everything one challan writes.
final class ChallanPosting {
  const ChallanPosting({
    required this.document,
    required this.lines,
    required this.stockMovements,
    required this.journal,
    required this.auditSummary,
    this.fromQuotationId,
  });

  final DocumentPosting document;
  final List<DocumentLinePosting> lines;
  final List<StockMovementPosting> stockMovements;

  /// The quotation these goods were sent against, linked `converted_from`
  /// (M25): the customer said yes, and the goods went before the bill.
  final String? fromQuotationId;

  /// Null only when nothing on it had a cost to move.
  final JournalEntryPosting? journal;
  final String auditSummary;
}

/// Builds a delivery challan from a priced cart.
final class DeliveryChallanBuilder {
  const DeliveryChallanBuilder();

  ChallanPosting build({
    required ActorContext actor,
    required SaleDraft draft,
    required CalculatedSale calculated,
    required AllocatedNumber number,
    required AllocatedNumber journalNumber,
  }) {
    if (draft.lines.isEmpty) {
      throw const ChallanRefused('A challan needs at least one item.');
    }
    if (draft.partyId == null) {
      // Goods sent on credit of a bill to come have to be sent to somebody
      // the bill can be made out to.
      throw const ChallanRefused(
        'A challan has to name the customer the goods are going to.',
      );
    }
    if (draft.tenders.isNotEmpty) {
      throw const ChallanRefused(
        'A challan takes no money. Record an advance as a receipt.',
      );
    }

    final millis = actor.epochMillis;
    final localDate = actor.businessDate.value;
    final fiscalYear = actor.businessDate.fiscalYear;

    final stock = <StockMovementPosting>[
      for (final l in calculated.lines)
        if (l.draft.tracksStock && !l.draft.baseQty.isZero)
          StockMovementPosting(
            itemId: l.draft.itemId,
            txnType: 'sale',
            qtyDelta: -l.draft.baseQty,
            rate: l.draft.unitCost,
            valueDelta: -l.cost,
            occurredAtUtcMillis: millis,
            occurredOnLocal: localDate,
            lineNo: l.lineNo,
            lotId: l.draft.lotId,
          ),
    ];

    //   Dr  Goods on Challan     cost of what left
    //     Cr  Inventory          cost of what left
    final cost = calculated.cost;
    final journal = cost.isZero
        ? null
        : JournalEntryPosting(
            entryNo: journalNumber.formatted,
            entryDateUtcMillis: millis,
            entryDateLocal: localDate,
            fiscalYear: fiscalYear,
            sourceType: 'sale',
            totalDebit: cost,
            totalCredit: cost,
            narration: 'Challan ${number.formatted}',
            lines: [
              JournalLinePosting(
                lineNo: 1,
                accountSystemKey: 'goods_on_challan',
                debit: cost,
                credit: Money.zero,
                partyId: draft.partyId,
                narration: 'Sent on ${number.formatted}',
              ),
              JournalLinePosting(
                lineNo: 2,
                accountSystemKey: 'inventory',
                debit: Money.zero,
                credit: cost,
              ),
            ],
          );

    final items = calculated.lines.length == 1
        ? '1 item'
        : '${calculated.lines.length} items';
    return ChallanPosting(
      fromQuotationId: draft.convertedFromId,
      document: DocumentPosting(
        docType: 'delivery_challan',
        docNo: number.formatted,
        docSeries: number.series,
        docSeq: number.sequence,
        fiscalYear: fiscalYear,
        docDateUtcMillis: millis,
        docDateLocal: localDate,
        partyId: draft.partyId,
        partyNameSnapshot: draft.partyName,
        partyNtnSnapshot: draft.partyNtn,
        partyStrnSnapshot: draft.partyStrn,
        partyAddressSnapshot: draft.partyAddress,
        subtotal: calculated.subtotal,
        lineDiscount: calculated.lineDiscountTotal,
        billDiscount: calculated.billDiscount,
        taxable: calculated.taxable,
        tax: calculated.tax,
        furtherTax: calculated.furtherTax,
        withholding: calculated.withholding,
        extraCharges: calculated.extraCharges,
        roundOff: calculated.roundOff,
        total: calculated.total,
        // Nothing is owed on a challan. The value is printed so the customer
        // knows what the bill will say; the bill is what they owe.
        paid: Money.zero,
        balance: Money.zero,
        cost: cost,
        roundingMode: roundingModeCode(draft.roundingMode),
        taxRuleVersion: calculated.ruleVersion,
        cashThresholdBreached: false,
        salespersonId: draft.salespersonId,
        notes: draft.notes,
        terms: 'Goods received in good condition',
      ),
      lines: [for (final l in calculated.lines) documentLineFor(l)],
      stockMovements: stock,
      journal: journal,
      auditSummary:
          'Challan ${number.formatted} to ${draft.partyName}, $items, '
          'valued ${calculated.total.amountOnly}',
    );
  }
}

/// What one challan sent, per item, for the bill made from it.
final class ChallanGoods {
  const ChallanGoods({
    required this.challanId,
    required this.docNo,
    required this.partyId,
    required this.byItem,
  });

  final String challanId;
  final String docNo;
  final String? partyId;

  /// Base quantity sent and what it cost, per item.
  final Map<String, ({Qty qty, Money cost})> byItem;

  Money get cost => Money.sum([for (final g in byItem.values) g.cost]);

  /// Several challans to one party, billed together (M25): what they sent
  /// between them, item by item.
  static ChallanGoods combine(List<ChallanGoods> challans) {
    if (challans.length == 1) return challans.single;
    final first = challans.first;
    for (final c in challans.skip(1)) {
      if (c.partyId != first.partyId) {
        throw ChallanRefused(
          '${c.docNo} went to somebody else than ${first.docNo}. One bill '
          'is for one customer.',
        );
      }
    }
    final byItem = <String, ({Qty qty, Money cost})>{};
    for (final c in challans) {
      for (final MapEntry(key: item, value: sent) in c.byItem.entries) {
        final held = byItem[item];
        byItem[item] = held == null
            ? sent
            : (qty: held.qty + sent.qty, cost: held.cost + sent.cost);
      }
    }
    return ChallanGoods(
      challanId: first.challanId,
      docNo: [for (final c in challans) c.docNo].join(', '),
      partyId: first.partyId,
      byItem: byItem,
    );
  }

  /// The cost of each calculated line, taken from what the challan sent.
  ///
  /// A bill from a challan bills exactly what the challan sent: every item,
  /// in the quantity sent. The price may be settled differently, which is
  /// often why the bill came later; the goods may not. Goods that came back
  /// are the challan cancelled and sent again, and more goods are another
  /// bill, so the cost the goods left at can be carried across to the paisa.
  Map<int, Money> costOfLines(List<CalculatedLine> lines) {
    final billed = <String, Qty>{};
    for (final l in lines) {
      billed[l.draft.itemId] =
          (billed[l.draft.itemId] ?? Qty.zero) + l.draft.baseQty;
    }
    for (final MapEntry(key: itemId, value: sent) in byItem.entries) {
      if (billed[itemId] != sent.qty) {
        throw ChallanRefused(
          'The bill has to be for exactly what went on $docNo. Change the '
          'price if you must, not the goods.',
        );
      }
    }
    if (billed.keys.any((id) => !byItem.containsKey(id))) {
      throw ChallanRefused(
        'The bill has something that did not go on $docNo. Bill it '
        'separately.',
      );
    }

    // An item on two lines shares its cost between them by quantity, the
    // last line taking what rounding leaves.
    final result = <int, Money>{};
    for (final MapEntry(key: itemId, value: sent) in byItem.entries) {
      final itemLines = [
        for (final l in lines)
          if (l.draft.itemId == itemId) l,
      ];
      if (sent.qty.isZero) {
        for (final l in itemLines) {
          result[l.lineNo] = Money.zero;
        }
        continue;
      }
      final shares = sent.cost.allocate([
        for (final l in itemLines) l.draft.baseQty.inThousandths,
      ]);
      for (var i = 0; i < itemLines.length; i++) {
        result[itemLines[i].lineNo] = shares[i];
      }
    }
    return result;
  }
}
