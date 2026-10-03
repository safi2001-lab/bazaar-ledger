import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../sales/receipt_screen.dart';
import 'recurring_bill_screen.dart';
import 'recurring_counter.dart';
import 'recurring_providers.dart';

/// Every repeating bill the shop keeps (M63): whose, how many items, when
/// next, and whether it is running, paused or ended. A tap opens one.
class RecurringListScreen extends ConsumerWidget {
  const RecurringListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final bills = ref.watch(recurringBillsProvider);
    final today = ref.watch(appServicesProvider).recurring.today;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.recurringListTitle)),
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
                    title: s.recurringEmpty,
                    message: s.recurringEmptyHint,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(
                    BlTokens.space4,
                    BlTokens.space3,
                    BlTokens.space4,
                    BlTokens.space10,
                  ),
                  children: [
                    for (final bill in rows)
                      RecurringBillTile(bill: bill, today: today),
                  ],
                ),
        ),
      ),
    );
  }
}

/// One repeating bill in a list: the customer, what and how often, and its
/// standing. Opens the bill's own page.
class RecurringBillTile extends StatelessWidget {
  const RecurringBillTile({super.key, required this.bill, required this.today});

  final RecurringBill bill;
  final BusinessDate today;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final next = bill.nextAfter(today);
    final over = bill.isOver(today);
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: BlCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RecurringBillDetailScreen(id: bill.id),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    bill.partyName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                ),
                const SizedBox(width: BlTokens.space2),
                // Gives way rather than pushing off the card at 200%.
                Flexible(
                  flex: 2,
                  child: _StandingChip(bill: bill, over: over),
                ),
              ],
            ),
            Text(
              '${everyText(s, bill.every)} · '
              '${s.recurringItemCount(bill.lines.length)}',
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            if (!over && !bill.paused)
              Text(
                next == null
                    ? s.recurringNoNext
                    : s.recurringNext(shortDate(next.value)),
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
          ],
        ),
      ),
    );
  }
}

class _StandingChip extends StatelessWidget {
  const _StandingChip({required this.bill, required this.over});

  final RecurringBill bill;
  final bool over;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    if (over) return BlChip(s.recurringEnded);
    if (bill.paused) {
      return BlChip(s.recurringPaused, tone: BlChipTone.warn);
    }
    return BlChip(
      bill.byItself ? s.recurringByItself : s.recurringActive,
      tone: BlChipTone.good,
    );
  }
}

/// One repeating bill's page (M63): what it holds, when it comes round,
/// the bills it has made, and the ways to pause, change or end it.
class RecurringBillDetailScreen extends ConsumerWidget {
  const RecurringBillDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final bill = ref.watch(recurringBillProvider(id));
    final today = ref.watch(appServicesProvider).recurring.today;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.recurringListTitle)),
      body: SafeArea(
        child: bill.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 3),
          ),
          error: (error, _) =>
              BlError(title: s.commonSomethingWentWrong, message: '$error'),
          data: (bill) {
            if (bill == null) {
              return BlEmpty(title: s.recurringProblemNotKept);
            }
            return _Detail(bill: bill, today: today);
          },
        ),
      ),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.bill, required this.today});

  final RecurringBill bill;
  final BusinessDate today;

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(RecurringServices r) act,
    String done,
  ) async {
    final s = AppStrings.of(context);
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await act(services.recurring);
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(recurringProblemText(s, error))),
      );
    }
  }

  Future<void> _end(BuildContext context, WidgetRef ref) async {
    final s = AppStrings.of(context);
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.recurringEnd),
        content: Text(s.recurringEndConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.actionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.recurringEnd),
          ),
        ],
      ),
    );
    if (!(sure ?? false) || !context.mounted) return;
    await _act(context, ref, (r) => r.end(bill.id), s.recurringEndedDone);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final history = ref.watch(recurringHistoryProvider(bill.id));
    final gone = ref.watch(recurringGoneProvider(bill.id)).valueOrNull;
    final over = bill.isOver(today);
    final next = bill.nextAfter(today);
    final due = bill.dueOn(today);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        BlTokens.space4,
        BlTokens.space3,
        BlTokens.space4,
        BlTokens.space10,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Text(
                s.recurringFor(bill.partyName),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
            ),
            const SizedBox(width: BlTokens.space2),
            Flexible(
              flex: 2,
              child: _StandingChip(bill: bill, over: over),
            ),
          ],
        ),
        const SizedBox(height: BlTokens.space1),
        Text(
          [
            everyText(s, bill.every),
            if (bill.endOn case final end?)
              s.recurringEndOnDate(shortDate(end.value, thisYear: today.year)),
            if (bill.times case final n?) s.recurringTimesLeft(n),
          ].join(' · '),
          style: TextStyle(fontSize: 14, color: t.inkMuted),
        ),
        Text(
          [
            bill.prices == RecurringPrices.fixed
                ? s.recurringPricesFixed
                : s.recurringPricesToday,
            bill.byItself ? s.recurringModeAuto : s.recurringModeRemind,
          ].join(' · '),
          style: TextStyle(fontSize: 14, color: t.inkMuted),
        ),
        if (!over && !bill.paused)
          Text(
            due.isNotEmpty
                ? s.recurringDueSince(shortDate(due.first.value))
                : next == null
                ? s.recurringNoNext
                : s.recurringNext(shortDate(next.value)),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: due.isNotEmpty ? t.warning : t.ink,
            ),
          ),
        if (gone != null && gone.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: BlTokens.space1),
            child: Text(
              s.recurringGoneWarn(gone.join(', ')),
              style: TextStyle(fontSize: 13, color: t.danger),
            ),
          ),
        const SizedBox(height: BlTokens.space4),
        BlSectionHeader(s.recurringItems),
        const SizedBox(height: BlTokens.space2),
        for (final l in bill.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: BlTokens.space1),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.name,
                    style: TextStyle(
                      fontSize: 15,
                      color: (gone ?? const []).contains(l.name)
                          ? t.inkMuted
                          : t.ink,
                    ),
                  ),
                ),
                Text(
                  '${l.qty.display} ${l.unitCode}'.trim(),
                  style: TextStyle(fontSize: 15, color: t.ink),
                ),
              ],
            ),
          ),
        const SizedBox(height: BlTokens.space4),
        if (!over)
          Wrap(
            spacing: BlTokens.space2,
            runSpacing: BlTokens.space2,
            children: [
              if (due.isNotEmpty && !bill.paused)
                BlButton(
                  label: s.recurringMakeOne,
                  icon: Icons.point_of_sale_outlined,
                  onPressed: () => unawaited(
                    makeOnCounter(context, ref, bill: bill, forDate: due.first),
                  ),
                ),
              BlButton(
                label: s.recurringEdit,
                icon: Icons.edit_outlined,
                kind: BlButtonKind.secondary,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) => RecurringBillScreen(bill: bill),
                  ),
                ),
              ),
              if (bill.paused)
                BlButton(
                  label: s.recurringResume,
                  icon: Icons.play_arrow_outlined,
                  kind: BlButtonKind.secondary,
                  onPressed: () => unawaited(
                    _act(
                      context,
                      ref,
                      (r) => r.resume(bill.id),
                      s.recurringResumedDone,
                    ),
                  ),
                )
              else
                BlButton(
                  label: s.recurringPause,
                  icon: Icons.pause_outlined,
                  kind: BlButtonKind.secondary,
                  onPressed: () => unawaited(
                    _act(
                      context,
                      ref,
                      (r) => r.pause(bill.id),
                      s.recurringPausedDone,
                    ),
                  ),
                ),
              BlButton(
                label: s.recurringEnd,
                icon: Icons.stop_circle_outlined,
                kind: BlButtonKind.ghost,
                onPressed: () => unawaited(_end(context, ref)),
              ),
            ],
          ),
        const SizedBox(height: BlTokens.space5),
        BlSectionHeader(s.recurringHistory),
        const SizedBox(height: BlTokens.space2),
        history.when(
          loading: () => const BlSkeletonList(rows: 2),
          error: (error, _) =>
              BlError(title: s.commonSomethingWentWrong, message: '$error'),
          data: (made) => made.isEmpty
              ? Text(
                  s.recurringHistoryEmpty,
                  style: TextStyle(fontSize: 14, color: t.inkMuted),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final m in made) _MadeTile(made: m)],
                ),
        ),
      ],
    );
  }
}

/// One bill a template made: the day it was for, its number and total, and
/// a tap to its own page.
class _MadeTile extends StatelessWidget {
  const _MadeTile({required this.made});

  final RecurringMade made;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final late = made.forDate != made.madeOn;
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: BlCard(
        padding: const EdgeInsets.all(BlTokens.space3),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ReceiptScreen(documentId: made.documentId, docNo: made.docNo),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    made.docNo,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: made.isVoid ? t.inkMuted : t.ink,
                    ),
                  ),
                  Text(
                    late
                        ? s.recurringHistoryLate(
                            shortDate(made.forDate.value),
                            shortDate(made.madeOn.value),
                          )
                        : s.recurringHistoryFor(shortDate(made.forDate.value)),
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: BlTokens.space2),
            // Scaled down inside its share, never cut, at 200%.
            Flexible(
              flex: 2,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    BlMoney(made.total, size: 15),
                    if (made.isVoid)
                      BlChip(s.recurringCancelled, tone: BlChipTone.bad),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
