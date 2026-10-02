import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../khata/chase_screen.dart';
import '../khata/khata_screen.dart';
import 'party_editor.dart';
import 'party_groups.dart';
import 'party_groups_screen.dart';

/// Reset when the screen goes. See [itemsQueryProvider].
final partiesQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// The khata: who owes what.
///
/// Since M40 it is also the khata a wholesaler keeps by route: narrowed to
/// one group with that group's totals at the top, ordered by who owes the
/// most or who has owed the longest, and sorted into groups several names
/// at a time.
class PartiesScreen extends ConsumerStatefulWidget {
  const PartiesScreen({super.key});

  @override
  ConsumerState<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends ConsumerState<PartiesScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  /// The group the list is narrowed to. Null is everyone.
  String? _group;

  /// Only the people in no group, for sorting the stragglers.
  bool _ungrouped = false;

  PartySort _sort = PartySort.name;

  /// Picking several names to file under one group. Null when not picking.
  Set<String>? _selected;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) ref.read(partiesQueryProvider.notifier).state = value.trim();
    });
  }

  void _toggle(PartySummary party) {
    final selected = {...?_selected};
    if (!selected.remove(party.id)) selected.add(party.id);
    setState(() => _selected = selected);
  }

  Future<void> _setGroup() async {
    final selected = _selected;
    if (selected == null || selected.isEmpty) return;
    final moved = await showSetGroupSheet(
      context,
      partyIds: selected.toList(),
      current: _group,
    );
    if (moved && mounted) setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final query = ref.watch(partiesQueryProvider);
    final known = ref.watch(partyGroupsProvider);
    final groups = known.valueOrNull ?? const [];
    // A group renamed or merged away from the groups page, while the list
    // was narrowed to it, would narrow to nobody: the list goes back to
    // everyone instead.
    final group = known.hasValue && !groups.any((g) => g.name == _group)
        ? null
        : _group;
    final filter = PartyListFilter(
      query: query,
      group: group,
      ungrouped: _ungrouped,
      sort: _sort,
    );
    final parties = ref.watch(partyListProvider(filter));
    final selected = _selected;
    final picking = selected != null;
    PartyGroupSummary? header;
    for (final g in groups) {
      if (g.name == group) header = g;
    }

    return PopScope(
      // Back leaves picking first, as it would close a sheet: losing the
      // whole screen and the names ticked on it is not what back means.
      canPop: !picking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && picking) setState(() => _selected = null);
      },
      child: Scaffold(
        backgroundColor: t.paper,
        appBar: picking
            ? AppBar(
                leading: BlIconButton(
                  icon: Icons.close,
                  label: s.actionClose,
                  onPressed: () => setState(() => _selected = null),
                ),
                title: Text(s.partiesSelected(selected.length)),
                actions: [
                  BlIconButton(
                    icon: Icons.drive_file_move_outline,
                    label: s.groupSet,
                    onPressed: selected.isEmpty
                        ? null
                        : () => unawaited(_setGroup()),
                  ),
                ],
              )
            : AppBar(
                title: Text(s.partiesTitle),
                actions: [
                  _SortMenu(
                    sort: _sort,
                    onChanged: (sort) => setState(() => _sort = sort),
                  ),
                  BlIconButton(
                    icon: Icons.workspaces_outline,
                    label: s.groupsTitle,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PartyGroupsScreen(),
                      ),
                    ),
                  ),
                  BlIconButton(
                    icon: Icons.checklist,
                    label: s.partiesSelect,
                    onPressed: () => setState(() => _selected = {}),
                  ),
                  // The list answers "what does Rashid owe". This answers
                  // "who do I call today", which is the question a
                  // shopkeeper opens the book for in the evening.
                  BlIconButton(
                    icon: Icons.notifications_active_outlined,
                    label: s.chaseTitle,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ChaseScreen(),
                      ),
                    ),
                  ),
                ],
              ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  BlTokens.space4,
                  BlTokens.space3,
                  BlTokens.space4,
                  BlTokens.space2,
                ),
                child: BlField(
                  controller: _search,
                  label: s.actionSearch,
                  hint: s.partyName,
                  onChanged: _onChanged,
                  prefix: const Icon(Icons.search, size: 20),
                ),
              ),
              // Only once the shop has a group: a khata nobody has sorted
              // has nothing to narrow by, and three dead chips would say
              // otherwise.
              if (groups.isNotEmpty || group != null || _ungrouped)
                GroupChipRow(
                  padding: const EdgeInsets.fromLTRB(
                    BlTokens.space4,
                    0,
                    BlTokens.space4,
                    BlTokens.space2,
                  ),
                  children: [
                    ChoiceChip(
                      selected: group == null && !_ungrouped,
                      label: Text(s.groupAll),
                      onSelected: (_) => setState(() {
                        _group = null;
                        _ungrouped = false;
                      }),
                    ),
                    for (final g in groups)
                      ChoiceChip(
                        selected: group == g.name,
                        label: Text(g.name),
                        onSelected: (_) => setState(() {
                          _group = g.name;
                          _ungrouped = false;
                        }),
                      ),
                    ChoiceChip(
                      selected: _ungrouped,
                      label: Text(s.groupNone),
                      onSelected: (_) => setState(() {
                        _group = null;
                        _ungrouped = true;
                      }),
                    ),
                  ],
                ),
              if (header != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BlTokens.space4,
                    0,
                    BlTokens.space4,
                    BlTokens.space2,
                  ),
                  child: GroupTotalsCard(group: header),
                ),
              Expanded(
                child: parties.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(BlTokens.space4),
                    child: BlSkeletonList(),
                  ),
                  error: (error, _) => Center(
                    child: BlError(
                      title: s.commonSomethingWentWrong,
                      message: '$error',
                      retryLabel: s.actionRetry,
                      onRetry: () => ref.invalidate(partyListProvider(filter)),
                    ),
                  ),
                  data: (rows) {
                    if (rows.isEmpty) {
                      final narrowed = group != null || _ungrouped;
                      return Center(
                        child: BlEmpty(
                          title: query.isNotEmpty
                              ? s.emptyNoResults
                              : narrowed
                              ? s.groupNobody
                              : s.partiesEmpty,
                          message: query.isNotEmpty
                              ? s.emptyNoResultsHint
                              : narrowed
                              ? null
                              : s.partiesEmptyHint,
                          icon: Icons.people_alt_outlined,
                          action: narrowed && query.isEmpty
                              ? null
                              : BlButton(
                                  label: s.partiesAdd,
                                  icon: Icons.person_add_alt,
                                  onPressed: () => _open(context),
                                ),
                        ),
                      );
                    }
                    // Said, never silently cut off: the list used to stop
                    // at forty names without a word.
                    final capped = rows.length >= partyListLimit;
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        BlTokens.space4,
                        0,
                        BlTokens.space4,
                        BlTokens.space10 * 2,
                      ),
                      itemCount: rows.length + (capped ? 1 : 0),
                      itemExtent: blRowExtent(context, 68),
                      itemBuilder: (context, i) {
                        if (i == rows.length) {
                          return Center(
                            child: Text(
                              s.partiesCapped(partyListLimit),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: t.inkMuted),
                            ),
                          );
                        }
                        final party = rows[i];
                        return PartyRowTile(
                          key: ValueKey(party.id),
                          party: party,
                          selected: selected?.contains(party.id),
                          onTap: picking
                              ? () => _toggle(party)
                              : () => _open(context, party),
                          // A long press starts picking, as it does in
                          // every phone's own gallery and contacts.
                          onLongPress: picking
                              ? null
                              : () => setState(() => _selected = {party.id}),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: picking
            ? null
            : FloatingActionButton.extended(
                onPressed: () => _open(context),
                icon: const Icon(Icons.person_add_alt),
                label: Text(s.partiesAdd),
              ),
      ),
    );
  }

  /// A name in a khata opens the khata. Adding one opens the editor.
  ///
  /// Tapping a customer used to open the editor — a form for their phone
  /// number and their credit limit. That is the second thing a shopkeeper
  /// wants from a name in a khata. The first is how much, and what they do
  /// next is take money off it.
  static void _open(BuildContext context, [PartySummary? party]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => party == null
            ? const PartyEditorScreen()
            : KhataScreen(party: party),
      ),
    );
  }
}

/// How the list is ordered: by name, by who owes most, by who has owed
/// longest.
class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.sort, required this.onChanged});

  final PartySort sort;
  final ValueChanged<PartySort> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return PopupMenuButton<PartySort>(
      tooltip: s.partiesSort,
      icon: Icon(Icons.sort, color: t.ink),
      initialValue: sort,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final (value, label) in [
          (PartySort.name, s.partiesSortName),
          (PartySort.balance, s.partiesSortBalance),
          (PartySort.oldestDue, s.partiesSortOldest),
        ])
          CheckedPopupMenuItem<PartySort>(
            value: value,
            checked: value == sort,
            child: Text(label),
          ),
      ],
    );
  }
}

/// A group's name, how many are in it, and what they owe and are owed.
///
/// From the groups query, which sums every member, never from the rows
/// below it: a route of 400 retailers has a header that counts all 400,
/// whatever the list under it has loaded.
class GroupTotalsCard extends StatelessWidget {
  const GroupTotalsCard({super.key, required this.group, this.onTap});

  final PartyGroupSummary group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return BlCard(
      accent: true,
      onTap: onTap,
      padding: const EdgeInsets.all(BlTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
              ),
              const SizedBox(width: BlTokens.space2),
              Flexible(child: BlChip(s.groupMembers(group.members))),
              if (onTap != null) Icon(Icons.chevron_right, color: t.inkFaint),
            ],
          ),
          const SizedBox(height: BlTokens.space2),
          BlAmountRow(
            label: s.groupReceivable,
            labelStyle: TextStyle(fontSize: 13, color: t.inkMuted),
            child: BlMoney(
              group.receivable,
              size: 16,
              weight: FontWeight.w700,
              colour: group.receivable.isPositive ? t.warning : null,
              semanticPrefix: s.groupReceivable,
            ),
          ),
          BlAmountRow(
            label: s.groupPayable,
            labelStyle: TextStyle(fontSize: 13, color: t.inkMuted),
            child: BlMoney(
              group.payable,
              size: 16,
              semanticPrefix: s.groupPayable,
            ),
          ),
        ],
      ),
    );
  }
}

/// One customer in a list, with what they owe.
class PartyRowTile extends StatelessWidget {
  const PartyRowTile({
    super.key,
    required this.party,
    required this.onTap,
    this.trailingChevron = true,
    this.selected,
    this.onLongPress,
  });

  final PartySummary party;
  final VoidCallback onTap;
  final bool trailingChevron;

  /// Ticked or not, while names are being picked; null otherwise.
  final bool? selected;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final owes = party.balance.isPositive;
    final group = party.group;

    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: BlTokens.space2),
          child: Row(
            children: [
              if (selected != null)
                Checkbox(
                  value: selected,
                  onChanged: (_) => onTap(),
                  semanticLabel: party.name,
                ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      party.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                      ),
                    ),
                    if (party.phone != null || group != null) ...[
                      const SizedBox(height: 2),
                      // The phone and, beside it, the group as a small
                      // label (M40): at the counter "which Bilal" is
                      // answered by the route as often as by the number.
                      Row(
                        children: [
                          if (party.phone != null)
                            Flexible(
                              child: Text(
                                party.phone!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: t.inkMuted,
                                  fontFeatures: BlTokens.tabular,
                                ),
                              ),
                            ),
                          if (party.phone != null && group != null)
                            const SizedBox(width: BlTokens.space2),
                          if (group != null) Flexible(child: GroupTag(group)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: BlTokens.space3),
              // Flexible and scaled, not a fixed lump.
              //
              // A non-flex child of a Row claims its full natural width
              // first, so at 200% the balance chip took 204dp of a 360dp
              // screen and left the customer's name 70dp — about two glyphs
              // and an ellipsis. Every debtor in the khata rendered as the
              // same unreadable stub, and only for the users who turned the
              // font up because they could not read the small one.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: owes
                      ? BlChip(
                          s.partyOwes(party.balance.amountOnly),
                          tone:
                              party.isOverCreditLimit ||
                                  party.hasUnsettledBounce
                              ? BlChipTone.bad
                              : BlChipTone.warn,
                        )
                      // A supplier the shop owes is not "settled". Before
                      // this, every mill with an unpaid delivery read as
                      // Hisaab saaf in the one list anybody looks at.
                      : party.payable.isPositive
                      ? BlChip(s.partyWeOwe(party.payable.amountOnly))
                      : BlChip(s.partySettled, tone: BlChipTone.good),
                ),
              ),
              if (trailingChevron && selected == null)
                Icon(Icons.chevron_right, color: t.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}
