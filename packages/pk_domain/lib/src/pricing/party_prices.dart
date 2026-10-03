/// A price list of a customer's own (M66): "Haji Sahib: Atta 50kg Rs 4,800,
/// Cheeni Rs 135 a kilo".
///
/// A wholesaler agrees a rate with each of his regular buyers, item by item,
/// and keeps it in his head or on the last page of the register. Tiers
/// (M7, M15) put a buyer on one of three columns of every item; this is the
/// rate agreed with one buyer for one item, whatever column they are on.
/// Vyapar sells it as "party-wise item rate", a premium setting.
///
/// ## The order the counter prices a line in, decided once
///
///  1. **A price the cashier typed.** It stands whatever else is true, as it
///     has since M7: the cashier meant it, and a price that changed under
///     their thumb is the one they would never notice. Picking one of the
///     customer's last prices (M37) is typing it.
///  2. **The customer's own price**, where they have one for the item. It
///     is the rate agreed with them, so it wins over a slab even where the
///     slab is lower (a buyer with his own rate is not repriced by the
///     board on the wall; the owner who agreed it sees the slab when he
///     sets it), and their standing discount is not taken off it again:
///     the agreed rate is what they pay.
///  3. **The item's quantity slab (M43)**, where it is lower than (4).
///  4. **Their tier's price** — VIP, wholesale — falling back a tier at a
///     time where the item has none (M15).
///  5. **The item's own price.**
///
/// A bonus (M43) is about quantity, not price, and is given on a line at
/// the customer's own price as on any other; a bill slab is worked out on
/// what the lines come to, whatever priced them. The last-price hint (M37)
/// stays a hint: it shows what they paid, and tapped it is (1).
///
/// One `settings` row per customer, so a shop with two hundred buyers on
/// their own rates reads one row at the counter, not two hundred. Rates are
/// per the item's own unit, as an item's prices are, and carried into the
/// unit a line is sold in exactly, or not at all.
///
/// Pure: the counter reads a customer's list once and asks it.
library;

import 'dart:convert';

import 'package:pk_money/pk_money.dart';

import '../ports/app_queries.dart';
import 'price_tier.dart';
import 'schemes.dart';

/// Where a customer's own prices are kept: one `settings` row per customer,
/// keyed by this and the party's id, holding [PartyPrices.toJson].
const partyPriceKeyPrefix = 'price.party.';

/// Why a line is at the price it is.
enum PriceSource {
  /// The cashier typed it, or picked a past deal (M37).
  typed,

  /// The customer's own price for the item.
  party,

  /// The item's quantity slab (M43).
  slab,

  /// The customer's tier, wholesale or VIP (M7, M15).
  tier,

  /// The item's own price.
  item,
}

/// One customer's own prices, by item id, per the item's own unit.
final class PartyPrices {
  const PartyPrices({required this.partyId, this.rates = const {}});

  final String partyId;
  final Map<String, Rate> rates;

  bool get isEmpty => rates.isEmpty;

  /// The settings key this is kept under.
  String get settingKey => '$partyPriceKeyPrefix$partyId';

  /// Their own price for [itemId], per its own unit, or null.
  Rate? rateFor(String itemId) => rates[itemId];

  /// The list with [itemId] at [rate], or off it when [rate] is null.
  PartyPrices withRate(String itemId, Rate? rate) => PartyPrices(
    partyId: partyId,
    rates: {
      for (final e in rates.entries)
        if (e.key != itemId) e.key: e.value,
      itemId: ?rate,
    },
  );

  /// Integers only.
  String toJson() => jsonEncode({
    'items': {for (final e in rates.entries) e.key: e.value.inMilliPaisa},
  });

  /// What a settings row holds; an empty list for anything it cannot read.
  static PartyPrices fromJson(String partyId, String? source) {
    if (source == null || source.trim().isEmpty) {
      return PartyPrices(partyId: partyId);
    }
    try {
      final root = jsonDecode(source);
      final items = root is Map<String, Object?> ? root['items'] : null;
      if (items is! Map<String, Object?>) return PartyPrices(partyId: partyId);
      return PartyPrices(
        partyId: partyId,
        rates: {
          for (final e in items.entries)
            if (e.value case final int milli when milli > 0)
              e.key: Rate.raw(milli),
        },
      );
    } on FormatException {
      return PartyPrices(partyId: partyId);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PartyPrices &&
      other.partyId == partyId &&
      other.rates.length == rates.length &&
      rates.entries.every((e) => other.rates[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    partyId,
    Object.hashAllUnordered([
      for (final e in rates.entries) Object.hash(e.key, e.value),
    ]),
  );
}

/// What the counter charges for [item] taken [baseQty] of (in its own unit)
/// by a [tier] buyer whose own prices are [own], per the item's own unit,
/// and why — every step after (1) of the order in this file's comment.
({Rate rate, PriceSource source}) counterPrice(
  ItemSummary item, {
  required PriceTier tier,
  required Qty baseQty,
  SchemeBook book = SchemeBook.empty,
  PartyPrices? own,
}) {
  if (own?.rateFor(item.id) case final mine?) {
    return (rate: mine, source: PriceSource.party);
  }
  final tierRate = priceFor(item, tier);
  final slab = book.slabRate(item.id, baseQty);
  if (slab != null && slab < tierRate) {
    return (rate: slab, source: PriceSource.slab);
  }
  final byTier =
      tier != PriceTier.retail &&
      (item.wholesaleRate != null || item.vipRate != null) &&
      tierRate != item.saleRate;
  return (rate: tierRate, source: byTier ? PriceSource.tier : PriceSource.item);
}
