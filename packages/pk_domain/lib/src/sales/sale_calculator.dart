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
      final lineGross =
          line.isFreeItem ? Money.zero : line.rate.amountFor(line.qty, mode: mode);
      gross.add(lineGross);

      final discount = line.explicitDiscount ??
          lineGross.percentBp(line.discountBp, mode: mode);
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

    final salesTax = byKind(TaxKind.salesTax) +
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
    final tendered = Money.sum([for (final t in draft.tenders) t.amount]);
    if (tendered > total && !draft.tenders.any((t) => t.isCash)) {
      throw ArgumentError(
        'Non-cash tenders total ${tendered.amountOnly} against a bill of '
        '${total.amountOnly}. There is no change to give on a bank transfer.',
      );
    }

    // A cash tender is capped at what is actually due; anything beyond it is
    // change, not revenue.
    final nonCash = Money.sum([
      for (final t in draft.tenders)
        if (!t.isCash) t.amount,
    ]);
    final cashOffered = Money.sum([
      for (final t in draft.tenders)
        if (t.isCash) t.amount,
    ]);
    final cashDue = total - nonCash;
    final cashApplied = cashOffered > cashDue
        ? (cashDue.isNegative ? Money.zero : cashDue)
        : cashOffered;
    final changeDue = cashOffered - cashApplied;

    final paid = nonCash + cashApplied;
    final balance = total - paid;

    final cashPaid = cashApplied;
    final breached =
        total.inPaisa > cashThresholdPaisa && cashPaid.isPositive;

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
    final total = Money.sum(weights);
    if (total.isZero) {
      // Nothing to weight against — an all-free bill with a discount typed on
      // it. Spread it evenly rather than losing it.
      return amount.split(weights.length);
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
