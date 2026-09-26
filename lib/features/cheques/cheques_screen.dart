import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// Cheques the shop is holding, soonest due first.
final chequesInHandProvider = FutureProvider.autoDispose<List<ChequeInHand>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.chequesInHand(firm.id);
});

/// Cheques the bank returned, most recent first.
final bouncedChequesProvider = FutureProvider.autoDispose<List<BouncedCheque>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.bouncedCheques(firm.id);
});

/// The cheque drawer, as a list.
///
/// A wholesaler holds dozens of post-dated cheques at once, each due on a
/// different day, and the paper ones live in a drawer with a rubber band
/// round them. Missing a date means the cheque goes stale; missing a bounce
/// means a customer who has not paid reads as paid. So what is due comes
/// first, what is late is marked late, and a bounce says the day by which
/// the 489-F notice has to go.
class ChequesScreen extends ConsumerWidget {
  const ChequesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final inHand = ref.watch(chequesInHandProvider);
    final bounced = ref.watch(bouncedChequesProvider).valueOrNull ?? const [];
    final today = BusinessDate.now(ref.watch(appServicesProvider).clock);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.homeCheques)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            BlSectionHeader(s.chequesInHand),
            const SizedBox(height: BlTokens.space2),
            inHand.when(
              loading: () => const BlSkeletonList(rows: 3),
              error: (error, _) => BlError(
                title: s.commonSomethingWentWrong,
                message: '$error',
                retryLabel: s.actionRetry,
                onRetry: () => ref.invalidate(chequesInHandProvider),
              ),
              data: (rows) => rows.isEmpty
                  ? BlEmpty(
                      icon: Icons.description_outlined,
                      title: s.chequesEmpty,
                      message: s.chequesEmptyHint,
                    )
                  : Column(
                      children: [
                        for (final cheque in rows)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: BlTokens.space2,
                            ),
                            child: _ChequeTile(cheque: cheque, today: today),
                          ),
                      ],
                    ),
            ),
            if (bounced.isNotEmpty) ...[
              const SizedBox(height: BlTokens.space5),
              BlSectionHeader(s.chequesBounced),
              const SizedBox(height: BlTokens.space2),
              for (final b in bounced)
                Padding(
                  padding: const EdgeInsets.only(bottom: BlTokens.space2),
                  child: _BouncedTile(cheque: b, today: today),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChequeTile extends StatelessWidget {
  const _ChequeTile({required this.cheque, required this.today});

  final ChequeInHand cheque;
  final BusinessDate today;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final due = cheque.due;
    final days = due == null ? null : daysUntil(today, due);

    final (String label, BlChipTone tone) = switch (days) {
      null => (s.chequeNoDate, BlChipTone.neutral),
      0 => (s.chequeDueTodayChip, BlChipTone.good),
      < 0 => (s.chequeOverdueChip('${-days}'), BlChipTone.bad),
      _ => (s.chequeDueInChip('$days'), BlChipTone.neutral),
    };

    return BlCard(
      onTap: () => unawaited(_showActions(context, cheque)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cheque.partyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                Text(
                  [
                    cheque.chequeNo,
                    ?cheque.bank,
                    if (due != null) due.value,
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
                const SizedBox(height: BlTokens.space1),
                Wrap(
                  spacing: BlTokens.space2,
                  children: [
                    BlChip(label, tone: tone),
                    if (cheque.deposited)
                      BlChip(
                        s.chequeAtBank,
                        icon: Icons.account_balance_outlined,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: BlTokens.space2),
          BlMoney(cheque.amount, size: 16),
        ],
      ),
    );
  }
}

class _BouncedTile extends StatelessWidget {
  const _BouncedTile({required this.cheque, required this.today});

  final BouncedCheque cheque;
  final BusinessDate today;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final late = daysUntil(today, cheque.noticeBy) < 0;

    return BlCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cheque.partyName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                Text(
                  '${cheque.chequeNo} · '
                  '${s.chequeBouncedOn(cheque.bouncedOn.value)}',
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
                const SizedBox(height: BlTokens.space1),
                BlChip(
                  s.chequeNoticeBy(cheque.noticeBy.value),
                  tone: late ? BlChipTone.bad : BlChipTone.warn,
                  icon: Icons.gavel_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(width: BlTokens.space2),
          BlMoney(cheque.amount, size: 16, colour: t.danger),
        ],
      ),
    );
  }
}

/// What can happen to this cheque next.
Future<void> _showActions(BuildContext context, ChequeInHand cheque) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ChequeActions(cheque: cheque),
    );

class _ChequeActions extends ConsumerStatefulWidget {
  const _ChequeActions({required this.cheque});

  final ChequeInHand cheque;

  @override
  ConsumerState<_ChequeActions> createState() => _ChequeActionsState();
}

enum _Step { choose, clear, bounce }

class _ChequeActionsState extends ConsumerState<_ChequeActions> {
  final _reason = TextEditingController();
  _Step _step = _Step.choose;
  String? _bankAccountId;
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function(MoveChequeUseCase cheques, ActorContext actor) step,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    try {
      await step(services.cheques, services.actorNow());
      container.bumpRefresh();
      navigator.pop();
    } on ChequeRefused catch (refused) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = refused.reason;
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

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final cheque = widget.cheque;

    // Where a cleared cheque can land: the bank, and the wallets and Raast
    // that settle into it. Never the cash drawer, and never the cheque
    // account itself, which is Cheques in Hand.
    final accounts = [
      for (final a
          in ref.watch(paymentAccountsProvider).valueOrNull ??
              const <PaymentAccountSummary>[])
        if (a.modeLabel != 'cash' && a.modeLabel != 'cheque') a,
    ];
    final today = BusinessDate.now(ref.watch(appServicesProvider).clock);
    // A bank will not take a post-dated cheque early, so neither does this.
    final due = cheque.isDueBy(today);
    final bankId =
        _bankAccountId ??
        accounts
            .where((a) => a.modeLabel == 'bank_transfer')
            .map((a) => a.id)
            .firstOrNull ??
        accounts.firstOrNull?.id;

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
              cheque.partyName,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            Text(
              '${cheque.chequeNo} · ${cheque.amount.amountOnly}',
              style: TextStyle(fontSize: 14, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space4),
            if (_step == _Step.choose) ...[
              if (!due) ...[
                BlOfflineNote(message: s.chequeNotYet(cheque.due!.value)),
                const SizedBox(height: BlTokens.space3),
              ],
              if (!cheque.deposited) ...[
                BlButton(
                  label: s.chequeDeposit,
                  icon: Icons.account_balance_outlined,
                  kind: BlButtonKind.secondary,
                  busy: _busy,
                  onPressed: _busy || !due
                      ? null
                      : () => unawaited(
                          _run((c, a) => c.deposit(a, cheque.paymentId)),
                        ),
                ),
                const SizedBox(height: BlTokens.space2),
              ],
              BlButton(
                label: s.chequeClear,
                icon: Icons.check_circle_outline,
                onPressed: _busy || !due
                    ? null
                    : () => setState(() => _step = _Step.clear),
              ),
              const SizedBox(height: BlTokens.space2),
              BlButton(
                label: s.chequeBounce,
                icon: Icons.report_gmailerrorred_outlined,
                kind: BlButtonKind.danger,
                onPressed: _busy
                    ? null
                    : () => setState(() => _step = _Step.bounce),
              ),
            ],
            if (_step == _Step.clear) ...[
              Text(
                s.chequeClearInto,
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
              const SizedBox(height: BlTokens.space2),
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space2,
                children: [
                  for (final a in accounts)
                    ChoiceChip(
                      selected: a.id == bankId,
                      label: Text(a.name),
                      onSelected: (_) => setState(() => _bankAccountId = a.id),
                    ),
                ],
              ),
              const SizedBox(height: BlTokens.space4),
              BlButton(
                label: s.chequeClear,
                icon: Icons.check,
                big: true,
                busy: _busy,
                onPressed: _busy || bankId == null
                    ? null
                    : () => unawaited(
                        _run(
                          (c, a) => c.clear(
                            a,
                            cheque.paymentId,
                            bankAccountId: bankId,
                          ),
                        ),
                      ),
              ),
            ],
            if (_step == _Step.bounce) ...[
              BlOfflineNote(
                message: s.chequeBounceWarning(
                  cheque.amount.amountOnly,
                  cheque.partyName,
                ),
              ),
              const SizedBox(height: BlTokens.space3),
              BlField(controller: _reason, label: s.chequeBounceReason),
              const SizedBox(height: BlTokens.space4),
              BlButton(
                label: s.chequeBounce,
                icon: Icons.report_gmailerrorred_outlined,
                kind: BlButtonKind.danger,
                big: true,
                busy: _busy,
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        _run(
                          (c, a) => c.bounce(
                            a,
                            cheque.paymentId,
                            reason: _reason.text,
                          ),
                        ),
                      ),
              ),
            ],
            if (_failure != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(_failure!, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
          ],
        ),
      ),
    );
  }
}
