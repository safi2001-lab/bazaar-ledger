/// A customer bringing goods back.
///
/// Distinct from a void, and the distinction is the whole reason this exists.
/// A void says the bill should never have happened; a return says it did, and
/// then some of it came back. A shopkeeper who sold five things and had one
/// returned cannot void the bill — the other four were sold, the customer
/// keeps them, and the tax on them is owed.
///
/// ## The cost the goods come back at
///
/// Whatever they left at, read off `document_lines.cost_paisa` on the
/// original sale. NOT today's average.
///
/// This is the single most important decision here and the easy one to get
/// wrong. Stock has moved since: deliveries have landed, the average has
/// shifted. Bringing a tin back in at today's cost would create or destroy
/// inventory value out of nothing — the shop would book a profit or a loss on
/// a customer changing their mind — and the difference would land in no
/// account at all.
///
/// The same principle as `document_lines.cost_paisa` existing in the first
/// place: a historical document's cost is a snapshot, and every report that
/// recomputes margin from today's average silently restates last month's
/// profit.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';

/// One line of the original bill, as it was sold.
final class SoldLine {
  const SoldLine({
    required this.documentLineId,
    required this.itemId,
    required this.itemName,
    required this.unitId,
    required this.unitCode,
    required this.soldQty,
    required this.alreadyReturned,
    required this.rate,
    required this.cost,
  });

  final String documentLineId;
  final String itemId;
  final String itemName;
  final String unitId;
  final String unitCode;

  /// In the item's base unit.
  final Qty soldQty;

  /// What earlier returns against this line already took back. A customer
  /// returning one tin twice from a bill for two is two separate visits, and
  /// the second must not be allowed to take back a third.
  final Qty alreadyReturned;

  /// What the customer paid per base unit.
  final Rate rate;

  /// What the goods cost the shop when they left, in whole paisa for the
  /// WHOLE line. A snapshot, never recomputed.
  final Money cost;

  Qty get returnable =>
      Qty.raw(soldQty.inThousandths - alreadyReturned.inThousandths);
}

/// How much of one line is coming back.
final class ReturnLineDraft {
  const ReturnLineDraft({required this.documentLineId, required this.qty});

  final String documentLineId;
  final Qty qty;
}

/// What the shopkeeper entered.
final class ReturnDraft {
  const ReturnDraft({
    required this.originalDocumentId,
    required this.lines,
    required this.reason,
    this.refundNow = Money.zero,
    this.paymentAccountId,
  });

  final String originalDocumentId;
  final List<ReturnLineDraft> lines;
  final String reason;

  /// Cash handed back over the counter. The rest reduces what the customer
  /// owes, or becomes credit if they owed nothing.
  final Money refundNow;
  final String? paymentAccountId;
}

/// Why a return cannot be recorded.
final class ReturnRefused implements Exception {
  const ReturnRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Everything one return writes.
final class ReturnPosting {
  const ReturnPosting({
    required this.document,
    required this.lines,
    required this.stockMovements,
    required this.journal,
    required this.originalDocumentId,
    required this.refund,
    required this.auditSummary,
  });

  final DocumentPosting document;
  final List<DocumentLinePosting> lines;
  final List<StockMovementPosting> stockMovements;
  final JournalEntryPosting journal;

  /// What this returns against, written to `doc_links` so the pair can always
  /// be found together and a second return knows what the first took.
  final String originalDocumentId;

  final Money refund;
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
          'amount. Goods coming back are a debit to returns, not a negative '
          'sale.',
        );
      }
    }
  }
}

/// Builds the rows one sale return writes.
final class ReturnBuilder {
  const ReturnBuilder();

  ReturnPosting build({
    required ActorContext actor,
    required ReturnDraft draft,
    required List<SoldLine> soldLines,
    required String originalDocNo,
    required String? partyId,
    required AllocatedNumber returnNumber,
    required AllocatedNumber journalNumber,
    String? refundLedgerAccountId,
  }) {
    if (draft.lines.isEmpty) {
      throw const ReturnRefused('Nothing was selected to come back.');
    }
    if (draft.reason.trim().isEmpty) {
      throw const ReturnRefused('A return has to say why.');
    }
    if (draft.refundNow.isNegative) {
      throw const ReturnRefused(
        'A negative refund is a sale, and it has its own path.',
      );
    }
    if (draft.refundNow.isPositive && refundLedgerAccountId == null) {
      throw const ReturnRefused(
        'Money is being handed back and there is no account it comes out of.',
      );
    }

    final byLineId = {for (final l in soldLines) l.documentLineId: l};

    final lines = <DocumentLinePosting>[];
    final movements = <StockMovementPosting>[];
    var goods = Money.zero;
    var costBack = Money.zero;
    var lineNo = 1;

    for (final wanted in draft.lines) {
      final sold = byLineId[wanted.documentLineId];
      if (sold == null) {
        throw const ReturnRefused(
          'One of the lines is not on that bill. A return can only take back '
          'what was actually sold.',
        );
      }
      if (!wanted.qty.isPositive) {
        throw ReturnRefused(
          'A return of nothing on ${sold.itemName} is not a return.',
        );
      }
      if (wanted.qty.inThousandths > sold.returnable.inThousandths) {
        // The check that stops a customer returning three tins from a bill
        // for two — across visits, not just within one. Without counting what
        // earlier returns took, a shop can be walked out of its entire stock
        // one bill at a time.
        throw ReturnRefused(
          'Only ${sold.returnable.display} ${sold.unitCode} of '
          '${sold.itemName} is left to come back on that bill.',
        );
      }

      final refundValue = sold.rate.amountFor(wanted.qty);
      // The line's cost, pro-rated by how much of it is coming back. Whole
      // paisa, allocated so a part return of an odd cost cannot lose one.
      final costOfReturn =
          sold.soldQty.inThousandths == wanted.qty.inThousandths
          ? sold.cost
          : sold.cost.allocate([
              wanted.qty.inThousandths,
              sold.soldQty.inThousandths - wanted.qty.inThousandths,
            ]).first;

      goods += refundValue;
      costBack += costOfReturn;

      lines.add(
        DocumentLinePosting(
          lineNo: lineNo,
          itemId: sold.itemId,
          itemNameSnapshot: sold.itemName,
          qty: wanted.qty,
          unitId: sold.unitId,
          unitCodeSnapshot: sold.unitCode,
          baseQty: wanted.qty,
          rate: sold.rate,
          gross: refundValue,
          discount: Money.zero,
          discountBp: 0,
          taxable: refundValue,
          // Tax on a return lands in M12 with the rest of the tax pack. A
          // return of a taxed sale currently gives back the goods value and
          // nothing else, which is visibly incomplete rather than quietly
          // wrong — and it is stated here so it is not mistaken for done.
          tax: Money.zero,
          lineTotal: refundValue,
          cost: costOfReturn,
          isFreeItem: false,
          taxes: const [],
        ),
      );

      movements.add(
        StockMovementPosting(
          itemId: sold.itemId,
          txnType: 'sale_return',
          qtyDelta: wanted.qty,
          // At the cost it left at. See the library comment: today's average
          // would book a profit or a loss on a customer changing their mind.
          rate: sold.cost.isZero
              ? const Rate.raw(0)
              : Rate.raw(
                  divideRounded(
                    scaleOrThrow(costOfReturn.inPaisa, 1000000, 'return cost'),
                    wanted.qty.inThousandths,
                    RoundingMode.halfUp,
                  ),
                ),
          valueDelta: costOfReturn,
          occurredAtUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
          occurredOnLocal: actor.businessDate.value,
          lineNo: lineNo,
        ),
      );
      lineNo++;
    }

    if (draft.refundNow > goods) {
      throw ReturnRefused(
        'More is being handed back than the goods were sold for: '
        '${draft.refundNow.amountOnly} against ${goods.amountOnly}.',
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

    // Dr Sales Returns, gross. A contra-revenue account rather than a debit
    // to Sales, because a shopkeeper who took Rs 40,000 of returns in a month
    // needs to be able to see that number — netting it into Sales hides it.
    post(
      key: 'sales_returns',
      debit: goods,
      narration: 'Returned on $originalDocNo',
    );

    // Cash out of the drawer for what was handed back now.
    post(
      key: '#$refundLedgerAccountId',
      credit: draft.refundNow,
      narration: 'Refunded on ${returnNumber.formatted}',
    );

    // The rest comes off what the customer owes. With no party there is
    // nobody to credit, which is why a walk-in return has to be refunded in
    // full — checked below rather than discovered as an unbalanced entry.
    final credited = goods - draft.refundNow;
    if (credited.isPositive) {
      if (partyId == null) {
        throw const ReturnRefused(
          'A walk-in return has to be paid back over the counter. There is no '
          'khata to put the credit on.',
        );
      }
      post(
        key: 'accounts_receivable',
        credit: credited,
        party: partyId,
        narration: 'Credit on ${returnNumber.formatted}',
      );
    }

    // And the goods come back onto the shelf at what they cost.
    post(key: 'inventory', debit: costBack);
    post(key: 'cogs', credit: costBack);

    final totalDebit = Money.sum([for (final l in journalLines) l.debit]);
    final totalCredit = Money.sum([for (final l in journalLines) l.credit]);

    final posting = ReturnPosting(
      document: DocumentPosting(
        docType: 'sale_return',
        docNo: returnNumber.formatted,
        docSeries: returnNumber.series,
        docSeq: returnNumber.sequence,
        fiscalYear: actor.businessDate.fiscalYear,
        docDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        docDateLocal: actor.businessDate.value,
        subtotal: goods,
        lineDiscount: Money.zero,
        billDiscount: Money.zero,
        taxable: goods,
        tax: Money.zero,
        furtherTax: Money.zero,
        withholding: Money.zero,
        extraCharges: Money.zero,
        roundOff: Money.zero,
        total: goods,
        paid: draft.refundNow,
        balance: Money.zero,
        cost: costBack,
        roundingMode: 'half_up',
        taxRuleVersion: '',
        cashThresholdBreached: false,
        partyId: partyId,
        notes: draft.reason.trim(),
      ),
      lines: lines,
      stockMovements: movements,
      journal: JournalEntryPosting(
        entryNo: journalNumber.formatted,
        entryDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        entryDateLocal: actor.businessDate.value,
        fiscalYear: actor.businessDate.fiscalYear,
        sourceType: 'sale_return',
        totalDebit: totalDebit,
        totalCredit: totalCredit,
        narration: 'Return ${returnNumber.formatted} against $originalDocNo',
        lines: journalLines,
      ),
      originalDocumentId: draft.originalDocumentId,
      refund: draft.refundNow,
      auditSummary:
          'Return ${returnNumber.formatted} against $originalDocNo for '
          '${goods.amountOnly}: ${draft.reason.trim()}',
    );

    posting.assertBalanced();
    return posting;
  }
}
