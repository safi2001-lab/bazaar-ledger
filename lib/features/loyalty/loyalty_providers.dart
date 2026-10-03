import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../l10n/app_strings.dart';
import '../pos/pos_screen.dart' show cartPreviewByProvider;

/// What the screens read of M66: the shop's loyalty rule, a customer's
/// points and own prices, and the profit on the bill on the counter.
///
/// Each is read again whenever the books move (the refresh tick), so a bill
/// saved on this phone or arriving from another counter changes the points
/// the khata and the payment sheet show.

/// Every version of the shop's loyalty rule.
final loyaltyRulesProvider = FutureProvider<LoyaltyRules>((ref) async {
  ref.watch(refreshTickProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return LoyaltyRules.none;
  return ref.watch(appServicesProvider).loyalty.rules();
});

/// One customer's points, as the books stand today.
final loyaltyStandingProvider = FutureProvider.autoDispose
    .family<LoyaltyStanding, String>((ref, partyId) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).loyalty.standingOf(partyId);
    });

/// One customer's own prices, with their items, by name.
final partyPriceListProvider = FutureProvider.autoDispose
    .family<List<({ItemSummary item, Rate rate})>, String>((
      ref,
      partyId,
    ) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).loyalty.priceListOf(partyId);
    });

/// Whether the counter shows the bill's profit: false, without reading the
/// switch, for a role that may not see costs.
final marginShownProvider = FutureProvider.autoDispose<bool>((ref) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  if (!services.can(Permission.seeCosts)) return false;
  return services.loyalty.marginShown();
});

/// What each item on the counter costs, per its own unit, or null when the
/// profit is not shown — in which case nothing is read at all, so no
/// widget a cashier sees can be handed a cost by mistake.
///
/// Keyed by the items on the bill (bonus goods included), not by the bill,
/// so a quantity stepped asks nothing new.
final counterCostsProvider = FutureProvider.autoDispose<Map<String, Rate>?>((
  ref,
) async {
  if (!await ref.watch(marginShownProvider.future)) return null;
  final ids = ref.watch(
    cartPreviewByProvider(null).select(
      (p) => p == null
          ? ''
          : ({
              for (final l in p.lines) ?l.draft.itemId,
            }.toList()..sort()).join('|'),
    ),
  );
  if (ids.isEmpty) return const {};
  return ref.watch(appServicesProvider).loyalty.counterCosts(ids.split('|'));
});

/// The profit on the bill on the counter, priced as [mode] pays it (M59);
/// null when it is not shown.
final counterMarginProvider = Provider.autoDispose.family<BillMargin?, String?>(
  (ref, mode) {
    final costs = ref.watch(counterCostsProvider).valueOrNull;
    if (costs == null) return null;
    final preview = ref.watch(cartPreviewByProvider(mode));
    if (preview == null) return null;
    return BillMargin.fromSale(preview, costs);
  },
);

/// [problem] in the shopkeeper's words.
String loyaltyProblemText(AppStrings s, LoyaltyProblem problem) =>
    switch (problem) {
      LoyaltyProblem.figures => s.loyaltyProblemFigures,
      LoyaltyProblem.tooGenerous => s.loyaltyProblemTooGenerous,
      LoyaltyProblem.cap => s.loyaltyProblemCap,
      LoyaltyProblem.expiry => s.loyaltyProblemExpiry,
      LoyaltyProblem.noCustomer => s.loyaltyProblemNoCustomer,
      LoyaltyProblem.notEnough => s.loyaltyProblemNotEnough,
      LoyaltyProblem.overCap => s.loyaltyProblemOverCap,
      LoyaltyProblem.off => s.loyaltyProblemOff,
      LoyaltyProblem.mismatch => s.loyaltyProblemMismatch,
    };

/// A count of points as the shop writes it: 1,240.
String pointsText(int points) {
  final negative = points < 0;
  final digits = (negative ? -points : points).toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return negative ? '-$out' : '$out';
}
