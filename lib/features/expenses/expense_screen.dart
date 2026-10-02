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
/// lines that add up to nothing anybody can read. The chips are
/// [expenseHeads], the same closed list the builder refuses anything outside
/// of, so the screen cannot offer a head the books would reject.
///
/// ## The note is required, and says so before Save
///
/// "Misc — Rs 4,000" six months later is a number nobody can defend. The
/// builder refuses it too; checking here as well means the shopkeeper is told
/// which field is empty in their own language rather than shown an exception.
///
/// ## Correcting one (M31)
///
/// Handed [editing], the same screen corrects an expense already saved:
/// filled in with it, and saved as one act that cancels it and writes the
/// corrected one. It pops `true` when something was saved.
class ExpenseScreen extends ConsumerStatefulWidget {
  const ExpenseScreen({super.key, this.editing});

  final EntryDocument? editing;

  @override
  ConsumerState<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends ConsumerState<ExpenseScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _reason = ReasonController();

  String _head = 'rent';
  bool _paidNow = true;
  String? _accountId;
  PartySummary? _payee;
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    if (editing == null) return;
    // The expense being corrected, as it was saved.
    final head = editing.head;
    _head = head != null && expenseHeads.contains(head) ? head : 'misc';
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
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _reason.dispose();
    super.dispose();
  }

  Money get _entered {
    final raw = _amount.text.trim().replaceAll(',', '');
    if (raw.isEmpty) return Money.zero;
    return Money.tryParse(raw) ?? Money.zero;
  }

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

    if (!_entered.isPositive) {
      setState(() => _failure = s.wasooliAmountRequired);
      return;
    }
    if (_note.text.trim().isEmpty) {
      setState(() => _failure = s.expenseNoteRequired);
      return;
    }
    if (_paidNow && accountId == null) {
      setState(() => _failure = s.tenderNoAccount);
      return;
    }
    if (!_paidNow && _payee == null) {
      // Money the shop can never settle, sitting in a total it can never
      // explain. The builder refuses this too; it is caught here so the
      // shopkeeper is pointed at the field rather than shown a sentence
      // about the books.
      setState(() => _failure = s.expensePayeeRequired);
      return;
    }

    setState(() {
      _busy = true;
      _failure = null;
    });

    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final draft = ExpenseDraft(
        accountSystemKey: _head,
        amount: _entered,
        note: _note.text.trim(),
        paymentAccountId: _paidNow ? accountId : null,
        partyId: _paidNow ? null : _payee!.id,
      );
      final editing = widget.editing;
      final String said;
      if (editing == null) {
        final recorded = await services.recordExpense(
          services.actorNow(),
          draft,
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
        _failure = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final accounts = ref.watch(paymentAccountsProvider);
    final editing = widget.editing;

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
    final accountId =
        _accountId ??
        (available.isEmpty
            ? null
            : available
                  .firstWhere((a) => a.isDefault, orElse: () => available.first)
                  .id);

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
                  BlSectionHeader(s.expenseHead),
                  const SizedBox(height: BlTokens.space2),
                  Wrap(
                    spacing: BlTokens.space2,
                    runSpacing: BlTokens.space2,
                    children: [
                      for (final head in expenseHeads)
                        ChoiceChip(
                          selected: _head == head,
                          label: Text(expenseHeadLabel(s, head)),
                          onSelected: (_) => setState(() {
                            _head = head;
                            _failure = null;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: BlTokens.space4),
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
                  if (_paidNow && available.length > 1) ...[
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
                  if (!_paidNow)
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
