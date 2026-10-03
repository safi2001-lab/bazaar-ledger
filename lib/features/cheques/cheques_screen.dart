import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../attachments/attachment_strip.dart'; // M54
import '../printing/pdf_font.dart';

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

/// Cheques the shop wrote that the bank has not yet paid, soonest first.
final chequesIssuedProvider = FutureProvider.autoDispose<List<IssuedCheque>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.chequesIssued(firm.id);
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
    final issued = ref.watch(chequesIssuedProvider).valueOrNull ?? const [];
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
            // The other side of the drawer: the shop's own cheques, which
            // the supplier can present from their date, and which need the
            // money in the bank when they are.
            if (issued.isNotEmpty) ...[
              const SizedBox(height: BlTokens.space5),
              BlSectionHeader(s.chequesIssued),
              const SizedBox(height: BlTokens.space2),
              for (final c in issued)
                Padding(
                  padding: const EdgeInsets.only(bottom: BlTokens.space2),
                  child: _IssuedTile(cheque: c, today: today),
                ),
            ],
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
      onTap: () => unawaited(
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _NoticeSheet(cheque: cheque, today: today),
        ),
      ),
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

class _IssuedTile extends StatelessWidget {
  const _IssuedTile({required this.cheque, required this.today});

  final IssuedCheque cheque;
  final BusinessDate today;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final due = cheque.due;
    final days = due == null ? null : daysUntil(today, due);

    final (String label, BlChipTone tone) = switch (days) {
      null => (s.chequeNoDate, BlChipTone.neutral),
      <= 0 => (s.chequeIssuedPresentable, BlChipTone.warn),
      _ => (s.chequeDueInChip('$days'), BlChipTone.neutral),
    };

    return BlCard(
      onTap: () => unawaited(
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _IssuedActions(cheque: cheque),
        ),
      ),
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
                    cheque.bankAccountName,
                    if (due != null) due.value,
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
                const SizedBox(height: BlTokens.space1),
                BlChip(label, tone: tone),
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

/// A cheque the shop wrote: paid by the bank, or returned.
class _IssuedActions extends ConsumerStatefulWidget {
  const _IssuedActions({required this.cheque});

  final IssuedCheque cheque;

  @override
  ConsumerState<_IssuedActions> createState() => _IssuedActionsState();
}

class _IssuedActionsState extends ConsumerState<_IssuedActions> {
  final _reason = TextEditingController();
  bool _bouncing = false;
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
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failure = error is ChequeRefused ? error.reason : '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final cheque = widget.cheque;
    final today = BusinessDate.now(ref.watch(appServicesProvider).clock);
    final due = cheque.isDueBy(today);

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
              '${cheque.chequeNo} · ${cheque.bankAccountName} · '
              '${cheque.amount.amountOnly}',
              style: TextStyle(fontSize: 14, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space4),
            if (!_bouncing) ...[
              if (!due) ...[
                BlOfflineNote(message: s.chequeNotYet(cheque.due!.value)),
                const SizedBox(height: BlTokens.space3),
              ],
              BlButton(
                label: s.chequeIssuedPaid,
                icon: Icons.check_circle_outline,
                busy: _busy,
                onPressed: _busy || !due
                    ? null
                    : () => unawaited(
                        _run((c, a) => c.clearIssued(a, cheque.paymentId)),
                      ),
              ),
              const SizedBox(height: BlTokens.space2),
              BlButton(
                label: s.chequeBounce,
                icon: Icons.report_gmailerrorred_outlined,
                kind: BlButtonKind.danger,
                onPressed: _busy
                    ? null
                    : () => setState(() => _bouncing = true),
              ),
            ] else ...[
              BlOfflineNote(
                message: s.chequeIssuedBounceWarning(
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
                          (c, a) => c.bounceIssued(
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
  final _fee = TextEditingController();
  _Step _step = _Step.choose;
  String? _bankAccountId;

  /// Whether the bank's fee is put on the customer's khata as well.
  bool _chargeFee = false;
  bool _busy = false;
  String? _failure;

  @override
  void dispose() {
    _reason.dispose();
    _fee.dispose();
    super.dispose();
  }

  /// Runs [step], and once it has stood, [then]. A failure in [then] does
  /// not undo [step]: it is said, and the sheet closes on what was saved.
  Future<void> _run(
    Future<void> Function(MoveChequeUseCase cheques, ActorContext actor) step, {
    Future<void> Function(AppServices services)? then,
    String Function(Object error)? thenFailed,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await step(services.cheques, services.actorNow());
      if (then != null) {
        try {
          await then(services);
        } on Object catch (error) {
          messenger.showSnackBar(
            SnackBar(content: Text(thenFailed?.call(error) ?? '$error')),
          );
        }
      }
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
    final fee = Money.tryParse(_fee.text);
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
            // M54: the cheque's own photographs, front and back and the
            // deposit slip, on its own page (M60's strip; the khata's
            // payment page has always shown the same ones).
            AttachmentStrip(
              owner: AttachmentOwner.payment(cheque.paymentId, cheque: true),
              compact: true,
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
              const SizedBox(height: BlTokens.space3),
              // What the bank took from the shop for it. Booked as a bank
              // charge from the account it came out of, so the bank balance
              // in the books still matches the statement.
              BlField(
                controller: _fee,
                label: s.chequeBounceFee,
                numeric: true,
                onChanged: (_) => setState(() {}),
              ),
              if (fee != null && fee.isPositive) ...[
                const SizedBox(height: BlTokens.space2),
                Text(
                  s.chequeBounceFeeFrom,
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
                        onSelected: (_) =>
                            setState(() => _bankAccountId = a.id),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _chargeFee,
                  title: Text(s.chargeBounceFee(cheque.partyName)),
                  onChanged: (v) => setState(() => _chargeFee = v),
                ),
              ],
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
                          then: fee == null || !fee.isPositive || bankId == null
                              ? null
                              : (services) async {
                                  await services.recordExpense(
                                    services.actorNow(),
                                    ExpenseDraft(
                                      // No head of its own yet; misc, with
                                      // the cheque named, is findable.
                                      accountSystemKey: 'misc',
                                      amount: fee,
                                      note: s.chequeBounceFeeNote(
                                        cheque.chequeNo,
                                        cheque.partyName,
                                      ),
                                      paymentAccountId: bankId,
                                    ),
                                  );
                                  // And back from the customer who caused
                                  // it, as a debit note on their khata.
                                  if (_chargeFee) {
                                    await services.chargeParty(
                                      services.actorNow(),
                                      DebitNoteDraft(
                                        partyId: cheque.partyId,
                                        partyName: cheque.partyName,
                                        amount: fee,
                                        note: s.chargeBounceFeeNote(
                                          cheque.chequeNo,
                                        ),
                                      ),
                                    );
                                  }
                                },
                          thenFailed: (error) =>
                              s.chequeBounceFeeFailed('$error'),
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

/// The 489-F demand notice for one bounced cheque, drawn up and shared.
class _NoticeSheet extends ConsumerStatefulWidget {
  const _NoticeSheet({required this.cheque, required this.today});

  final BouncedCheque cheque;
  final BusinessDate today;

  @override
  ConsumerState<_NoticeSheet> createState() => _NoticeSheetState();
}

class _NoticeSheetState extends ConsumerState<_NoticeSheet> {
  bool _busy = false;
  String? _failure;

  Future<void> _share() async {
    // First statement, so two taps in one frame make one notice.
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final services = ref.read(appServicesProvider);
      final firm = await ref.read(firmProvider.future);
      final notice = await services.queries.demandNotice(
        firm!.id,
        widget.cheque.paymentId,
        issuedOn: widget.today,
      );
      if (notice == null) throw StateError('cheque ${widget.cheque.chequeNo}');
      final bytes = await demandNoticePdf(
        notice,
        // The names on it may be in Urdu, and the file is printed on some
        // other machine with no fonts of this phone's to fall back on.
        unicodeFont: await PdfUnicodeFont.bytes(),
      );
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}${demandNoticeFileName(notice)}',
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: notice.title,
        ),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _failure = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final cheque = widget.cheque;
    final late = daysUntil(widget.today, cheque.noticeBy) < 0;

    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewPaddingOf(context).bottom + BlTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.chequeNoticeTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          Text(
            '${cheque.partyName} · ${cheque.chequeNo} · '
            '${cheque.amount.amountOnly}',
            style: TextStyle(fontSize: 14, color: t.inkMuted),
          ),
          const SizedBox(height: BlTokens.space3),
          Text(
            late
                ? s.chequeNoticeLate(cheque.noticeBy.value)
                : s.chequeNoticeBy(cheque.noticeBy.value),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: late ? t.danger : t.ink,
            ),
          ),
          const SizedBox(height: BlTokens.space3),
          BlOfflineNote(message: s.chequeNoticeHint),
          const SizedBox(height: BlTokens.space4),
          BlButton(
            label: s.chequeNoticeShare,
            icon: Icons.picture_as_pdf_outlined,
            big: true,
            busy: _busy,
            onPressed: _busy ? null : () => unawaited(_share()),
          ),
          if (_failure != null) ...[
            const SizedBox(height: BlTokens.space3),
            Text(
              '${s.commonSomethingWentWrong}: $_failure',
              style: TextStyle(color: t.danger, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }
}
