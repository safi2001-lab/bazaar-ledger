import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// What PTA said of a phone, in the shopkeeper's words (M50).
String ptaWords(AppStrings s, PtaStatus? status) => switch (status) {
  PtaStatus.approved => s.mobilePtaApproved,
  PtaStatus.validUnapproved => s.mobilePtaValidUnapproved,
  PtaStatus.nonCompliant => s.mobilePtaNonCompliant,
  PtaStatus.unknown || null => s.mobilePtaUnknown,
};

/// A phone's PTA standing as a chip: green approved, amber not approved or
/// not asked, red non-compliant.
class PtaChip extends StatelessWidget {
  const PtaChip({super.key, required this.status});

  final PtaStatus? status;

  @override
  Widget build(BuildContext context) => BlChip(
    ptaWords(AppStrings.of(context), status),
    icon: Icons.verified_user_outlined,
    tone: switch (status) {
      PtaStatus.approved => BlChipTone.good,
      PtaStatus.nonCompliant => BlChipTone.bad,
      _ => BlChipTone.warn,
    },
  );
}

/// Opens the phone's own messages app with [imei] typed to 8484, for the
/// shopkeeper to press Send from their own SIM.
///
/// Nothing is sent by this app — it holds no SEND_SMS permission and calls
/// no server — and the answer comes back as an ordinary message, which the
/// shopkeeper writes down with [askPtaAnswer]. Needs signal and costs the
/// shop's SIM about ten paisa **[as reported, unverified]**.
Future<void> checkOn8484(BuildContext context, String imei) async {
  final s = AppStrings.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final uri = ptaCheckSms(imei);
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } on Object {
    // Said below: no messages app took the link.
  }
  messenger.showSnackBar(
    SnackBar(content: Text(s.mobilePtaNoSmsApp(imeiDigits(imei)))),
  );
}

/// Asks what PTA's reply said, and returns it; null when nothing was picked.
Future<PtaStatus?> askPtaAnswer(BuildContext context, {PtaStatus? current}) {
  final s = AppStrings.of(context);
  return showModalBottomSheet<PtaStatus>(
    context: context,
    useSafeArea: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(BlTokens.space4),
            child: Text(
              s.mobilePtaAnswerTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          for (final status in PtaStatus.values)
            ListTile(
              leading: Icon(
                status == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(ptaWords(s, status)),
              onTap: () => Navigator.of(context).pop(status),
            ),
          Padding(
            padding: const EdgeInsets.all(BlTokens.space4),
            child: Text(
              s.mobilePtaUnverifiedNote,
              style: TextStyle(fontSize: 12, color: context.bl.inkMuted),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Before a phone PTA has called non-compliant goes on a bill: says so, and
/// lets the shopkeeper go on knowingly (M50). A warning, never a block: the
/// customer may be buying it for parts, or abroad.
///
/// True to go on.
Future<bool> ptaAllowsSale(
  BuildContext context,
  WidgetRef ref,
  String lotId,
) async {
  final phone = await ref.read(appServicesProvider).mobile.phone(lotId);
  if (phone == null || !(phone.pta?.mayBeBlocked ?? false)) return true;
  if (!context.mounted) return false;
  final s = AppStrings.of(context);
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(s.mobilePtaWarnTitle),
      content: Text(s.mobilePtaWarnBody(phone.itemName, phone.imei1)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(s.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(s.mobilePtaWarnSellAnyway),
        ),
      ],
    ),
  );
  return go ?? false;
}
