import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'loyalty_providers.dart';

/// Settings → Loyalty points and profit (M66): the shop's rule for points,
/// and whether the counter shows the bill's profit.
///
/// Everyone may read the rule — the cashier is asked about it across the
/// counter — and only the owner changes it. A change is kept as a new
/// version from the moment it is saved, so no point already earned moves.
class LoyaltySettingsScreen extends ConsumerStatefulWidget {
  const LoyaltySettingsScreen({super.key});

  @override
  ConsumerState<LoyaltySettingsScreen> createState() =>
      _LoyaltySettingsScreenState();
}

class _LoyaltySettingsScreenState extends ConsumerState<LoyaltySettingsScreen> {
  final _earnPoints = TextEditingController(text: '1');
  final _earnPer = TextEditingController(text: '100');
  final _redeemPoints = TextEditingController(text: '100');
  final _redeemValue = TextEditingController(text: '50');
  final _expiry = TextEditingController(text: '0');
  final _cap = TextEditingController(text: '50');
  bool _on = true;
  bool _margin = true;
  bool _loaded = false;
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final services = ref.read(appServicesProvider);
    final rule = (await services.loyalty.rules()).current;
    final margin = await services.loyalty.marginSwitchedOn();
    if (!mounted) return;
    setState(() {
      if (rule != null) {
        _on = rule.isOn;
        _earnPoints.text = '${rule.earnPoints}';
        _earnPer.text = _plain(rule.earnPer);
        _redeemPoints.text = '${rule.redeemPoints}';
        _redeemValue.text = _plain(rule.redeemValue);
        _expiry.text = '${rule.expiryMonths}';
        // Basis points read as a figure with two decimals, as M43's do.
        _cap.text = _plain(Money.paisa(rule.maxBillBp));
      }
      _margin = margin;
      _loaded = true;
    });
  }

  static String _plain(Money m) {
    final text = m.amountOnly.replaceAll(',', '');
    return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
  }

  @override
  void dispose() {
    for (final c in [
      _earnPoints,
      _earnPer,
      _redeemPoints,
      _redeemValue,
      _expiry,
      _cap,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    int? whole(TextEditingController c) => int.tryParse(c.text.trim());
    final earnPoints = whole(_earnPoints);
    final earnPer = Money.tryParse(_earnPer.text.trim());
    final redeemPoints = whole(_redeemPoints);
    final redeemValue = Money.tryParse(_redeemValue.text.trim());
    final expiry = whole(_expiry);
    final cap = Money.tryParse(_cap.text.trim())?.inPaisa;
    if (earnPoints == null ||
        earnPer == null ||
        redeemPoints == null ||
        redeemValue == null ||
        expiry == null ||
        cap == null) {
      setState(() => _failure = s.loyaltyProblemFigures);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appServicesProvider)
          .loyalty
          .saveRule(
            LoyaltyRule(
              from: '',
              isOn: _on,
              earnPoints: earnPoints,
              earnPer: earnPer,
              redeemPoints: redeemPoints,
              redeemValue: redeemValue,
              expiryMonths: expiry,
              maxBillBp: cap,
            ),
          );
      if (!mounted) return;
      ref.bumpRefresh();
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(s.loyaltySaved)));
    } on LoyaltyRefused catch (refused) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = loyaltyProblemText(s, refused.problem);
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = '$error';
        });
      }
    }
  }

  Future<void> _setMargin(bool on) async {
    setState(() => _margin = on);
    try {
      await ref.read(appServicesProvider).loyalty.setMarginShown(shown: on);
      if (mounted) ref.bumpRefresh();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _margin = !on;
          _failure = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final mayEdit = services.loyalty.maySetRules;
    final rule = ref.watch(loyaltyRulesProvider).valueOrNull?.current;

    Widget field(TextEditingController c, String label, {int decimals = 2}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: BlTokens.space3),
          child: BlField(
            controller: c,
            label: label,
            numeric: true,
            decimals: decimals,
            enabled: mayEdit,
          ),
        );

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.settingsLoyalty)),
      body: SafeArea(
        child: !_loaded
            ? const BlSkeletonList(rows: 4)
            : ListView(
                padding: EdgeInsets.fromLTRB(
                  BlTokens.space4,
                  BlTokens.space3,
                  BlTokens.space4,
                  MediaQuery.viewInsetsOf(context).bottom + BlTokens.space6,
                ),
                children: [
                  BlSectionHeader(s.loyaltyTitle),
                  const SizedBox(height: BlTokens.space2),
                  Text(
                    s.loyaltyIntro,
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                  if (rule != null) ...[
                    const SizedBox(height: BlTokens.space2),
                    Text(
                      rule.isOn
                          ? s.loyaltyRuleNow(
                              '${rule.earnPoints}',
                              rule.earnPer.amountOnly,
                              '${rule.redeemPoints}',
                              rule.redeemValue.amountOnly,
                              marginLabel(rule.givenBackBp),
                            )
                          : s.loyaltyRuleOff,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                  ],
                  if (!mayEdit) ...[
                    const SizedBox(height: BlTokens.space3),
                    BlOfflineNote(message: s.loyaltyOwnerOnly),
                  ],
                  const SizedBox(height: BlTokens.space3),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _on,
                    title: Text(s.loyaltyOn),
                    onChanged: mayEdit ? (v) => setState(() => _on = v) : null,
                  ),
                  field(_earnPoints, s.loyaltyEarnPoints, decimals: 0),
                  field(_earnPer, s.loyaltyEarnPer),
                  field(_redeemPoints, s.loyaltyRedeemPoints, decimals: 0),
                  field(_redeemValue, s.loyaltyRedeemValue),
                  field(_expiry, s.loyaltyExpiry, decimals: 0),
                  field(_cap, s.loyaltyCap),
                  Text(
                    s.loyaltyBooksNote,
                    style: TextStyle(fontSize: 12, color: t.inkFaint),
                  ),
                  if (_failure != null) ...[
                    const SizedBox(height: BlTokens.space3),
                    Text(
                      _failure!,
                      style: TextStyle(fontSize: 13, color: t.danger),
                    ),
                  ],
                  if (mayEdit) ...[
                    const SizedBox(height: BlTokens.space3),
                    BlButton(
                      label: s.actionSave,
                      icon: Icons.check,
                      busy: _busy,
                      onPressed: _busy ? null : () => unawaited(_save()),
                    ),
                  ],
                  const SizedBox(height: BlTokens.space5),
                  BlSectionHeader(s.marginHeader),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _margin,
                    title: Text(s.marginSwitch),
                    subtitle: Text(
                      s.marginSwitchHint,
                      style: TextStyle(fontSize: 12, color: t.inkMuted),
                    ),
                    onChanged: mayEdit ? (v) => unawaited(_setMargin(v)) : null,
                  ),
                ],
              ),
      ),
    );
  }
}
