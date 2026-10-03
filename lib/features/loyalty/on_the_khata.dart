import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'loyalty_providers.dart';
import 'party_prices_screen.dart';

/// M66 on a customer's khata: their loyalty points, and their own prices.

/// What the customer holds in points, worth what at today's rate, what they
/// earned, used and let lapse, and the next points to expire. Nothing for a
/// shop that has never given points.
class PointsOnKhata extends ConsumerWidget {
  const PointsOnKhata({super.key, required this.partyId});

  final String partyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rule = ref.watch(loyaltyRulesProvider).valueOrNull?.current;
    if (rule == null) return const SizedBox.shrink();
    final standing = ref.watch(loyaltyStandingProvider(partyId)).valueOrNull;
    if (standing == null) return const SizedBox.shrink();
    final s = AppStrings.of(context);
    final t = context.bl;
    final held = standing.outstanding < 0 ? 0 : standing.outstanding;
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space3),
      child: BlCard(
        padding: const EdgeInsets.all(BlTokens.space3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.stars_outlined, size: 20, color: t.accent),
            const SizedBox(width: BlTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.khataPoints(
                      pointsText(held),
                      rule.valueOf(held).amountOnly,
                    ),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  Text(
                    s.khataPointsSummary(
                      pointsText(standing.earned),
                      pointsText(standing.redeemed),
                      pointsText(standing.expired),
                    ),
                    style: TextStyle(fontSize: 12, color: t.inkMuted),
                  ),
                  if (standing.expiringNext case final next?)
                    Text(
                      s.khataPointsExpiring(pointsText(next.points), next.on),
                      style: TextStyle(fontSize: 12, color: t.warning),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Apne rate: 2 cheezen", opening the customer's own price list, for
/// anyone, so a cashier can read what was agreed. Nothing for a customer
/// with none: the khata is a list the shopkeeper scrolls for its bills, and
/// the first price is given from their details or from the counter line.
class OwnPricesOnKhata extends ConsumerWidget {
  const OwnPricesOnKhata({super.key, required this.party});

  final PartySummary party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(partyPriceListProvider(party.id)).valueOrNull;
    if (list == null || list.isEmpty) return const SizedBox.shrink();
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space3),
      child: BlCard(
        padding: const EdgeInsets.symmetric(
          horizontal: BlTokens.space3,
          vertical: BlTokens.space2,
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PartyPricesScreen(party: party),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.sell_outlined, size: 20, color: t.inkMuted),
            const SizedBox(width: BlTokens.space3),
            Expanded(
              child: Text(
                s.partyPricesCount(list.length),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: t.inkFaint),
          ],
        ),
      ),
    );
  }
}
