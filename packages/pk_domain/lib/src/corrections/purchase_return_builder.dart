/// Goods going back to the supplier.
///
/// The correction a delivery has been missing. A sack that arrived torn, a
/// carton of the wrong brand, ten entered where the mill sent eight: until
/// this, nothing could take a delivery back, and a void was refused on
/// purpose because reversing a delivery's stock without its cost leaves the
/// average resting on goods the shop no longer has.
///
/// ## Two different numbers leave with the goods
///
///  * **What the supplier credits** — the goods value on their bill, pro-rated
///    by how much goes back. This is what comes off what the shop owes them,
///    or back into the drawer.
///  * **What the shelf gives up** — the LANDED cost the goods came in at, freight
///    included, read off `document_lines.cost_paisa` on the delivery. Not
///    today's average: see `returnStock`.
///
/// They differ by the freight that was paid to bring back goods that are
/// going back, and by rounding. That difference is the shop's, and it goes
/// to cost of goods where a shopkeeper's margin report can see it, rather than
/// being quietly folded into the average of what stays.
///
/// ## Money the supplier owes back
///
/// What comes off the delivery is capped at what is still owed on it. If the
/// shop has already paid for the goods going back, the supplier owes that
/// money back — an asset, and the chart has no advances-to-suppliers account
/// to hold it. So the rest must be taken back in cash now, and a return that
/// would leave it nowhere is refused in words, the same rule a supplier
/// payment follows.
library;

import 'package:pk_money/pk_money.dart';

import '../costing/moving_average.dart';
import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';
import 'return_builder.dart';

/// One line of the delivery, as it came in.
///
/// ## In the unit it was billed in (M57)
///
/// A mill bills in maunds and the shelf counts kilos. What can go back used
/// to be counted, shown and typed in kilos with the maund's name on it, so a
/// delivery of two maunds offered "80 maund" back, a tap on plus sent one
/// kilo, and the return's own line said "1 maund" for a kilo. The money
/// was right — the supplier's line total pro-rated over the kilos — but
/// nothing a shopkeeper read about the quantity was. It is now counted in
/// the unit the delivery was billed in, converted to the shelf's unit by
/// the conversion the delivery itself was made with.
///
/// The bill to a supplier carries no discount and no tax of its own here
/// (a delivery's lines are rate times quantity), so the first of the sale
/// return's two bugs has nothing to bite on: what the supplier credits is
/// already a share of the line total they billed.
final class BoughtLine {
  const BoughtLine({
    required this.documentLineId,
    required this.itemId,
    required this.itemName,
    required this.unitId,
    required this.unitCode,
    required this.boughtQty,
    required this.alreadyReturned,
    required this.goodsValue,
    required this.landedCost,
    this._qty,
    this._rate,
  });

  final String documentLineId;
  final String itemId;
  final String itemName;
  final String unitId;

  /// The unit the supplier billed in.
  final String unitCode;

  /// In the item's base unit.
  final Qty boughtQty;

  final Qty? _qty;

  /// As billed: two maunds is 2 here and 80 in [boughtQty].
  Qty get qty => _qty ?? boughtQty;

  final Rate? _rate;

  /// Per the unit billed in, as on the supplier's bill.
  Rate get rate =>
      _rate ??
      (qty.isPositive
          ? Rate.fromPack(goodsValue, qty, mode: RoundingMode.halfUp)
          : Rate.zero);

  /// What earlier returns against this line already sent back, in the base
  /// unit.
  final Qty alreadyReturned;

  /// What the supplier billed for the whole line.
  final Money goodsValue;

  /// What the whole line cost the shop, freight included. A snapshot.
  final Money landedCost;

  /// What can still go back, in the base unit.
  Qty get returnableBase {
    final left = boughtQty.inThousandths - alreadyReturned.inThousandths;
    return left > 0 ? Qty.raw(left) : Qty.zero;
  }

  /// What can still go back, in the unit billed in: what the sheet shows
  /// and what may be typed. Rounded down.
  Qty get returnable {
    final left = returnableBase.inThousandths;
    if (left == 0 || boughtQty.inThousandths <= 0) return Qty.zero;
    if (qty.inThousandths == boughtQty.inThousandths) return Qty.raw(left);
    return Qty.raw(left * qty.inThousandths ~/ boughtQty.inThousandths);
  }

  /// [inUnit] of the unit billed in, in the base unit: exactly, or refused.
  /// All that is left is always all that is left.
  Qty baseOf(Qty inUnit) {
    if (inUnit == returnable) return returnableBase;
    if (qty.inThousandths == boughtQty.inThousandths) return inUnit;
    final numerator = inUnit.inThousandths * boughtQty.inThousandths;
    if (numerator % qty.inThousandths != 0) {
      throw ReturnRefused(
        '${inUnit.display} $unitCode of $itemName does not come out even on '
        'the shelf. Send back a whole number of $unitCode, or all of it.',
      );
    }
    return Qty.raw(numerator ~/ qty.inThousandths);
  }

  /// What sending back [base] (in the base unit) is credited at, and what
  /// it gives up off the shelf: each the cumulative share of the line, so
  /// two sacks sent back on two days are credited exactly what the line
  /// was billed at between them, never a paisa more.
  ({Money credit, Money landed}) shareOf(Qty base) {
    final before = alreadyReturned.inThousandths;
    Money part(Money whole) => returnedShare(
      whole,
      before: before < 0 ? 0 : before,
      taking: base.inThousandths,
      outOf: boughtQty.inThousandths,
    );
    return (credit: part(goodsValue), landed: part(landedCost));
  }
}

/// What the shopkeeper entered.
final class PurchaseReturnDraft {
  const PurchaseReturnDraft({
    required this.originalDocumentId,
    required this.lines,
    required this.reason,
    this.refundNow = Money.zero,
    this.paymentAccountId,
  });

  final String originalDocumentId;

  /// Quantities in the unit each line was billed in (M57).
  final List<ReturnLineDraft> lines;
  final String reason;

  /// Money the supplier hands back now. The rest comes off the delivery.
  final Money refundNow;
  final String? paymentAccountId;
}

/// Everything one return to a supplier writes.
final class PurchaseReturnPosting {
  const PurchaseReturnPosting({
    required this.document,
    required this.lines,
    required this.stockMovements,
    required this.newAverages,
    required this.journal,
    required this.originalDocumentId,
    required this.refund,
    required this.againstBill,
    required this.auditSummary,
  });

  final DocumentPosting document;
  final List<DocumentLinePosting> lines;
  final List<StockMovementPosting> stockMovements;

  /// What each item's average becomes. Computed here so the writer applies
  /// numbers rather than working them out a second way.
  final Map<String, Rate> newAverages;

  final JournalEntryPosting journal;
  final String originalDocumentId;
  final Money refund;

  /// What comes off what the shop still owes on the delivery.
  final Money againstBill;

  final String auditSummary;

  void assertBalanced() {
    final debit = Money.sum([for (final l in journal.lines) l.debit]);
    final credit = Money.sum([for (final l in journal.lines) l.credit]);
    if (debit != credit) {
      throw StateError(
        'Return ${document.docNo} would post an unbalanced entry: debits '
        '${debit.amountOnly}, credits ${credit.amountOnly}.',
      );
    }
    for (final line in journal.lines) {
      if (line.debit.isNegative || line.credit.isNegative) {
        throw StateError(
          'Return ${document.docNo} line ${line.lineNo} carries a negative '
          'amount. A reversal swaps the sides; it never negates.',
        );
      }
    }
    if (refund + againstBill != document.total) {
      throw StateError(
        'Return ${document.docNo} credits ${document.total.amountOnly} and '
        'accounts for ${(refund + againstBill).amountOnly} of it.',
      );
    }
  }
}

/// Builds the rows one return to a supplier writes.
final class PurchaseReturnBuilder {
  const PurchaseReturnBuilder();

  /// [positions] is what the shelf holds of each item right now, read in the
  /// same transaction, keyed by item id.
  PurchaseReturnPosting build({
    required ActorContext actor,
    required PurchaseReturnDraft draft,
    required List<BoughtLine> boughtLines,
    required String originalDocNo,
    required String partyId,
    required Money originalOutstanding,
    required Map<String, CostPosition> positions,
    required AllocatedNumber returnNumber,
    required AllocatedNumber journalNumber,
    String? refundLedgerAccountId,
  }) {
    if (draft.lines.isEmpty) {
      throw const ReturnRefused('Nothing was selected to go back.');
    }
    if (draft.reason.trim().isEmpty) {
      throw const ReturnRefused('A return has to say why.');
    }
    if (draft.refundNow.isNegative) {
      throw const ReturnRefused(
        'A negative refund is a payment, and it has its own path.',
      );
    }
    if (draft.refundNow.isPositive && refundLedgerAccountId == null) {
      throw const ReturnRefused(
        'Money is coming back and there is no account it goes into.',
      );
    }

    final byLineId = {for (final l in boughtLines) l.documentLineId: l};
    final running = <String, CostPosition>{...positions};

    final lines = <DocumentLinePosting>[];
    final movements = <StockMovementPosting>[];
    var credit = Money.zero;
    var shelfOut = Money.zero;
    var lineNo = 1;

    for (final wanted in draft.lines) {
      final bought = byLineId[wanted.documentLineId];
      if (bought == null) {
        throw const ReturnRefused(
          'One of the lines is not on that delivery. Only what came in on it '
          'can go back on it.',
        );
      }
      if (!wanted.qty.isPositive) {
        throw ReturnRefused(
          'A return of nothing on ${bought.itemName} is not a return.',
        );
      }
      if (wanted.qty > bought.returnable) {
        throw ReturnRefused(
          'Only ${bought.returnable.display} ${bought.unitCode} of '
          '${bought.itemName} is left to go back on that delivery.',
        );
      }
      // Typed in the unit billed in; the shelf speaks the base unit.
      final baseQty = bought.baseOf(wanted.qty);

      final before = running[bought.itemId] ?? CostPosition.zero;
      if (baseQty > before.qty) {
        // Goods that have been sold cannot be sent back. Letting this through
        // would drive the shelf negative with stock the shop is claiming to
        // hold and does not. Said in the unit the shopkeeper typed in.
        final onShelf =
            bought.qty.inThousandths == bought.boughtQty.inThousandths
            ? before.qty
            : Qty.raw(
                before.qty.inThousandths *
                    bought.qty.inThousandths ~/
                    bought.boughtQty.inThousandths,
              );
        throw ReturnRefused(
          'The shelf holds ${onShelf.display} ${bought.unitCode} of '
          '${bought.itemName}. What has already been sold cannot go back.',
        );
      }

      final (credit: goodsBack, landed: costBack) = bought.shareOf(baseQty);

      final change = returnStock(
        before: before,
        qtyOut: baseQty,
        valueOut: costBack,
      );
      running[bought.itemId] = change.after;

      credit += goodsBack;
      shelfOut += before.value - change.after.value;

      lines.add(
        DocumentLinePosting(
          lineNo: lineNo,
          itemId: bought.itemId,
          itemNameSnapshot: bought.itemName,
          // In the unit it was billed in, at the rate it was billed at, so
          // the return reads like the supplier's paper: "1 maund @ 4,800".
          qty: wanted.qty,
          unitId: bought.unitId,
          unitCodeSnapshot: bought.unitCode,
          baseQty: baseQty,
          rate: bought.rate,
          gross: goodsBack,
          discount: Money.zero,
          discountBp: 0,
          taxable: goodsBack,
          tax: Money.zero,
          lineTotal: goodsBack,
          cost: costBack,
          isFreeItem: false,
          taxes: const [],
        ),
      );
      movements.add(
        StockMovementPosting(
          itemId: bought.itemId,
          txnType: 'purchase_return',
          qtyDelta: Qty.raw(-baseQty.inThousandths),
          rate: change.after.avg,
          valueDelta: Money.paisa(-(before.value - change.after.value).inPaisa),
          occurredAtUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
          occurredOnLocal: actor.businessDate.value,
          lineNo: lineNo,
        ),
      );
      lineNo++;
    }

    if (draft.refundNow > credit) {
      throw ReturnRefused(
        'More is coming back than the goods were billed at: '
        '${draft.refundNow.amountOnly} against ${credit.amountOnly}.',
      );
    }

    final againstBill = credit - draft.refundNow;
    if (againstBill > originalOutstanding) {
      throw ReturnRefused(
        'Only ${originalOutstanding.amountOnly} is still owed on that '
        'delivery, so at least '
        '${(credit - originalOutstanding).amountOnly} has to come back in '
        'cash now. The shop has no account yet for money a supplier owes it.',
      );
    }

    final journalLines = <JournalLinePosting>[];
    var jl = 1;
    void post({
      required String key,
      Money debit = Money.zero,
      Money credit = Money.zero,
      String? party,
      String? narration,
    }) {
      if (debit.isZero && credit.isZero) return;
      journalLines.add(
        JournalLinePosting(
          lineNo: jl++,
          accountSystemKey: key,
          debit: debit,
          credit: credit,
          partyId: party,
          narration: narration,
        ),
      );
    }

    // What the shop owes the supplier comes down, by name.
    post(
      key: 'accounts_payable',
      debit: againstBill,
      party: partyId,
      narration: 'Returned on ${returnNumber.formatted}',
    );
    // And whatever they hand back now goes into the drawer or the bank.
    post(
      key: '#$refundLedgerAccountId',
      debit: draft.refundNow,
      narration: 'Refund on ${returnNumber.formatted}',
    );
    // The shelf gives up what the goods are carried at.
    post(
      key: 'inventory',
      credit: shelfOut,
      narration: 'Back to supplier on ${returnNumber.formatted}',
    );
    // The difference is the shop's: freight paid on goods that went back,
    // and rounding. Signed either way, so it is a debit or a credit and never
    // a negative.
    final difference = credit - shelfOut;
    post(
      key: 'cogs',
      debit: difference.isNegative ? difference.abs : Money.zero,
      credit: difference.isPositive ? difference : Money.zero,
      narration: 'Cost difference on ${returnNumber.formatted}',
    );

    final totalDebit = Money.sum([for (final l in journalLines) l.debit]);
    final totalCredit = Money.sum([for (final l in journalLines) l.credit]);

    final posting = PurchaseReturnPosting(
      document: DocumentPosting(
        docType: 'purchase_return',
        docNo: returnNumber.formatted,
        docSeries: returnNumber.series,
        docSeq: returnNumber.sequence,
        fiscalYear: actor.businessDate.fiscalYear,
        docDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        docDateLocal: actor.businessDate.value,
        subtotal: credit,
        lineDiscount: Money.zero,
        billDiscount: Money.zero,
        taxable: credit,
        tax: Money.zero,
        furtherTax: Money.zero,
        withholding: Money.zero,
        extraCharges: Money.zero,
        roundOff: Money.zero,
        total: credit,
        paid: draft.refundNow,
        balance: Money.zero,
        cost: shelfOut,
        roundingMode: 'half_up',
        taxRuleVersion: '',
        cashThresholdBreached: false,
        partyId: partyId,
        notes: draft.reason.trim(),
      ),
      lines: lines,
      stockMovements: movements,
      newAverages: {
        for (final line in lines) line.itemId!: running[line.itemId]!.avg,
      },
      journal: JournalEntryPosting(
        entryNo: journalNumber.formatted,
        entryDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        entryDateLocal: actor.businessDate.value,
        fiscalYear: actor.businessDate.fiscalYear,
        sourceType: 'purchase_return',
        totalDebit: totalDebit,
        totalCredit: totalCredit,
        narration: 'Return ${returnNumber.formatted} against $originalDocNo',
        lines: journalLines,
      ),
      originalDocumentId: draft.originalDocumentId,
      refund: draft.refundNow,
      againstBill: againstBill,
      auditSummary:
          'Return ${returnNumber.formatted} to supplier against '
          '$originalDocNo for ${credit.amountOnly}: ${draft.reason.trim()}',
    );

    posting.assertBalanced();
    return posting;
  }
}
