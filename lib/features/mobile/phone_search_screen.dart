import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'mobile_providers.dart';
import 'phone_story_screen.dart';
import 'pta.dart';
import 'qist_plans_screen.dart';
import 'used_phone_screen.dart';

/// The phone search from the items list, for a mobile shop (M50).
class PhoneSearchButton extends ConsumerWidget {
  const PhoneSearchButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isMobileShopProvider)) return const SizedBox.shrink();
    return BlIconButton(
      icon: Icons.phone_android_outlined,
      label: AppStrings.of(context).mobileSearchTitle,
      onPressed: () => unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PhoneSearchScreen()),
        ),
      ),
    );
  }
}

/// "Phone dhoondein" (M50): one box that takes any part of either IMEI —
/// the last five digits read off a box, the whole number from *#06#, the
/// second SIM's — and lists every phone that answers to it, in the shop or
/// long gone, each opening its whole story.
///
/// The mobile shop's front door, from the home screen: the search, buying
/// a used phone over the counter, and the phones sold on qist.
class PhoneSearchScreen extends ConsumerStatefulWidget {
  const PhoneSearchScreen({super.key, this.initial = ''});

  /// Digits to search for at once: what the counter or the items list was
  /// typed with when it sent the shopkeeper here.
  final String initial;

  @override
  ConsumerState<PhoneSearchScreen> createState() => _PhoneSearchScreenState();
}

class _PhoneSearchScreenState extends ConsumerState<PhoneSearchScreen> {
  late final _query = TextEditingController(text: widget.initial);
  late String _digits = imeiDigits(widget.initial);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _digits = imeiDigits(text));
    });
  }

  void _open(Widget screen) => unawaited(
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)),
  );

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final mobile = ref.watch(appServicesProvider).mobile;
    final results = ref.watch(phoneSearchProvider(_digits));

    return Scaffold(
      appBar: AppBar(title: Text(s.mobileSearchTitle)),
      body: ListView(
        padding: const EdgeInsets.all(BlTokens.space4),
        children: [
          BlField(
            controller: _query,
            label: s.mobileSearchLabel,
            hint: s.mobileSearchHint,
            keyboardType: TextInputType.number,
            autofocus: widget.initial.isEmpty,
            onChanged: _changed,
            prefix: const Icon(Icons.search),
          ),
          const SizedBox(height: BlTokens.space3),
          Wrap(
            spacing: BlTokens.space2,
            runSpacing: BlTokens.space2,
            children: [
              if (mobile.canBuyPhones)
                BlButton(
                  label: s.mobileBuyUsedTitle,
                  icon: Icons.add_to_home_screen_outlined,
                  kind: BlButtonKind.secondary,
                  onPressed: () => _open(const UsedPhoneScreen()),
                ),
              BlButton(
                label: s.mobileQistPlansTitle,
                icon: Icons.calendar_month_outlined,
                kind: BlButtonKind.secondary,
                onPressed: () => _open(const QistPlansScreen()),
              ),
            ],
          ),
          const SizedBox(height: BlTokens.space4),
          if (_digits.length < 3)
            Text(
              s.mobileSearchTypeMore,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            )
          else
            results.when(
              loading: () => const BlSkeletonList(rows: 3),
              error: (e, _) => BlError(
                title: s.commonSomethingWentWrong,
                message: '$e',
                onRetry: () => ref.invalidate(phoneSearchProvider(_digits)),
              ),
              data: (phones) => phones.isEmpty
                  ? BlEmpty(
                      title: s.mobileSearchNone(_digits),
                      icon: Icons.phone_android_outlined,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final phone in phones)
                          PhoneTile(
                            phone: phone,
                            onTap: () => _open(
                              PhoneStoryScreen(
                                lotId: phone.lotId,
                                title: phone.itemName,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

/// One phone in a list: its model, both IMEIs, whether it is in the shop,
/// and what PTA said.
class PhoneTile extends StatelessWidget {
  const PhoneTile({super.key, required this.phone, this.onTap});

  final PhoneUnit phone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: BlCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              phone.itemName,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: t.ink,
              ),
            ),
            const SizedBox(height: BlTokens.space1),
            for (final (i, imei) in phone.imeis.indexed)
              Text(
                phone.imeis.length > 1 ? 'IMEI ${i + 1}: $imei' : 'IMEI: $imei',
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
            const SizedBox(height: BlTokens.space2),
            Wrap(
              spacing: BlTokens.space2,
              runSpacing: BlTokens.space1,
              children: [
                BlChip(
                  phone.onHand ? s.mobileInShop : s.mobileNotInShop,
                  tone: phone.onHand ? BlChipTone.good : BlChipTone.neutral,
                ),
                if (phone.pta != null) PtaChip(status: phone.pta),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
