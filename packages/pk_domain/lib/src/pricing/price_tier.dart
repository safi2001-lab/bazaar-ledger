/// Which of an item's prices a buyer is sold at.
///
/// A wholesaler sells the same carton of oil to the man who walks in off the
/// street and to the retailer who takes forty every week, at two prices, and
/// has done so on paper for as long as the shop has existed. The item has
/// carried both prices since M1; the party now says which one they pay.
library;

import 'package:pk_money/pk_money.dart';

import '../ports/app_queries.dart';

enum PriceTier {
  retail('retail'),
  wholesale('wholesale'),

  /// The shop's best buyers (M15): a third price, below wholesale.
  vip('vip');

  const PriceTier(this.code);

  /// What the database stores.
  final String code;

  /// Anything unknown is retail: the price every buyer was charged before
  /// tiers existed, and never a price the shop did not mean to give.
  static PriceTier parse(String? code) =>
      values.where((t) => t.code == code).firstOrNull ?? retail;
}

/// The price per base unit [item] is sold at to a [tier] buyer: the tier's
/// own price where the item has one, falling back a tier at a time — VIP to
/// wholesale to retail — where it does not.
Rate priceFor(ItemSummary item, PriceTier tier) => switch (tier) {
  PriceTier.vip => item.vipRate ?? item.wholesaleRate ?? item.saleRate,
  PriceTier.wholesale => item.wholesaleRate ?? item.saleRate,
  PriceTier.retail => item.saleRate,
};
