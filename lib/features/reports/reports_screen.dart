import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../subscription/plans_screen.dart';
import 'report_registry.dart';
import 'report_screen.dart';
import 'report_shelf.dart';
import 'today_strip.dart';

export 'report_registry.dart' show isAccountingReport, reportName;
export 'report_screen.dart' show ReportScreen;

/// The reports hub: did the shop make money, who owes what, where did it go
/// (M8; grouped, searched and starred since M33).
///
/// The reports sit in groups the way the shop apps this market already
/// knows lay them out, every group in one scroll: transactions, parties,
/// items and stock, business status, taxes, expenses, orders, loans. A
/// group with nothing in it yet is not shown. Above them sit the reports
/// this phone starred and the last few it opened, and a search in the bar
/// finds any of them by name.
///
/// Above everything since M46, a strip with today's figures off the night's
/// Z report, which opens it.
///
/// The list is the registry (`report_registry.dart`), so a report added
/// there appears here in its group with nothing else to change. A report
/// about what goods cost is not listed for a role that may not see costs,
/// and the engine refuses it to them as well.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final _search = TextEditingController();
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggleSearch() => setState(() {
    _searching = !_searching;
    if (!_searching) {
      _search.clear();
      _query = '';
    }
  });

  Future<void> _open(ReportEntry entry) async {
    final services = ref.read(appServicesProvider);
    final plan = entry.plan;
    if (plan == null || services.plans.has(plan)) {
      ref.read(reportShelfProvider.notifier).opened(entry.kind);
    }
    if (plan != null) {
      await openWithPlan(
        context,
        ref,
        plan,
        () => ReportScreen(kind: entry.kind),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReportScreen(kind: entry.kind)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final shelf = ref.watch(reportShelfProvider);

    final allowed = [
      for (final e in reportRegistry)
        if (!e.showsCost || services.can(Permission.seeCosts)) e,
    ];
    final query = _query.trim().toLowerCase();
    bool matches(ReportEntry e) =>
        query.isEmpty ||
        e.name(s).toLowerCase().contains(query) ||
        e.hint(s).toLowerCase().contains(query);

    final byKind = {for (final e in allowed) e.kind: e};
    final favourites = [for (final k in shelf.favourites) ?byKind[k]];
    final recent = [
      for (final k in shelf.recent)
        if (byKind[k] case final e? when !shelf.isFavourite(k)) e,
    ];
    final groups = [
      for (final g in ReportGroup.values)
        (
          group: g,
          entries: [
            for (final e in allowed)
              if (e.group == g && matches(e)) e,
          ],
        ),
    ].where((g) => g.entries.isNotEmpty).toList();

    Widget section(String title, List<ReportEntry> entries) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlSectionHeader(title),
        BlCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) Divider(height: 1, color: t.line),
                _ReportTile(
                  entry: entries[i],
                  starred: shelf.isFavourite(entries[i].kind),
                  onOpen: () => unawaited(_open(entries[i])),
                  onStar: () => ref
                      .read(reportShelfProvider.notifier)
                      .toggleFavourite(entries[i].kind),
                ),
              ],
            ],
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: s.reportSearchHint,
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : Text(s.reportsTitle),
        actions: [
          BlIconButton(
            icon: _searching ? Icons.close : Icons.search,
            label: _searching ? s.actionClose : s.actionSearch,
            onPressed: _toggleSearch,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            BlTokens.space4,
            0,
            BlTokens.space4,
            BlTokens.space6,
          ),
          children: [
            if (query.isEmpty) const TodayStrip(),
            if (query.isEmpty && favourites.isNotEmpty)
              section(s.reportFavourites, favourites),
            if (query.isEmpty && recent.isNotEmpty) ...[
              BlSectionHeader(s.reportRecent),
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space1,
                children: [
                  for (final e in recent)
                    ActionChip(
                      avatar: Icon(e.icon, size: 16),
                      label: Text(e.name(s)),
                      onPressed: () => unawaited(_open(e)),
                    ),
                ],
              ),
            ],
            for (final g in groups)
              section(reportGroupName(s, g.group), g.entries),
            if (groups.isEmpty)
              BlEmpty(title: s.reportSearchNone, icon: Icons.search_off),
          ],
        ),
      ),
    );
  }
}

/// One report in a group: what it is, what it answers, whether the plan
/// has it, and its star.
class _ReportTile extends StatelessWidget {
  const _ReportTile({
    required this.entry,
    required this.starred,
    required this.onOpen,
    required this.onStar,
  });

  final ReportEntry entry;
  final bool starred;
  final VoidCallback onOpen;
  final VoidCallback onStar;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.only(
          left: BlTokens.space4,
          top: BlTokens.space2,
          bottom: BlTokens.space2,
        ),
        child: Row(
          children: [
            Icon(entry.icon, color: t.inkMuted),
            const SizedBox(width: BlTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name(s),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  Text(
                    entry.hint(s),
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                ],
              ),
            ),
            if (entry.plan case final plan?) PlanLock(plan),
            BlIconButton(
              icon: starred ? Icons.star : Icons.star_border,
              label: starred ? s.reportUnstar : s.reportStar,
              colour: starred ? t.accent : t.inkMuted,
              onPressed: onStar,
            ),
          ],
        ),
      ),
    );
  }
}
