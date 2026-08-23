import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// The shop's own details, as they appear on a bill.
class ShopDetailsScreen extends ConsumerStatefulWidget {
  const ShopDetailsScreen({super.key});

  @override
  ConsumerState<ShopDetailsScreen> createState() => _ShopDetailsScreenState();
}

class _ShopDetailsScreenState extends ConsumerState<ShopDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _phone = TextEditingController();
  final _ntn = TextEditingController();
  final _strn = TextEditingController();

  bool _loaded = false;
  bool _registered = false;
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _city.dispose();
    _phone.dispose();
    _ntn.dispose();
    _strn.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // First statement, before the validate and before any await. A disabled
    // button only disables on the next build, so two taps in one frame both
    // reach here.
    if (_busy) return;
    final s = AppStrings.of(context);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    // Held across the await. Backing out of this screen while the write is in
    // flight disposes the element, and `ref.invalidate` on a disposed
    // ConsumerState throws — in release as well as debug. The catch below then
    // finds `mounted == false` and swallows it, so the row was written and
    // nothing on screen ever knew: the shop name stayed stale in the app bar
    // and on every receipt printed afterwards.
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await ref.read(appServicesProvider).updateFirm({
        'name': _name.text.trim(),
        'address_line1': _text(_address),
        'city': _text(_city),
        'phone': _text(_phone),
        'ntn': _text(_ntn),
        'strn': _text(_strn),
        'is_sales_tax_registered': _registered ? 1 : 0,
      });
      container.invalidate(firmProvider);
      container.bumpRefresh();
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(s.actionDone)));
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _failure = '$error';
          _busy = false;
        });
      }
    }
  }

  static String? _text(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final firm = ref.watch(firmProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.settingsShop)),
      body: SafeArea(
        child: firm.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 5),
          ),
          error: (error, _) => Center(
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
              retryLabel: s.actionRetry,
              onRetry: () => ref.invalidate(firmProvider),
            ),
          ),
          data: (profile) {
            if (profile == null) {
              return Center(child: BlEmpty(title: s.commonNothingSaved));
            }
            if (!_loaded) {
              _loaded = true;
              _name.text = profile.name;
              _address.text = profile.addressLine1 ?? '';
              _city.text = profile.city ?? '';
              _phone.text = profile.phone ?? '';
              _ntn.text = profile.ntn ?? '';
              _strn.text = profile.strn ?? '';
              _registered = profile.isSalesTaxRegistered;
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(BlTokens.space4),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
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
                        BlField(
                          controller: _name,
                          label: s.setupShopName,
                          textInputAction: TextInputAction.next,
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? s.commonRequired
                              : null,
                        ),
                        const SizedBox(height: BlTokens.space4),
                        BlField(
                          controller: _address,
                          label: s.settingsAddress,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: BlTokens.space4),
                        Row(
                          children: [
                            Expanded(
                              child: BlField(
                                controller: _city,
                                label: s.setupCity,
                                textInputAction: TextInputAction.next,
                              ),
                            ),
                            const SizedBox(width: BlTokens.space3),
                            Expanded(
                              child: BlField(
                                controller: _phone,
                                label: s.partyPhone,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: BlTokens.space5),

                        // Most kiryana stores are not sales-tax registered:
                        // under s.3(9) STA a non-Tier-1 retailer pays through
                        // the electricity bill instead. So this is off by
                        // default and nothing in the product waits on it.
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _registered,
                          title: Text(s.settingsTaxRegistered),
                          subtitle: Text(
                            s.settingsTaxRegisteredNote,
                            style: TextStyle(fontSize: 12, color: t.inkMuted),
                          ),
                          isThreeLine: true,
                          onChanged: (v) => setState(() => _registered = v),
                        ),
                        if (_registered) ...[
                          const SizedBox(height: BlTokens.space3),
                          Row(
                            children: [
                              Expanded(
                                child: BlField(
                                  controller: _ntn,
                                  label: 'NTN',
                                  textInputAction: TextInputAction.next,
                                ),
                              ),
                              const SizedBox(width: BlTokens.space3),
                              Expanded(
                                child: BlField(
                                  controller: _strn,
                                  label: 'STRN',
                                  textInputAction: TextInputAction.done,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_failure != null) ...[
                          const SizedBox(height: BlTokens.space4),
                          Text(
                            _failure!,
                            style: TextStyle(fontSize: 13, color: t.danger),
                          ),
                        ],
                        const SizedBox(height: BlTokens.space6),
                        BlButton(
                          label: s.actionSave,
                          icon: Icons.check,
                          big: true,
                          busy: _busy,
                          onPressed: _busy ? null : _save,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
