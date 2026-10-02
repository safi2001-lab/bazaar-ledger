import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'due_chip.dart';
import 'khata_screen.dart';
import 'udhaar_providers.dart';

/// Which customers the chase list opens on.
///
/// The home screen's card says "3 due today, 12 late, 2 promised today", and
/// each line opens the list already narrowed to the customers it counted.
enum ChaseView { all, dueToday, overdue, promisedToday, promised }

/// Who to chase, and how late they are.
///
/// A total tells a shopkeeper how much is out and nothing they can act on.
/// Rs 200,000 spread across this month's customers and Rs 200,000 sitting
/// since March are the same number and completely different problems, and the
/// second one is why shops keep a book at all.
///
/// Sorted by how late the oldest debt is rather than by size of balance. A
/// list sorted by amount puts the customer who owes Rs 40,000 since last week
/// ahead of the one who owes Rs 3,000 since March, every time — and the
/// second is the urgent conversation.
///
/// ## By due date (M38)
///
/// Late means past the day it was due — the bill's date plus the customer's
/// credit days, or the shop's usual month — not merely old. A wholesale
/// customer on fifteen days is late on day sixteen; a household on salary
/// day is not late in the third week. So the buckets split off what is not
/// yet due, and the rest are counted in days past due. The list can also be
/// read by the day customers promised to pay, soonest first, which is the
/// order the evening's phone calls go in.
class ChaseScreen extends ConsumerStatefulWidget {
  const ChaseScreen({super.key, this.initialView = ChaseView.all});

  final ChaseView initialView;

  @override
  ConsumerState<ChaseScreen> createState() => _ChaseScreenState();
}

class _ChaseScreenState extends ConsumerState<ChaseScreen> {
  DueBucket? _bucket;
  late ChaseView _view = widget.initialView;
  bool _byPromise = false;

  /// [rows] narrowed to the bucket and the view, in the order asked for.
  List<DueParty> _shown(List<DueParty> rows, String today) {
    final shown = [
      for (final r in rows)
        if ((_bucket == null || r.bucket == _bucket) && _inView(r, today)) r,
    ];
    if (_byPromise) {
      // Promised soonest first; nobody's promise after everybody's, in the
      // order they were already in (most late first).
      final order = {for (var i = 0; i < shown.length; i++) shown[i]: i};
      shown.sort((a, b) {
        final pa = a.livePromiseOn(today)?.promisedFor;
        final pb = b.livePromiseOn(today)?.promisedFor;
        if (pa != null && pb != null && pa != pb) return pa.compareTo(pb);
        if (pa != null && pb == null) return -1;
        if (pa == null && pb != null) return 1;
        return order[a]!.compareTo(order[b]!);
      });
    }
    return shown;
  }

  bool _inView(DueParty r, String today) => switch (_view) {
    ChaseView.all => true,
    ChaseView.dueToday => r.hasDueToday,
    ChaseView.overdue => r.isOverdue,
    ChaseView.promisedToday =>
      r.promise?.standingOn(today) == PromiseStanding.dueToday,
    ChaseView.promised => r.livePromiseOn(today) != null,
  };

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final aging = ref.watch(dueAgingProvider);
    final chase = ref.watch(duePartiesProvider);
    final today = ref.watch(appServicesProvider).udhaar.today;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.chaseTitle)),
      body: SafeArea(
        // One scrolling list, the summary and the filters at its head: at
        // 200% on a small phone the two together are taller than the
        // screen, and a fixed header left no room for a single name.
        child: Builder(
          builder: (context) {
            final header = <Widget>[
              aging.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(BlTokens.space4),
                  child: BlSkeletonList(rows: 1),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.all(BlTokens.space4),
                  child: BlError(
                    title: s.commonSomethingWentWrong,
                    message: '$error',
                  ),
                ),
                data: (data) => _Summary(
                  aging: data,
                  selected: _bucket,
                  onSelect: (bucket) => setState(
                    () => _bucket = _bucket == bucket ? null : bucket,
                  ),
                ),
              ),
              _Views(
                view: _view,
                byPromise: _byPromise,
                onView: (view) => setState(
                  () => _view = _view == view ? ChaseView.all : view,
                ),
                onSort: (byPromise) => setState(() => _byPromise = byPromise),
              ),
            ];
            final Widget? alone = chase.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(BlTokens.space4),
                child: BlSkeletonList(),
              ),
              error: (error, _) => BlError(
                title: s.commonSomethingWentWrong,
                message: '$error',
                retryLabel: s.actionRetry,
                onRetry: () => ref.invalidate(duePartiesProvider),
              ),
              data: (rows) => _shown(rows, today).isNotEmpty
                  ? null
                  : Padding(
                      padding: const EdgeInsets.all(BlTokens.space4),
                      child: BlEmpty(
                        icon: Icons.check_circle_outline,
                        title: rows.isEmpty ? s.chaseEmpty : s.emptyNoResults,
                        message: rows.isEmpty
                            ? s.chaseEmptyHint
                            : s.emptyNoResultsHint,
                      ),
                    ),
            );
            final shown = alone == null
                ? _shown(chase.valueOrNull ?? const [], today)
                : const <DueParty>[];
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: BlTokens.space10),
              itemCount: header.length + (alone == null ? shown.length : 1),
              itemBuilder: (context, i) {
                if (i < header.length) return header[i];
                if (alone != null) return alone;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: BlTokens.space4,
                  ),
                  child: _ChaseRow(due: shown[i - header.length], today: today),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// The five buckets by due date, tappable as a filter.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.aging,
    required this.selected,
    required this.onSelect,
  });

  final DueAging aging;
  final DueBucket? selected;
  final ValueChanged<DueBucket> onSelect;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    return Padding(
      padding: const EdgeInsets.all(BlTokens.space4),
      child: BlCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.chaseTotal,
                        style: TextStyle(fontSize: 13, color: t.inkMuted),
                      ),
                      BlMoney(aging.total, size: 26, withSymbol: true),
                    ],
                  ),
                ),
                if (aging.overdue.isPositive)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        s.chaseOverdue,
                        style: TextStyle(fontSize: 13, color: t.warning),
                      ),
                      BlMoney(aging.overdue, size: 18, colour: t.warning),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: BlTokens.space3),
            Wrap(
              spacing: BlTokens.space2,
              runSpacing: BlTokens.space2,
              children: [
                for (final bucket in DueBucket.values)
                  ChoiceChip(
                    selected: selected == bucket,
                    onSelected: (_) => onSelect(bucket),
                    label: Text(
                      '${bucket == DueBucket.notYetDue ? s.dueNotYet : bucket.label}'
                      '   ${aging[bucket].amountOnly}',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Narrowing by what is due today or promised, and the order to read in.
class _Views extends StatelessWidget {
  const _Views({
    required this.view,
    required this.byPromise,
    required this.onView,
    required this.onSort,
  });

  final ChaseView view;
  final bool byPromise;
  final ValueChanged<ChaseView> onView;
  final ValueChanged<bool> onSort;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BlTokens.space4,
        0,
        BlTokens.space4,
        BlTokens.space3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: BlTokens.space2,
            runSpacing: BlTokens.space2,
            children: [
              for (final (v, label) in [
                (ChaseView.dueToday, s.chaseFilterDueToday),
                (ChaseView.overdue, s.chaseFilterOverdue),
                (ChaseView.promisedToday, s.chaseFilterPromisedToday),
                (ChaseView.promised, s.chaseFilterPromised),
              ])
                FilterChip(
                  selected: view == v,
                  label: Text(label),
                  onSelected: (_) => onView(v),
                ),
            ],
          ),
          const SizedBox(height: BlTokens.space2),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text(s.chaseSortLate)),
              ButtonSegment(value: true, label: Text(s.chaseSortPromise)),
            ],
            selected: {byPromise},
            onSelectionChanged: (v) => onSort(v.first),
          ),
        ],
      ),
    );
  }
}

/// One customer to chase.
class _ChaseRow extends StatelessWidget {
  const _ChaseRow({required this.due, required this.today});

  final DueParty due;
  final String today;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final promise = due.promise;
    final standing = promise?.standingOn(today);
    // A promise worth showing on the row: one still to come, or one broken
    // and not yet followed by another — "Jumma kaha tha" is the opening line
    // of the call.
    final showPromise =
        standing != null &&
        (standing.isLive || standing == PromiseStanding.broken);

    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: BlCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => KhataScreen(party: due.party),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    due.party.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: BlTokens.space2,
                    runSpacing: BlTokens.space1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // How late, first, because it decides whether the
                      // shopkeeper calls today.
                      if (due.oldestDueLocal case final oldest?)
                        DueChip(
                          dueDateLocal: oldest,
                          daysOverdue: due.daysOverdue,
                        ),
                      if (showPromise)
                        BlChip(
                          '${promiseText(s, promise!)} · '
                          '${promiseStandingText(s, standing)}',
                          tone: promiseTone(standing),
                          icon: Icons.handshake_outlined,
                        ),
                      if (due.openBills > 0)
                        Text(
                          s.chaseBills(due.openBills),
                          style: TextStyle(fontSize: 12, color: t.inkMuted),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: BlTokens.space2),
            BlMoney(due.party.balance, size: 17),
          ],
        ),
      ),
    );
  }
}
