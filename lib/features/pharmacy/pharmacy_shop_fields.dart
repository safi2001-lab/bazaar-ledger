import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'pharmacy_providers.dart';

/// What kind of shop this is, in the shop's details, and — for a medical
/// store — its standing discount off the printed price (M49).
///
/// The kind was asked once at first run and could never be changed, so a
/// shop set up as a general store that also runs a medicine counter had no
/// way to say so. Saying "Medical store" here is what turns the pharmacy
/// pack on: the DRAP price enforced at the counter, the medicine fields in
/// the item editor, and the near-expiry list.
class PharmacyShopFields extends ConsumerWidget {
  const PharmacyShopFields({
    super.key,
    required this.kind,
    required this.offMrp,
    required this.onKind,
  });

  /// `firms.business_kind`.
  final String kind;

  /// The standing discount off the MRP, as a percentage typed.
  final TextEditingController offMrp;
  final ValueChanged<String> onKind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final kinds = {
      'general': s.businessKindGeneral,
      'kiryana': s.businessKindKiryana,
      'pharmacy': s.businessKindPharmacy,
      'garments': s.businessKindGarments,
      'cloth': s.businessKindCloth,
      'hardware': s.businessKindHardware,
      'electronics': s.businessKindElectronics,
      'restaurant': s.businessKindRestaurant,
      'services': s.businessKindServices,
      'wholesale': s.businessKindWholesale,
      'mobile': s.businessKindMobile, // M50
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: BlTokens.space4),
        DropdownButtonFormField<String>(
          initialValue: kinds.containsKey(kind) ? kind : 'general',
          isExpanded: true,
          decoration: InputDecoration(labelText: s.setupBusinessKind),
          items: [
            for (final MapEntry(key: code, value: name) in kinds.entries)
              DropdownMenuItem(value: code, child: Text(name)),
          ],
          onChanged: (v) {
            if (v != null) onKind(v);
          },
        ),
        if (kind == 'pharmacy') ...[
          const SizedBox(height: BlTokens.space3),
          BlField(
            controller: offMrp,
            label: s.pharmacyShopOffMrp,
            hint: '10',
            numeric: true,
            enabled: ref.read(appServicesProvider).pharmacy.canSetRules,
          ),
          const SizedBox(height: BlTokens.space1),
          Text(
            s.pharmacyShopOffMrpNote,
            style: TextStyle(fontSize: 12, color: t.inkMuted),
          ),
        ],
      ],
    );
  }
}

/// The standing discount off the MRP as the field shows it: "10" for 1000
/// basis points, empty for none.
String offMrpText(int bp) => bp == 0 ? '' : _percent(bp);

String _percent(int bp) {
  final whole = bp ~/ 100;
  final part = bp % 100;
  return part == 0 ? '$whole' : '$whole.${part.toString().padLeft(2, '0')}';
}

/// Saves the standing discount off the MRP typed in [offMrp], when the shop
/// is a pharmacy and whoever is signed in may set it, and it changed.
Future<void> savePharmacyShopFields(
  WidgetRef ref, {
  required String kind,
  required TextEditingController offMrp,
}) async {
  final pharmacy = ref.read(appServicesProvider).pharmacy;
  if (kind != 'pharmacy' || !pharmacy.canSetRules) return;
  // "10" is 1000 basis points, as rupees are paisa: no float is made of it.
  final bp = (Money.tryParse(offMrp.text) ?? Money.zero).inPaisa;
  final was = (await pharmacy.rules()).offMrpBp;
  if (bp == was) return;
  await pharmacy.setOffMrp(bp.clamp(0, 10000));
}

/// The standing discount as the shop has it now, for the field to start
/// from.
Future<String> loadOffMrpText(WidgetRef ref) async =>
    offMrpText((await ref.read(pharmacyRulesProvider.future)).offMrpBp);
