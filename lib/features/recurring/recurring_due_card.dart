import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'recurring_counter.dart';
import 'recurring_list_screen.dart';
import 'recurring_providers.dart';

/// "Aaj ke bill": the repeating bills whose day has come, on the screen the
/// shop opens every morning (M63).
///
/// There is no job in the background and no notification: the app follows
/// M20 and M47, and things happen when it is opened or comes back to the
/// front. So this card reads again when the app returns from behind
/// WhatsApp, and a hotel's milk bill that fell due overnight is on it.
///
/// Each due bill has "Banayein", which puts it on the counter to be checked
/// and paid for like any bill. "Sab bana dein" makes the ones set to make
/// themselves, each on the customer's khata, each its own bill, every check
/// of the counter made. Days the app was not opened are never made by
/// themselves: such a bill says how many and asks.
///
/// A shop with repeating bills and none due today sees one line saying how
/// many and when the next is, which opens the list; a shop with none sees
/// nothing at all.
class RecurringDueCard extends ConsumerStatefulWidget {
  const RecurringDueCard({super.key});

  @override
  ConsumerState<RecurringDueCard> createState() => _RecurringDueCardState();
}

class _RecurringDueCardState extends ConsumerState<RecurringDueCard>
    with WidgetsBindingObserver {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back to the front: the day may have turned while the app was behind.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(recurringHomeProvider);
    }
  }

  Future<void> _makeAll(List<RecurringDue> dues) async {
    if (_busy) return;
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      final outcomes = await services.recurring.makeEach([
        for (final d in dues) (bill: d.bill, forDate: d.latest),
      ]);
      container.bumpRefresh();
      // Waiting bills go to FBR once the batch is through (M19).
      unawaited(services.fbr.sendPending());
      if (!mounted) return;
      await showRecurringOutcomes(context, outcomes);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final home = ref.watch(recurringHomeProvider).valueOrNull;
    if (home == null) return const SizedBox.shrink();
    final due = home.due;

    void openList() => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RecurringListScreen()),
    );

    if (due.isEmpty) {
      if (home.kept == 0) return const SizedBox.shrink();
      final next = home.next;
      return Padding(
        padding: const EdgeInsets.only(top: BlTokens.space3),
        child: BlCard(
          onTap: openList,
          child: Row(
            children: [
              Icon(Icons.event_repeat_outlined, color: t.accent),
              const SizedBox(width: BlTokens.space3),
              Expanded(
                child: Text(
                  next == null
                      ? s.recurringKeptNoNext(home.kept)
                      : s.recurringKept(home.kept, shortDate(next.value)),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: t.inkMuted),
            ],
          ),
        ),
      );
    }

    // Made in one go: set to make themselves, and owed for one day only.
    final byThemselves = [
      for (final d in due)
        if (d.bill.byItself && !d.missed) d,
    ];

    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space3),
      child: BlCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.event_repeat_outlined, color: t.warning),
                const SizedBox(width: BlTokens.space3),
                Expanded(
                  child: Text(
                    s.recurringDueTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: t.ink,
                    ),
                  ),
                ),
                BlChip('${due.length}', tone: BlChipTone.warn),
              ],
            ),
            for (final d in due) _DueRow(due: d),
            const SizedBox(height: BlTokens.space2),
            Wrap(
              spacing: BlTokens.space2,
              runSpacing: BlTokens.space2,
              alignment: WrapAlignment.end,
              children: [
                BlButton(
                  label: s.recurringSeeAll,
                  kind: BlButtonKind.ghost,
                  onPressed: openList,
                ),
                if (byThemselves.isNotEmpty)
                  BlButton(
                    label: s.recurringMakeAll(byThemselves.length),
                    icon: Icons.done_all,
                    busy: _busy,
                    onPressed: _busy
                        ? null
                        : () => unawaited(_makeAll(byThemselves)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One bill due: whose, what, how late, and the way to make it — or, for
/// days missed, the question.
class _DueRow extends ConsumerWidget {
  const _DueRow({required this.due});

  final RecurringDue due;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final bill = due.bill;
    final today = ref.read(appServicesProvider).recurring.today;
    final status = due.missed
        ? s.recurringMissed(
            due.dates.length,
            shortDate(due.earliest.value),
            shortDate(due.latest.value),
          )
        : due.latest == today
        ? s.recurringDueToday
        : s.recurringDueSince(shortDate(due.latest.value));

    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
              Flexible(
                flex: 2,
                child: BlChip(
                  bill.byItself ? s.recurringByItself : s.recurringRemind,
                  tone: bill.byItself ? BlChipTone.good : BlChipTone.neutral,
                ),
              ),
            ],
          ),
          Text(
            '${everyText(s, bill.every)} · '
            '${s.recurringItemCount(bill.lines.length)}',
            style: TextStyle(fontSize: 13, color: t.inkMuted),
          ),
          Text(
            status,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: due.missed ? t.danger : t.warning,
            ),
          ),
          if (due.gone.isNotEmpty)
            Text(
              s.recurringGoneWarn(due.gone.join(', ')),
              style: TextStyle(fontSize: 13, color: t.danger),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: BlButton(
              label: due.missed ? s.recurringAsk : s.recurringMakeOne,
              icon: due.missed
                  ? Icons.help_outline
                  : Icons.point_of_sale_outlined,
              kind: BlButtonKind.secondary,
              onPressed: () => unawaited(
                due.missed
                    ? showMissedSheet(context, due)
                    : makeOnCounter(
                        context,
                        ref,
                        bill: bill,
                        forDate: due.latest,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The question for days the app was not opened: make them all, only the
/// latest, or none.
///
/// A bill set to make itself makes them here, each on the khata, each dated
/// today and recorded for its own day. One that only reminds goes to the
/// counter: "all" puts the earliest there and the card offers the next once
/// it is paid for; "the latest" lets the earlier days go first.
Future<void> showMissedSheet(BuildContext context, RecurringDue due) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MissedSheet(due: due),
    );

class _MissedSheet extends ConsumerStatefulWidget {
  const _MissedSheet({required this.due});

  final RecurringDue due;

  @override
  ConsumerState<_MissedSheet> createState() => _MissedSheetState();
}

class _MissedSheetState extends ConsumerState<_MissedSheet> {
  bool _busy = false;
  String? _failure;

  Future<void> _run(
    Future<void> Function(
      AppServices app,
      NavigatorState navigator,
      BuildContext host,
    )
    act,
  ) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    // The screen under this sheet, which outlives it.
    final host = Navigator.of(context).context;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await act(services, navigator, host);
      container.bumpRefresh();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = recurringProblemText(s, error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final due = widget.due;
    final bill = due.bill;
    final dates = due.dates;
    final before = dates[dates.length - 2];

    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewPaddingOf(context).bottom + BlTokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.recurringMissedTitle(bill.partyName, dates.length),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            const SizedBox(height: BlTokens.space2),
            Text(
              s.recurringMissedBody(
                [for (final d in dates) shortDate(d.value)].join(', '),
              ),
              style: TextStyle(fontSize: 14, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.recurringMissedAll(dates.length),
              icon: Icons.done_all,
              big: true,
              busy: _busy,
              onPressed: _busy
                  ? null
                  : () => unawaited(
                      _run((app, navigator, host) async {
                        if (!bill.byItself) {
                          navigator.pop();
                          if (host.mounted) {
                            await makeOnCounter(
                              host,
                              ref,
                              bill: bill,
                              forDate: due.earliest,
                            );
                          }
                          return;
                        }
                        final outcomes = await app.recurring.makeEach([
                          for (final d in dates) (bill: bill, forDate: d),
                        ]);
                        unawaited(app.fbr.sendPending());
                        navigator.pop();
                        if (host.mounted) {
                          await showRecurringOutcomes(host, outcomes);
                        }
                      }),
                    ),
            ),
            const SizedBox(height: BlTokens.space2),
            BlButton(
              label: s.recurringMissedLatest(shortDate(due.latest.value)),
              icon: Icons.today_outlined,
              kind: BlButtonKind.secondary,
              big: true,
              onPressed: _busy
                  ? null
                  : () => unawaited(
                      _run((app, navigator, host) async {
                        await app.recurring.letGo(bill.id, before);
                        final kept = await app.recurring.byId(bill.id) ?? bill;
                        navigator.pop();
                        if (!host.mounted) return;
                        if (!bill.byItself) {
                          await makeOnCounter(
                            host,
                            ref,
                            bill: kept,
                            forDate: due.latest,
                          );
                          return;
                        }
                        final outcome = await app.recurring.make(
                          kept,
                          due.latest,
                        );
                        unawaited(app.fbr.sendPending());
                        if (host.mounted) {
                          await showRecurringOutcomes(host, [outcome]);
                        }
                      }),
                    ),
            ),
            const SizedBox(height: BlTokens.space2),
            BlButton(
              label: s.recurringMissedSkip,
              icon: Icons.block,
              kind: BlButtonKind.ghost,
              onPressed: _busy
                  ? null
                  : () => unawaited(
                      _run((app, navigator, host) async {
                        await app.recurring.letGo(bill.id, due.latest);
                        navigator.pop();
                      }),
                    ),
            ),
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

/// What "Sab bana dein" did, bill by bill: made, waiting on the cashier's
/// word (with "Phir bhi banayein"), or not made and why.
Future<void> showRecurringOutcomes(
  BuildContext context,
  List<RecurringOutcome> outcomes,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _OutcomesSheet(outcomes: outcomes),
);

class _OutcomesSheet extends ConsumerStatefulWidget {
  const _OutcomesSheet({required this.outcomes});

  final List<RecurringOutcome> outcomes;

  @override
  ConsumerState<_OutcomesSheet> createState() => _OutcomesSheetState();
}

class _OutcomesSheetState extends ConsumerState<_OutcomesSheet> {
  late final List<RecurringOutcome> _outcomes = [...widget.outcomes];
  int? _working;

  Future<void> _anyway(int index) async {
    if (_working != null) return;
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final was = _outcomes[index];
    setState(() => _working = index);
    final now = await services.recurring.make(
      was.bill,
      was.forDate,
      confirmed: true,
    );
    container.bumpRefresh();
    unawaited(services.fbr.sendPending());
    if (!mounted) return;
    setState(() {
      _outcomes[index] = now;
      _working = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    String heldText(RecurringOutcome o) {
      final name = o.bill.partyName;
      return [
        if (o.overLimit case final over?)
          s.recurringHeldOverLimit(
            name,
            over.limit.amountOnly,
            over.after.amountOnly,
          ),
        if (o.bounced) s.recurringHeldBounced(name),
        if (o.short.isNotEmpty)
          s.recurringHeldShort(
            name,
            o.short.map((x) => x.shelf.itemName).join(', '),
          ),
      ].join('\n');
    }

    return Padding(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom: MediaQuery.viewPaddingOf(context).bottom + BlTokens.space4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.recurringResultsTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: t.ink,
              ),
            ),
            if (_outcomes.isEmpty)
              Text(
                s.recurringNothingToMake,
                style: TextStyle(fontSize: 14, color: t.inkMuted),
              ),
            for (var i = 0; i < _outcomes.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: BlTokens.space3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _outcomes[i].made
                          ? Icons.check_circle_outline
                          : _outcomes[i].held
                          ? Icons.help_outline
                          : Icons.block,
                      color: _outcomes[i].made
                          ? t.money
                          : _outcomes[i].held
                          ? t.warning
                          : t.danger,
                    ),
                    const SizedBox(width: BlTokens.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(switch (_outcomes[i]) {
                            final o when o.made => s.recurringMadeLine(
                              o.posted!.docNo,
                              o.bill.partyName,
                              o.posted!.total.amountOnly,
                            ),
                            final o when o.held => heldText(o),
                            final o => s.recurringNotMade(
                              o.bill.partyName,
                              recurringProblemText(s, o.refusal!),
                            ),
                          }, style: TextStyle(fontSize: 14, color: t.ink)),
                          if (_outcomes[i].held)
                            Align(
                              alignment: Alignment.centerRight,
                              child: BlButton(
                                label: s.recurringMakeAnyway,
                                kind: BlButtonKind.secondary,
                                busy: _working == i,
                                onPressed: _working != null
                                    ? null
                                    : () => unawaited(_anyway(i)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.actionClose,
              kind: BlButtonKind.ghost,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
