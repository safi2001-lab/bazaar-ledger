import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// A report's table arranged by the shop (M67): which columns show and in
/// what order, a filter on any column, and for the ageing reports the
/// buckets the money is cut into.
///
/// The arranging itself is `arrangeTable` in pk_reports, applied to the
/// finished table; this file is the chooser, the filter and the row of
/// chips above the table that says what is arranged and takes it off
/// again. Every control has its name in words beside it, so it reads at
/// 200% on a 360dp phone and to a screen reader, and nothing here adds a
/// figure up.

/// The chips above the table, when there is something to say: the buckets
/// an ageing report cuts its money into, and a chip for each column filter
/// that is on, with a cross to take it off. Nothing at all otherwise, so a
/// report the shop never arranged reads as it always did. The column
/// chooser and the column filter themselves sit in the app bar.
class ReportTableTools extends StatelessWidget {
  const ReportTableTools({
    required this.table,
    required this.arrangement,
    required this.onArranged,
    this.ageing,
    this.onAgeing,
    super.key,
  });

  /// The table as the builder made it, before it was arranged.
  final ReportTable table;
  final TableArrangement arrangement;
  final ValueChanged<TableArrangement> onArranged;

  /// The buckets the report was aged in, for an ageing report; null for
  /// any other.
  final AgeingBuckets? ageing;
  final ValueChanged<AgeingBuckets>? onAgeing;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final keys = columnKeys(table);
    final kinds = {
      for (var i = 0; i < keys.length; i++) keys[i]: table.columns[i].kind,
    };
    final filters = [
      for (final f in arrangement.filters)
        if (kinds.containsKey(f.column) && table.isSortable) f,
    ];
    if (ageing == null && filters.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: Wrap(
        spacing: BlTokens.space2,
        runSpacing: BlTokens.space1,
        children: [
          if (ageing case final buckets?)
            ActionChip(
              avatar: const Icon(Icons.timelapse_outlined, size: 16),
              label: Text(s.reportAgeingBuckets(buckets.label)),
              onPressed: () => unawaited(_ageing(context, buckets)),
            ),
          for (final f in filters)
            InputChip(
              label: Text(columnFilterLabel(s, f, kinds[f.column]!)),
              selected: true,
              showCheckmark: false,
              onPressed: () => unawaited(_edit(context, f)),
              onDeleted: () => onArranged(
                arrangement.withFilters([
                  for (final g in arrangement.filters)
                    if (g != f) g,
                ]),
              ),
              deleteButtonTooltipMessage: s.reportFilterClear,
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, ColumnFilter f) async {
    final next = await filterAColumn(context, table, arrangement, editing: f);
    if (next != null) onArranged(next);
  }

  Future<void> _ageing(BuildContext context, AgeingBuckets current) async {
    final chosen = await showDialog<AgeingBuckets>(
      context: context,
      builder: (_) => _AgeingDialog(current: current),
    );
    if (chosen != null) onAgeing?.call(chosen);
  }
}

/// Opens the column chooser for [table] and answers [arrangement] with its
/// columns as chosen, its filters kept; null when it was closed.
Future<TableArrangement?> chooseColumns(
  BuildContext context,
  ReportTable table,
  TableArrangement arrangement,
) async {
  final chosen = await showModalBottomSheet<TableArrangement>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ColumnChooser(table: table, arrangement: arrangement),
  );
  return chosen == null ? null : arrangement.withColumns(chosen);
}

/// Asks which column to filter and how, or changes [editing], and answers
/// [arrangement] with the filter in place; null when nothing was chosen. A
/// new filter on a column that has one already takes its place.
Future<TableArrangement?> filterAColumn(
  BuildContext context,
  ReportTable table,
  TableArrangement arrangement, {
  ColumnFilter? editing,
}) async {
  final s = AppStrings.of(context);
  final keys = columnKeys(table);
  final key =
      editing?.column ??
      await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                BlSectionHeader(s.reportColumnFilterPick),
                for (final k in arrangement.allKeys(table))
                  ListTile(
                    title: Text(k),
                    onTap: () => Navigator.of(context).pop(k),
                  ),
              ],
            ),
          ),
        ),
      );
  if (key == null || !context.mounted || !keys.contains(key)) return null;
  final kind = table.columns[keys.indexOf(key)].kind;
  final made = await showDialog<ColumnFilter>(
    context: context,
    builder: (_) =>
        _ColumnFilterDialog(column: key, kind: kind, current: editing),
  );
  if (made == null) return null;
  return arrangement.withFilters([
    for (final g in arrangement.filters)
      if (g != editing && g.column != made.column) g,
    made,
  ]);
}

/// A column filter as its chip reads: `Party: "rashid"`, `Owed ≥ Rs
/// 5,000.00`.
String columnFilterLabel(AppStrings s, ColumnFilter f, CellKind kind) =>
    switch (f.test) {
      ColumnTest.contains => s.reportColumnFilterContainsChip(
        f.column,
        f.text ?? '',
      ),
      ColumnTest.atLeast => s.reportColumnFilterAtLeastChip(
        f.column,
        figureText(f.value ?? 0, kind),
      ),
      ColumnTest.atMost => s.reportColumnFilterAtMostChip(
        f.column,
        figureText(f.value ?? 0, kind),
      ),
    };

/// Which columns show, and in what order: a tick to show or hide each, and
/// arrows to move it, every one named for the screen reader.
class _ColumnChooser extends StatefulWidget {
  const _ColumnChooser({required this.table, required this.arrangement});

  final ReportTable table;
  final TableArrangement arrangement;

  @override
  State<_ColumnChooser> createState() => _ColumnChooserState();
}

class _ColumnChooserState extends State<_ColumnChooser> {
  late final List<String> _order = widget.arrangement.allKeys(widget.table);
  late final Set<String> _hidden = {
    for (final k in widget.arrangement.hidden)
      if (_order.contains(k)) k,
  };

  void _move(int from, int to) => setState(() {
    final key = _order.removeAt(from);
    _order.insert(to, key);
  });

  TableArrangement get _chosen {
    final natural = columnKeys(widget.table);
    var same = natural.length == _order.length;
    for (var i = 0; same && i < natural.length; i++) {
      same = natural[i] == _order[i];
    }
    return TableArrangement(order: same ? const [] : _order, hidden: _hidden);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final shown = _order.length - _hidden.length;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BlSectionHeader(s.reportColumnsTitle),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: BlTokens.space4,
                ),
                child: Text(
                  s.reportColumnsHint,
                  style: TextStyle(fontSize: 13, color: t.inkMuted),
                ),
              ),
              const SizedBox(height: BlTokens.space2),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var i = 0; i < _order.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: BlTokens.space2,
                          right: BlTokens.space2,
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: !_hidden.contains(_order[i]),
                              // The last column shown stays shown: a table
                              // of nothing says nothing.
                              onChanged:
                                  !_hidden.contains(_order[i]) && shown <= 1
                                  ? null
                                  : (on) => setState(() {
                                      if (on ?? false) {
                                        _hidden.remove(_order[i]);
                                      } else {
                                        _hidden.add(_order[i]);
                                      }
                                    }),
                            ),
                            Expanded(
                              child: Text(
                                _order[i],
                                style: TextStyle(fontSize: 15, color: t.ink),
                              ),
                            ),
                            BlIconButton(
                              icon: Icons.arrow_upward,
                              label: s.reportColumnUp(_order[i]),
                              onPressed: i == 0 ? null : () => _move(i, i - 1),
                            ),
                            BlIconButton(
                              icon: Icons.arrow_downward,
                              label: s.reportColumnDown(_order[i]),
                              onPressed: i == _order.length - 1
                                  ? null
                                  : () => _move(i, i + 1),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(BlTokens.space3),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: BlTokens.space2,
                  runSpacing: BlTokens.space2,
                  children: [
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context).pop(TableArrangement.none),
                      child: Text(s.reportColumnsReset),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(_chosen),
                      child: Text(s.actionDone),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A filter on one column: words it contains, or a figure it is at least
/// or at most, typed as the column shows it.
class _ColumnFilterDialog extends StatefulWidget {
  const _ColumnFilterDialog({
    required this.column,
    required this.kind,
    this.current,
  });

  final String column;
  final CellKind kind;
  final ColumnFilter? current;

  @override
  State<_ColumnFilterDialog> createState() => _ColumnFilterDialogState();
}

class _ColumnFilterDialogState extends State<_ColumnFilterDialog> {
  late ColumnTest _test =
      widget.current?.test ??
      (widget.kind == CellKind.text ? ColumnTest.contains : ColumnTest.atLeast);
  late final _typed = TextEditingController(text: _start());

  String _start() {
    final c = widget.current;
    if (c == null) return '';
    if (c.test == ColumnTest.contains) return c.text ?? '';
    final v = c.value ?? 0;
    return switch (widget.kind) {
      // Rupees, and a percentage, both read in hundredths.
      CellKind.money ||
      CellKind.percent => Money.paisa(v).amountOnly.replaceAll(',', ''),
      CellKind.qty => Qty.raw(v).display,
      CellKind.count || CellKind.text => '$v',
    };
  }

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  /// What was typed, in the column's own smallest unit; null when it is
  /// not a figure.
  int? get _value {
    final text = _typed.text.trim().replaceAll(',', '');
    if (text.isEmpty) return null;
    return switch (widget.kind) {
      CellKind.money || CellKind.percent => Money.tryParse(text)?.inPaisa,
      CellKind.qty => Qty.tryParse(text)?.inThousandths,
      CellKind.count => int.tryParse(text),
      CellKind.text => null,
    };
  }

  ColumnFilter? get _made {
    if (_test == ColumnTest.contains) {
      final text = _typed.text.trim();
      return text.isEmpty ? null : ColumnFilter.contains(widget.column, text);
    }
    final v = _value;
    if (v == null) return null;
    return _test == ColumnTest.atLeast
        ? ColumnFilter.atLeast(widget.column, v)
        : ColumnFilter.atMost(widget.column, v);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final text = widget.kind == CellKind.text;
    final made = _made;
    return AlertDialog(
      title: Text(widget.column),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!text) ...[
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space1,
                children: [
                  for (final (test, label) in [
                    (ColumnTest.atLeast, s.reportColumnAtLeast),
                    (ColumnTest.atMost, s.reportColumnAtMost),
                  ])
                    ChoiceChip(
                      selected: _test == test,
                      label: Text(label),
                      onSelected: (_) => setState(() => _test = test),
                    ),
                ],
              ),
              const SizedBox(height: BlTokens.space2),
            ],
            BlField(
              controller: _typed,
              label: text ? s.reportColumnContains : s.reportColumnFilterValue,
              autofocus: true,
              numeric: !text,
              decimals: switch (widget.kind) {
                CellKind.money || CellKind.percent => 2,
                CellKind.qty => 3,
                CellKind.count || CellKind.text => 0,
              },
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (made != null) Navigator.of(context).pop(made);
              },
            ),
            if (!text && made == null && _typed.text.trim().isNotEmpty) ...[
              const SizedBox(height: BlTokens.space2),
              Text(
                s.reportColumnFilterBad,
                style: TextStyle(fontSize: 13, color: t.danger),
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
          onPressed: made == null
              ? null
              : () => Navigator.of(context).pop(made),
          child: Text(s.reportColumnFilterApply),
        ),
      ],
    );
  }
}

/// Where each ageing bucket ends, typed as the shop says it: "15, 30, 60".
class _AgeingDialog extends StatefulWidget {
  const _AgeingDialog({required this.current});

  final AgeingBuckets current;

  @override
  State<_AgeingDialog> createState() => _AgeingDialogState();
}

class _AgeingDialogState extends State<_AgeingDialog> {
  late final _typed = TextEditingController(text: widget.current.typed);

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final buckets = AgeingBuckets.tryParse(_typed.text);
    return AlertDialog(
      title: Text(s.reportAgeingTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.reportAgeingHint,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space3),
            BlField(
              controller: _typed,
              label: s.reportAgeingField,
              hint: '15, 30, 60',
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: BlTokens.space2),
            Text(
              buckets == null
                  ? s.reportAgeingBad
                  : s.reportAgeingBuckets(buckets.label),
              style: TextStyle(
                fontSize: 13,
                color: buckets == null ? t.danger : t.inkMuted,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(AgeingBuckets.standard),
          child: Text(s.reportAgeingReset),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.actionCancel),
        ),
        FilledButton(
          onPressed: buckets == null
              ? null
              : () => Navigator.of(context).pop(buckets),
          child: Text(s.actionSave),
        ),
      ],
    );
  }
}
