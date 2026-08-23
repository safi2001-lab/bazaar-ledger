import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'khata_providers.dart';
import 'khata_screen.dart';

/// Who to chase, and how long they have had it.
///
/// A total tells a shopkeeper how much is out and nothing they can act on.
/// Rs 200,000 spread across this month's customers and Rs 200,000 sitting
/// since March are the same number and completely different problems, and the
/// second one is why shops keep a book at all.
///
/// Sorted by the age of the oldest debt rather than by size of balance. A
/// list sorted by amount puts the customer who owes Rs 40,000 since last week
/// ahead of the one who owes Rs 3,000 since March, every time — and the
/// second is the urgent conversation.
class ChaseScreen extends ConsumerStatefulWidget {
  const ChaseScreen({super.key});

  @override
  ConsumerState<ChaseScreen> createState() => _ChaseScreenState();
}

class _ChaseScreenState extends ConsumerState<ChaseScreen> {
  AgeBucket? _filter;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final aging = ref.watch(agingProvider);
    final chase = ref.watch(chaseListProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.chaseTitle)),
      body: SafeArea(
        child: Column(
          children: [
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
                selected: _filter,
                onSelect: (bucket) =>
                    setState(() => _filter = _filter == bucket ? null : bucket),
              ),
            ),
            Expanded(
              child: chase.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(BlTokens.space4),
                  child: BlSkeletonList(),
                ),
                error: (error, _) => Center(
                  child: BlError(
                    title: s.commonSomethingWentWrong,
                    message: '$error',
                    retryLabel: s.actionRetry,
                    onRetry: () => ref.invalidate(chaseListProvider),
                  ),
                ),
                data: (rows) {
                  final shown = _filter == null
                      ? rows
                      : rows.where((r) => r.bucket == _filter).toList();
                  if (shown.isEmpty) {
                    return Center(
                      child: BlEmpty(
                        icon: Icons.check_circle_outline,
                        title: rows.isEmpty ? s.chaseEmpty : s.emptyNoResults,
                        message: rows.isEmpty
                            ? s.chaseEmptyHint
                            : s.emptyNoResultsHint,
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      BlTokens.space4,
                      0,
                      BlTokens.space4,
                      BlTokens.space10,
                    ),
                    itemCount: shown.length,
                    itemBuilder: (context, i) => _ChaseRow(aged: shown[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The four buckets, tappable as a filter.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.aging,
    required this.selected,
    required this.onSelect,
  });

  final Aging aging;
  final AgeBucket? selected;
  final ValueChanged<AgeBucket> onSelect;

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
                for (final bucket in AgeBucket.values)
                  ChoiceChip(
                    selected: selected == bucket,
                    onSelected: (_) => onSelect(bucket),
                    label: Text(
                      '${bucket.label}   ${aging[bucket].amountOnly}',
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

/// One customer to chase.
class _ChaseRow extends StatelessWidget {
  const _ChaseRow({required this.aged});

  final AgedParty aged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: BlCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => KhataScreen(party: aged.party),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    aged.party.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      // The age first, because it is what decides whether the
                      // shopkeeper calls today.
                      BlChip(
                        s.chaseSince(aged.oldestDays),
                        tone: switch (aged.bucket) {
                          AgeBucket.current => BlChipTone.neutral,
                          AgeBucket.thirty => BlChipTone.neutral,
                          AgeBucket.sixty => BlChipTone.warn,
                          AgeBucket.ninety => BlChipTone.bad,
                        },
                      ),
                      const SizedBox(width: BlTokens.space2),
                      Text(
                        s.chaseBills(aged.openBills),
                        style: TextStyle(fontSize: 12, color: t.inkMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            BlMoney(aged.party.balance, size: 17),
          ],
        ),
      ),
    );
  }
}
