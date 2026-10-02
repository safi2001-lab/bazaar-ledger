/// What a party was charged for an item before, put beside the line (M37).
///
/// A wholesaler's customer does not ask the price of a sack of sugar. He
/// says "same as last time", and the shop that cannot tell him what last
/// time was either quotes high and loses him or quotes low and loses the
/// margin. myBillBook shows the last five prices for a party and an item,
/// Marg has Alt+L, and Vyapar keeps party-wise rates behind its premium
/// plan. This is the same answer, kept on the phone: the last few bills the
/// item was on for this customer (or, on a delivery, from this supplier),
/// newest first, each one a tap from being this line's price.
///
/// It is shown, never applied by itself. A customer on wholesale is charged
/// the wholesale price until the cashier taps an old rate; a stale rate that
/// quietly beat the price list would undo M7 and M15 without anybody
/// deciding to.
library;

import 'package:pk_money/pk_money.dart';

import '../catalogue/unit_converter.dart';

/// One earlier bill with the item on it.
///
/// Lines of the same item at the same price on one bill — three phones on
/// one invoice, each its own line for its IMEI — are one deal here, with
/// their quantities added: the customer bought three, once.
final class PastDeal {
  const PastDeal({
    required this.documentId,
    required this.docNo,
    required this.dateLocal,
    required this.qty,
    required this.unitCode,
    required this.rate,
    this.unitId,
    this.discountBp = 0,
    this.discount = Money.zero,
    this.partyName,
  });

  final String documentId;
  final String docNo;

  /// The shop's own day, `YYYY-MM-DD` in Pakistan time.
  final String dateLocal;

  /// What was on the bill, in the unit it was sold (or bought) in.
  final Qty qty;
  final String? unitId;
  final String unitCode;

  /// The price per [unitCode] as it was on the bill, before any discount.
  final Rate rate;

  /// The line's own percentage off, in basis points, when it was given as
  /// one.
  final int discountBp;

  /// Everything that came off these lines, in money: the line's own
  /// discount and its share of a discount on the whole bill.
  final Money discount;

  /// Who it was sold to or bought from, for a list that is not about one
  /// party: the last delivery of an item, from whoever brought it.
  final String? partyName;

  /// [rate] as a price per [toUnitId], or null when it is not one.
  ///
  /// The deal was struck in whatever unit it was struck in — five thousand
  /// a bori — and the line on the counter today may be in kilos. A price per
  /// bori typed onto a line in kilos would charge fifty times over, so the
  /// price is carried across exactly, through the same conversions the
  /// counter sells by, or not at all. Null too when the old line named no
  /// unit, unless it is the unit asked for.
  Rate? rateIn(
    String toUnitId, {
    required String itemId,
    UnitConverter? units,
  }) {
    final from = unitId;
    if (from == toUnitId) return rate;
    if (from == null || units == null) return null;
    try {
      return units.convertRate(
        rate,
        fromUnitId: from,
        toUnitId: toUnitId,
        itemId: itemId,
      );
    } on UnitConversionException {
      return null;
    }
  }
}
