import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Settings → Credit, closing and counter control (M68): the shop's credit
/// rules, days that close by themselves, the random stock check and
/// cashier mode. Each section keeps its own Save, so changing one never
/// rewrites another, and each says when only the owner may change it.
class ControlSettingsScreen extends ConsumerWidget {
  const ControlSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.controlSettingsTitle)),
      body: SafeArea(
        // Every section built at once, not lazily: four short forms, and a
        // Save scrolled past must still be the one it was.
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            BlTokens.space4,
            BlTokens.space3,
            BlTokens.space4,
            MediaQuery.viewInsetsOf(context).bottom + BlTokens.space6,
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CreditDefaultsSection(),
              SizedBox(height: BlTokens.space6),
              _AutoLockSection(),
              SizedBox(height: BlTokens.space6),
              _StockCheckSection(),
              SizedBox(height: BlTokens.space6),
              _CashierModeSection(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Choice chips, one per option, the selected one marked.
Widget _choices<T>(
  T value,
  List<(T, String)> options,
  ValueChanged<T>? onPick,
) => Wrap(
  spacing: BlTokens.space2,
  runSpacing: BlTokens.space2,
  children: [
    for (final (v, label) in options)
      ChoiceChip(
        selected: value == v,
        label: Text(label),
        onSelected: onPick == null ? null : (_) => onPick(v),
      ),
  ],
);

/// A section's heading, its few words, and the owner-only note.
List<Widget> _head(
  BuildContext context,
  String title,
  String intro, {
  required bool mayEdit,
  required String ownerOnly,
}) {
  final t = context.bl;
  return [
    BlSectionHeader(title),
    const SizedBox(height: BlTokens.space2),
    Text(intro, style: TextStyle(fontSize: 13, color: t.inkMuted)),
    if (!mayEdit) ...[
      const SizedBox(height: BlTokens.space2),
      BlOfflineNote(message: ownerOnly),
    ],
    const SizedBox(height: BlTokens.space2),
  ];
}

Widget _label(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(top: BlTokens.space3, bottom: BlTokens.space2),
  child: Text(
    text,
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: context.bl.ink,
    ),
  ),
);

Widget _failureText(BuildContext context, String? failure) => failure == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: BlTokens.space2),
        child: Text(
          failure,
          style: TextStyle(fontSize: 13, color: context.bl.danger),
        ),
      );

String _plainError(Object error) =>
    error is PermissionDenied ? error.reason : '$error';

// ---------------------------------------------------------------------------
// Credit rules
// ---------------------------------------------------------------------------

class _CreditDefaultsSection extends ConsumerStatefulWidget {
  const _CreditDefaultsSection();

  @override
  ConsumerState<_CreditDefaultsSection> createState() =>
      _CreditDefaultsSectionState();
}

class _CreditDefaultsSectionState
    extends ConsumerState<_CreditDefaultsSection> {
  final _bills = TextEditingController();
  final _days = TextEditingController();
  CreditMode _limit = CreditMode.warn;
  CreditMode _billsMode = CreditMode.warn;
  CreditMode _daysMode = CreditMode.warn;
  CreditMode _bounce = CreditMode.warn;
  bool _loaded = false;
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final rules = await ref.read(appServicesProvider).credit.defaults();
    if (!mounted) return;
    setState(() {
      _limit = rules.limitMode;
      _bills.text = rules.maxOpenBills?.toString() ?? '';
      _billsMode = rules.billsMode;
      _days.text = rules.maxDays?.toString() ?? '';
      _daysMode = rules.daysMode;
      _bounce = rules.bounceMode;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _bills.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    int? whole(TextEditingController c) =>
        c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());
    final bills = whole(_bills);
    final days = whole(_days);
    if ((_bills.text.trim().isNotEmpty && bills == null) ||
        (_days.text.trim().isNotEmpty && days == null)) {
      setState(() => _failure = s.creditFiguresBad);
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
          .credit
          .setDefaults(
            CreditDefaults(
              limitMode: _limit,
              maxOpenBills: bills,
              billsMode: _billsMode,
              maxDays: days,
              daysMode: _daysMode,
              bounceMode: _bounce,
            ),
          );
      if (!mounted) return;
      ref.bumpRefresh();
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(s.creditSaved)));
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = _plainError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final mayEdit = ref.watch(appServicesProvider).credit.mayChange;
    final pick = mayEdit ? (void Function() f) => setState(f) : null;
    final warnBlock = [
      (CreditMode.warn, s.creditModeWarn),
      (CreditMode.block, s.creditModeBlock),
    ];
    if (!_loaded) return const BlSkeletonList(rows: 3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._head(
          context,
          s.creditRulesHeader,
          s.creditRulesIntro,
          mayEdit: mayEdit,
          ownerOnly: s.creditOwnerOnly,
        ),
        _label(context, s.creditLimitRule),
        _choices<CreditMode>(_limit, [
          ...warnBlock,
          (CreditMode.off, s.creditModeOff),
        ], pick == null ? null : (v) => pick(() => _limit = v)),
        _label(context, s.creditBillsRule),
        BlField(
          controller: _bills,
          label: s.creditBillsRule,
          hint: s.creditEmptyHint,
          numeric: true,
          decimals: 0,
          enabled: mayEdit,
        ),
        const SizedBox(height: BlTokens.space2),
        _choices<CreditMode>(
          _billsMode,
          warnBlock,
          pick == null ? null : (v) => pick(() => _billsMode = v),
        ),
        _label(context, s.creditDaysRule),
        BlField(
          controller: _days,
          label: s.creditDaysRule,
          hint: s.creditEmptyHint,
          numeric: true,
          decimals: 0,
          enabled: mayEdit,
        ),
        const SizedBox(height: BlTokens.space2),
        _choices<CreditMode>(
          _daysMode,
          warnBlock,
          pick == null ? null : (v) => pick(() => _daysMode = v),
        ),
        _label(context, s.creditBounceRule),
        _choices<CreditMode>(_bounce, [
          ...warnBlock,
          (CreditMode.off, s.creditModeOff),
        ], pick == null ? null : (v) => pick(() => _bounce = v)),
        _failureText(context, _failure),
        if (mayEdit) ...[
          const SizedBox(height: BlTokens.space3),
          BlButton(
            label: s.actionSave,
            icon: Icons.check,
            busy: _busy,
            onPressed: _busy ? null : () => unawaited(_save()),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Days that close by themselves
// ---------------------------------------------------------------------------

class _AutoLockSection extends ConsumerStatefulWidget {
  const _AutoLockSection();

  @override
  ConsumerState<_AutoLockSection> createState() => _AutoLockSectionState();
}

class _AutoLockSectionState extends ConsumerState<_AutoLockSection> {
  final _days = TextEditingController(text: '2');
  AutoLockMode _mode = AutoLockMode.off;
  BusinessDate? _closedThrough;
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
    final rule = await services.autoLock.rule();
    final locks = await services.audit.locks();
    if (!mounted) return;
    setState(() {
      _mode = rule.mode;
      _days.text = '${rule.days}';
      _closedThrough = locks.closedThrough;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final days = int.tryParse(_days.text.trim());
    if (_mode == AutoLockMode.olderThan && days == null) {
      setState(() => _failure = s.creditFiguresBad);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final services = ref.read(appServicesProvider);
      await services.autoLock.setRule(AutoLock(mode: _mode, days: days ?? 2));
      final locks = await services.audit.locks();
      if (!mounted) return;
      ref.bumpRefresh();
      setState(() {
        _busy = false;
        _closedThrough = locks.closedThrough;
      });
      messenger.showSnackBar(SnackBar(content: Text(s.autoLockSaved)));
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = _plainError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final mayEdit = ref.watch(appServicesProvider).audit.isOwner;
    if (!_loaded) return const BlSkeletonList(rows: 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._head(
          context,
          s.autoLockHeader,
          s.autoLockIntro,
          mayEdit: mayEdit,
          ownerOnly: s.creditOwnerOnly,
        ),
        _choices<AutoLockMode>(_mode, [
          (AutoLockMode.off, s.autoLockOff),
          (AutoLockMode.olderThan, s.autoLockOlder),
          (AutoLockMode.atDayClose, s.autoLockAtClose),
        ], mayEdit ? (v) => setState(() => _mode = v) : null),
        if (_mode == AutoLockMode.olderThan) ...[
          const SizedBox(height: BlTokens.space3),
          BlField(
            controller: _days,
            label: s.autoLockDays,
            numeric: true,
            decimals: 0,
            enabled: mayEdit,
          ),
        ],
        if (_closedThrough case final through?) ...[
          const SizedBox(height: BlTokens.space2),
          Text(
            s.autoLockNow(shortDate(through.value)),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: t.ink,
            ),
          ),
        ],
        _failureText(context, _failure),
        if (mayEdit) ...[
          const SizedBox(height: BlTokens.space3),
          BlButton(
            label: s.actionSave,
            icon: Icons.check,
            busy: _busy,
            onPressed: _busy ? null : () => unawaited(_save()),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The random stock check
// ---------------------------------------------------------------------------

class _StockCheckSection extends ConsumerStatefulWidget {
  const _StockCheckSection();

  @override
  ConsumerState<_StockCheckSection> createState() => _StockCheckSectionState();
}

class _StockCheckSectionState extends ConsumerState<_StockCheckSection> {
  final _size = TextEditingController(text: '5');
  bool _daily = false;
  bool _loaded = false;
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final rule = await ref.read(appServicesProvider).stockChecks.rule();
    if (!mounted) return;
    setState(() {
      _size.text = '${rule.size}';
      _daily = rule.daily;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _size.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final size = int.tryParse(_size.text.trim());
    if (size == null) {
      setState(() => _failure = s.creditFiguresBad);
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
          .stockChecks
          .setRule(StockCheckRule(size: size, daily: _daily));
      if (!mounted) return;
      ref.bumpRefresh();
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(s.creditSaved)));
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = _plainError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final mayEdit = ref.watch(appServicesProvider).can(Permission.settings);
    if (!_loaded) return const BlSkeletonList(rows: 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._head(
          context,
          s.stockCheckTitle,
          s.stockCheckIntro,
          mayEdit: mayEdit,
          ownerOnly: s.creditOwnerOnly,
        ),
        BlField(
          controller: _size,
          label: s.stockCheckSize,
          numeric: true,
          decimals: 0,
          enabled: mayEdit,
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _daily,
          title: Text(s.stockCheckDaily),
          onChanged: mayEdit ? (v) => setState(() => _daily = v) : null,
        ),
        _failureText(context, _failure),
        if (mayEdit) ...[
          const SizedBox(height: BlTokens.space2),
          BlButton(
            label: s.actionSave,
            icon: Icons.check,
            busy: _busy,
            onPressed: _busy ? null : () => unawaited(_save()),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Cashier mode
// ---------------------------------------------------------------------------

class _CashierModeSection extends ConsumerStatefulWidget {
  const _CashierModeSection();

  @override
  ConsumerState<_CashierModeSection> createState() =>
      _CashierModeSectionState();
}

class _CashierModeSectionState extends ConsumerState<_CashierModeSection> {
  bool _on = false;
  Set<String> _salesmen = {};
  List<StaffMember> _staff = const [];
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
    final mode = await services.cashier.mode();
    final firm = services.identity?.firmId;
    final staff = firm == null
        ? const <StaffMember>[]
        : await services.staffStore.staff(firm);
    if (!mounted) return;
    setState(() {
      _on = mode.on;
      _salesmen = {...mode.salesmen};
      _staff = [
        for (final m in staff)
          if (m.isActive && m.role != Role.owner) m,
      ];
      _loaded = true;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() {
      _busy = true;
      _failure = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appServicesProvider)
          .cashier
          .setMode(CashierMode(on: _on, salesmen: _salesmen));
      if (!mounted) return;
      ref.bumpRefresh();
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(s.cashierModeSaved)));
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = _plainError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final mayEdit = ref.watch(appServicesProvider).can(Permission.settings);
    if (!_loaded) return const BlSkeletonList(rows: 2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._head(
          context,
          s.cashierModeHeader,
          s.cashierModeIntro,
          mayEdit: mayEdit,
          ownerOnly: s.creditOwnerOnly,
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _on,
          title: Text(s.cashierModeOn),
          onChanged: mayEdit ? (v) => setState(() => _on = v) : null,
        ),
        if (_on) ...[
          _label(context, s.cashierModeSalesmen),
          if (_staff.isEmpty)
            Text(
              s.cashierModeNoStaff,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            )
          else
            for (final m in _staff)
              CheckboxListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _salesmen.contains(m.id),
                title: Text(m.name),
                onChanged: mayEdit
                    ? (v) => setState(
                        () => v ?? false
                            ? _salesmen.add(m.id)
                            : _salesmen.remove(m.id),
                      )
                    : null,
              ),
        ],
        _failureText(context, _failure),
        if (mayEdit) ...[
          const SizedBox(height: BlTokens.space3),
          BlButton(
            label: s.actionSave,
            icon: Icons.check,
            busy: _busy,
            onPressed: _busy ? null : () => unawaited(_save()),
          ),
        ],
      ],
    );
  }
}
