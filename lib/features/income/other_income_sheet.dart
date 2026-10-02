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
import 'other_income_screen.dart';

final _otherIncomeProvider = FutureProvider.autoDispose
    .family<OtherIncomeDetail?, String>((ref, documentId) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return null;
      return services.shopMoney.otherIncome(documentId);
    });

/// One entry of other income, opened from the list (M47): read whole,
/// corrected, or cancelled with a reason — M31's page for a charge or an
/// expense, for the shop's own income. A cashier is offered neither, and
/// the service refuses one anyway.
Future<void> showOtherIncomeSheet(
  BuildContext context, {
  required String documentId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _OtherIncomeSheet(documentId: documentId),
);

class _OtherIncomeSheet extends ConsumerWidget {
  const _OtherIncomeSheet({required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final entry = ref.watch(_otherIncomeProvider(documentId));
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
        data: (income) => income == null
            ? BlEmpty(title: s.commonNothingSaved)
            : _Body(income: income),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.income});

  final OtherIncomeDetail income;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final heads = ref.watch(incomeHeadsProvider).valueOrNull ?? const [];
    final accounts =
        ref.watch(paymentAccountsProvider).valueOrNull ??
        const <PaymentAccountSummary>[];
    final into = accounts
        .where((a) => a.id == income.paymentAccountId)
        .firstOrNull;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${incomeKeyName(s, income.headKey, heads)} · ${income.docNo}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          const SizedBox(height: BlTokens.space3),
          Row(
            children: [
              BlMoney(income.amount, size: 28, withSymbol: true),
              const SizedBox(width: BlTokens.space3),
              if (income.isCancelled)
                BlChip(
                  s.entryCancelled,
                  tone: BlChipTone.bad,
                  icon: Icons.block,
                ),
            ],
          ),
          const SizedBox(height: BlTokens.space3),
          EntryLine(s.entryDate, income.dateLocal),
          if (income.fromName case final from?) EntryLine(s.entryFrom, from),
          if (into != null) EntryLine(s.incomeInto, into.name),
          if (income.note.isNotEmpty) EntryLine(s.expenseNote, income.note),
          EntryLine(s.entryEnteredBy, income.enteredBy),
          if (income.voidReason case final why? when income.isCancelled)
            EntryLine(s.voidReason, why),
          if (!income.isCancelled) ...[
            const SizedBox(height: BlTokens.space4),
            if (canCorrect(ref)) ...[
              BlButton(
                label: s.actionEdit,
                icon: Icons.edit_outlined,
                kind: BlButtonKind.secondary,
                onPressed: () => unawaited(_edit(context)),
              ),
              const SizedBox(height: BlTokens.space3),
              BlButton(
                label: s.entryCancel,
                icon: Icons.block,
                kind: BlButtonKind.danger,
                onPressed: () => unawaited(_cancel(context)),
              ),
            ] else
              EntryNote(s.entryNotAllowed),
          ],
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final navigator = Navigator.of(context);
    final saved = await navigator.push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => OtherIncomeScreen(editing: income),
      ),
    );
    if (saved ?? false) navigator.pop();
  }

  Future<void> _cancel(BuildContext context) async {
    final navigator = Navigator.of(context);
    final cancelled = await showCancelEntrySheet(
      context,
      no: income.docNo,
      cancel: (services, reason) => services.shopMoney.cancelOtherIncome(
        documentId: income.id,
        reason: reason,
      ),
    );
    if (cancelled) navigator.pop();
  }
}
