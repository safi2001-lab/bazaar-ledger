/// The printed retail price, and what happens when a bill goes above it.
///
/// One check for the whole product. The Third Schedule's printed price
/// (M59, `tax/third_schedule.dart`) and the pharmacy's DRAP price (M49) ask
/// the same question — is what this line is charged more than the price
/// printed on that many packs? — and both ask it here, through
/// [isAboveRetail]. Below is always allowed, and is how most chemists sell:
/// "10% off on all medicines".
///
/// What differs between shops is only what is done about it:
///
///  * a **pharmacy** is refused, beneath every screen: DRAP fixes a
///    medicine's maximum retail price and selling above it is an offence;
///  * **any other shop** is warned, on the line itself, for Third Schedule
///    goods (M59's note under the line): the MRP typed into the item may be
///    last year's, and the customer is standing there.
library;

import 'package:pk_money/pk_money.dart';

/// What a shop does with a line priced above its printed retail price.
enum MrpRule {
  /// Refused, beneath every screen: a pharmacy.
  block,

  /// Warned of on the line, and let through by the books: every other shop,
  /// for its Third Schedule goods (M59).
  warn,
}

/// The rule a shop sells under: refused for a pharmacy, warned for the rest.
MrpRule mrpRuleFor({required bool isPharmacy}) =>
    isPharmacy ? MrpRule.block : MrpRule.warn;

/// The printed retail price of the goods on one line: what one pack's MRP
/// comes to over everything that left the shelf (M59).
///
/// [baseQty] is in the item's own unit, which is the unit its MRP is printed
/// for, so a carton of 24 sold as one carton is 24 times the pack's price.
/// Null when there is no MRP, which is every loose line and most items in a
/// kiryana that never typed one.
///
/// The one place a printed price is multiplied out: the Third Schedule's tax
/// base, the counter's warning and the pharmacy's refusal all read it.
Money? retailValueOf({required Money? mrp, required Qty baseQty}) {
  if (mrp == null || !mrp.isPositive || !baseQty.isPositive) return null;
  // The rate arithmetic rounds the paisa once, half up, as a line does.
  return Rate.perUnit(mrp).amountFor(baseQty);
}

/// THE above-MRP check: whether [charged] is more than [retail], the printed
/// price of the goods it was charged for. Nothing printed is nothing to be
/// above.
///
/// Every question of the kind comes here, so a line the counter shows in red
/// is exactly a line a pharmacy's sale path refuses.
bool isAboveRetail(Money charged, Money? retail) =>
    retail != null && charged > retail;

/// Whether a line is being sold above the printed price on its pack (M59).
///
/// [lineValue] is what the line comes to after its own discount: a cashier
/// who types Rs 130 for a Rs 120 pack and then gives Rs 10 off has sold at
/// the printed price. A bill discount spread across the lines is not
/// counted — it is not on the line the cashier is looking at — and it can
/// only bring a line down, never up.
bool sellsAboveMrp({
  required Money? mrp,
  required Qty baseQty,
  required Money lineValue,
}) => isAboveRetail(lineValue, retailValueOf(mrp: mrp, baseQty: baseQty));

/// One item on a bill priced above what its printed price allows.
final class MrpBreach {
  const MrpBreach({
    required this.itemName,
    required this.qty,
    required this.charged,
    required this.ceiling,
    this.itemId,
  });

  final String? itemId;
  final String itemName;

  /// How much of it, in the unit the ceiling was worked out in.
  final Qty qty;

  /// What the bill charges for it, after discounts and with tax.
  final Money charged;

  /// The most the printed price allows for [qty].
  final Money ceiling;

  /// How far above.
  Money get over => charged - ceiling;
}

/// [charged] for [qty] of [itemName] against [ceiling] — the printed price
/// of that many, batch by batch where batches carry their own — or null
/// when it is within, or there is nothing printed to be within.
MrpBreach? aboveMrp({
  required String itemName,
  required Qty qty,
  required Money charged,
  required Money? ceiling,
  String? itemId,
}) {
  if (!isAboveRetail(charged, ceiling)) return null;
  return MrpBreach(
    itemId: itemId,
    itemName: itemName,
    qty: qty,
    charged: charged,
    ceiling: ceiling!,
  );
}

/// A bill refused because it sells above the printed retail price where
/// that is not allowed.
final class MrpRefused implements Exception {
  const MrpRefused(this.breaches);

  final List<MrpBreach> breaches;

  @override
  String toString() {
    final first = breaches.first;
    final more = breaches.length > 1
        ? ' (and ${breaches.length - 1} more)'
        : '';
    return '${first.itemName} is charged ${first.charged.amountOnly}, above '
        'its printed retail price of ${first.ceiling.amountOnly} for '
        '${first.qty.display}$more. DRAP fixes the most a medicine may be '
        'sold for: sell it at or below the MRP.';
  }
}
