/// A report's table arranged the way the shop reads it (M67).
///
/// Vyapar's own help pages say it cannot hide a column; Zoho's reports have
/// a column chooser and a filter on every column, and an accountant used
/// to either reaches for both on the first day. A wholesaler reading the
/// Sale report on a 360dp phone wants the bill, the party and the balance,
/// not the eleven columns the accountant's export carries; the accountant
/// wants every column, in the order her spreadsheet already has them.
///
/// So the shop arranges each report once: which columns show, in which
/// order, and a filter on any of them ("Party contains Rashid", "Balance at
/// least Rs 5,000"). The arrangement is applied to the finished table, on
/// screen and in every file it goes out as, and nothing in it is a second
/// answer to a question the builder answered:
///
/// * a column is hidden or moved, never recomputed;
/// * a filter keeps or drops whole rows the builder made, and only rows a
///   report lists side by side ([ReportTable.isSortable]): a profit and
///   loss is a statement, and dropping one of its lines would leave a
///   subtotal that no longer adds up;
/// * the Total row stays the builder's, the whole report's. What the rows
///   left showing come to is a row of its own, "Shown rows (12 of 40)",
///   summed only in the columns the builder itself totals, so a column of
///   shares or a running balance is never added up into nonsense.
///
/// Columns are named by their title, as a saved view's sort is (M61): a
/// title survives a report gaining a column, where a position would not.
/// A title a report has twice (the sales tax summary's two "Tax" columns)
/// is told apart by its place among them, "Tax (2)".
library;

import 'dart:convert';

import 'package:pk_money/pk_money.dart';

import 'report_table.dart';

/// What a column filter asks of its column.
enum ColumnTest {
  /// Words: the cell contains the text, capitals aside.
  contains,

  /// A figure: the cell is this much or more.
  atLeast,

  /// A figure: the cell is this much or less.
  atMost,
}

/// One filter on one column.
final class ColumnFilter {
  /// Rows whose [column] contains [text], capitals aside.
  const ColumnFilter.contains(this.column, String this.text)
    : test = ColumnTest.contains,
      value = null;

  /// Rows whose [column] is [value] or more.
  const ColumnFilter.atLeast(this.column, int this.value)
    : test = ColumnTest.atLeast,
      text = null;

  /// Rows whose [column] is [value] or less.
  const ColumnFilter.atMost(this.column, int this.value)
    : test = ColumnTest.atMost,
      text = null;

  /// The column's key, as [columnKeys] gives it.
  final String column;
  final ColumnTest test;

  /// For [ColumnTest.contains].
  final String? text;

  /// For a figure, in the column's own smallest unit: paisa for money,
  /// thousandths for a quantity, basis points for a share, and a plain
  /// count for a count. The screen turns what the shopkeeper typed into it.
  final int? value;

  /// Whether a row whose cell under [column] is [cell] is kept.
  ///
  /// A blank in a column of money, quantities or counts is nothing, as the
  /// builders write a zero; a blank share (khula maal's margin, which has
  /// no cost to take one from) has no figure and is never kept by a test on
  /// one.
  bool keeps(Object? cell, CellKind kind) {
    if (test == ColumnTest.contains) {
      final wanted = (text ?? '').trim().toLowerCase();
      if (wanted.isEmpty) return true;
      return '${cell ?? ''}'.toLowerCase().contains(wanted);
    }
    final int? figure = switch (cell) {
      final Money m => m.inPaisa,
      final Qty q => q.inThousandths,
      final int n => n,
      null when kind != CellKind.percent => 0,
      _ => null,
    };
    if (figure == null || value == null) return false;
    return test == ColumnTest.atLeast ? figure >= value! : figure <= value!;
  }

  /// In words, for the head of an export and the chip on screen:
  /// `Party contains "rashid"`, `Balance at least Rs 5,000.00`.
  String describe(CellKind kind) {
    final name = keyTitle(column);
    if (test == ColumnTest.contains) return '$name contains "${text ?? ''}"';
    final words = test == ColumnTest.atLeast ? 'at least' : 'at most';
    return '$name $words ${figureText(value ?? 0, kind)}';
  }

  Map<String, Object?> toJson() => {
    'column': column,
    'test': test.name,
    'text': ?text,
    'value': ?value,
  };

  /// What [toJson] wrote, or null for anything else.
  static ColumnFilter? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final column = raw['column'];
    if (column is! String || column.isEmpty) return null;
    final test = ColumnTest.values
        .where((t) => t.name == raw['test'])
        .firstOrNull;
    final text = raw['text'];
    final value = raw['value'];
    return switch (test) {
      ColumnTest.contains when text is String => ColumnFilter.contains(
        column,
        text,
      ),
      ColumnTest.atLeast when value is int => ColumnFilter.atLeast(
        column,
        value,
      ),
      ColumnTest.atMost when value is int => ColumnFilter.atMost(column, value),
      _ => null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ColumnFilter &&
      other.column == column &&
      other.test == test &&
      other.text == text &&
      other.value == value;

  @override
  int get hashCode => Object.hash(column, test, text, value);
}

/// A figure typed into a column filter, as the column shows it: rupees for
/// money, a quantity, a percentage, a count.
String figureText(int value, CellKind kind) => switch (kind) {
  CellKind.money => 'Rs ${Money.paisa(value).amountOnly}',
  CellKind.qty => Qty.raw(value).display,
  CellKind.percent => formatBp(value),
  CellKind.count || CellKind.text => '$value',
};

/// Every column's key, in the table's own order: its title, or for the
/// second and later columns of one title, the title and its place, so a
/// key always names exactly one column.
List<String> columnKeys(ReportTable table) {
  final seen = <String, int>{};
  return [
    for (final c in table.columns)
      switch (seen.update(c.title, (n) => n + 1, ifAbsent: () => 1)) {
        1 => c.title,
        final n => '${c.title} ($n)',
      },
  ];
}

/// The title a key was made from.
String keyTitle(String key) => key.replaceFirst(RegExp(r' \(\d+\)$'), '');

/// How one report's table is arranged: its columns' order, the ones
/// hidden, and the filters on them. Empty is the table as built.
final class TableArrangement {
  const TableArrangement({
    this.order = const [],
    this.hidden = const {},
    this.filters = const [],
  });

  static const none = TableArrangement();

  /// Column keys in the order the shop put them. A column the report has
  /// and this list does not (one added since) goes after them, in the
  /// report's own order.
  final List<String> order;

  /// Column keys not shown.
  final Set<String> hidden;

  final List<ColumnFilter> filters;

  bool get isEmpty => order.isEmpty && hidden.isEmpty && filters.isEmpty;

  /// Whether the columns are moved or hidden, which the phone remembers
  /// for the report; the filters are the screen's, and a view's.
  bool get arrangesColumns => order.isNotEmpty || hidden.isNotEmpty;

  /// The same columns with other [filters].
  TableArrangement withFilters(List<ColumnFilter> filters) =>
      TableArrangement(order: order, hidden: hidden, filters: filters);

  /// The same filters with the columns arranged as [columns] says.
  TableArrangement withColumns(TableArrangement columns) => TableArrangement(
    order: columns.order,
    hidden: columns.hidden,
    filters: filters,
  );

  /// Only the columns: what the phone keeps for the report.
  TableArrangement get columnsOnly =>
      TableArrangement(order: order, hidden: hidden);

  /// The keys of [table]'s columns in the order shown, hidden ones left
  /// out; never none, because a table of no columns says nothing.
  List<String> shownKeys(ReportTable table) {
    final keys = columnKeys(table);
    final ordered = [
      for (final k in order)
        if (keys.contains(k)) k,
      for (final k in keys)
        if (!order.contains(k)) k,
    ];
    final shown = [
      for (final k in ordered)
        if (!hidden.contains(k)) k,
    ];
    return shown.isEmpty ? [keys.first] : shown;
  }

  /// [table]'s keys in the order shown, hidden ones included: what the
  /// chooser lists.
  List<String> allKeys(ReportTable table) {
    final keys = columnKeys(table);
    return [
      for (final k in order)
        if (keys.contains(k)) k,
      for (final k in keys)
        if (!order.contains(k)) k,
    ];
  }

  Map<String, Object?> toJson() => {
    if (order.isNotEmpty) 'order': order,
    if (hidden.isNotEmpty) 'hidden': hidden.toList(),
    if (filters.isNotEmpty) 'filters': [for (final f in filters) f.toJson()],
  };

  /// What [toJson] wrote. Anything of the wrong shape is read as not set,
  /// never as a guess, so a file this build cannot read arranges nothing.
  static TableArrangement fromJson(Object? raw) {
    if (raw is! Map) return none;
    List<String> texts(Object? list) => [
      if (list is List)
        for (final v in list)
          if (v is String && v.isNotEmpty) v,
    ];
    final filters = raw['filters'];
    return TableArrangement(
      order: texts(raw['order']),
      hidden: texts(raw['hidden']).toSet(),
      filters: [
        if (filters is List)
          for (final f in filters) ?ColumnFilter.fromJson(f),
      ],
    );
  }

  /// [toJson] as text, for a file of the phone's own.
  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is TableArrangement &&
      _sameList(other.order, order) &&
      other.hidden.length == hidden.length &&
      other.hidden.containsAll(hidden) &&
      _sameList(other.filters, filters);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(order),
    Object.hashAllUnordered(hidden),
    Object.hashAll(filters),
  );
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The label of the row of what the filtered rows come to, as the table
/// and every export write it.
String shownRowsLabel(int shown, int of) => 'Shown rows ($shown of $of)';

const _shownRowsNote =
    'Shown rows adds up only the rows the column filters left; the Total '
    'row is still the whole report\'s.';

/// [table] as [arrangement] arranges it: its rows kept by the column
/// filters, a row of what the kept rows come to, and its columns in the
/// order and number the shop chose. The same table, untouched, when the
/// arrangement is empty.
ReportTable arrangeTable(ReportTable table, TableArrangement arrangement) {
  if (arrangement.isEmpty) return table;
  final keys = columnKeys(table);
  final kinds = {
    for (var i = 0; i < keys.length; i++) keys[i]: table.columns[i].kind,
  };

  // The filters a table can take: on its own columns, and only when its
  // rows stand side by side.
  final filters = [
    for (final f in arrangement.filters)
      if (kinds.containsKey(f.column) && table.isSortable) f,
  ];
  var rows = table.rows;
  final described = <String>[];
  if (filters.isNotEmpty) {
    final at = {for (var i = 0; i < keys.length; i++) keys[i]: i};
    bool kept(ReportRow r) =>
        filters.every((f) => f.keeps(r.cells[at[f.column]!], kinds[f.column]!));
    final lines = table.rows.where((r) => r.style == RowStyle.line).toList();
    final shown = lines.where(kept).toList();
    final totals = table.rows.where((r) => r.style != RowStyle.line).toList();
    described.addAll([for (final f in filters) f.describe(kinds[f.column]!)]);
    // The label of the shown rows goes in the first text column left on
    // show; with none, the count is said at the head of the export instead.
    final label = arrangement
        .shownKeys(table)
        .map(keys.indexOf)
        .where((i) => table.columns[i].kind == CellKind.text)
        .firstOrNull;
    final words = shownRowsLabel(shown.length, lines.length);
    final cells = _shownCells(table, shown, totals.firstOrNull);
    if (label != null) cells[label] = words;
    // A total of its own, so the rows above it still sort and it stays at
    // the foot with the builder's, on screen and on paper.
    rows = [...shown, ReportRow(cells, style: RowStyle.total), ...totals];
    if (label == null) described.add(words);
  }

  final shownKeys = arrangement.shownKeys(table);
  final pick = [for (final k in shownKeys) keys.indexOf(k)];
  final moved = !_sameList(pick, [for (var i = 0; i < keys.length; i++) i]);
  return ReportTable(
    id: table.id,
    title: table.title,
    period: table.period,
    columns: moved ? [for (final i in pick) table.columns[i]] : table.columns,
    rows: moved
        ? [
            for (final r in rows)
              ReportRow(
                [for (final i in pick) r.cells[i]],
                style: r.style,
                link: r.link,
              ),
          ]
        : rows,
    notes: [...table.notes, if (filters.isNotEmpty) _shownRowsNote],
    summary: table.summary,
    filters: [...table.filters, ...described],
    bucketColumns: table.bucketColumns,
  );
}

/// What [shown] come to, in every column the builder's own [total] row
/// adds up: money, quantities and counts, never a share. With no total row
/// the builder added nothing up, and neither does this.
List<Object?> _shownCells(
  ReportTable table,
  List<ReportRow> shown,
  ReportRow? total,
) {
  final cells = List<Object?>.filled(table.columns.length, null);
  if (total == null) return cells;
  for (var i = 0; i < table.columns.length; i++) {
    final kind = table.columns[i].kind;
    final theirs = total.cells[i];
    if (theirs == null || kind == CellKind.text || kind == CellKind.percent) {
      continue;
    }
    cells[i] = switch (kind) {
      CellKind.money => Money.sum([
        for (final r in shown)
          if (r.cells[i] case final Money m) m,
      ]),
      CellKind.qty => Qty.sum([
        for (final r in shown)
          if (r.cells[i] case final Qty q) q,
      ]),
      CellKind.count => shown.fold<int>(
        0,
        (n, r) => n + (r.cells[i] is int ? r.cells[i]! as int : 0),
      ),
      CellKind.text || CellKind.percent => null,
    };
  }
  return cells;
}
