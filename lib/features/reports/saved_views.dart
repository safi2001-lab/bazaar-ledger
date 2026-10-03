import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'report_filters_bar.dart';
import 'report_registry.dart';
import 'report_shelf.dart';

/// The shop's own views of its reports (M61): "my Monday udhaar list".
///
/// A view is a report kept the way the shop likes it — its period as
/// chosen ("this week", never last week's dates), its filters, the column
/// it is sorted by, and table or chart — saved by name from any report's
/// screen and opened from the hub in one tap. What a view holds, and how it
/// is written down, is `SavedReportView` in pk_reports; this file keeps the
/// views on the phone and draws them.
///
/// Kept beside the report shelf's favourites (M33), in a small file of its
/// own in the app's support directory, and not in the books: a view is how
/// one person likes their phone, it is not the shop's, and it must not
/// travel to the other counters with a sync or come back with somebody
/// else's backup. Read synchronously for the same reason the shelf is — a
/// few hundred bytes, and a list that redrew itself under the thumb a
/// moment after the hub opened would be worse than the wait.
abstract final class SavedViewsFile {
  static const fileName = 'report_views.json';

  /// The views kept in [directory], or none.
  static List<SavedReportView> loadFrom(Directory directory) {
    try {
      final file = File('${directory.path}${Platform.pathSeparator}$fileName');
      if (!file.existsSync()) return const [];
      return decodeSavedViews(file.readAsStringSync());
    } on FileSystemException {
      return const [];
    }
  }

  /// Writes [views] into [directory], beside and then renamed over, as the
  /// shelf does, so a kill mid-write leaves the old file.
  static void saveTo(Directory directory, List<SavedReportView> views) {
    final path = '${directory.path}${Platform.pathSeparator}$fileName';
    final temporary = File('$path.tmp');
    temporary.writeAsStringSync(encodeSavedViews(views), flush: true);
    temporary.renameSync(path);
  }
}

/// The views, in the order they were saved, as the hub and the report
/// screens read and change them.
final savedViewsProvider =
    NotifierProvider<SavedViewsNotifier, List<SavedReportView>>(
      SavedViewsNotifier.new,
    );

class SavedViewsNotifier extends Notifier<List<SavedReportView>> {
  Directory? _directory;
  int _made = 0;

  @override
  List<SavedReportView> build() {
    // The same directory as the shelf, so a test that points the shelf at a
    // directory of its own points the views there too.
    final directory = ref.watch(reportShelfDirectoryProvider).valueOrNull;
    _directory = directory;
    if (directory == null) return const [];
    return SavedViewsFile.loadFrom(directory);
  }

  /// Keeps [view] under its name. A view of the same report already kept
  /// under the same name — capitals and spaces aside — is replaced where it
  /// stands, which is how a view is changed: open it, change it, save it
  /// again under its own name. Returns the view as kept.
  SavedReportView save(SavedReportView view) {
    String key(SavedReportView v) =>
        '${v.kind.name}|${v.name.trim().toLowerCase()}';
    final same = state.where((v) => key(v) == key(view)).firstOrNull;
    final kept = same == null
        ? SavedReportView(
            id: view.id.isEmpty ? _newId() : view.id,
            name: view.name.trim(),
            kind: view.kind,
            preset: view.preset,
            custom: view.custom,
            filters: view.filters,
            sortColumn: view.sortColumn,
            sortAscending: view.sortAscending,
            asChart: view.asChart,
            arrangement: view.arrangement, // M67
          )
        : SavedReportView(
            id: same.id,
            name: view.name.trim(),
            kind: view.kind,
            preset: view.preset,
            custom: view.custom,
            filters: view.filters,
            sortColumn: view.sortColumn,
            sortAscending: view.sortAscending,
            asChart: view.asChart,
            arrangement: view.arrangement, // M67
          );
    _keep([
      for (final v in state) v.id == kept.id ? kept : v,
      if (same == null) kept,
    ]);
    return kept;
  }

  void rename(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _keep([for (final v in state) v.id == id ? v.renamed(trimmed) : v]);
  }

  void delete(String id) => _keep([
    for (final v in state)
      if (v.id != id) v,
  ]);

  String _newId() =>
      'v${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${(_made++).toRadixString(36)}';

  void _keep(List<SavedReportView> next) {
    state = next;
    final directory = _directory;
    if (directory == null) return;
    try {
      SavedViewsFile.saveTo(directory, next);
    } on FileSystemException {
      // A full disk loses a view, never a report. The list on screen is
      // still right until the app is closed.
    }
  }
}

/// Asks for a name and keeps [view] under it, saying so at the foot of the
/// screen. [view]'s own name is offered to start from.
Future<SavedReportView?> saveReportView(
  BuildContext context,
  WidgetRef ref,
  SavedReportView view,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final s = AppStrings.of(context);
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _ViewNameDialog(
      title: s.reportSaveView,
      current: view.name,
      explain: true,
    ),
  );
  if (name == null) return null;
  final kept = ref
      .read(savedViewsProvider.notifier)
      .save(view.renamed(name.trim()));
  messenger.showSnackBar(SnackBar(content: Text(s.reportViewSaved(kept.name))));
  return kept;
}

/// The hub's "My views" (M61): every view of a report this person may open,
/// each opened by a tap, renamed or deleted from its menu.
class MyViewsSection extends ConsumerWidget {
  const MyViewsSection({required this.views, required this.onOpen, super.key});

  /// Already narrowed to the reports this person may open.
  final List<SavedReportView> views;
  final void Function(SavedReportView view) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlSectionHeader(s.reportMyViews),
        BlCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < views.length; i++) ...[
                if (i > 0) Divider(height: 1, color: t.line),
                _ViewTile(view: views[i], onOpen: () => onOpen(views[i])),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

enum _ViewAction { rename, delete }

class _ViewTile extends ConsumerWidget {
  const _ViewTile({required this.view, required this.onOpen});

  final SavedReportView view;
  final VoidCallback onOpen;

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    _ViewAction action,
  ) async {
    final s = AppStrings.of(context);
    final views = ref.read(savedViewsProvider.notifier);
    switch (action) {
      case _ViewAction.rename:
        final name = await showDialog<String>(
          context: context,
          builder: (_) =>
              _ViewNameDialog(title: s.reportViewRename, current: view.name),
        );
        if (name != null) views.rename(view.id, name);
      case _ViewAction.delete:
        final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(s.reportViewDelete),
            content: Text(s.reportViewDeleteConfirm(view.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(s.actionCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(s.reportViewDelete),
              ),
            ],
          ),
        );
        if (yes ?? false) views.delete(view.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final entry = reportEntry(view.kind);
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
                    view.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  Text(
                    savedViewSummary(s, view),
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                ],
              ),
            ),
            PopupMenuButton<_ViewAction>(
              tooltip: s.reportViewOptions,
              icon: Icon(Icons.more_vert, color: t.inkMuted),
              onSelected: (a) => unawaited(_act(context, ref, a)),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _ViewAction.rename,
                  child: Text(s.reportViewRename),
                ),
                PopupMenuItem(
                  value: _ViewAction.delete,
                  child: Text(s.reportViewDelete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One line under a view's name: its report, its period as chosen, and
/// what it is narrowed to, "Udhaar by age · Is hafta · Group: Mandi".
String savedViewSummary(AppStrings s, SavedReportView view) {
  final entry = reportEntry(view.kind);
  final period = entry.isAsOfToday
      ? null
      : view.preset == DatePreset.custom
      ? view.custom?.label
      : reportPresetLabel(s, view.preset);
  return [
    entry.name(s),
    ?period,
    for (final f in ReportFilter.values)
      if (entry.filters.contains(f) && view.filters.has(f))
        switch (filterValueLabel(s, f, view.filters)) {
          final String value => '${reportFilterName(s, f)}: $value',
          null => reportFilterName(s, f),
        },
  ].join(' · ');
}

/// The period presets as the report screen's chips name them.
String reportPresetLabel(AppStrings s, DatePreset preset) => switch (preset) {
  DatePreset.today => s.reportToday,
  DatePreset.yesterday => s.reportYesterday,
  DatePreset.thisWeek => s.reportThisWeek,
  DatePreset.thisMonth => s.reportThisMonth,
  DatePreset.lastMonth => s.reportLastMonth,
  DatePreset.thisQuarter => s.reportThisQuarter,
  DatePreset.thisFiscalYear => s.reportThisYear,
  DatePreset.lastFiscalYear => s.reportLastYear,
  DatePreset.custom => s.reportCustom,
};

/// A view's name, typed: to save one, or to rename it.
class _ViewNameDialog extends StatefulWidget {
  const _ViewNameDialog({
    required this.title,
    required this.current,
    this.explain = false,
  });

  final String title;
  final String current;

  /// Whether to say what a view keeps, and where: when one is first saved.
  final bool explain;

  @override
  State<_ViewNameDialog> createState() => _ViewNameDialogState();
}

class _ViewNameDialogState extends State<_ViewNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.current,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final blank = _name.text.trim().isEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BlField(
              controller: _name,
              label: s.reportViewName,
              hint: s.reportViewNameHint,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (!blank) Navigator.of(context).pop(_name.text.trim());
              },
            ),
            if (widget.explain) ...[
              const SizedBox(height: BlTokens.space3),
              Text(
                s.reportViewKeeps,
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.actionCancel),
        ),
        FilledButton(
          onPressed: blank
              ? null
              : () => Navigator.of(context).pop(_name.text.trim()),
          child: Text(s.actionSave),
        ),
      ],
    );
  }
}
