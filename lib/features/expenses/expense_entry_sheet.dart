import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../audit/history_screen.dart';
import '../khata/entry_actions.dart';
import '../khata/khata_providers.dart';
import 'expense_screen.dart';
import 'shop_money_providers.dart';

/// One expense, opened from the list (M31).
///
/// A month's rent entered twice, bijli typed as Rs 40,000 for Rs 4,000:
/// until M31 an expense, once saved, was a line in a list that did nothing
/// when tapped. Here it can be read whole, corrected, or cancelled — each
/// the append-only way, with a reversing entry and the original kept.
///
/// One left on account to a supplier who has since been paid against it is
/// not offered either: the payment would be left settling an expense that
/// no longer stands, so the page names the payment to cancel first.
///
/// Since M47 the page says whose money it was. The home's spending is the
/// owner's or the accountant's to change, and the page offers nothing to
/// anyone else; goods taken home are cancelled, never edited (the shelf
/// and the cost both come back with the cancel, and the goods are entered
/// again from the shelf).
Future<void> showExpenseEntrySheet(
  BuildContext context, {
  required String documentId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _ExpenseEntrySheet(documentId: documentId),
);

class _ExpenseEntrySheet extends ConsumerWidget {
  const _ExpenseEntrySheet({required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final entry = ref.watch(entryDocumentProvider(documentId));
    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewPaddingOf(context).bottom + BlTokens.space4,
      ),
      child: entry.when(
        loading: () => const BlSkeletonList(rows: 4),
        error: (error, _) =>
            BlError(title: s.commonSomethingWentWrong, message: '$error'),
        data: (expense) => expense == null
            ? BlEmpty(title: s.commonNothingSaved)
            : _Body(expense: expense),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.expense});

  final EntryDocument expense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final accounts =
        ref.watch(paymentAccountsProvider).valueOrNull ??
        const <PaymentAccountSummary>[];
    final paidFrom = accounts
        .where((a) => a.id == expense.paidFromAccountId)
        .firstOrNull;
    final standing = !expense.isCancelled && expense.paidBy.isEmpty;
    final facts = ref.watch(expenseFactsProvider(expense.id)).valueOrNull;
    final forHome = facts?.forHome ?? false;
    final goods = facts?.goods ?? false;
    final mayChange =
        canCorrect(ref) &&
        (!forHome || ref.read(appServicesProvider).shopMoney.canSpendForHome);
    final title = facts == null
        ? expenseHeadLabel(s, expense.head ?? 'misc')
        : expenseTitle(
            s,
            forHome: forHome,
            systemKey: facts.headSystemKey,
            headName: facts.headName,
          );

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$title · ${expense.docNo}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          const SizedBox(height: BlTokens.space3),
          Row(
            children: [
              BlMoney(expense.total, size: 28, withSymbol: true),
              const SizedBox(width: BlTokens.space3),
              if (expense.isCancelled)
                BlChip(
                  s.entryCancelled,
                  tone: BlChipTone.bad,
                  icon: Icons.block,
                )
              else if (forHome)
                BlChip(s.expenseHomeChip, icon: Icons.home_outlined),
            ],
          ),
          const SizedBox(height: BlTokens.space3),
          EntryLine(s.entryDate, expense.dateLocal),
          EntryLine(s.expenseNote, expense.note),
          if (paidFrom != null) EntryLine(s.expensePaidFrom, paidFrom.name),
          if (expense.partyName case final name?)
            EntryLine(s.expensePayee, name),
          EntryLine(s.entryEnteredBy, expense.enteredBy),
          // Everything that happened to it since, in one place (M42).
          HistoryButton.wide(
            record: RecordRef.document(expense.id),
            label: expense.docNo,
          ),
          if (expense.paidBy.isNotEmpty) ...[
            const SizedBox(height: BlTokens.space3),
            EntryNote(s.entryPaidBy(expense.paidBy.join(', '))),
          ],
          if (standing) ...[
            const SizedBox(height: BlTokens.space4),
            if (mayChange) ...[
              if (goods)
                EntryNote(s.expenseGoodsCancelOnly)
              else
                BlButton(
                  label: s.actionEdit,
                  icon: Icons.edit_outlined,
                  kind: BlButtonKind.secondary,
                  onPressed: () => unawaited(_edit(context, facts)),
                ),
              const SizedBox(height: BlTokens.space3),
              BlButton(
                label: s.entryCancel,
                icon: Icons.block,
                kind: BlButtonKind.danger,
                onPressed: () => unawaited(_cancel(context)),
              ),
            ] else
              EntryNote(
                forHome && canCorrect(ref)
                    ? s.expenseHomeNotAllowed
                    : s.entryNotAllowed,
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, ExpenseFacts? facts) async {
    final navigator = Navigator.of(context);
    final saved = await navigator.push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ExpenseScreen(editing: expense, facts: facts),
      ),
    );
    // The page was about the expense just cancelled; the list underneath
    // now shows the one that replaced it.
    if (saved ?? false) navigator.pop();
  }

  Future<void> _cancel(BuildContext context) async {
    final navigator = Navigator.of(context);
    final cancelled = await showCancelEntrySheet(
      context,
      no: expense.docNo,
      cancel: (services, reason) => services.corrections.cancelExpense(
        services.actorNow(),
        documentId: expense.id,
        reason: reason,
      ),
    );
    if (cancelled) navigator.pop();
  }
}
