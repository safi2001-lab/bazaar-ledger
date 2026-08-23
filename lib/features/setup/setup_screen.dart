import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// First run. Three fields, one button, and the shop exists.
///
/// Deliberately not a multi-step carousel. The competitors that ask for a
/// phone number and an OTP before you can write a single line lose people at
/// that screen; there is no account here to verify, so there is nothing to
/// ask. Everything else — city, province, trade, tax registration — is a
/// Settings row the shopkeeper can fill in later, or never.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shop = TextEditingController();
  final _owner = TextEditingController();
  final _city = TextEditingController();
  final _counter = TextEditingController(text: 'Counter 1');

  String _province = 'punjab';
  String _businessKind = 'general';
  bool _busy = false;
  Object? _failure;

  @override
  void dispose() {
    _shop.dispose();
    _owner.dispose();
    _city.dispose();
    _counter.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    // Held across the await. This one matters most of all: the firm provider
    // is what the root switches on, so if it is never invalidated the shop is
    // created and the app stays on the setup wizard, inviting the shopkeeper
    // to create it a second time.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref
          .read(appServicesProvider)
          .setUpShop(
            shopName: _shop.text.trim(),
            ownerName: _owner.text.trim(),
            deviceLabel: _counter.text.trim().isEmpty
                ? 'Counter 1'
                : _counter.text.trim(),
            city: _city.text.trim(),
            province: _province,
            businessKind: _businessKind,
          );
      // The firm provider is what `_Root` switches on, so invalidating it is
      // the whole of the navigation.
      container.invalidate(firmProvider);
    } on Object catch (error) {
      if (mounted) setState(() => _failure = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    if (_failure != null) {
      return Scaffold(
        backgroundColor: t.paper,
        body: SafeArea(
          child: Center(
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$_failure',
              reassurance: s.errorNothingWasSaved,
              retryLabel: s.actionRetry,
              onRetry: () => setState(() => _failure = null),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: t.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(BlTokens.space5),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                // Re-validated as the shopkeeper types, once they have
                // touched the form. Without this a field validated on Save
                // keeps its red border and its error message after the text
                // is corrected — the message only refreshes on the next
                // `validate()` call. Found by hand on the handset: "Aap ka
                // naam" read "Yeh khana zaroori hai" in red while holding
                // "Malik Sahib". For an audience where 60% national and 52%
                // rural literacy is the design constraint, an error that
                // will not go away is a dead end.
                autovalidateMode: AutovalidateMode.onUserInteraction,
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: BlTokens.space6),
                    Text(
                      s.setupTitle,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                    const SizedBox(height: BlTokens.space2),
                    Text(
                      s.setupSubtitle,
                      style: TextStyle(fontSize: 15, color: t.inkMuted),
                    ),
                    const SizedBox(height: BlTokens.space6),
                    BlField(
                      controller: _shop,
                      label: s.setupShopName,
                      hint: s.setupShopNameHint,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? s.commonRequired : null,
                    ),
                    const SizedBox(height: BlTokens.space4),
                    BlField(
                      controller: _owner,
                      label: s.setupOwnerName,
                      hint: s.setupOwnerNameHint,
                      textInputAction: TextInputAction.next,
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? s.commonRequired : null,
                    ),
                    const SizedBox(height: BlTokens.space4),
                    BlField(
                      controller: _city,
                      label: s.setupCity,
                      hint: s.setupCityHint,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: BlTokens.space4),
                    _Picker(
                      label: s.setupProvince,
                      value: _province,
                      options: {
                        'punjab': s.provincePunjab,
                        'sindh': s.provinceSindh,
                        'kpk': s.provinceKpk,
                        'balochistan': s.provinceBalochistan,
                        'ict': s.provinceIct,
                        'gb': s.provinceGb,
                        'ajk': s.provinceAjk,
                      },
                      onChanged: (v) => setState(() => _province = v),
                    ),
                    const SizedBox(height: BlTokens.space4),
                    _Picker(
                      label: s.setupBusinessKind,
                      value: _businessKind,
                      options: {
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
                      },
                      onChanged: (v) => setState(() => _businessKind = v),
                    ),
                    const SizedBox(height: BlTokens.space4),
                    BlField(
                      controller: _counter,
                      label: s.setupCounterName,
                      hint: s.setupCounterHint,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _finish(),
                    ),
                    const SizedBox(height: BlTokens.space6),
                    BlButton(
                      label: s.setupFinish,
                      icon: Icons.storefront_outlined,
                      big: true,
                      busy: _busy,
                      onPressed: _busy ? null : _finish,
                    ),
                    const SizedBox(height: BlTokens.space5),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline, size: 16, color: t.inkFaint),
                        const SizedBox(width: BlTokens.space2),
                        Expanded(
                          child: Text(
                            s.setupPrivacyNote,
                            style: TextStyle(fontSize: 13, color: t.inkFaint),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: BlTokens.space6),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled dropdown that stays inside the design system.
class _Picker extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final entry in options.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (v) => v == null ? null : onChanged(v),
    );
  }
}
