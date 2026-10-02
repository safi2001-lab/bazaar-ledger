import 'package:flutter/material.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// The table as computed: one row per row, totals in bold, losses in red
/// (M8), and since M33 sortable by any column and opened by a tap.
///
/// A year of a wholesaler's bills is twenty thousand rows, and a phone that
/// laid all of them out at once would stall for seconds. So the first
/// [pageSize] are drawn and the rest are a tap away, while the total row
/// stays at the foot whatever is showing: the export carries every row, and
/// the total on screen is always the whole period's.
class ReportTableView extends StatefulWidget {
  const ReportTableView({
    required this.table,
    this.canOpen,
    this.onOpen,
    super.key,
  });

  final ReportTable table;

  /// Whether a row's link leads anywhere from here.
  final bool Function(ReportLink link)? canOpen;
  final void Function(ReportLink link)? onOpen;

  static const pageSize = 200;

  @override
  State<ReportTableView> createState() => _ReportTableViewState();
}

class _ReportTableViewState extends State<ReportTableView> {
  int _visible = ReportTableView.pageSize;
  int? _sortColumn;
  bool _ascending = false;

  @override
  void didUpdateWidget(ReportTableView old) {
    super.didUpdateWidget(old);
    if (!identical(old.table, widget.table)) {
      _visible = ReportTableView.pageSize;
      if (_sortColumn != null &&
          (_sortColumn! >= widget.table.columns.length ||
              !widget.table.isSortable)) {
        _sortColumn = null;
      }
    }
  }

  void _sortBy(int column) => setState(() {
    if (_sortColumn == column) {
      _ascending = !_ascending;
    } else {
      // Newest, largest, last in the alphabet first: the order a shop owner
      // reaching for a header is looking for, since the report already
      // opens oldest first.
      _sortColumn = column;
      _ascending = false;
    }
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final table = widget.table;
    final columns = table.columns;
    final sorted = _sortColumn == null
        ? table.rows
        : sortedRows(table, _sortColumn!, ascending: _ascending);
    final cut = sorted.length > _visible;
    final shown = cut
        ? [
            ...sorted.take(_visible),
            ...sorted.skip(_visible).where((r) => r.style == RowStyle.total),
          ]
        : sorted;

    Widget cell(ReportRow row, int i) {
      final value = row.cells[i];
      final style = row.style;
      final numeric = columns[i].isNumeric && style != RowStyle.heading;
      final strong = style != RowStyle.line;
      final negative = switch (value) {
        final Money m => m.isNegative,
        _ => false,
      };
      final text = Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BlTokens.space2,
          vertical: BlTokens.space1 + 2,
        ),
        child: Text(
          reportCellText(value, columns[i].kind),
          textAlign: numeric ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            fontSize: 14,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
            color: negative ? t.danger : t.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
      final link = row.link;
      if (link == null ||
          widget.onOpen == null ||
          !(widget.canOpen?.call(link) ?? true)) {
        return text;
      }
      return TableRowInkWell(onTap: () => widget.onOpen!(link), child: text);
    }

    Widget header(int i) {
      final c = columns[i];
      final label = Text(
        c.title,
        textAlign: c.isNumeric ? TextAlign.end : TextAlign.start,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _sortColumn == i ? t.ink : t.inkMuted,
        ),
      );
      if (!table.isSortable) {
        return Padding(
          padding: const EdgeInsets.all(BlTokens.space2),
          child: label,
        );
      }
      return Semantics(
        button: true,
        label: s.reportSortedBy(c.title),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => _sortBy(i),
          child: Padding(
            padding: const EdgeInsets.all(BlTokens.space2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: c.isNumeric
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                Flexible(child: label),
                if (_sortColumn == i)
                  Icon(
                    _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                    size: 14,
                    color: t.ink,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlCard(
          padding: const EdgeInsets.all(BlTokens.space2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: t.line)),
                  ),
                  children: [
                    for (var i = 0; i < columns.length; i++) header(i),
                  ],
                ),
                for (final row in shown)
                  TableRow(
                    decoration: row.style == RowStyle.total
                        ? BoxDecoration(
                            border: Border(top: BorderSide(color: t.line)),
                          )
                        : null,
                    children: [
                      for (var i = 0; i < columns.length; i++) cell(row, i),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (cut) ...[
          const SizedBox(height: BlTokens.space2),
          BlButton(
            label: s.reportShowMore(
              _visible,
              sorted.where((r) => r.style == RowStyle.line).length,
            ),
            kind: BlButtonKind.ghost,
            onPressed: () =>
                setState(() => _visible += ReportTableView.pageSize),
          ),
        ],
        for (final note in table.notes) ...[
          const SizedBox(height: BlTokens.space2),
          Text(note, style: TextStyle(fontSize: 13, color: t.inkMuted)),
        ],
      ],
    );
  }
}

/// A cell as the screen writes it.
String reportCellText(Object? value, CellKind kind) => switch (value) {
  null => '',
  final Money m => m.amountOnly,
  final Qty q => q.display,
  final int bp when kind == CellKind.percent => formatBp(bp),
  _ => '$value',
};
