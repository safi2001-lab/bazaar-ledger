import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../khata/entry_actions.dart';
import '../parties/party_picker.dart';
import 'home_goods_screen.dart';
import 'shop_money_providers.dart';

/// Writing down rent, bijli, or the boy who carries sacks.
///
/// `RecordExpenseUseCase` has posted to the right heads since it was written,
/// and nothing in `lib/` called it. A writer with no button is the failure
/// this repository keeps finding in itself — the printer and the costing
/// engine both shipped that way first — so this screen is the half of the
/// feature a shopkeeper can actually touch.
///
/// ## The head is a choice, never typed
///
/// Free text produces "Bijli", "bijli", "Electricity" and "Light bill" as four
/// lines that add up to nothing anybody can read. The chips are the shop's
/// heads: the shipped [expenseHeads] and, since M47, the heads the shop added
/// itself under Heads, each an account of the chart, so the screen cannot
/// offer a head the books would reject. A head the shop hid is not offered.
///
/// ## The note is required, and says so before Save
///
/// "Misc — Rs 4,000" six months later is a number nobody can defend. The
/// builder refuses it too; checking here as well means the shopkeeper is told
/// which field is empty in their own language rather than shown an exception.
///
/// ## The shop's or the home's (M47)
///
/// The first choice on the screen, for the owner and the accountant: is this
/// the shop's spending or the home's? Ghar ka kharcha is posted to the
/// owner's drawings and never reaches the profit and loss; it is paid now,
/// never left owed to a supplier, and has no head. A manager or anyone else
/// keeping the expense book is not offered it, and the service refuses it
/// anyway.
///
/// ## A monthly bill (M47)
///
/// Handed a [bill] — "Pay now" on a due card — the screen opens filled in
/// from it, and the expense it saves carries the bill's tag, which is how
/// the card knows this month is paid. A new expense can be kept as a monthly
/// bill from here too, with the day it falls due.
///
/// ## Correcting one (M31)
///
/// Handed [editing], the same screen corrects an expense already saved:
/// filled in with it, and saved as one act that cancels it and writes the
/// corrected one. [facts] says whose money it was and which head and bill
/// it carried. It pops `true` when something was saved.
class ExpenseScreen extends ConsumerStatefulWidget {
  const ExpenseScreen({super.key, this.editing, this.facts, this.bill});

  final EntryDocument? editing;
  final ExpenseFacts? facts;
  final MonthlyBill? bill;

  @override
  ConsumerState<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends ConsumerState<ExpenseScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _remindDay = TextEditingController();
  final _reason = ReasonController();

  String _head = 'rent';
  bool _forHome = false;
  bool _paidNow = true;
  bool _remind = false;
  String? _tag;
  String? _accountId;
  PartySummary? _payee;
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    final bill = widget.bill;
    if (editing != null) {
      // The expense being corrected, as it was saved.
      final facts = widget.facts;
      final head = facts?.headKey ?? editing.head;
      _head = head != null && isExpenseHeadKey(head) ? head : 'misc';
      _forHome = facts?.forHome ?? false;
      _tag = facts?.tag;
      _amount.text = editing.total.amountOnly.replaceAll(',', '');
      _note.text = editing.note;
      _paidNow = editing.partyId == null;
      _accountId = editing.paidFromAccountId;
      if (editing.partyId case final partyId?) {
        _payee = PartySummary(
          id: partyId,
          name: editing.partyName ?? '',
          partyType: 'supplier',
          balance: Money.zero,
        );
      }
    } else if (bill != null) {
      // Pay now, from a monthly bill's card: what it usually comes to, to be
      // changed if this month's bill says otherwise.
      _forHome = bill.forHome;
      if (!bill.forHome && isExpenseHeadKey(bill.headKey)) _head = bill.headKey;
      _amount.text = bill.amount.amountOnly.replaceAll(',', '');
      _note.text = bill.note;
      _accountId = bill.paymentAccountId;
      _tag = bill.tag;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _remindDay.dispose();
    _reason.dispose();
    super.dispose();
  }

  Money get _entered {
    final raw = _amount.text.trim().replaceAll(',', '');
    if (raw.isEmpty) return Money.zero;
    return Money.tryParse(raw) ?? Money.zero;
  }

  /// Kept as a monthly bill from here only when it is new, and not already
  /// paying one.
  bool get _canRemind => widget.editing == null && widget.bill == null;

  Future<void> _pickPayee() async {
    final party = await showModalBottomSheet<PartySummary?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const PartyPicker(),
    );
    if (party != null && mounted) {
      setState(() {
        _payee = party;
        _failure = null;
      });
    }
  }

  Future<void> _save(String? accountId) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    // The home's spending is paid now, always.
    final paidNow = _forHome || _paidNow;

    if (!_entered.isPositive) {
      setState(() => _failure = s.wasooliAmountRequired);
      return;
    }
    if (_note.text.trim().isEmpty) {
      setState(() => _failure = s.expenseNoteRequired);
      return;
    }
    if (paidNow && accountId == null) {
      setState(() => _failure = s.tenderNoAccount);
      return;
    }
    if (!paidNow && _payee == null) {
      // Money the shop can never settle, sitting in a total it can never
      // explain. The builder refuses this too; it is caught here so the
      // shopkeeper is pointed at the field rather than shown a sentence
      // about the books.
      setState(() => _failure = s.expensePayeeRequired);
      return;
    }
    int? remindOn;
    if (_canRemind && _remind) {
      remindOn = int.tryParse(_remindDay.text.trim());
      if (remindOn == null || remindOn < 1 || remindOn > 31) {
        setState(() => _failure = s.expenseRemindDayInvalid);
        return;
      }
    }

    setState(() {
      _busy = true;
      _failure = null;
    });

    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final draft = ExpenseDraft(
        accountSystemKey: _forHome ? ownerDrawingsKey : _head,
        amount: _entered,
        note: _note.text.trim(),
        paymentAccountId: paidNow ? accountId : null,
        partyId: paidNow ? null : _payee!.id,
        forHome: _forHome,
        tag: _tag,
      );
      final editing = widget.editing;
      final String said;
      if (editing == null) {
        final recorded = await services.shopMoney.recordExpense(
          draft,
          remindOnDay: remindOn,
        );
        said = s.expenseSaved(recorded.docNo);
      } else {
        // One act: the old expense cancelled and the corrected one written,
        // or neither.
        final corrected = await services.corrections.editExpense(
          services.actorNow(),
          documentId: editing.id,
          draft: draft,
          reason: editReason(s, _reason),
        );
        said = s.entryEditSaved(corrected.cancelledNo, corrected.no);
      }
      container.bumpRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(said)));
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = switch (error) {
          PermissionDenied(:final reason) => reason,
          _ => '$error',
        };
      });
    }
  }

  Future<void> _takeGoodsHome() async {
    final navigator = Navigator.of(context);
    final saved = await navigator.push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const HomeGoodsScreen()),
    );
    // The goods were the entry; there is no money to write as well.
    if ((saved ?? false) && mounted) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final accounts = ref.watch(paymentAccountsProvider);
    final editing = widget.editing;
    final canHome = services.shopMoney.canSpendForHome;

    // The shop's heads, the one already chosen kept even if it is hidden.
    // Until they arrive, the shipped heads, so the screen is never empty.
    final heads = ref.watch(expenseHeadsProvider).valueOrNull;
    final offered = <(String, String)>[
      if (heads == null)
        for (final key in expenseHeads) (key, expenseHeadLabel(s, key))
      else
        for (final h in heads)
          if (!h.hidden || h.key == _head) (h.key, expenseHeadName(s, h)),
    ];

    // Resolved for this build rather than stored, for the same reason as the
    // receipt sheet: the accounts arrive asynchronously, and a null here is a
    // Save that fails at the last step.
    //
    // Never the cheque account. It posts to Cheques in Hand, which is paper
    // customers gave the shop; paying rent from it is endorsing somebody's
    // cheque over, and a cheque the shop writes itself is a post-dated
    // liability. Both are the M6 lifecycle's to record, not this screen's.
    final available = [
      for (final a in accounts.valueOrNull ?? const <PaymentAccountSummary>[])
        if (a.modeLabel != 'cheque') a,
    ];
    final picked = available.where((a) => a.id == _accountId).firstOrNull;
    final accountId =
        picked?.id ??
        (available.isEmpty
            ? null
            : available
                  .firstWhere((a) => a.isDefault, orElse: () => available.first)
                  .id);
    final paidNow = _forHome || _paidNow;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(
          editing == null ? s.expenseNew : s.entryEditTitle(editing.docNo),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  BlTokens.space4,
                  BlTokens.space3,
                  BlTokens.space4,
                  MediaQuery.viewInsetsOf(context).bottom + BlTokens.space5,
                ),
                children: [
                  if (editing != null) ...[
                    EntryNote(s.entryEditExplain),
                    const SizedBox(height: BlTokens.space3),
                  ],
                  if (canHome) ...[
                    BlSectionHeader(s.expenseWhose),
                    const SizedBox(height: BlTokens.space2),
                    Wrap(
                      spacing: BlTokens.space2,
                      runSpacing: BlTokens.space2,
                      children: [
                        ChoiceChip(
                          selected: !_forHome,
                          avatar: const Icon(Icons.storefront, size: 18),
                          label: Text(s.expenseForShop),
                          onSelected: (_) => setState(() {
                            _forHome = false;
                            _failure = null;
                          }),
                        ),
                        ChoiceChip(
                          selected: _forHome,
                          avatar: const Icon(Icons.home_outlined, size: 18),
                          label: Text(s.expenseForHome),
                          onSelected: (_) => setState(() {
                            _forHome = true;
                            _failure = null;
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: BlTokens.space4),
                  ],
                  if (_forHome) ...[
                    EntryNote(s.expenseHomeExplain),
                    if (_canRemind) ...[
                      const SizedBox(height: BlTokens.space2),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: Text(s.expenseHomeGoodsLink),
                          onPressed: () => unawaited(_takeGoodsHome()),
                        ),
                      ),
                    ],
                    const SizedBox(height: BlTokens.space3),
                  ] else ...[
                    BlSectionHeader(s.expenseHead),
                    const SizedBox(height: BlTokens.space2),
                    Wrap(
                      spacing: BlTokens.space2,
                      runSpacing: BlTokens.space2,
                      children: [
                        for (final (key, label) in offered)
                          ChoiceChip(
                            selected: _head == key,
                            label: Text(label),
                            onSelected: (_) => setState(() {
                              _head = key;
                              _failure = null;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: BlTokens.space4),
                  ],
                  BlField(
                    controller: _amount,
                    label: s.expenseAmount,
                    numeric: true,
                    onChanged: (_) => setState(() => _failure = null),
                  ),
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _note,
                    label: s.expenseNote,
                    onChanged: (_) => setState(() => _failure = null),
                  ),
                  const SizedBox(height: BlTokens.space4),
                  if (!_forHome) ...[
                    Wrap(
                      spacing: BlTokens.space2,
                      runSpacing: BlTokens.space2,
                      children: [
                        ChoiceChip(
                          selected: _paidNow,
                          avatar: const Icon(Icons.payments_outlined, size: 18),
                          label: Text(s.expensePaidNow),
                          onSelected: (_) => setState(() {
                            _paidNow = true;
                            _failure = null;
                          }),
                        ),
                        ChoiceChip(
                          selected: !_paidNow,
                          avatar: const Icon(Icons.schedule, size: 18),
                          label: Text(s.expensePayLater),
                          onSelected: (_) => setState(() {
                            _paidNow = false;
                            _failure = null;
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: BlTokens.space3),
                  ],
                  if (paidNow && available.length > 1) ...[
                    Text(
                      s.expensePaidFrom,
                      style: TextStyle(fontSize: 13, color: t.inkMuted),
                    ),
                    const SizedBox(height: BlTokens.space2),
                    Wrap(
                      spacing: BlTokens.space2,
                      runSpacing: BlTokens.space2,
                      children: [
                        for (final account in available)
                          ChoiceChip(
                            selected: account.id == accountId,
                            label: Text(account.name),
                            onSelected: (_) =>
                                setState(() => _accountId = account.id),
                          ),
                      ],
                    ),
                  ],
                  if (!paidNow)
                    BlCard(
                      onTap: () => unawaited(_pickPayee()),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 20,
                            color: t.inkMuted,
                          ),
                          const SizedBox(width: BlTokens.space3),
                          Expanded(
                            child: Text(
                              _payee?.name ?? s.expensePayee,
                              style: TextStyle(
                                fontSize: 15,
                                color: _payee == null ? t.inkMuted : t.ink,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: t.inkFaint,
                          ),
                        ],
                      ),
                    ),
                  if (_canRemind) ...[
                    const SizedBox(height: BlTokens.space3),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _remind,
                      title: Text(s.expenseRemind),
                      onChanged: (on) => setState(() {
                        _remind = on;
                        _failure = null;
                        if (on && _remindDay.text.isEmpty) {
                          _remindDay.text =
                              '${BusinessDate.now(services.clock).day}';
                        }
                      }),
                    ),
                    if (_remind)
                      BlField(
                        controller: _remindDay,
                        label: s.expenseRemindDay,
                        numeric: true,
                        decimals: 0,
                        onChanged: (_) => setState(() => _failure = null),
                      ),
                  ],
                  if (editing != null) ...[
                    const SizedBox(height: BlTokens.space4),
                    ReasonPicker(reason: _reason),
                  ],
                ],
              ),
            ),
            // Pinned, the same as the purchase screen's: whatever the
            // keyboard squeezes out, Save stays reachable.
            Container(
              width: double.infinity,
              color: t.surface,
              padding: EdgeInsets.only(
                left: BlTokens.space4,
                right: BlTokens.space4,
                top: BlTokens.space3,
                bottom:
                    BlTokens.space3 +
                    (MediaQuery.viewInsetsOf(context).bottom > 0
                        ? 0
                        : MediaQuery.viewPaddingOf(context).bottom),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_failure != null) ...[
                    Text(
                      _failure!,
                      style: TextStyle(color: t.danger, fontSize: 14),
                    ),
                    const SizedBox(height: BlTokens.space2),
                  ],
                  BlButton(
                    label: editing == null ? s.expenseSave : s.entryEditSave,
                    icon: Icons.check,
                    big: true,
                    busy: _busy,
                    onPressed: _busy ? null : () => unawaited(_save(accountId)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a head is called on screen.
///
/// The key is what the books store; this is only ever display text, so
/// switching the app to English renames nothing that was posted.
String expenseHeadLabel(AppStrings s, String head) => switch (head) {
  'rent' => s.expenseHeadRent,
  'salaries' => s.expenseHeadSalaries,
  'utilities' => s.expenseHeadUtilities,
  'freight' => s.expenseHeadFreight,
  _ => s.expenseHeadMisc,
};
