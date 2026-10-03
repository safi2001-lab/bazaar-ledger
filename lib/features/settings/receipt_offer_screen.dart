import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../sales/receipt_offer.dart' show receiptOfferName;

/// What a party nobody set is offered when money moves (M70): asked every
/// time, WhatsApp opened by itself with the message typed, or nothing.
///
/// The shop's default, kept the moment it is tapped. A party set on their
/// own form, or from the offer itself, keeps their own.
class ReceiptOfferScreen extends ConsumerStatefulWidget {
  const ReceiptOfferScreen({super.key});

  @override
  ConsumerState<ReceiptOfferScreen> createState() => _ReceiptOfferScreenState();
}

class _ReceiptOfferScreenState extends ConsumerState<ReceiptOfferScreen> {
  ReceiptOffer? _offer;
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final offer = await ref.read(appServicesProvider).receiptOfferDefault();
    if (mounted) setState(() => _offer = offer);
  }

  Future<void> _choose(ReceiptOffer offer) async {
    // First statement: two taps in one frame both reach here.
    if (_busy || offer == _offer) return;
    final s = AppStrings.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await ref.read(appServicesProvider).setReceiptOfferDefault(offer);
      if (!mounted) return;
      setState(() => _offer = offer);
      messenger.showSnackBar(SnackBar(content: Text(s.receiptOfferSaved)));
    } on Object catch (error) {
      if (mounted) {
        setState(() => _failure = '${s.commonSomethingWentWrong}: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final offer = _offer;
    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.settingsReceiptOffer)),
      body: SafeArea(
        child: offer == null
            ? const Padding(
                padding: EdgeInsets.all(BlTokens.space4),
                child: BlSkeletonList(rows: 3),
              )
            : ListView(
                padding: const EdgeInsets.all(BlTokens.space4),
                children: [
                  Text(
                    s.receiptOfferSettingsIntro,
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  BlSectionHeader(s.receiptOfferDefaultTitle),
                  for (final choice in ReceiptOffer.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: BlTokens.space2),
                      child: Semantics(
                        selected: offer == choice,
                        button: true,
                        child: BlCard(
                          accent: offer == choice,
                          onTap: () => unawaited(_choose(choice)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: BlTokens.space4,
                            vertical: BlTokens.space3,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                offer == choice
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                color: offer == choice ? t.accent : t.inkFaint,
                              ),
                              const SizedBox(width: BlTokens.space3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      receiptOfferName(s, choice),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: t.ink,
                                      ),
                                    ),
                                    Text(
                                      switch (choice) {
                                        ReceiptOffer.ask =>
                                          s.receiptOfferAskHint,
                                        ReceiptOffer.auto =>
                                          s.receiptOfferAutoHint,
                                        ReceiptOffer.never =>
                                          s.receiptOfferNeverHint,
                                      },
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: t.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: BlTokens.space2),
                  Text(
                    s.receiptOfferPerParty,
                    style: TextStyle(fontSize: 12, color: t.inkMuted),
                  ),
                  const SizedBox(height: BlTokens.space2),
                  Text(
                    s.receiptOfferNote,
                    style: TextStyle(fontSize: 12, color: t.inkMuted),
                  ),
                  if (_failure != null) ...[
                    const SizedBox(height: BlTokens.space3),
                    Text(
                      _failure!,
                      style: TextStyle(fontSize: 13, color: t.danger),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
