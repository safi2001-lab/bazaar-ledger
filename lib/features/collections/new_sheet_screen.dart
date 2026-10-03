import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../khata/due_chip.dart';
import '../khata/goods_given.dart';
import '../khata/udhaar_providers.dart';
import 'sheet_screen.dart';

/// Everyone in the shop who could take a round.
final _staffProvider = FutureProvider.autoDispose<List<StaffMember>>((
  ref,
) async {
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return [
    for (final m in await services.staffStore.staff(firm.id))
      if (m.isActive) m,
  ];
});

/// Every customer who owes, whose debt is oldest first.
///
/// The khata list's own read (M40), not the chase list's: the chase list
/// counts open bills, and a customer whose whole debt is the old register's
/// purana baqaya has none — yet he is exactly who a recovery man is sent to.
final _owingProvider = FutureProvider.autoDispose<List<PartySummary>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return [
    for (final p in await services.queries.partyList(
      firm.id,
      filter: const PartyListFilter(sort: PartySort.oldestDue),
      limit: 2000,
    ))
      if (p.isCustomer && p.balance.isPositive) p,
  ];
});

/// Which customers the sheet is picked from.
enum _Pick { all, late, dueToday }

/// A new sheet: who goes, and to whom (M55).
///
/// Everyone who owes, oldest debt first, with what the chase list (M38)
/// knows about each — how late, due today — narrowed to the late ones, to
/// those due today, or to a route (M40's groups): a wholesaler's man goes by
/// route, and a route's late customers are the morning's sheet. Ticked in the
/// order the man is to visit; the sheet keeps that order and numbers it.
///
/// The man is a member of staff, or a name typed in: the recovery man is
/// often nobody who signs in to the phone.
class NewSheetScreen extends ConsumerStatefulWidget {
  const NewSheetScreen({super.key});

  @override
  ConsumerState<NewSheetScreen> createState() => _NewSheetScreenState();
}

class _NewSheetScreenState extends ConsumerState<NewSheetScreen> {
  final _name = TextEditingController();
  String? _staffId;
  _Pick _pick = _Pick.all;
  String? _group;
  final _ticked = <String>[];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  List<PartySummary> _shown(
    List<PartySummary> rows,
    Map<String, DueParty> due,
  ) => [
    for (final p in rows)
      if ((_group == null || p.group == _group) &&
          switch (_pick) {
            _Pick.all => true,
            _Pick.late => due[p.id]?.isOverdue ?? false,
            _Pick.dueToday => due[p.id]?.hasDueToday ?? false,
          })
        p,
  ];

  void _tick(String partyId, bool on) => setState(() {
    _error = null;
    on ? _ticked.add(partyId) : _ticked.remove(partyId);
  });

  void _tickAll(List<PartySummary> shown) => setState(() {
    _error = null;
    for (final p in shown) {
      if (!_ticked.contains(p.id)) _ticked.add(p.id);
    }
  });

  /// What the sheet was made from, in words: "Route 3 · Der wale".
  String? _title(AppStrings s) {
    final pick = switch (_pick) {
      _Pick.all => null,
      _Pick.late => s.chaseFilterOverdue,
      _Pick.dueToday => s.chaseFilterDueToday,
    };
    final words = [?_group, ?pick];
    return words.isEmpty ? null : words.join(' · ');
  }

  Future<void> _make(List<StaffMember> staff) async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final member = staff.where((m) => m.id == _staffId).firstOrNull;
    final collector = member?.name ?? _name.text.trim();
    if (collector.isEmpty) {
      setState(() => _error = s.sheetCollectorMissing);
      return;
    }
    if (_ticked.isEmpty) {
      setState(() => _error = s.sheetNoneTicked);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final sheet = await ref
          .read(appServicesProvider)
          .collections
          .makeSheet(
            SheetDraft(
              partyIds: List.of(_ticked),
              collector: collector,
              collectorUserId: member?.id,
              title: _title(s),
            ),
          );
      container.bumpRefresh();
      unawaited(
        navigator.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => SheetScreen(sheetId: sheet.id),
          ),
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final staff = ref.watch(_staffProvider).valueOrNull ?? const [];
    final owing = ref.watch(_owingProvider);
    final rows = owing.valueOrNull ?? const <PartySummary>[];
    final due = {
      for (final d
          in ref.watch(duePartiesProvider).valueOrNull ?? const <DueParty>[])
        d.party.id: d,
    };
    final unpricedBy = {
      for (final u
          in ref.watch(unpricedPartiesProvider).valueOrNull ??
              const <UnpricedParty>[])
        u.partyId: u.lines,
    };
    final groups = {
      for (final p in rows)
        if (p.group case final g? when g.isNotEmpty) g,
    }.toList()..sort();
    final shown = _shown(rows, due);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.sheetNew)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            BlTokens.space4,
            BlTokens.space3,
            BlTokens.space4,
            BlTokens.space10,
          ),
          children: [
            Text(
              s.sheetCollector,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: t.inkMuted,
              ),
            ),
            const SizedBox(height: BlTokens.space2),
            if (staff.isNotEmpty)
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space2,
                children: [
                  for (final m in staff)
                    ChoiceChip(
                      selected: _staffId == m.id,
                      label: Text(m.name),
                      onSelected: (on) => setState(() {
                        _staffId = on ? m.id : null;
                        if (on) _name.clear();
                      }),
                    ),
                ],
              ),
            const SizedBox(height: BlTokens.space2),
            BlField(
              controller: _name,
              label: s.sheetCollectorName,
              onChanged: (_) => setState(() => _staffId = null),
            ),
            const SizedBox(height: BlTokens.space4),
            Text(
              s.sheetPickWho,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: t.inkMuted,
              ),
            ),
            const SizedBox(height: BlTokens.space2),
            Wrap(
              spacing: BlTokens.space2,
              runSpacing: BlTokens.space2,
              children: [
                for (final (pick, label) in [
                  (_Pick.all, s.groupAll),
                  (_Pick.late, s.chaseFilterOverdue),
                  (_Pick.dueToday, s.chaseFilterDueToday),
                ])
                  ChoiceChip(
                    selected: _pick == pick,
                    label: Text(label),
                    onSelected: (_) => setState(() => _pick = pick),
                  ),
              ],
            ),
            if (groups.isNotEmpty) ...[
              const SizedBox(height: BlTokens.space2),
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space2,
                children: [
                  for (final g in groups)
                    FilterChip(
                      selected: _group == g,
                      label: Text(g),
                      onSelected: (on) =>
                          setState(() => _group = on ? g : null),
                    ),
                ],
              ),
            ],
            const SizedBox(height: BlTokens.space2),
            if (shown.isNotEmpty)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: BlButton(
                  label: s.sheetTickAll,
                  icon: Icons.done_all,
                  kind: BlButtonKind.ghost,
                  onPressed: () => _tickAll(shown),
                ),
              ),
            if (owing.isLoading) const BlSkeletonList(rows: 3),
            if (!owing.isLoading && shown.isEmpty)
              BlEmpty(
                icon: Icons.check_circle_outline,
                title: rows.isEmpty ? s.chaseEmpty : s.emptyNoResults,
                message: rows.isEmpty ? s.chaseEmptyHint : s.emptyNoResultsHint,
              ),
            for (final p in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: BlTokens.space2),
                child: _PartyTick(
                  party: p,
                  due: due[p.id],
                  ticked: _ticked.contains(p.id),
                  position: _ticked.indexOf(p.id) + 1,
                  unpriced: unpricedBy[p.id] ?? 0,
                  onTick: (on) => _tick(p.id, on),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: BlTokens.space2),
              Text(_error!, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
            const SizedBox(height: BlTokens.space3),
            BlButton(
              label: s.sheetMake(_ticked.length),
              icon: Icons.assignment_ind_outlined,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_make(staff)),
            ),
          ],
        ),
      ),
    );
  }
}

/// One customer who could go on the sheet.
class _PartyTick extends StatelessWidget {
  const _PartyTick({
    required this.party,
    required this.due,
    required this.ticked,
    required this.position,
    required this.unpriced,
    required this.onTick,
  });

  final PartySummary party;

  /// What the chase list knows about them; null when nothing they owe is
  /// on a bill (an opening balance only).
  final DueParty? due;
  final bool ticked;

  /// Where on the sheet, once ticked: the order the man goes in.
  final int position;
  final int unpriced;
  final ValueChanged<bool> onTick;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final due = this.due;
    return BlCard(
      onTap: () => onTick(!ticked),
      child: Row(
        children: [
          Checkbox(value: ticked, onChanged: (v) => onTick(v ?? false)),
          if (ticked)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: BlTokens.space2),
              child: Text(
                '$position.',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: t.accent,
                ),
              ),
            ),
          Expanded(
            child: Column(
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
                Wrap(
                  spacing: BlTokens.space2,
                  runSpacing: BlTokens.space1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (party.group case final g?)
                      Text(
                        g,
                        style: TextStyle(fontSize: 12, color: t.inkMuted),
                      ),
                    if (due?.oldestDueLocal case final oldest?)
                      DueChip(
                        dueDateLocal: oldest,
                        daysOverdue: due!.daysOverdue,
                      ),
                    if (unpriced > 0)
                      BlChip(
                        s.goodsGivenUnpriced(unpriced),
                        tone: BlChipTone.warn,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: BlTokens.space2),
          BlMoney(party.balance, size: 16),
        ],
      ),
    );
  }
}
