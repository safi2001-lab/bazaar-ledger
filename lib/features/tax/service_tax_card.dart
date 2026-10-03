import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// The province's tax on the shop's services, as Settings, Tax shows it.
final serviceTaxProvider = FutureProvider.autoDispose<ServiceTaxSetting?>((
  ref,
) {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).counterTax.serviceTax();
});

/// The province's sales tax on the shop's services, in Settings, Tax (M59).
///
/// For a repair shop, a salon, a tailor or a restaurant: who collects it,
/// and its two rates — in cash, and by card, wallet or QR. Picking PRA or
/// SRB fills in the rates as this pack found them published; KPRA and BRA
/// were not checked, so their fields start empty and the owner types what
/// their notice says. Only items marked as a service are taxed by it.
class ServiceTaxCard extends ConsumerStatefulWidget {
  const ServiceTaxCard({super.key});

  @override
  ConsumerState<ServiceTaxCard> createState() => _ServiceTaxCardState();
}

class _ServiceTaxCardState extends ConsumerState<ServiceTaxCard> {
  final _standard = TextEditingController();
  final _digital = TextEditingController();
  ServiceTaxAuthority? _authority;
  bool _loaded = false;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _standard.dispose();
    _digital.dispose();
    super.dispose();
  }

  void _load(ServiceTaxSetting? held) {
    if (_loaded) return;
    _loaded = true;
    _authority = held?.authority;
    _standard.text = held == null ? '' : _percent(held.standardBp);
    _digital.text = held == null ? '' : _percent(held.digitalBp);
  }

  /// `1600` as "16", `850` as "8.5": what the owner would type.
  static String _percent(int bp) => percentOfBp(bp).replaceAll('%', '');

  /// "16" or "8.5" as basis points: two decimals of a percent are exactly
  /// the paisa of an amount, so the money parser reads them without a float.
  static int? _bp(String typed) => Money.tryParse(typed)?.inPaisa;

  void _pick(ServiceTaxAuthority? authority) {
    final published = authority == null
        ? null
        : ServiceTaxSetting.publishedFor(authority);
    setState(() {
      _authority = authority;
      _message = null;
      _standard.text = published == null ? '' : _percent(published.standardBp);
      _digital.text = published == null ? '' : _percent(published.digitalBp);
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final authority = _authority;
    ServiceTaxSetting? setting;
    if (authority != null) {
      final standard = _bp(_standard.text);
      final digital = _bp(_digital.text);
      if (standard == null ||
          digital == null ||
          !ServiceTaxSetting.validRateBp(standard) ||
          !ServiceTaxSetting.validRateBp(digital)) {
        setState(() => _message = s.serviceTaxRateWrong);
        return;
      }
      setting = ServiceTaxSetting(
        authority: authority,
        standardBp: standard,
        digitalBp: digital,
      );
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final container = ProviderScope.containerOf(context, listen: false);
    String message;
    try {
      await ref.read(appServicesProvider).counterTax.setServiceTax(setting);
      message = s.serviceTaxSaved;
    } on PermissionDenied catch (e) {
      message = e.reason;
    } on Object catch (e) {
      message = '$e';
    }
    container.bumpRefresh();
    if (mounted) {
      setState(() {
        _busy = false;
        _message = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final held = ref.watch(serviceTaxProvider);
    if (held.hasValue) _load(held.value);
    final canSet = services.counterTax.canSet;
    final authority = _authority;
    final unchecked = authority != null && authority.published == null;

    final choices = <(ServiceTaxAuthority?, String)>[
      (null, s.serviceTaxNone),
      (ServiceTaxAuthority.pra, s.serviceTaxPra),
      (ServiceTaxAuthority.srb, s.serviceTaxSrb),
      (ServiceTaxAuthority.kpra, s.serviceTaxKpra),
      (ServiceTaxAuthority.bra, s.serviceTaxBra),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlSectionHeader(s.serviceTaxTitle),
        const SizedBox(height: BlTokens.space2),
        Text(
          s.serviceTaxHint,
          style: TextStyle(fontSize: 13, color: t.inkMuted),
        ),
        const SizedBox(height: BlTokens.space2),
        Wrap(
          spacing: BlTokens.space2,
          runSpacing: BlTokens.space2,
          children: [
            for (final (choice, label) in choices)
              ChoiceChip(
                selected: authority == choice,
                label: Text(label),
                onSelected: canSet && !_busy ? (_) => _pick(choice) : null,
              ),
          ],
        ),
        if (authority != null) ...[
          const SizedBox(height: BlTokens.space3),
          if (unchecked) ...[
            Text(
              s.serviceTaxUnchecked,
              style: TextStyle(fontSize: 12, color: t.warning),
            ),
            const SizedBox(height: BlTokens.space2),
          ],
          BlField(
            controller: _standard,
            label: s.serviceTaxStandard,
            numeric: true,
            enabled: canSet,
            onChanged: (_) => setState(() => _message = null),
          ),
          const SizedBox(height: BlTokens.space2),
          BlField(
            controller: _digital,
            label: s.serviceTaxDigital,
            numeric: true,
            enabled: canSet,
            onChanged: (_) => setState(() => _message = null),
          ),
        ],
        if (canSet) ...[
          const SizedBox(height: BlTokens.space3),
          BlButton(
            label: s.serviceTaxSave,
            icon: Icons.check,
            kind: BlButtonKind.secondary,
            busy: _busy,
            onPressed: _busy ? null : () => unawaited(_save()),
          ),
        ],
        if (_message case final message?) ...[
          const SizedBox(height: BlTokens.space2),
          Text(message, style: TextStyle(fontSize: 14, color: t.ink)),
        ],
      ],
    );
  }
}
