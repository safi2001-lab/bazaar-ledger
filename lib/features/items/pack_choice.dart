import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Which of an item's units a delivery line is counted in: its own, or one
/// of its packs (M53). "pcs", "carton · 24 pcs", "bori · 50 kg".
///
/// The counter offers packs already, through the unit chips every line has,
/// because those read the item's own conversions; a delivery picker counted
/// only in the base unit, so a supplier's bill for ten cartons had to be
/// typed as two hundred and forty pieces. Shown only when the item has a
/// pack, so the ordinary delivery looks exactly as it did.
///
/// Null is the item's own unit.
class PackChoice extends ConsumerWidget {
  const PackChoice({
    super.key,
    required this.item,
    required this.selected,
    required this.onChanged,
  });

  final ItemSummary item;
  final ItemPack? selected;
  final ValueChanged<ItemPack?> onChanged;

  /// The item's packs, as the shop's conversions hold them.
  static List<ItemPack> packsFor(WidgetRef ref, ItemSummary item) {
    final converter = ref.watch(unitConverterProvider).valueOrNull;
    final units = ref.watch(unitsProvider).valueOrNull ?? const [];
    if (converter == null) return const [];
    return packsOf(
      converter,
      itemId: item.id,
      baseUnitId: item.unitId,
      codes: {for (final u in units) u.id: u.code},
    );
  }

  /// [qty] in the item's base unit, counted in [pack]; null when it does not
  /// come out exactly, which the picker treats as nothing typed yet.
  static Qty? inBase(Qty qty, ItemPack? pack) {
    if (pack == null) return qty;
    try {
      return pack.inBase(qty);
    } on UnitConversionException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final packs = packsFor(ref, item);
    if (packs.isEmpty) return const SizedBox.shrink();
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.purchaseInPack,
            style: TextStyle(fontSize: 13, color: t.inkMuted),
          ),
          const SizedBox(height: BlTokens.space1),
          Wrap(
            spacing: BlTokens.space2,
            runSpacing: BlTokens.space2,
            children: [
              ChoiceChip(
                label: Text(item.unitCode),
                selected: selected == null,
                onSelected: (_) => onChanged(null),
              ),
              for (final pack in packs)
                ChoiceChip(
                  label: Text(
                    '${pack.unitCode} · ${pack.size.display} ${item.unitCode}',
                  ),
                  selected: selected?.unitId == pack.unitId,
                  onSelected: (_) => onChanged(pack),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
