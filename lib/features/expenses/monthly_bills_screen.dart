import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../loans/loan_fields.dart' show MoneyAccountChips;
import 'expense_screen.dart';
import 'shop_money_providers.dart';

/// The bills that come every month (M47): rent on the 1st, bijli around
/// the 10th, wages on the 30th.
///
/// Each is a reminder, never a payment. On its day the Expenses screen shows
/// it as due with Pay now, which opens the expense filled in from it; the
/// money leaves the books only when the shopkeeper saves that.
class MonthlyBillsScreen extends ConsumerWidget {
  const MonthlyBillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final bills = ref.watch(monthlyBillsProvider);
    final heads = ref.watch(expenseHeadsProvider).valueOrNull ?? const [];

    String headOf(MonthlyBill bill) {
      if (bill.forHome) return s.expenseForHome;
      for (final h in heads) {
        if (h.key == bill.headKey) return expenseHeadName(s, h);
      }
      return expenseHeadLabel(s, bill.headKey);
    }

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.billsTitle)),
      body: SafeArea(
        child: bills.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 3),
          ),
          error: (error, _) =>
              BlError(title: s.commonSomethingWentWrong, message: '$error'),
          data: (rows) => rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(BlTokens.space4),
                  child: BlEmpty(
                    icon: Icons.event_repeat_outlined,
                    title: s.billsEmpty,
                    message: s.billsEmptyHint,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    BlTokens.space4,
                    BlTokens.space3,
                    BlTokens.space4,
                    BlTokens.space10 * 2,
                  ),
                  children: [
                    for (final bill in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: BlTokens.space2),
                        child: BlCard(
                          onTap: () => unawaited(
                            showMonthlyBillSheet(context, bill: bill),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      bill.note,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: t.ink,
                                      ),
                                    ),
                                    Text(
                                      '${headOf(bill)} · '
                                      '${s.billEvery('${bill.day}')}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: t.inkMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              BlMoney(bill.amount, size: 16),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(showMonthlyBillSheet(context)),
        icon: const Icon(Icons.add),
        label: Text(s.billsNew),
      ),
    );
  }
}

/// A monthly bill, new or kept, to save or stop.
Future<void> showMonthlyBillSheet(BuildContext context, {MonthlyBill? bill}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MonthlyBillSheet(bill: bill),
    );

class _MonthlyBillSheet extends ConsumerStatefulWidget {
  const _MonthlyBillSheet({this.bill});

  final MonthlyBill? bill;

  @override
  ConsumerState<_MonthlyBillSheet> createState() => _MonthlyBillSheetState();
}

class _MonthlyBillSheetState extends ConsumerState<_MonthlyBillSheet> {
  late final _note = TextEditingController(text: widget.bill?.note ?? '');
  late final _amount = TextEditingController(
    text: widget.bill?.amount.amountOnly.replaceAll(',', '') ?? '',
  );
  late final _day = TextEditingController(
    text: widget.bill == null ? '1' : '${widget.bill!.day}',
  );
  late String _head = widget.bill?.headKey ?? 'rent';
  late bool _forHome = widget.bill?.forHome ?? false;
  late String? _accountId = widget.bill?.paymentAccountId;
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _note.dispose();
    _amount.dispose();
    _day.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final amount = Money.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (amount == null || !amount.isPositive) {
      setState(() => _failure = s.wasooliAmountRequired);
      return;
    }
    final day = int.tryParse(_day.text.trim());
    if (day == null || day < 1 || day > 31) {
      setState(() => _failure = s.expenseRemindDayInvalid);
      return;
    }
    if (_note.text.trim().isEmpty) {
      setState(() => _failure = s.expenseNoteRequired);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await services.shopMoney.saveMonthlyBill(
        MonthlyBill(
          id: widget.bill?.id ?? services.shopMoney.newMonthlyBillId(),
          headKey: _forHome ? ownerDrawingsKey : _head,
          amount: amount,
          note: _note.text.trim(),
          day: day,
          forHome: _forHome,
          paymentAccountId: _accountId,
          skippedMonth: widget.bill?.skippedMonth,
        ),
      );
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.monthlyBillSaved)));
      navigator.pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = switch (error) {
          MonthlyBillRefused(:final reason) => reason,
          PermissionDenied(:final reason) => reason,
          HeadRefused(:final reason) => reason,
          _ => '$error',
        };
      });
    }
  }

  Future<void> _remove(MonthlyBill bill) async {
    final s = AppStrings.of(context);
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await services.shopMoney.removeMonthlyBill(bill);
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.billDeleted)));
      navigator.pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _failure = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final canHome = services.shopMoney.canSpendForHome;
    final heads = ref.watch(expenseHeadsProvider).valueOrNull;
    final bill = widget.bill;
    final offered = <(String, String)>[
      if (heads == null)
        for (final key in expenseHeads) (key, expenseHeadLabel(s, key))
      else
        for (final h in heads)
          if (!h.hidden || h.key == _head) (h.key, expenseHeadName(s, h)),
    ];

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
              bill?.note ?? s.billsNew,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            const SizedBox(height: BlTokens.space3),
            if (canHome) ...[
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space2,
                children: [
                  ChoiceChip(
                    selected: !_forHome,
                    label: Text(s.expenseForShop),
                    onSelected: (_) => setState(() => _forHome = false),
                  ),
                  ChoiceChip(
                    selected: _forHome,
                    label: Text(s.expenseForHome),
                    onSelected: (_) => setState(() => _forHome = true),
                  ),
                ],
              ),
              const SizedBox(height: BlTokens.space3),
            ],
            if (!_forHome) ...[
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space2,
                children: [
                  for (final (key, label) in offered)
                    ChoiceChip(
                      selected: _head == key,
                      label: Text(label),
                      onSelected: (_) => setState(() => _head = key),
                    ),
                ],
              ),
              const SizedBox(height: BlTokens.space3),
            ],
            BlField(controller: _note, label: s.billName),
            const SizedBox(height: BlTokens.space3),
            BlField(controller: _amount, label: s.billAmount, numeric: true),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _day,
              label: s.expenseRemindDay,
              numeric: true,
              decimals: 0,
            ),
            const SizedBox(height: BlTokens.space3),
            MoneyAccountChips(
              label: s.billPaidFrom,
              selectedId: _accountId,
              onSelected: (id) => setState(() => _accountId = id),
            ),
            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(_failure!, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.billSave,
              icon: Icons.check,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_save()),
            ),
            if (bill != null) ...[
              const SizedBox(height: BlTokens.space2),
              BlButton(
                label: s.billDelete,
                icon: Icons.notifications_off_outlined,
                kind: BlButtonKind.ghost,
                onPressed: () => unawaited(_remove(bill)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
