/// Third Schedule goods: packaged goods sold on the retail price printed on
/// the pack (M59).
///
/// Section 3(2)(a) of the Sales Tax Act charges these goods "at the rate of
/// eighteen per cent of the retail price", and the retail price is the one
/// the maker prints on the pack. STGO 8 of 2026 (7 July 2026) makes 56
/// categories print the retail price and the tax inside it — juices, soft
/// drinks, tea, shampoo, detergents, biscuits, cooking oil, batteries — and
/// the 2026 budget takes the regime to more than three thousand items. On a
/// bill that means three things, and this file is all three:
///
///  * the price is tax-inclusive, and the tax inside it is worked out on the
///    printed price, not on whatever the counter happened to charge: a
///    Rs 118 packet sold at Rs 110 still carries the Rs 18 of tax printed on
///    its side ([thirdScheduleTax]);
///  * selling above the printed price is an offence, so the counter says so
///    the moment a line goes above it ([sellsAboveMrp]) — a warning, never a
///    block, because the shopkeeper may have the wrong MRP typed in and the
///    customer is standing there;
///  * the line shows "MRP Rs X", so the cashier and the customer can both
///    see what the pack says.
///
/// The printed price multiplied out ([retailValueOf]) and the above-MRP
/// check ([sellsAboveMrp]) live in `pricing/mrp.dart`, shared with M49's
/// pharmacy, where selling above the DRAP price is refused: one function
/// answers the question for both (`isAboveRetail`).
library;

import 'package:pk_money/pk_money.dart';

import '../pricing/mrp.dart';

/// The tax inside a price that includes it, rounded half up to the paisa:
/// `price × rate / (1 + rate)`. Rs 118 at 18% has Rs 18 inside it.
///
/// Worked in [BigInt] so a wholesaler's crore-rupee bill cannot overflow the
/// multiplication.
Money taxInsidePrice(Money price, int rateBp) {
  if (price.isZero || rateBp == 0) return Money.zero;
  final numerator = BigInt.from(price.inPaisa) * BigInt.from(rateBp);
  final denominator = BigInt.from(10000 + rateBp);
  return Money.paisa(_halfUp(numerator, denominator));
}

/// The sales tax on a Third Schedule line.
///
/// Worked out on the printed retail price — [retailValue], the pack's MRP
/// over the line's quantity — whatever the line was sold for, because that
/// is the base s.3(2)(a) taxes. A pack sold below its MRP (a pharmacy's "10%
/// off MRP", a shop clearing old stock) still owes the tax printed on it.
///
/// Two limits, both the shopkeeper's protection:
///
///  * sold ABOVE the MRP — which the counter warns of — the tax is the tax
///    inside what was actually charged, never less. Whether FBR would assess
///    the excess on the higher price is not something this pack has been
///    able to confirm, and the shop that charged it has the money either way;
///  * the tax is never more than the line itself: a pack given away at under
///    a sixth of its printed price cannot carry a tax larger than its price,
///    and a bill whose value before tax is negative is not a bill.
///
/// With no MRP on the item the tax is taken out of the price charged, which
/// is what M12 did for every Third Schedule line.
Money thirdScheduleTax({
  required Money saleValue,
  required Money? retailValue,
  required int rateBp,
}) {
  if (!saleValue.isPositive) return Money.zero;
  final onSale = taxInsidePrice(saleValue, rateBp);
  if (retailValue == null) return onSale;
  final onRetail = taxInsidePrice(retailValue, rateBp);
  final tax = onRetail > onSale ? onRetail : onSale;
  return tax > saleValue ? saleValue : tax;
}

int _halfUp(BigInt numerator, BigInt denominator) {
  final negative = numerator.isNegative != denominator.isNegative;
  final n = numerator.abs();
  final d = denominator.abs();
  final q = n ~/ d;
  final r = n.remainder(d) * BigInt.two;
  final rounded = r >= d ? q + BigInt.one : q;
  return (negative ? -rounded : rounded).toInt();
}

/// [value] times [numerator] over [denominator], rounded half up to the
/// paisa, in [BigInt] so nothing overflows on the way.
Money proRataShare(Money value, int numerator, int denominator) {
  if (denominator == 0) {
    throw ArgumentError.value(denominator, 'denominator', 'must not be zero');
  }
  return Money.paisa(
    _halfUp(
      BigInt.from(value.inPaisa) * BigInt.from(numerator),
      BigInt.from(denominator),
    ),
  );
}
