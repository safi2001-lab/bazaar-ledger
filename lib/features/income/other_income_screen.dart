import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../expenses/shop_money_providers.dart';
import '../khata/entry_actions.dart';
import '../loans/loan_fields.dart' show LoanDateField, MoneyAccountChips;
import '../parties/party_picker.dart';

/// Writing down money the shop earned that is not a sale (M47).
///
/// Under which head, how much, into the drawer or the bank, on which day,
/// and — when the shopkeeper says — from whom and what it was. The head is a
/// choice, as an expense's is; who paid is a name, picked from the khata or
/// typed, and only a name: rent from the tailor upstairs is not something
/// he owes, and a party on it would put it on his khata as a charge.
///
/// Handed [editing], the same screen corrects an entry already saved, as
/// M31's screens do: filled in with it, and saved as one act that cancels
/// it and writes the corrected one. It pops `true` when something was
/// saved.
class OtherIncomeScreen extends ConsumerStatefulWidget {
  const OtherIncomeScreen({super.key, this.editing});

  final OtherIncomeDetail? editing;

  @override
  ConsumerState<OtherIncomeScreen> createState() => _OtherIncomeScreenState();
}

class _OtherIncomeScreenState extends ConsumerState<OtherIncomeScreen> {
  final _amount = TextEditingController();
  final _from = TextEditingController();
  final _note = TextEditingController();
  final _reason = ReasonController();

  String _head = 'rent_received';
  String? _into;
  BusinessDate? _date;
  bool _busy = false;
  String? _failure;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    if (editing == null) return;
    _head = editing.headKey;
    _amount.text = editing.amount.amountOnly.replaceAll(',', '');
    _from.text = editing.fromName ?? '';
    _note.text = editing.note;
    _into = editing.paymentAccountId;
    _date = BusinessDate(editing.dateLocal);
  }

  @override
  void dispose() {
    _amount.dispose();
    _from.dispose();
    _note.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickFrom() async {
    final party = await showModalBottomSheet<PartySummary?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const PartyPicker(),
    );
    if (party != null && mounted) {
      setState(() {
        _from.text = party.name;
        _failure = null;
      });
    }
  }

  Future<void> _save(String? into, BusinessDate date) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final amount = Money.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (amount == null || !amount.isPositive) {
      setState(() => _failure = s.wasooliAmountRequired);
      return;
    }
    if (into == null) {
      setState(() => _failure = s.tenderNoAccount);
      return;
    }
    setState(() {
      _busy = true;
      _failure = null;
    });
    final money = ref.read(appServicesProvider).shopMoney;
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final draft = OtherIncomeDraft(
      headKey: _head,
      amount: amount,
      paymentAccountId: into,
      receivedOn: date,
      note: _note.text,
      fromName: _from.text,
    );
    try {
      final editing = widget.editing;
      final String said;
      if (editing == null) {
        said = s.incomeSaved((await money.recordOtherIncome(draft)).docNo);
      } else {
        final corrected = await money.editOtherIncome(
          documentId: editing.id,
          draft: draft,
          reason: editReason(s, _reason),
        );
        said = s.entryEditSaved(corrected.cancelledNo, corrected.no);
      }
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(said)));
      navigator.pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = switch (error) {
          OtherIncomeRefused(:final reason) => reason,
          VoidRefused(:final reason) => reason,
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
    final services = ref.watch(appServicesProvider);
    final editing = widget.editing;
    final today = BusinessDate.now(services.clock);
    final date = _date ?? today;
    final (_, into) = MoneyAccountChips.resolve(
      ref.watch(paymentAccountsProvider).valueOrNull ?? const [],
      _into,
    );
    final heads = ref.watch(incomeHeadsProvider).valueOrNull;
    final offered = <(String, String)>[
      if (heads == null)
        for (final key in shippedIncomeHeads) (key, shippedIncomeLabel(s, key))
      else
        for (final h in heads)
          if (!h.hidden || h.key == _head) (h.key, incomeHeadName(s, h)),
    ];

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(
          editing == null ? s.incomeNew : s.entryEditTitle(editing.docNo),
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
                  EntryNote(
                    editing == null ? s.incomeNotASale : s.entryEditExplain,
                  ),
                  const SizedBox(height: BlTokens.space3),
                  BlSectionHeader(s.incomeHead),
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
                  BlField(
                    controller: _amount,
                    label: s.expenseAmount,
                    numeric: true,
                    onChanged: (_) => setState(() => _failure = null),
                  ),
                  const SizedBox(height: BlTokens.space3),
                  MoneyAccountChips(
                    label: s.incomeInto,
                    selectedId: into,
                    onSelected: (id) => setState(() => _into = id),
                  ),
                  const SizedBox(height: BlTokens.space3),
                  LoanDateField(
                    date: date,
                    today: today,
                    onChanged: (d) => setState(() => _date = d),
                  ),
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _from,
                    label: s.incomeFrom,
                    suffix: BlIconButton(
                      icon: Icons.person_search_outlined,
                      label: s.incomeFromParty,
                      onPressed: () => unawaited(_pickFrom()),
                    ),
                  ),
                  const SizedBox(height: BlTokens.space3),
                  BlField(
                    controller: _note,
                    label: s.incomeNote,
                    onChanged: (_) => setState(() => _failure = null),
                  ),
                  if (editing != null) ...[
                    const SizedBox(height: BlTokens.space4),
                    ReasonPicker(reason: _reason),
                  ],
                ],
              ),
            ),
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
                    label: editing == null ? s.incomeSave : s.entryEditSave,
                    icon: Icons.check,
                    big: true,
                    busy: _busy,
                    onPressed: _busy
                        ? null
                        : () => unawaited(_save(into, date)),
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
