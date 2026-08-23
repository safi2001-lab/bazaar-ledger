import 'package:pk_money/pk_money.dart';

import '../tax/tax_charge.dart';
import 'sale_draft.dart';

/// One line, fully priced.
final class CalculatedLine {
  const CalculatedLine({
    required this.draft,
    required this.lineNo,
    required this.gross,
    required this.lineDiscount,
    required this.apportionedBillDiscount,
    required this.taxable,
    required this.taxes,
    required this.lineTotal,
    required this.cost,
  });

  final SaleLineDraft draft;
  final int lineNo;

  /// Rate times quantity, before any discount.
  final Money gross;

  /// The discount typed on this line.
  final Money lineDiscount;

  /// This line's share of a discount typed on the whole bill.
  final Money apportionedBillDiscount;

  /// What tax is charged on: gross less both discounts.
  final Money taxable;

  final List<TaxCharge> taxes;

  /// Taxable plus tax.
  final Money lineTotal;

  /// Cost of goods on this line, at the weighted average when it was sold.
  final Money cost;

  Money get totalDiscount => lineDiscount + apportionedBillDiscount;

  Money get tax => Money.sum([for (final t in taxes) t.amount]);
}

/// How one tender actually landed.
///
/// The capping arithmetic lives here, in the pure calculator, and nowhere
/// else. It used to be repeated in the posting builder, and the two copies
/// disagreed: a tender the builder decided contributed nothing was silently
/// skipped, taking its already-allocated payment number with it. A gap in a
/// receipt series is the first thing an auditor asks about.
final class AppliedTender {
  const AppliedTender({
    required this.index,
    required this.draft,
    required this.offered,
    required this.applied,
    required this.change,
  });

  /// Position in the draft's tender list, so a caller can match them up.
  final int index;

  final TenderDraft draft;

  /// What the customer actually handed over. For cash that is `tendered` when
  /// the cashier typed it, and `amount` otherwise.
  final Money offered;

  /// What came off the bill. Never more than was owed.
  final Money applied;

  /// Handed back out of the drawer.
  final Money change;

  /// Whether this settlement went through a banking or digital channel.
  ///
  /// Feeds s.21(s): cash is obviously not one, and neither is an internal
  /// adjustment, which is a book entry rather than a payment at all.
  bool get isBankingChannel => draft.isBankingChannel;

  /// Whether this tender becomes a payment row.
  ///
  /// A note that settles nothing is handed straight back across the counter —
  /// the customer paid the bill some other way, or gave more cash than was
  /// needed on top of an exact transfer. Nothing entered the drawer and
  /// nothing left it, so there is no payment, no allocation and no receipt
  /// number. Writing one anyway produced a row with `amount_paisa = 0`, which
  /// the schema refuses outright.
  bool get isPosted => applied.isPositive;
}

/// A sale, fully priced, ready to be written.
final class CalculatedSale {
  const CalculatedSale({
    required this.lines,
    required this.subtotal,
    required this.lineDiscountTotal,
    required this.billDiscount,
    required this.taxable,
    required this.tax,
    required this.furtherTax,
    required this.withholding,
    required this.extraCharges,
    required this.roundOff,
    required this.total,
    required this.paid,
    required this.balance,
    required this.tenders,
    required this.cost,
    required this.changeDue,
    required this.cashThresholdBreached,
    required this.ruleVersion,
  });

  final List<CalculatedLine> lines;

  final Money subtotal;
  final Money lineDiscountTotal;
  final Money billDiscount;
  final Money taxable;
  final Money tax;
  final Money furtherTax;
  final Money withholding;
  final Money extraCharges;

  /// The adjustment that took the bill to a whole rupee. Posted to its own
  /// account, never quietly absorbed.
  final Money roundOff;

  final Money total;
  final Money paid;

  /// What is still owed. Positive means the customer is on udhaar for it.
  final Money balance;

  final Money cost;

  /// Cash handed over less the cash actually due.
  final Money changeDue;

  /// Each tender, with what it actually settled and what came back as change.
  ///
  /// Only the ones that will be written: a caller allocating receipt numbers
  /// asks this list how many it needs, so a number is never drawn for a
  /// payment row that is then not written.
  final List<AppliedTender> tenders;

  /// s.21(s), Finance Act 2025: 50% of an expenditure is disallowed where a
  /// single invoice above Rs 200,000 is settled otherwise than through a
  /// banking or digital channel. Nobody else in this market flags it.
  final bool cashThresholdBreached;

  final String ruleVersion;

  Money get grossProfit => taxable - cost;

  bool get isFullyPaid => balance.isZero;
}

/// Turns a [SaleDraft] into a [CalculatedSale].
///
/// Pure: same input, same output, no clock, no database, no randomness. Every
/// rounding decision in the application happens here or in `pk_money`, and
/// nowhere else — which is what makes it possible to say with confidence that
/// a reprinted invoice still adds up to what was printed the first time.
final class SaleCalculator {
  const SaleCalculator({
    this.taxEngine = const UntaxedEngine(),
    this.cashThresholdPaisa = 20000000,
  });

  final TaxEngine taxEngine;

  /// Rs 200,000, in paisa.
  final int cashThresholdPaisa;

  CalculatedSale calculate(SaleDraft draft, TaxContext context) {
    if (draft.lines.isEmpty) {
      throw ArgumentError.value(
        draft.lines,
        'lines',
        'a sale must have at least one line',
      );
    }

    final mode = draft.roundingMode;

    // --- Pass one: gross and line discount. ------------------------------
    final gross = <Money>[];
    final lineDiscounts = <Money>[];
    for (final line in draft.lines) {
      final lineGross = line.isFreeItem
          ? Money.zero
          : line.rate.amountFor(line.qty, mode: mode);
      gross.add(lineGross);

      if (line.qty.isNegative) {
        throw ArgumentError.value(
          line.qty.display,
          'qty',
          'a sale line cannot carry a negative quantity; a return is a '
              'credit note against the original bill',
        );
      }
      // And not zero either. A zero-quantity line prices to nothing, passes
      // every other guard here, and dies on the schema's
      // `CHECK (qty_thousandths <> 0)` — after the documents row has already
      // been inserted. The transaction rolls back, so nothing is corrupted,
      // but the cashier is handed an untranslated SQLite string on a sale
      // they were told was going through. Caught here, where the message can
      // name the line and say why.
      if (line.qty.isZero) {
        throw ArgumentError.value(
          line.qty.display,
          'qty',
          '${line.itemName}: a line has to be for some quantity of '
              'something. Remove the line instead.',
        );
      }
      final discount =
          line.explicitDiscount ??
          lineGross.percentBp(line.discountBp, mode: mode);
      // A negative discount is a surcharge that never appears on the bill.
      // It made `taxable` exceed `subtotal`, so the printed lines stopped
      // adding up to the printed total with nothing on the paper explaining
      // the gap — and the customer is the one holding that paper.
      if (discount.isNegative) {
        throw ArgumentError.value(
          discount.amountOnly,
          'discount',
          'a discount cannot be negative on "${line.itemName}"; a surcharge '
              'is an extra charge and belongs in its own field',
        );
      }
      if (discount > lineGross) {
        throw ArgumentError.value(
          discount,
          'explicitDiscount',
          'discount ${discount.amountOnly} exceeds the line total '
              '${lineGross.amountOnly} on "${line.itemName}"',
        );
      }
      lineDiscounts.add(discount);
    }

    // --- Pass two: apportion the bill discount. --------------------------
    //
    // Pro-rata on what is left after line discounts, allocated so the parts
    // re-sum to exactly the discount that was typed. A bill discount that
    // loses a paisa in the split makes the invoice total disagree with the
    // sum of its own lines, which an auditor will find and a shopkeeper will
    // not be able to explain.
    final netOfLineDiscount = [
      for (var i = 0; i < gross.length; i++) gross[i] - lineDiscounts[i],
    ];
    final apportioned = _apportion(draft.billDiscount, netOfLineDiscount);

    // --- Pass three: tax on the final base. ------------------------------
    final calculated = <CalculatedLine>[];
    for (var i = 0; i < draft.lines.length; i++) {
      final line = draft.lines[i];
      final taxable = netOfLineDiscount[i] - apportioned[i];

      final taxes = taxEngine.chargesFor(
        taxableBase: taxable,
        mrp: line.mrp,
        itemTaxRuleId: line.taxRuleId,
        isThirdSchedule: line.isThirdSchedule,
        context: context,
      );
      final taxTotal = Money.sum([for (final t in taxes) t.amount]);

      calculated.add(
        CalculatedLine(
          draft: line,
          lineNo: i + 1,
          gross: gross[i],
          lineDiscount: lineDiscounts[i],
          apportionedBillDiscount: apportioned[i],
          taxable: taxable,
          taxes: taxes,
          lineTotal: taxable + taxTotal,
          // Cost follows the goods, so a free item still costs what it cost.
          cost: line.unitCost.amountFor(line.baseQty, mode: mode),
        ),
      );
    }

    // --- Totals. ---------------------------------------------------------
    final subtotal = Money.sum(gross);
    final lineDiscountTotal = Money.sum(lineDiscounts);
    final taxable = Money.sum([for (final l in calculated) l.taxable]);
    final cost = Money.sum([for (final l in calculated) l.cost]);

    Money byKind(TaxKind kind) => Money.sum([
      for (final l in calculated)
        for (final t in l.taxes)
          if (t.kind == kind) t.amount,
    ]);

    final salesTax =
        byKind(TaxKind.salesTax) +
        byKind(TaxKind.extraTax) +
        byKind(TaxKind.provincialSt) +
        byKind(TaxKind.fed) +
        byKind(TaxKind.cess);
    final furtherTax = byKind(TaxKind.furtherTax);
    final withholding = byKind(TaxKind.withholding);

    final beforeRounding =
        taxable + salesTax + furtherTax + draft.extraCharges - withholding;
    final roundOff = draft.roundToRupee
        ? beforeRounding.roundingDelta(mode: mode)
        : Money.zero;
    final total = beforeRounding + roundOff;

    // --- Tenders. --------------------------------------------------------
    //
    // Nothing that is not cash can be overpaid: a customer does not transfer
    // Rs 6,000 for a Rs 5,525 bill and take Rs 475 out of the till, and a
    // shop that posts the difference as revenue ends the day with more money
    // in the books than in the box. This used to be allowed through whenever
    // a cash tender happened to be present alongside, which then produced a
    // zero-amount payment row and a negative receivable — both refused by the
    // schema three layers later, as a raw constraint error on a sale the
    // shopkeeper had already been told was going through.
    for (final t in draft.tenders) {
      // A negative tender is a refund wearing a sale's clothes. Allowed
      // through, it produced a negative receivable that balanced — the sums
      // still matched — and then died on the schema's own
      // `CHECK (debit_paisa >= 0)`. A return is its own document type.
      if (t.amount.isNegative || (t.tendered?.isNegative ?? false)) {
        throw ArgumentError.value(
          t.amount.amountOnly,
          'tender',
          'a tender cannot be negative; a refund is a credit note',
        );
      }
    }

    final nonCash = Money.sum([
      for (final t in draft.tenders)
        if (!t.isCash) t.amount,
    ]);
    if (nonCash > total) {
      throw ArgumentError(
        'Non-cash tenders total ${nonCash.amountOnly} against a bill of '
        '${total.amountOnly}. There is no change to give on a bank transfer.',
      );
    }

    // Cash is capped at what is actually due; anything beyond it is change out
    // of the drawer. `tendered` is what the customer handed over when the
    // cashier typed it — the note, not the amount being settled — and it is
    // the basis for the change, exactly as the field's own documentation
    // promises.
    final applied = <AppliedTender>[];
    var cashDue = total - nonCash;
    if (cashDue.isNegative) cashDue = Money.zero;

    for (var i = 0; i < draft.tenders.length; i++) {
      final t = draft.tenders[i];
      final Money offered;
      final Money settled;
      if (t.isCash) {
        // Two separate caps, and both are needed. `amount` is what the
        // cashier is settling; `tendered` is the note in their hand. Capping
        // only by what is due turned "3,000 of this 5,000 bill, here is a
        // 5,000 note" into a fully-paid bill with no change given.
        offered = t.tendered ?? t.amount;
        final intended = offered < t.amount ? offered : t.amount;
        settled = intended > cashDue ? cashDue : intended;
        cashDue -= settled;
      } else {
        offered = t.amount;
        settled = t.amount;
      }
      applied.add(
        AppliedTender(
          index: i,
          draft: t,
          offered: offered,
          applied: settled,
          change: offered - settled,
        ),
      );
    }

    final posted = [
      for (final a in applied)
        if (a.isPosted) a,
    ];

    final paid = Money.sum([for (final a in posted) a.applied]);
    final changeDue = Money.sum([for (final a in posted) a.change]);
    final balance = total - paid;

    // s.21(s) turns on how the invoice was settled, not merely on whether any
    // cash was involved. An internal adjustment is not cash, but it is not a
    // banking or digital channel either, and the statute covers it.
    final outsideBankingChannel = Money.sum([
      for (final a in posted)
        if (!a.isBankingChannel) a.applied,
    ]);
    final breached =
        total.inPaisa > cashThresholdPaisa && outsideBankingChannel.isPositive;

    return CalculatedSale(
      lines: List.unmodifiable(calculated),
      subtotal: subtotal,
      lineDiscountTotal: lineDiscountTotal,
      billDiscount: draft.billDiscount,
      taxable: taxable,
      tax: salesTax,
      furtherTax: furtherTax,
      withholding: withholding,
      extraCharges: draft.extraCharges,
      roundOff: roundOff,
      total: total,
      paid: paid,
      balance: balance,
      tenders: List.unmodifiable(posted),
      cost: cost,
      changeDue: changeDue,
      cashThresholdBreached: breached,
      ruleVersion: taxEngine.ruleVersion,
    );
  }

  /// Splits [amount] across [weights] so the parts sum back to exactly
  /// [amount].
  static List<Money> _apportion(Money amount, List<Money> weights) {
    if (amount.isZero) {
      return List<Money>.filled(weights.length, Money.zero);
    }
    if (amount.isNegative) {
      throw ArgumentError.value(
        amount.amountOnly,
        'billDiscount',
        'a bill discount cannot be negative',
      );
    }
    final total = Money.sum(weights);
    if (total.isZero) {
      // A discount against a bill worth nothing. Spreading it evenly, which is
      // what this used to do, made every line's taxable value negative — a
      // negative tax base and a negative invoice total, and it slipped past
      // the "discount exceeds the bill" guard below because there was no bill
      // to exceed. It is an input error, and it says so.
      throw ArgumentError.value(
        amount.amountOnly,
        'billDiscount',
        'a discount of ${amount.amountOnly} against a bill worth nothing',
      );
    }
    if (amount > total) {
      throw ArgumentError.value(
        amount,
        'billDiscount',
        'a bill discount of ${amount.amountOnly} exceeds the bill total of '
            '${total.amountOnly}',
      );
    }
    return amount.allocate([for (final w in weights) w.inPaisa]);
  }
}
