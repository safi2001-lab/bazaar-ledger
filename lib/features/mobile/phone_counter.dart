import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'phone_search_screen.dart';

/// A phone in the shop found at the counter by part of either IMEI (M50):
/// "the last five digits on the box", typed into the counter's own search
/// box. The whole IMEI, and IMEI 2, are found before this by the counter's
/// serial lookup; this is what a mobile shop types when it cannot read the
/// whole number.
///
/// One phone that answers is the phone; more than one are offered to pick
/// from; none, a shop that is not a mobile shop, fewer than five digits, or
/// digits an item's own code or name answers to, is null and the counter
/// searches items as ever.
Future<LotOnHand?> phoneOnCounter(
  BuildContext context,
  WidgetRef ref,
  String typed,
) async {
  final digits = imeiDigits(typed);
  if (digits.length < 5 ||
      digits.length >= 15 ||
      !RegExp(r'^\d+$').hasMatch(digits)) {
    return null;
  }
  final services = ref.read(appServicesProvider);
  final mobile = services.mobile;
  if (!await mobile.isMobileShop()) return null;
  // An item's own code or name that the digits find comes first: "12345"
  // typed for the charger kept under that code is the charger, not a phone
  // whose IMEI happens to hold those digits.
  final firm = await services.queries.currentFirm();
  if (firm == null) return null;
  if ((await services.queries.searchItems(
    firm.id,
    query: digits,
    limit: 1,
  )).isNotEmpty) {
    return null;
  }
  final phones = [
    for (final p in await mobile.findPhones(digits))
      if (p.onHand) p,
  ];
  if (phones.isEmpty || !context.mounted) return null;
  final picked = phones.length == 1
      ? phones.single
      : await showModalBottomSheet<PhoneUnit>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          builder: (context) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(BlTokens.space4),
              children: [
                Text(
                  AppStrings.of(context).mobileCounterPick(digits),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: BlTokens.space3),
                for (final p in phones)
                  PhoneTile(
                    phone: p,
                    onTap: () => Navigator.of(context).pop(p),
                  ),
              ],
            ),
          ),
        );
  if (picked == null) return null;
  return LotOnHand(
    lotId: picked.lotId,
    itemId: picked.itemId,
    itemName: picked.itemName,
    lotNo: picked.imei1,
    qty: Qty.one,
    cost: Rate.zero,
    serial: picked.imei1,
  );
}
