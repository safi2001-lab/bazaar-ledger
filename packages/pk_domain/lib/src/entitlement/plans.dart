/// The subscription plans (M21), as the plan document prices them.
///
/// Free is a whole shop for ever: bills, khatas, stock, cash book, printing,
/// sharing and a backup by hand. The paid plans add what a bigger shop
/// needs. Whatever a plan unlocks, losing it never locks the books: every
/// bill, cheque, batch or recipe already made stays readable and keeps
/// working; only starting new ones of a paid kind waits for the plan.
library;

import 'dart:convert';

enum Plan {
  free,
  silver,
  gold,
  platinum;

  /// Play Console subscription id for this plan; free has none.
  String? get productId => this == free ? null : 'plan_$name';

  /// The plan a Play subscription id unlocks, or null for anything else.
  static Plan? forProduct(String productId) =>
      Plan.values.where((p) => p.productId == productId).firstOrNull;

  /// Rupees a year, as the plan document sets them. Play shows its own
  /// price string once it has loaded; this is what is shown before then.
  int get rupeesPerYear => switch (this) {
    free => 0,
    silver => 1999,
    gold => 3499,
    platinum => 5999,
  };

  /// Whether this plan includes everything [other] does.
  bool covers(Plan other) => index >= other.index;

  static Plan parse(String? name) =>
      Plan.values.where((p) => p.name == name).firstOrNull ?? free;

  /// Firms one phone may keep; null is no limit.
  int? get firms => switch (this) {
    free => 1,
    silver || gold => 3,
    platinum => null,
  };

  /// People who may sign in, the owner included; null is no limit.
  int? get users => switch (this) {
    free || silver => 1,
    gold => 5,
    platinum => null,
  };
}

/// What a paid plan unlocks, and the cheapest plan that does.
///
/// One table, so moving a feature to another plan is one line.
enum PlanFeature {
  /// Receipts and shared bills without the "made with" line.
  noWatermark(Plan.silver),

  /// The daily Google Drive backup (M20).
  autoDriveBackup(Plan.silver),

  /// Recording new post-dated cheques (M6).
  cheques(Plan.silver),

  /// Wholesale and VIP price lists (M7, M15).
  priceLists(Plan.silver),

  /// Profit and loss, balance sheet, trial balance and the tax reports.
  accountingReports(Plan.silver),

  /// Batch and expiry, serial and IMEI tracking (M11).
  tracking(Plan.gold),

  /// Weighing-scale labels at the counter (M16).
  scaleLabels(Plan.gold),

  /// Godowns and stock transfers between them (M11).
  godowns(Plan.gold),

  /// More than one counter on the shop's wi-fi (M13).
  lanSync(Plan.gold),

  /// Reporting bills to FBR live (M19).
  fbr(Plan.platinum),

  /// Recipes and production runs (M17).
  manufacturing(Plan.platinum),

  /// Vans and rider settlement (M18).
  vans(Plan.platinum);

  const PlanFeature(this.plan);

  final Plan plan;
}

/// Refused because the shop's plan does not include it. Says which plan
/// would, so the screen can offer exactly that one.
final class PlanRequired implements Exception {
  const PlanRequired(this.needed, this.reason);

  final Plan needed;
  final String reason;

  @override
  String toString() => reason;
}

/// A Google Play purchase, read from the JSON Play signed.
final class PlayPurchase {
  const PlayPurchase({
    required this.productId,
    required this.purchaseToken,
    required this.purchaseState,
    required this.purchaseTimeMillis,
    required this.packageName,
    this.autoRenewing = true,
  });

  final String productId;
  final String purchaseToken;

  /// 0 purchased, 1 cancelled, 2 pending.
  final int purchaseState;
  final int purchaseTimeMillis;
  final String packageName;
  final bool autoRenewing;

  bool get isPurchased => purchaseState == 0;
}

/// How long a plan Play last confirmed is honoured while the phone cannot
/// reach Play. A shop with no signal for a month keeps its plan; a lapsed
/// subscription stops at the next check that reaches Play.
const planOfflineGrace = Duration(days: 30);

/// The plan a verified purchase gives, at [nowUtc].
///
/// Free unless the signature checked out, the purchase is a completed one
/// for this app, it names a plan, and Play confirmed it within
/// [planOfflineGrace]. Never falls open: any doubt is free.
Plan planFor({
  required PlayPurchase? purchase,
  required bool signatureValid,
  required DateTime? confirmedUtc,
  required DateTime nowUtc,
  required String packageName,
}) {
  if (purchase == null || !signatureValid || confirmedUtc == null) {
    return Plan.free;
  }
  if (!purchase.isPurchased || purchase.packageName != packageName) {
    return Plan.free;
  }
  if (nowUtc.difference(confirmedUtc) > planOfflineGrace) return Plan.free;
  return Plan.forProduct(purchase.productId) ?? Plan.free;
}

/// Reads the purchase JSON Play signed; null if it is not one.
PlayPurchase? readPlayPurchase(String originalJson) {
  final Object? decoded;
  try {
    decoded = jsonDecode(originalJson);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) return null;
  final product = decoded['productId'];
  final token = decoded['purchaseToken'];
  if (product is! String || token is! String) return null;
  final state = decoded['purchaseState'];
  final time = decoded['purchaseTime'];
  return PlayPurchase(
    productId: product,
    purchaseToken: token,
    purchaseState: state is int ? state : 0,
    purchaseTimeMillis: time is int ? time : 0,
    packageName: '${decoded['packageName'] ?? ''}',
    autoRenewing: decoded['autoRenewing'] != false,
  );
}
