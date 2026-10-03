import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'control_providers.dart';

/// One customer's credit rules, from their editor's credit section (M68).
///
/// The limit itself stays on the editor, where it has been since M3; here
/// is what going over it does, how many bills they may leave open, how old
/// the oldest may be, what a bounced cheque does, and a temporary limit
/// that lapses by itself. Each left on "the shop's rule" takes Settings'.
class PartyCreditTile extends ConsumerWidget {
  const PartyCreditTile({super.key, required this.party});

  final PartySummary party;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final read = ref.watch(partyCreditProvider(party.id)).valueOrNull;
    final today = BusinessDate.now(ref.watch(appServicesProvider).clock);
    final own = read?.own ?? PartyCreditRules.none;
    final temp = own.tempLimitOn(today);
    return BlCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PartyCreditScreen(party: party),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.rule_outlined, size: 20, color: t.inkMuted),
          const SizedBox(width: BlTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.creditRulesHeader,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                Text(
                  own.isNone ? s.partyCreditShopRules : s.partyCreditOwnRules,
                  style: TextStyle(fontSize: 13, color: t.inkMuted),
                ),
                if (temp != null)
                  Text(
                    s.partyCreditTemp(
                      temp.amountOnly,
                      shortDate(own.tempUntil!.value),
                    ),
                    style: TextStyle(fontSize: 13, color: t.accent),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 20, color: t.inkFaint),
        ],
      ),
    );
  }
}

class PartyCreditScreen extends ConsumerStatefulWidget {
  const PartyCreditScreen({super.key, required this.party});

  final PartySummary party;

  @override
  ConsumerState<PartyCreditScreen> createState() => _PartyCreditScreenState();
}

/// A rule's choice on this screen: the shop's, the customer's own figure
/// and mode, or none for them.
enum _Pick { shop, own, none }

class _PartyCreditScreenState extends ConsumerState<PartyCreditScreen> {
  final _bills = TextEditingController();
  final _days = TextEditingController();
  final _temp = TextEditingController();
  CreditMode? _limitMode;
  _Pick _billsPick = _Pick.shop;
  CreditMode _billsMode = CreditMode.warn;
  _Pick _daysPick = _Pick.shop;
  CreditMode _daysMode = CreditMode.warn;
  CreditMode? _bounceMode;
  BusinessDate? _tempUntil;
  CreditStanding? _standing;
  bool _loaded = false;
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final credit = ref.read(appServicesProvider).credit;
    final own = await credit.rulesOf(widget.party.id);
    final standing = await credit.standingOf(widget.party.id);
    if (!mounted) return;
    setState(() {
      _standing = standing;
      _limitMode = own.limitMode;
      _billsPick = own.noBillsRule
          ? _Pick.none
          : own.maxOpenBills == null
          ? _Pick.shop
          : _Pick.own;
      _bills.text = own.maxOpenBills?.toString() ?? '';
      _billsMode = own.billsMode ?? CreditMode.warn;
      _daysPick = own.noDaysRule
          ? _Pick.none
          : own.maxDays == null
          ? _Pick.shop
          : _Pick.own;
      _days.text = own.maxDays?.toString() ?? '';
      _daysMode = own.daysMode ?? CreditMode.warn;
      _bounceMode = own.bounceMode;
      _temp.text = own.tempLimit?.amountOnly.replaceAll(',', '') ?? '';
      _tempUntil = own.tempUntil;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _bills.dispose();
    _days.dispose();
    _temp.dispose();
    super.dispose();
  }

  Future<void> _pickUntil() async {
    final clock = ref.read(appServicesProvider).clock;
    final today = BusinessDate.now(clock);
    final first = DateTime(today.year, today.month, today.day);
    final at = _tempUntil ?? today.addDays(7);
    final picked = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: first.add(const Duration(days: 366)),
      initialDate: DateTime(at.year, at.month, at.day),
    );
    if (picked == null || !mounted) return;
    setState(
      () => _tempUntil = BusinessDate.tryParse(
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}',
      ),
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    int? whole(TextEditingController c) => int.tryParse(c.text.trim());
    final bills = _billsPick == _Pick.own ? whole(_bills) : null;
    final days = _daysPick == _Pick.own ? whole(_days) : null;
    final tempText = _temp.text.trim();
    final temp = tempText.isEmpty ? null : Money.tryParse(tempText);
    if ((_billsPick == _Pick.own && bills == null) ||
        (_daysPick == _Pick.own && days == null) ||
        (tempText.isNotEmpty && temp == null)) {
      setState(() => _failure = s.creditFiguresBad);
      return;
    }
    final today = BusinessDate.now(ref.read(appServicesProvider).clock);
    // A temporary limit typed with no day picked stands for a week.
    final until = temp == null ? null : _tempUntil ?? today.addDays(7);
    setState(() {
      _busy = true;
      _failure = null;
    });
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appServicesProvider)
          .credit
          .setRules(
            widget.party.id,
            PartyCreditRules(
              limitMode: _limitMode,
              maxOpenBills: bills,
              billsMode: _billsPick == _Pick.own ? _billsMode : null,
              noBillsRule: _billsPick == _Pick.none,
              maxDays: days,
              daysMode: _daysPick == _Pick.own ? _daysMode : null,
              noDaysRule: _daysPick == _Pick.none,
              bounceMode: _bounceMode,
              tempLimit: temp,
              tempUntil: until,
            ),
          );
      if (!mounted) return;
      ref.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.creditSaved)));
      navigator.pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = error is PermissionDenied ? error.reason : '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final mayEdit = services.credit.mayChange;
    final shop =
        ref.watch(creditDefaultsProvider).valueOrNull ??
        CreditDefaults.standard;
    final today = BusinessDate.now(services.clock);
    final standing = _standing;

    String shopSays(CreditMode mode, [int? figure]) =>
        '${s.creditModeShop}: ${figure == null ? '' : '$figure, '}'
        '${creditModeName(s, mode)}';

    Widget modes<T>(T value, List<(T, String)> options, ValueChanged<T> on) =>
        Wrap(
          spacing: BlTokens.space2,
          runSpacing: BlTokens.space2,
          children: [
            for (final (v, label) in options)
              ChoiceChip(
                selected: value == v,
                label: Text(label),
                onSelected: mayEdit ? (_) => setState(() => on(v)) : null,
              ),
          ],
        );

    final warnBlock = [
      (CreditMode.warn, s.creditModeWarn),
      (CreditMode.block, s.creditModeBlock),
    ];

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(
        top: BlTokens.space4,
        bottom: BlTokens.space2,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: t.ink,
        ),
      ),
    );

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.creditRulesHeader)),
      body: SafeArea(
        child: !_loaded
            ? const BlSkeletonList(rows: 4)
            : SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  BlTokens.space4,
                  BlTokens.space3,
                  BlTokens.space4,
                  MediaQuery.viewInsetsOf(context).bottom + BlTokens.space6,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.party.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                    if (standing != null)
                      Text(
                        standing.openBills == 0
                            ? s.partyCreditClear
                            : s.partyCreditStanding(
                                standing.balance.amountOnly,
                                standing.openBills,
                                daysBetween(
                                  standing.oldestOpenBill!.value,
                                  today.value,
                                ),
                              ),
                        style: TextStyle(fontSize: 13, color: t.inkMuted),
                      ),
                    const SizedBox(height: BlTokens.space2),
                    Text(
                      s.creditRulesIntro,
                      style: TextStyle(fontSize: 12, color: t.inkFaint),
                    ),
                    if (!mayEdit) ...[
                      const SizedBox(height: BlTokens.space3),
                      BlOfflineNote(message: s.creditOwnerOnly),
                    ],

                    heading(s.creditLimitRule),
                    modes<CreditMode?>(_limitMode, [
                      (null, shopSays(shop.limitMode)),
                      ...warnBlock,
                      (CreditMode.off, s.creditModeOff),
                    ], (v) => _limitMode = v),

                    heading(s.creditBillsRule),
                    modes<_Pick>(_billsPick, [
                      (
                        _Pick.shop,
                        shop.maxOpenBills == null
                            ? '${s.creditModeShop}: ${s.creditModeOff}'
                            : shopSays(shop.billsMode, shop.maxOpenBills),
                      ),
                      (_Pick.own, s.partyCreditOwn),
                      (_Pick.none, s.partyCreditNoRule),
                    ], (v) => _billsPick = v),
                    if (_billsPick == _Pick.own) ...[
                      const SizedBox(height: BlTokens.space2),
                      BlField(
                        controller: _bills,
                        label: s.creditBillsRule,
                        numeric: true,
                        decimals: 0,
                        enabled: mayEdit,
                      ),
                      const SizedBox(height: BlTokens.space2),
                      modes(_billsMode, warnBlock, (v) => _billsMode = v),
                    ],

                    heading(s.creditDaysRule),
                    modes<_Pick>(_daysPick, [
                      (
                        _Pick.shop,
                        shop.maxDays == null
                            ? '${s.creditModeShop}: ${s.creditModeOff}'
                            : shopSays(shop.daysMode, shop.maxDays),
                      ),
                      (_Pick.own, s.partyCreditOwn),
                      (_Pick.none, s.partyCreditNoRule),
                    ], (v) => _daysPick = v),
                    if (_daysPick == _Pick.own) ...[
                      const SizedBox(height: BlTokens.space2),
                      BlField(
                        controller: _days,
                        label: s.creditDaysRule,
                        numeric: true,
                        decimals: 0,
                        enabled: mayEdit,
                      ),
                      const SizedBox(height: BlTokens.space2),
                      modes(_daysMode, warnBlock, (v) => _daysMode = v),
                    ],

                    heading(s.creditBounceRule),
                    modes<CreditMode?>(_bounceMode, [
                      (null, shopSays(shop.bounceMode)),
                      ...warnBlock,
                      (CreditMode.off, s.creditModeOff),
                    ], (v) => _bounceMode = v),

                    heading(s.partyCreditTempHeader),
                    Text(
                      s.partyCreditTempHint,
                      style: TextStyle(fontSize: 12, color: t.inkMuted),
                    ),
                    const SizedBox(height: BlTokens.space2),
                    BlField(
                      controller: _temp,
                      label: s.partyCreditTempAmount,
                      numeric: true,
                      enabled: mayEdit,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: BlTokens.space2),
                    Wrap(
                      spacing: BlTokens.space2,
                      runSpacing: BlTokens.space2,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.event_outlined, size: 16),
                          label: Text(
                            _tempUntil == null
                                ? s.partyCreditTempNone
                                : s.partyCreditTempPick(
                                    shortDate(_tempUntil!.value),
                                  ),
                          ),
                          onPressed: mayEdit
                              ? () => unawaited(_pickUntil())
                              : null,
                        ),
                        if (_temp.text.isNotEmpty || _tempUntil != null)
                          ActionChip(
                            label: Text(s.partyCreditTempClear),
                            onPressed: mayEdit
                                ? () => setState(() {
                                    _temp.clear();
                                    _tempUntil = null;
                                  })
                                : null,
                          ),
                      ],
                    ),
                    if (_tempUntil case final until?
                        when today.value.compareTo(until.value) > 0 &&
                            _temp.text.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: BlTokens.space2),
                        child: Text(
                          s.partyCreditTempLapsed(
                            _temp.text,
                            shortDate(until.value),
                          ),
                          style: TextStyle(fontSize: 12, color: t.warning),
                        ),
                      ),
                    if (_failure != null) ...[
                      const SizedBox(height: BlTokens.space3),
                      Text(
                        _failure!,
                        style: TextStyle(fontSize: 13, color: t.danger),
                      ),
                    ],
                    if (mayEdit) ...[
                      const SizedBox(height: BlTokens.space4),
                      BlButton(
                        label: s.actionSave,
                        icon: Icons.check,
                        busy: _busy,
                        onPressed: _busy ? null : () => unawaited(_save()),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}
