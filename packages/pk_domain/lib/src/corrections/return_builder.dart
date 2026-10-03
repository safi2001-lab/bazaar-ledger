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
///
/// ## The money that comes back (M57)
///
/// Exactly what the line was charged, never its list price. This used to
/// multiply the rate by the quantity coming back, which was wrong twice over:
///
///  * a line sold with something off came back at full price. Ten soaps at
///    Rs 100 with 10% off were paid Rs 900 for, and the return handed back
///    Rs 1,000 — the shop paid the customer Rs 100 to change their mind, and
///    Discount Given kept the Rs 100 it had been debited for goods that were
///    no longer sold;
///  * the rate is per the unit the line was SOLD in, and the quantity was in
///    the item's base unit. A maund of atta at Rs 5,000 is forty kilos on
///    the shelf, so the sheet offered "40 maund" back and taking them all
///    gave the customer Rs 2,00,000 for a Rs 5,000 sale — forty times over,
///    twelve times for a dozen, the pack size for a carton.
///
/// So a return now takes a SHARE of what the sale stored on the line — its
/// total after the line discount and its part of the bill discount, its
/// taxes, its discount and its cost — in proportion to the base quantity
/// coming back, and the quantity is entered and recorded in the unit the
/// line was sold in. See [returnedShare] for how the shares are rounded so
/// that a line coming back a piece at a time gives back exactly what it was
/// charged, to the paisa, and never more.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';
import '../tax/tax_charge.dart';

/// What one return takes of an amount spread over a line.
///
/// [whole] is spread evenly over [outOf] — the line's quantity, in base
/// thousandths. Earlier returns took [before] of that quantity and this one
/// takes [taking]. The share is the difference of two cumulative figures,
/// each rounded once, the way the sale rounded:
///
///     round(whole × (before + taking) / outOf) − round(whole × before / outOf)
///
/// Why cumulative, rather than rounding each return's own part. Rs 299.99
/// over three soaps is Rs 99.996 each; rounded on its own, every soap comes
/// back at Rs 100.00 and the three refunds come to Rs 300.00 — a paisa the
/// customer was never charged. Rounding what has come back SO FAR, and
/// taking the difference, gives Rs 100.00, Rs 99.99 and Rs 100.00: never more
/// than the line in total, never less, and the last return takes exactly
/// what is left. A return of the whole line in one go is the whole amount,
/// and the first return of any line is its own part rounded once.
Money returnedShare(
  Money whole, {
  required int before,
  required int taking,
  required int outOf,
  RoundingMode mode = RoundingMode.halfUp,
}) {
  if (outOf <= 0 || taking <= 0 || whole.isZero) return Money.zero;
  int upTo(int n) {
    if (n >= outOf) return whole.inPaisa;
    if (n <= 0) return 0;
    return _mulDiv(whole.inPaisa, n, outOf, mode);
  }

  return Money.paisa(upTo(before + taking) - upTo(before));
}

/// `value × times / over`, rounded once per [mode], without wrapping.
///
/// A line of a crore against a thousand maunds in thousandths is past what a
/// 64-bit product can hold; that case goes through [BigInt] rather than
/// wrapping silently into a negative refund.
int _mulDiv(int value, int times, int over, RoundingMode mode) {
  const maxSafe = 9223372036854775807;
  if (value == 0 || times == 0) return 0;
  if (value.abs() <= maxSafe ~/ times.abs()) {
    return divideRounded(value * times, over, mode);
  }
  final n = BigInt.from(value) * BigInt.from(times);
  final d = BigInt.from(over);
  final magnitude = n.abs();
  var q = magnitude ~/ d;
  final r = magnitude.remainder(d);
  if (r != BigInt.zero) {
    final twice = r * BigInt.two;
    q += switch (mode) {
      RoundingMode.truncate => BigInt.zero,
      RoundingMode.ceilAbs => BigInt.one,
      RoundingMode.halfUp => twice >= d ? BigInt.one : BigInt.zero,
      RoundingMode.halfEven =>
        twice > d || (twice == d && q.isOdd) ? BigInt.one : BigInt.zero,
    };
  }
  final result = n.isNegative ? -q : q;
  if (!result.isValidInt) {
    throw StateError('A share of ${Money.paisa(value)} is too large to hold.');
  }
  return result.toInt();
}

/// The rounding mode a document was posted with, from its stored code.
///
/// The inverse of `roundingModeCode`. A return rounds its shares the way
/// the bill it came off rounded, so the paisa land where they landed.
RoundingMode roundingModeFor(String? code) => switch (code) {
  'half_even' => RoundingMode.halfEven,
  'truncate' => RoundingMode.truncate,
  'ceil_abs' => RoundingMode.ceilAbs,
  _ => RoundingMode.halfUp,
};

/// One line of the original bill, as it was sold.
///
/// The money fields are what the bill STORED for the whole line, read off
/// `document_lines` and `document_line_taxes`, never worked out again from
/// the rate. A rate times a quantity knows nothing of the discount that was
/// typed on the line or the share of the bill discount it carried.
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
    this._qty,
    this._charged,
    this.discount = Money.zero,
    this.salesTax = Money.zero,
    this.salesTaxBp = 0,
    this.furtherTax = Money.zero,
    this.furtherTaxBp = 0,
    this.taxInclusive = false,
    this.roundingMode = RoundingMode.halfUp,
    this.itemCode,
    this.hsCode,
  });

  final String documentLineId;

  /// Null for a loose line (M37): something sold by description and amount
  /// with no item behind it. It comes back as money only — there is no
  /// shelf for it to go back onto and no cost to reverse.
  final String? itemId;
  final String itemName;
  final String? itemCode;

  /// As it was on the bill, which is what a credit note to FBR (M28) has to
  /// name — not whatever the item says today.
  final String? hsCode;
  final String unitId;

  /// The unit the line was SOLD in: maund, dozen, carton. What is left is
  /// shown in it and what comes back is typed in it.
  final String unitCode;

  /// In the item's base unit; for a loose line, as it was typed. Stock
  /// comes back on this.
  final Qty soldQty;

  final Qty? _qty;

  /// How much was sold, in the unit it was sold in: a maund of atta is 1
  /// here and 40 in [soldQty]. The two together are the conversion the bill
  /// was made with — a maund that was forty kilos on the day comes back as
  /// forty kilos, whatever the shop's maund says now, the same snapshot rule
  /// as the cost.
  Qty get qty => _qty ?? soldQty;

  /// What earlier returns against this line already took back, in the base
  /// unit. A customer returning one tin twice from a bill for two is two
  /// separate visits, and the second must not be allowed to take back a
  /// third.
  final Qty alreadyReturned;

  /// What the line was priced at per the unit it was sold in, before any
  /// discount. Printed on the return as it was on the bill; never multiplied
  /// into what comes back.
  final Rate rate;

  /// What the goods cost the shop when they left, in whole paisa for the
  /// WHOLE line. A snapshot, never recomputed.
  final Money cost;

  final Money? _charged;

  /// What the customer was charged for the whole line: after the discount
  /// typed on it and its share of a bill discount, with the tax added on top
  /// where it was added on top. `line_total_paisa`. A bill rounded to the
  /// rupee rounded the bill, not the line, so the round-off stays with it.
  ///
  /// Defaulted for a line built by hand (a test, a loose line) from the
  /// rate, the discount and the tax, which is how the sale arrived at it.
  Money get charged =>
      _charged ??
      rate.amountFor(qty, mode: roundingMode) -
          discount +
          (taxInclusive ? Money.zero : salesTax) +
          furtherTax;

  /// The line discount and the line's share of the bill discount, together:
  /// what the sale debited to Discount Given for this line.
  final Money discount;

  /// Every tax on the line that the sale credited to Output Sales Tax, and
  /// its rate. Whether it was inside the price is [taxInclusive].
  final Money salesTax;
  final int salesTaxBp;

  /// The further tax on the line, always on top of the price.
  final Money furtherTax;
  final int furtherTaxBp;
  final bool taxInclusive;

  /// How the bill rounded. Its shares round the same way.
  final RoundingMode roundingMode;

  /// What is left to come back, in the base unit.
  Qty get returnableBase {
    final left = soldQty.inThousandths - alreadyReturned.inThousandths;
    return left > 0 ? Qty.raw(left) : Qty.zero;
  }

  /// What is left to come back, in the unit it was sold in: what the sheet
  /// shows and what a shopkeeper may type. Rounded down, so it never offers
  /// more than the shelf took away.
  Qty get returnable {
    final left = returnableBase.inThousandths;
    if (left == 0 || soldQty.inThousandths <= 0) return Qty.zero;
    if (qty.inThousandths == soldQty.inThousandths) return Qty.raw(left);
    return Qty.raw(
      _mulDiv(
        left,
        qty.inThousandths,
        soldQty.inThousandths,
        RoundingMode.truncate,
      ),
    );
  }

  /// [inUnit] of the unit sold, in the base unit — exactly, or refused.
  ///
  /// Everything that is left always converts to everything that is left,
  /// so a line one earlier visit took an awkward part of can still be
  /// emptied.
  Qty _baseOf(Qty inUnit) {
    if (inUnit == returnable) return returnableBase;
    if (qty.inThousandths == soldQty.inThousandths) return inUnit;
    final numerator = inUnit.inThousandths * soldQty.inThousandths;
    if (numerator % qty.inThousandths != 0) {
      throw ReturnRefused(
        '${inUnit.display} $unitCode of $itemName does not come out even on '
        'the shelf. Take back a whole number of $unitCode, or all of it.',
      );
    }
    return Qty.raw(numerator ~/ qty.inThousandths);
  }

  /// What coming back [inUnit] of the unit sold gives back, exactly.
  ///
  /// Refused, in words, for nothing at all and for more than is left.
  ReturnShare shareOf(Qty inUnit) {
    if (!inUnit.isPositive) {
      throw ReturnRefused('A return of nothing on $itemName is not a return.');
    }
    if (inUnit > returnable) {
      // The check that stops a customer returning three tins from a bill
      // for two — across visits, not just within one. Without counting what
      // earlier returns took, a shop can be walked out of its entire stock
      // one bill at a time. Counted in the unit it was sold in, so a maund
      // sold is one maund, not forty.
      throw ReturnRefused(
        'Only ${returnable.display} $unitCode of $itemName is left to come '
        'back on that bill.',
      );
    }
    final base = _baseOf(inUnit);
    final before = alreadyReturned.inThousandths;
    Money part(Money whole) => returnedShare(
      whole,
      before: before < 0 ? 0 : before,
      taking: base.inThousandths,
      outOf: soldQty.inThousandths,
      mode: roundingMode,
    );

    final refund = part(charged);
    var st = part(salesTax);
    var ft = part(furtherTax);
    // The value of the goods is what is left of the refund once the taxes
    // on it are taken out, so the three always add back to the refund and
    // the entry balances to the paisa. Each is rounded on its own, so on a
    // return worth less than a few paisa the taxes could come to more than
    // the refund; the tax gives way, because the refund is what the
    // customer is owed and a negative value of goods is not a return.
    var taxable = refund - st - ft;
    if (taxable.isNegative) {
      var short = -taxable;
      final fromFurther = short < ft ? short : ft;
      ft -= fromFurther;
      short -= fromFurther;
      st -= short < st ? short : st;
      taxable = refund - st - ft;
    }
    final discount = part(this.discount);
    return ReturnShare(
      qty: inUnit,
      baseQty: base,
      refund: refund,
      discount: discount,
      taxable: taxable,
      salesTax: st,
      furtherTax: ft,
      gross: taxable + discount + (taxInclusive ? st : Money.zero),
      cost: part(cost),
    );
  }
}

/// What one line gives back when part or all of it comes back.
///
/// Each figure is the returned share of what the sale stored, so it mirrors
/// the sale line for line: [refund] is [taxable] plus both taxes, and
/// [gross] is the price before the discount, as on the bill.
final class ReturnShare {
  const ReturnShare({
    required this.qty,
    required this.baseQty,
    required this.refund,
    required this.discount,
    required this.taxable,
    required this.salesTax,
    required this.furtherTax,
    required this.gross,
    required this.cost,
  });

  /// In the unit it was sold in.
  final Qty qty;

  /// In the item's base unit: what goes back on the shelf.
  final Qty baseQty;

  /// What the customer gets back for it.
  final Money refund;
  final Money discount;

  /// The value of the goods, after the discount and without the tax.
  final Money taxable;
  final Money salesTax;
  final Money furtherTax;
  final Money gross;

  /// At what the goods left at. See the library comment.
  final Money cost;

  /// What Sales Returns is debited: what the sale credited to Sales for
  /// these goods, before the discount, which comes back off Discount Given.
  Money get sales => taxable + discount;
}

/// How much of one line is coming back.
final class ReturnLineDraft {
  const ReturnLineDraft({
    required this.documentLineId,
    required this.qty,
    this.lotId,
  });

  final String documentLineId;

  /// The batch it goes back out of, on a return to a supplier (M49): an
  /// expired batch sent back leaves that batch, not whichever the shelf
  /// would sell next. Null leaves the batches as they are.
  final String? lotId;

  /// In the unit the line was sold in — a maund line comes back in maunds
  /// (M57). On a delivery, in the unit it was billed in.
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
    this.locationCode = 'MAIN',
  });

  final String originalDocumentId;
  final List<ReturnLineDraft> lines;
  final String reason;

  /// Cash handed back over the counter. The rest reduces what the customer
  /// owes, or becomes credit if they owed nothing.
  final Money refundNow;
  final String? paymentAccountId;

  /// Where the goods come back to (M27): the shop floor, or the van the
  /// phone taking them back is selling from.
  final String locationCode;
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
    required this.againstBill,
    required this.onAccount,
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

  /// How much of the credit the original bill could absorb, and how much the
  /// shop is now holding for the customer. Stated so the writer applies these
  /// rather than working them out again from a different starting point.
  final Money againstBill;
  final Money onAccount;

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
    required Money originalOutstanding,
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
    var grossTotal = Money.zero;
    var discountBack = Money.zero;
    var salesBack = Money.zero;
    var taxableBack = Money.zero;
    var salesTaxBack = Money.zero;
    var furtherTaxBack = Money.zero;
    var costBack = Money.zero;
    var roundingMode = RoundingMode.halfUp;
    var lineNo = 1;

    for (final wanted in draft.lines) {
      final sold = byLineId[wanted.documentLineId];
      if (sold == null) {
        throw const ReturnRefused(
          'One of the lines is not on that bill. A return can only take back '
          'what was actually sold.',
        );
      }
      // Exactly what the line was charged, in proportion to what comes back,
      // with the quantity in the unit it was sold in. Refused in words for
      // nothing, and for more than is left across every earlier visit.
      final share = sold.shareOf(wanted.qty);
      roundingMode = sold.roundingMode;

      goods += share.refund;
      grossTotal += share.gross;
      discountBack += share.discount;
      salesBack += share.sales;
      taxableBack += share.taxable;
      salesTaxBack += share.salesTax;
      furtherTaxBack += share.furtherTax;
      costBack += share.cost;

      lines.add(
        DocumentLinePosting(
          lineNo: lineNo,
          itemId: sold.itemId,
          itemNameSnapshot: sold.itemName,
          itemCodeSnapshot: sold.itemCode,
          hsCodeSnapshot: sold.hsCode,
          // In the unit it was sold in, at the rate it was sold at, so the
          // return reads like the bill it came off: "0.5 maund @ 5,000".
          qty: share.qty,
          // A line sold with no unit named comes back with none, not with an
          // empty id pointing at no unit at all.
          unitId: sold.unitId.isEmpty ? null : sold.unitId,
          unitCodeSnapshot: sold.unitCode,
          baseQty: share.baseQty,
          rate: sold.rate,
          gross: share.gross,
          discount: share.discount,
          discountBp: 0,
          taxable: share.taxable,
          tax: share.salesTax + share.furtherTax,
          lineTotal: share.refund,
          cost: share.cost,
          isFreeItem: false,
          // The rate the sale charged, so the sales tax summary and a credit
          // note to FBR (M28) both say at what the tax came back.
          taxes: [
            if (!share.salesTax.isZero)
              TaxCharge(
                kind: TaxKind.salesTax,
                code: 'ST_RETURN',
                rateBp: sold.salesTaxBp,
                base: share.taxable,
                amount: share.salesTax,
                isInclusive: sold.taxInclusive,
              ),
            if (!share.furtherTax.isZero)
              TaxCharge(
                kind: TaxKind.furtherTax,
                code: 'FURTHER_RETURN',
                rateBp: sold.furtherTaxBp,
                base: share.taxable,
                amount: share.furtherTax,
              ),
          ],
        ),
      );

      // A loose line (M37) comes back as money and nothing else: it took
      // nothing off a shelf, so nothing goes back onto one, and its cost was
      // never known, so none is reversed (the share of a zero is zero).
      final itemId = sold.itemId;
      if (itemId == null) {
        lineNo++;
        continue;
      }
      movements.add(
        StockMovementPosting(
          itemId: itemId,
          locationCode: draft.locationCode,
          txnType: 'sale_return',
          // The shelf speaks the base unit: a maund comes back as forty
          // kilos.
          qtyDelta: share.baseQty,
          // At the cost it left at. See the library comment: today's average
          // would book a profit or a loss on a customer changing their mind.
          rate: share.cost.isZero
              ? const Rate.raw(0)
              : Rate.raw(
                  divideRounded(
                    scaleOrThrow(share.cost.inPaisa, 1000000, 'return cost'),
                    share.baseQty.inThousandths,
                    RoundingMode.halfUp,
                  ),
                ),
          valueDelta: share.cost,
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
    //
    // Gross of the discount, as the sale credited Sales gross, and the
    // discount on what came back comes off Discount Given: the mirror of the
    // sale's contra entry (M57). Netting it here instead would leave
    // Discount Given carrying riayat on goods that are no longer sold, and
    // the month's discount figure would overstate what was given away.
    post(
      key: 'sales_returns',
      debit: salesBack,
      narration: 'Returned on $originalDocNo',
    );
    post(key: 'discount_given', credit: discountBack);
    // The tax charged on what came back is no longer owed over.
    post(key: 'output_tax', debit: salesTaxBack);
    post(key: 'further_tax_payable', debit: furtherTaxBack);

    // Cash out of the drawer for what was handed back now.
    post(
      key: '#$refundLedgerAccountId',
      credit: draft.refundNow,
      narration: 'Refunded on ${returnNumber.formatted}',
    );

    // The rest comes off what the customer owes. With no party there is
    // nobody to credit, which is why a walk-in return has to be refunded in
    // full — checked here rather than discovered as an unbalanced entry.
    final credited = goods - draft.refundNow;
    var againstBill = Money.zero;
    var onAccount = Money.zero;
    if (credited.isPositive) {
      if (partyId == null) {
        throw const ReturnRefused(
          'A walk-in return has to be paid back over the counter. There is no '
          'khata to put the credit on.',
        );
      }

      // Split against what is actually still owed on that bill.
      //
      // Crediting Receivables for the whole amount would be wrong whenever
      // the customer had already paid: the ledger would say their udhaar came
      // down while `documents.balance_paisa` — which is what the khata screen
      // sums — had nothing left to come down from. The two would disagree by
      // exactly the returned amount, and the khata is the one the shopkeeper
      // reads.
      //
      // The same shape as a receipt: what a bill can absorb goes against the
      // bill, and the remainder is money the shop is holding.
      againstBill = credited < originalOutstanding
          ? credited
          : originalOutstanding;
      onAccount = credited - againstBill;

      post(
        key: 'accounts_receivable',
        credit: againstBill,
        party: partyId,
        narration: 'Credit on ${returnNumber.formatted}',
      );
      post(
        key: 'customer_advances',
        credit: onAccount,
        party: partyId,
        narration: 'On account from ${returnNumber.formatted}',
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
        // The same shape as the bill's own totals, so a return prints the
        // way a bill does: the price before the discount, the discount, the
        // tax, and what came back. The discount is the line's and its share
        // of the bill's together; the bill stored them per line as one.
        subtotal: grossTotal,
        lineDiscount: discountBack,
        billDiscount: Money.zero,
        taxable: taxableBack,
        tax: salesTaxBack,
        furtherTax: furtherTaxBack,
        withholding: Money.zero,
        extraCharges: Money.zero,
        roundOff: Money.zero,
        total: goods,
        paid: draft.refundNow,
        balance: Money.zero,
        cost: costBack,
        roundingMode: roundingModeCode(roundingMode),
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
      againstBill: againstBill,
      onAccount: onAccount,
      auditSummary:
          'Return ${returnNumber.formatted} against $originalDocNo for '
          '${goods.amountOnly}: ${draft.reason.trim()}',
    );

    posting.assertBalanced();
    return posting;
  }
}
