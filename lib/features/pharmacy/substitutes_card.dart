import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'pharmacy_providers.dart';

/// The medicines with the same salt and strength as [item] (M49), with what
/// the shelf holds of each and its price: what the chemist reaches for when
/// the brand the customer asked for is out.
///
/// Nothing at all for an item with no salt.
class SubstitutesCard extends ConsumerWidget {
  const SubstitutesCard({super.key, required this.item});

  final ItemSummary item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = item.medicine?.label;
    if (label == null) return const SizedBox.shrink();
    final s = AppStrings.of(context);
    final t = context.bl;
    final found = ref.watch(substitutesProvider(item.id)).valueOrNull;
    if (found == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BlSectionHeader(s.pharmacySubstitutes(label)),
          const SizedBox(height: BlTokens.space2),
          if (found.isEmpty)
            Text(
              s.pharmacyNoSubstitutes,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
          for (final other in found)
            Padding(
              padding: const EdgeInsets.only(bottom: BlTokens.space1),
              child: BlCard(
                padding: const EdgeInsets.all(BlTokens.space3),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            other.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: t.ink,
                            ),
                          ),
                          if (other.medicine?.manufacturer case final maker?)
                            Text(
                              maker,
                              style: TextStyle(fontSize: 12, color: t.inkMuted),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: BlTokens.space2),
                    BlChip(
                      '${other.stockOnHand.display} ${other.unitCode}',
                      tone: other.stockOnHand.isPositive
                          ? BlChipTone.good
                          : BlChipTone.bad,
                    ),
                    const SizedBox(width: BlTokens.space2),
                    // The price of one, in the item's own unit.
                    BlMoney(
                      other.saleRate.amountFor(Qty.one),
                      size: 14,
                      semanticPrefix: other.name,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
