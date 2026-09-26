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
  });

  final String documentLineId;
  final String itemId;
  final String itemName;
  final String unitId;
  final String unitCode;

  /// In the item's base unit.
  final Qty boughtQty;

  /// What earlier returns against this line already sent back.
  final Qty alreadyReturned;

  /// What the supplier billed for the whole line.
  final Money goodsValue;

  /// What the whole line cost the shop, freight included. A snapshot.
  final Money landedCost;

  Qty get returnable =>
      Qty.raw(boughtQty.inThousandths - alreadyReturned.inThousandths);
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

  /// Quantities in the item's base unit.
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
      if (wanted.qty.inThousandths > bought.returnable.inThousandths) {
        throw ReturnRefused(
          'Only ${bought.returnable.display} ${bought.unitCode} of '
          '${bought.itemName} is left to go back on that delivery.',
        );
      }

      final before = running[bought.itemId] ?? CostPosition.zero;
      if (wanted.qty.inThousandths > before.qty.inThousandths) {
        // Goods that have been sold cannot be sent back. Letting this through
        // would drive the shelf negative with stock the shop is claiming to
        // hold and does not.
        throw ReturnRefused(
          'The shelf holds ${before.qty.display} ${bought.unitCode} of '
          '${bought.itemName}. What has already been sold cannot go back.',
        );
      }

      final whole = wanted.qty.inThousandths == bought.boughtQty.inThousandths;
      List<int> shares() => [
        wanted.qty.inThousandths,
        bought.boughtQty.inThousandths - wanted.qty.inThousandths,
      ];
      final goodsBack = whole
          ? bought.goodsValue
          : bought.goodsValue.allocate(shares()).first;
      final costBack = whole
          ? bought.landedCost
          : bought.landedCost.allocate(shares()).first;

      final change = returnStock(
        before: before,
        qtyOut: wanted.qty,
        valueOut: costBack,
      );
      running[bought.itemId] = change.after;

      credit += goodsBack;
      shelfOut += before.value - change.after.value;

      final rate = Rate.raw(
        divideRounded(
          scaleOrThrow(goodsBack.inPaisa, 1000000, 'returned value'),
          wanted.qty.inThousandths,
          RoundingMode.halfUp,
        ),
      );

      lines.add(
        DocumentLinePosting(
          lineNo: lineNo,
          itemId: bought.itemId,
          itemNameSnapshot: bought.itemName,
          qty: wanted.qty,
          unitId: bought.unitId,
          unitCodeSnapshot: bought.unitCode,
          baseQty: wanted.qty,
          rate: rate,
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
          qtyDelta: Qty.raw(-wanted.qty.inThousandths),
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
