import 'package:flutter/material.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// How an item is taxed, on its editor (M59): goods sold on the price
/// printed on the pack (the Third Schedule), or a service the province
/// taxes. Neither is the ordinary case, which is goods taxed on what they
/// are sold for — so both are off until the owner says otherwise, and one
/// turned on turns the other off: a pack of biscuits is not a haircut.
class ItemTaxKindFields extends StatelessWidget {
  const ItemTaxKindFields({
    super.key,
    required this.thirdSchedule,
    required this.service,
    required this.onChanged,
  });

  final bool thirdSchedule;
  final bool service;

  /// The pair as it should now be.
  final void Function({required bool thirdSchedule, required bool service})
  onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Column(
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: thirdSchedule,
          title: Text(s.itemThirdSchedule),
          subtitle: Text(
            s.itemThirdScheduleHint,
            style: TextStyle(fontSize: 12, color: t.inkMuted),
          ),
          onChanged: (v) =>
              onChanged(thirdSchedule: v, service: v ? false : service),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: service,
          title: Text(s.itemService),
          subtitle: Text(
            s.itemServiceHint,
            style: TextStyle(fontSize: 12, color: t.inkMuted),
          ),
          onChanged: (v) =>
              onChanged(thirdSchedule: v ? false : thirdSchedule, service: v),
        ),
      ],
    );
  }
}

/// What stops the item being saved as it is, in words: a Third Schedule
/// item is taxed on its MRP, so it needs one.
String? itemTaxKindProblem(
  AppStrings s, {
  required bool thirdSchedule,
  required String mrp,
}) {
  if (!thirdSchedule) return null;
  final price = Money.tryParse(mrp);
  return price == null || !price.isPositive
      ? s.itemThirdScheduleNeedsMrp
      : null;
}
