import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../khata/entry_actions.dart' show EntryNote;
import 'shop_money_providers.dart';

/// The heads money goes out and comes in under (M47): added, renamed,
/// hidden, and a spending head filed above or below the gross profit line.
///
/// A spending head is an account of the chart, so renaming one renames it
/// in every report, and filing it as a cost of the goods moves it above the
/// gross profit line in every month's profit and loss. Hiding one only
/// stops it being offered: what was spent under it stays where it is. An
/// income head is a name on the shop's one Other Income account (see
/// `shop_money/heads.dart` for why).
///
/// For the owner and the accountant, who may change the chart.
class HeadsScreen extends ConsumerWidget {
  const HeadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final expense = ref.watch(expenseHeadsProvider).valueOrNull ?? const [];
    final income = ref.watch(incomeHeadsProvider).valueOrNull ?? const [];

    Widget tile({
      required String label,
      required List<Widget> chips,
      required VoidCallback onTap,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space1),
      child: BlCard(
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: TextStyle(fontSize: 15, color: t.ink)),
            ),
            ...chips,
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.headsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            BlTokens.space4,
            BlTokens.space3,
            BlTokens.space4,
            BlTokens.space10,
          ),
          children: [
            BlSectionHeader(
              s.headsExpense,
              trailing: BlIconButton(
                icon: Icons.add,
                label: s.headsAddExpense,
                onPressed: () => unawaited(_editExpenseHead(context, ref)),
              ),
            ),
            const SizedBox(height: BlTokens.space2),
            for (final h in expense)
              tile(
                label: expenseHeadName(s, h),
                chips: [
                  if (h.hidden) ...[
                    BlChip(s.headHidden, icon: Icons.visibility_off_outlined),
                    const SizedBox(width: BlTokens.space1),
                  ],
                  BlChip(h.isDirect ? s.headDirectChip : s.headIndirectChip),
                ],
                onTap: () => unawaited(_editExpenseHead(context, ref, head: h)),
              ),
            const SizedBox(height: BlTokens.space5),
            BlSectionHeader(
              s.headsIncome,
              trailing: BlIconButton(
                icon: Icons.add,
                label: s.headsAddIncome,
                onPressed: () => unawaited(_editIncomeHead(context, ref)),
              ),
            ),
            const SizedBox(height: BlTokens.space2),
            for (final h in income)
              tile(
                label: incomeHeadName(s, h),
                chips: [
                  if (h.hidden)
                    BlChip(s.headHidden, icon: Icons.visibility_off_outlined),
                ],
                onTap: () => unawaited(_editIncomeHead(context, ref, head: h)),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> _editExpenseHead(
  BuildContext context,
  WidgetRef ref, {
  ExpenseHead? head,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _HeadSheet(expense: head, isExpense: true),
);

Future<void> _editIncomeHead(
  BuildContext context,
  WidgetRef ref, {
  IncomeHead? head,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _HeadSheet(income: head, isExpense: false),
);

/// One head, new or kept: its name, and for a spending head whether it is
/// a cost of the goods; and whether it is offered.
class _HeadSheet extends ConsumerStatefulWidget {
  const _HeadSheet({required this.isExpense, this.expense, this.income});

  final bool isExpense;
  final ExpenseHead? expense;
  final IncomeHead? income;

  @override
  ConsumerState<_HeadSheet> createState() => _HeadSheetState();
}

class _HeadSheetState extends ConsumerState<_HeadSheet> {
  late final _name = TextEditingController();
  late bool _direct = widget.expense?.isDirect ?? false;
  late bool _hidden = widget.expense?.hidden ?? widget.income?.hidden ?? false;
  bool _busy = false;
  String? _failure;
  bool _named = false;

  bool get _isNew => widget.expense == null && widget.income == null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_named) return;
    _named = true;
    final s = AppStrings.of(context);
    _name.text = switch ((widget.expense, widget.income)) {
      (final ExpenseHead h, _) => expenseHeadName(s, h),
      (_, final IncomeHead h) => incomeHeadName(s, h),
      _ => '',
    };
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    setState(() {
      _busy = true;
      _failure = null;
    });
    final money = ref.read(appServicesProvider).shopMoney;
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final name = _name.text.trim();
    try {
      if (widget.isExpense) {
        final head = widget.expense;
        if (head == null) {
          final id = await money.addExpenseHead(name: name, isDirect: _direct);
          if (_hidden) await money.setExpenseHeadHidden(id, true);
        } else {
          // A shipped head keeps its own name until the shop types another.
          if (name != expenseHeadName(s, head)) {
            await money.renameExpenseHead(head.accountId, name);
          }
          if (_direct != head.isDirect) {
            await money.setExpenseHeadDirect(head.accountId, _direct);
          }
          if (_hidden != head.hidden) {
            await money.setExpenseHeadHidden(head.accountId, _hidden);
          }
        }
      } else {
        final head = widget.income;
        if (head == null) {
          final key = await money.addIncomeHead(name);
          if (_hidden) await money.setIncomeHeadHidden(key, true);
        } else {
          if (name != incomeHeadName(s, head)) {
            await money.renameIncomeHead(head.key, name);
          }
          if (_hidden != head.hidden) {
            await money.setIncomeHeadHidden(head.key, _hidden);
          }
        }
      }
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.headSaved)));
      navigator.pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = switch (error) {
          HeadRefused(:final reason) => reason,
          PermissionDenied(:final reason) => reason,
          _ => '$error',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom:
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.viewPaddingOf(context).bottom +
            BlTokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isNew
                  ? (widget.isExpense ? s.headsAddExpense : s.headsAddIncome)
                  : (widget.isExpense ? s.headsExpense : s.headsIncome),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _name,
              label: s.headName,
              autofocus: _isNew,
              onChanged: (_) => setState(() => _failure = null),
            ),
            if (widget.isExpense) ...[
              const SizedBox(height: BlTokens.space2),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _direct,
                title: Text(s.headDirect),
                onChanged: (on) => setState(() => _direct = on),
              ),
              EntryNote(s.headDirectExplain),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _hidden,
              title: Text(s.headHide),
              onChanged: (on) => setState(() => _hidden = on),
            ),
            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space2),
              Text(_failure!, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
            const SizedBox(height: BlTokens.space3),
            BlButton(
              label: s.headSave,
              icon: Icons.check,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_save()),
            ),
          ],
        ),
      ),
    );
  }
}
