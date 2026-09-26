/// Turning a supplier's bill into rows.
///
/// Pure. Given the bill, each item's costing position as it stands, and the
/// numbers already allocated, it produces every row the purchase writes,
/// moves each average, and proves the entry balances — with no database in
/// the way.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';
import 'moving_average.dart';
import 'purchase_posting.dart';

/// One line as the shopkeeper entered it.
final class PurchaseLineDraft {
  const PurchaseLineDraft({
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

  /// As billed — bori, carton, whatever the supplier writes.
  final Qty qty;

  /// The same quantity in the item's base unit. Converted before it gets
  /// here, because two maunds is eighty kilos and the stock ledger only ever
  /// speaks kilos.
  final Qty baseQty;

  final String unitId;
  final String unitCode;

  /// Per billed unit, not per base unit.
  final Rate rate;

  Money get lineTotal => rate.amountFor(qty);
}

/// One line of a delivery, landed: what it cost with its share of the
/// freight, and what that did to the item's average.
final class LandedLine {
  const LandedLine({
    required this.landed,
    required this.before,
    required this.change,
  });

  final Money landed;
  final CostPosition before;
  final CostChange change;
}

/// What each line of [draft] does to the cost of the goods it carries, in
/// order.
///
/// The one place this is worked out. The builder posts from it, and the
/// purchase screen shows the new average per line from it, so the figure a
/// shopkeeper watches move as they type is the figure that gets written.
List<LandedLine> landLines(
  PurchaseDraft draft,
  Map<String, CostPosition> positions,
) {
  // Freight across the lines by value, using the allocator that cannot lose
  // a paisa. Splitting it evenly would put as much delivery cost on a Rs 50
  // packet as on a Rs 5,000 sack.
  final shares = draft.freight.isZero || draft.lines.isEmpty
      ? [for (final _ in draft.lines) Money.zero]
      : draft.freight.allocate([
          for (final l in draft.lines) l.lineTotal.inPaisa,
        ]);

  // Carried between lines, so a bill with the same item twice — a real thing
  // on a wholesale delivery — averages the second line against the first
  // rather than against the shelf as it was this morning.
  final running = <String, CostPosition>{...positions};

  return [
    for (var i = 0; i < draft.lines.length; i++)
      () {
        final line = draft.lines[i];
        final landed = line.lineTotal + shares[i];
        final before = running[line.itemId] ?? CostPosition.zero;
        final change = receiveStock(
          before: before,
          qtyIn: line.baseQty,
          landedCost: landed,
        );
        running[line.itemId] = change.after;
        return LandedLine(landed: landed, before: before, change: change);
      }(),
  ];
}

/// A supplier's bill.
final class PurchaseDraft {
  const PurchaseDraft({
    required this.partyId,
    required this.lines,
    this.supplierBillNo,
    this.freight = Money.zero,
    this.paid = Money.zero,
    this.paymentAccountId,
    this.notes,
  });

  /// Always a supplier. A purchase with no party is stock that appeared from
  /// nowhere, and the shop cannot pay or query it.
  final String partyId;

  final List<PurchaseLineDraft> lines;

  /// The supplier's own number, which is what the shopkeeper matches against
  /// the paper. Never used for numbering — that series is the shop's.
  final String? supplierBillNo;

  /// Delivery, labour, the rickshaw. Apportioned across the lines by value,
  /// because it is what the goods cost to have on the shelf and a margin
  /// computed against the invoice alone has never paid for delivery.
  final Money freight;

  /// Paid at the door. The rest is payable.
  final Money paid;
  final String? paymentAccountId;

  final String? notes;

  Money get goodsTotal => Money.sum([for (final l in lines) l.lineTotal]);
  Money get total => goodsTotal + freight;
}

/// Builds the rows one purchase bill writes.
final class PurchaseBuilder {
  const PurchaseBuilder();

  /// [positions] is each item's costing as it stands, keyed by item id.
  /// [ledgerAccountId] is where any cash paid at the door comes from.
  PurchasePosting build({
    required ActorContext actor,
    required PurchaseDraft draft,
    required Map<String, CostPosition> positions,
    required AllocatedNumber billNumber,
    required AllocatedNumber journalNumber,
    String? ledgerAccountId,
  }) {
    if (draft.lines.isEmpty) {
      throw ArgumentError.value(
        draft.lines.length,
        'lines',
        'a bill with no lines is not a delivery',
      );
    }
    if (draft.paid.isNegative) {
      throw ArgumentError.value(
        draft.paid.inPaisa,
        'paid',
        'a negative payment is a refund and has its own path',
      );
    }
    if (draft.paid > draft.total) {
      // Not an advance to the supplier: that is a payment out with no bill,
      // and it belongs on the supplier's khata rather than inflating what
      // this delivery cost.
      throw ArgumentError.value(
        draft.paid.inPaisa,
        'paid',
        'more was paid than the bill is for. Money handed over beyond a bill '
            'is an advance to the supplier, not part of this delivery.',
      );
    }
    if (draft.paid.isPositive && ledgerAccountId == null) {
      throw ArgumentError.value(
        ledgerAccountId,
        'ledgerAccountId',
        'money was paid at the door and there is no account it came out of',
      );
    }

    final landedLines = landLines(draft, positions);

    final lines = <PurchaseLinePosting>[];
    final movements = <StockMovementPosting>[];
    var rounding = Money.zero;
    var shortfall = Money.zero;
    var inventoryDelta = Money.zero;

    for (var i = 0; i < draft.lines.length; i++) {
      final line = draft.lines[i];
      final LandedLine(:landed, :before, :change) = landedLines[i];
      // Same subtraction, two accounts. A shortfall this delivery covered is
      // a real loss the books never took; anything else is a rounding step.
      if (change.fromShortfall) {
        shortfall += change.adjustment;
      } else {
        rounding += change.adjustment;
      }
      inventoryDelta += change.after.value - before.value;

      lines.add(
        PurchaseLinePosting(
          lineNo: i + 1,
          itemId: line.itemId,
          itemName: line.itemName,
          qty: line.qty,
          unitId: line.unitId,
          unitCode: line.unitCode,
          baseQty: line.baseQty,
          rate: line.rate,
          lineTotal: line.lineTotal,
          landedCost: landed,
          avgAfter: change.after.avg,
          balanceAfter: change.after.qty,
        ),
      );

      movements.add(
        StockMovementPosting(
          itemId: line.itemId,
          txnType: 'purchase',
          qtyDelta: line.baseQty,
          rate: change.after.avg,
          valueDelta: landed,
          occurredAtUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
          occurredOnLocal: actor.businessDate.value,
          lineNo: i + 1,
        ),
      );
    }

    final journalLines = <JournalLinePosting>[];
    var lineNo = 1;

    void post({
      required String key,
      Money debit = Money.zero,
      Money credit = Money.zero,
      String? partyId,
      String? narration,
    }) {
      if (debit.isZero && credit.isZero) return;
      journalLines.add(
        JournalLinePosting(
          lineNo: lineNo++,
          accountSystemKey: key,
          debit: debit,
          credit: credit,
          partyId: partyId,
          narration: narration,
        ),
      );
    }

    // Dr Inventory by what the shelf is actually worth now, minus what it was
    // worth before. NOT by the landed cost: when the balance was negative the
    // account really did hold that negative figure, and debiting the landed
    // cost would assume it started at zero.
    post(
      key: 'inventory',
      debit: inventoryDelta.isPositive ? inventoryDelta : Money.zero,
      credit: inventoryDelta.isNegative ? inventoryDelta.abs : Money.zero,
      narration: 'Goods received ${billNumber.formatted}',
    );

    // A shortfall this delivery covered. The shop sold goods it had never
    // recorded receiving, so the books carried them out at the old average;
    // the delivery reveals what they actually cost, and the difference was
    // never anybody's profit.
    post(
      key: 'stock_wastage',
      debit: shortfall.isPositive ? shortfall : Money.zero,
      credit: shortfall.isNegative ? shortfall.abs : Money.zero,
      narration: 'Shortfall settled by ${billNumber.formatted}',
    );

    // The paisa induction could not place. Signed either way, so it is a
    // debit or a credit rather than a negative.
    post(
      key: 'cogs',
      debit: rounding.isPositive ? rounding : Money.zero,
      credit: rounding.isNegative ? rounding.abs : Money.zero,
      narration: 'Rounding on ${billNumber.formatted}',
    );

    // What was handed over at the door, and what is still owed.
    post(
      key: '#$ledgerAccountId',
      credit: draft.paid,
      narration: 'Paid on ${billNumber.formatted}',
    );
    post(
      key: 'accounts_payable',
      credit: draft.total - draft.paid,
      partyId: draft.partyId,
      narration: 'Owed on ${billNumber.formatted}',
    );

    final debits = Money.sum([for (final l in journalLines) l.debit]);
    final credits = Money.sum([for (final l in journalLines) l.credit]);

    final posting = PurchasePosting(
      document: DocumentPosting(
        docType: 'purchase_bill',
        docNo: billNumber.formatted,
        docSeries: billNumber.series,
        docSeq: billNumber.sequence,
        fiscalYear: actor.businessDate.fiscalYear,
        docDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        docDateLocal: actor.businessDate.value,
        subtotal: draft.goodsTotal,
        lineDiscount: Money.zero,
        billDiscount: Money.zero,
        taxable: draft.goodsTotal,
        tax: Money.zero,
        furtherTax: Money.zero,
        withholding: Money.zero,
        extraCharges: draft.freight,
        roundOff: Money.zero,
        total: draft.total,
        paid: draft.paid,
        balance: draft.total - draft.paid,
        cost: Money.sum([for (final l in lines) l.landedCost]),
        roundingMode: 'half_up',
        taxRuleVersion: '',
        cashThresholdBreached: false,
        partyId: draft.partyId,
        notes: draft.notes,
      ),
      lines: lines,
      stockMovements: movements,
      journal: JournalEntryPosting(
        entryNo: journalNumber.formatted,
        entryDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        entryDateLocal: actor.businessDate.value,
        fiscalYear: actor.businessDate.fiscalYear,
        sourceType: 'purchase',
        totalDebit: debits,
        totalCredit: credits,
        narration: 'Purchase ${billNumber.formatted}',
        lines: journalLines,
      ),
      rounding: rounding,
      shortfall: shortfall,
      auditSummary:
          'Purchase ${billNumber.formatted} for ${draft.total.amountOnly} '
          'across ${lines.length} line(s)'
          '${draft.supplierBillNo == null ? '' : ', supplier bill '
                    '${draft.supplierBillNo}'}',
    );

    posting.assertBalanced();
    return posting;
  }
}
