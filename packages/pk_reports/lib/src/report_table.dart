import 'package:pk_money/pk_money.dart';

import 'period.dart';

/// What a column holds, which decides how it is shown and exported.
enum CellKind {
  /// Words.
  text,

  /// A [Money] amount.
  money,

  /// A [Qty].
  qty,

  /// A share, in basis points as an [int]: 1250 is 12.50%.
  percent,

  /// A count of things, as an [int]: bills, entries.
  count,
}

/// One column of a report.
final class ReportColumn {
  const ReportColumn(this.title, this.kind, {this.isCost = false});

  final String title;
  final CellKind kind;

  /// What the goods cost, or what was made over it: a column a role that may
  /// not see costs never receives (M33). Struck from the table before it
  /// leaves the engine, so no screen and no export can show it.
  final bool isCost;

  bool get isNumeric => kind != CellKind.text;
}

/// How a row reads: an ordinary line, a heading over a section, or a total.
enum RowStyle { line, heading, subtotal, total }

/// One row. Each cell is a [String], a [Money], a [Qty], an [int] percent in
/// basis points, or null for a blank, matching its column's [CellKind].
final class ReportRow {
  const ReportRow(this.cells, {this.style = RowStyle.line, this.link});

  /// A heading across the table.
  ReportRow.heading(String title, int width)
    : cells = [title, ...List<Object?>.filled(width - 1, null)],
      style = RowStyle.heading,
      link = null;

  final List<Object?> cells;
  final RowStyle style;

  /// What the row stands for, when it is one thing the shop can open: a
  /// bill, or a party (M33). Null for a total, a heading or a sum.
  final ReportLink? link;
}

/// What a tap on a row opens (M33).
enum ReportLinkKind {
  /// A document: a bill, a return, a delivery.
  document,

  /// A customer or supplier.
  party,

  /// An item, whose stock history it opens (M34).
  item,

  /// A loan the shop has taken, whose statement it opens (M58).
  loan,
}

/// The thing behind a row, so the screen can open it. The report says what
/// the row is; the screen decides what opening it means.
final class ReportLink {
  const ReportLink.document(this.id, {required this.label, this.docType})
    : kind = ReportLinkKind.document,
      unitCode = null;

  /// A loan (M58): its own statement says what was borrowed and paid back.
  const ReportLink.loan(this.id, {required this.label})
    : kind = ReportLinkKind.loan,
      docType = null,
      unitCode = null;

  const ReportLink.party(this.id, {required this.label})
    : kind = ReportLinkKind.party,
      docType = null,
      unitCode = null;

  /// An item (M34): its stock history says where every piece went.
  const ReportLink.item(this.id, {required this.label, this.unitCode})
    : kind = ReportLinkKind.item,
      docType = null;

  final ReportLinkKind kind;
  final String id;

  /// What the shop calls it: a bill number, a party's name.
  final String label;

  /// A document's `doc_type`: `sale_invoice`, `purchase_bill`...
  final String? docType;

  /// An item's base unit, which its history counts in (M34).
  final String? unitCode;
}

/// One figure from the top of a report, shown as a tile above the table
/// (M33): Total sale, Received, Balance. Computed by the builder with the
/// rest, never summed by the screen.
final class ReportFigure {
  const ReportFigure(this.label, Money this.amount, {this.isCost = false})
    : count = null;

  const ReportFigure.count(this.label, int this.count)
    : amount = null,
      isCost = false;

  final String label;
  final Money? amount;
  final int? count;

  /// What the goods cost, as a column marked `isCost` is (M34): a stock
  /// report a cashier may read still never shows them its value at cost.
  final bool isCost;

  /// How this figure compares with the same figure for an earlier period,
  /// in basis points of what it was then; null when there is nothing to
  /// compare with.
  int? changeFrom(ReportFigure before) {
    if (amount != null && before.amount != null) {
      return changeBp(amount!, before.amount!);
    }
    if (count != null && before.count != null && before.count != 0) {
      return _bp(count! - before.count!, before.count!.abs());
    }
    return null;
  }
}

/// A finished report: every figure already computed, nothing left for the
/// screen or the exporter to add up.
///
/// A total the screen summed would be a second answer to a question the
/// builder already answered, and the two would disagree the first time one
/// of them rounded.
final class ReportTable {
  ReportTable({
    required this.id,
    required this.title,
    required this.period,
    required this.columns,
    required this.rows,
    this.notes = const [],
    this.summary = const [],
    this.filters = const [],
  }) {
    for (final row in rows) {
      if (row.cells.length != columns.length) {
        throw ArgumentError(
          '$title: a row has ${row.cells.length} cells for '
          '${columns.length} columns',
        );
      }
      for (var i = 0; i < columns.length; i++) {
        final cell = row.cells[i];
        if (cell == null) continue;
        final ok = switch (columns[i].kind) {
          CellKind.text => cell is String,
          CellKind.money => cell is Money,
          CellKind.qty => cell is Qty,
          CellKind.percent || CellKind.count => cell is int,
        };
        if (!ok && !(row.style == RowStyle.heading && i == 0)) {
          throw ArgumentError(
            '$title: "${columns[i].title}" holds ${cell.runtimeType}',
          );
        }
      }
    }
  }

  /// Stable, for file names and tests: `profit_and_loss`.
  final String id;
  final String title;
  final ReportPeriod period;
  final List<ReportColumn> columns;
  final List<ReportRow> rows;

  /// Lines printed under the table: what a figure does and does not include.
  final List<String> notes;

  /// The headline figures, for the tiles above the table (M33). Empty for a
  /// report whose table is already its own summary.
  final List<ReportFigure> summary;

  /// What the report was narrowed by, in words, one line each (M33):
  /// "Party: Rashid Traders". Printed at the head of every export, because
  /// a filtered total read as the whole shop's is a wrong answer.
  final List<String> filters;

  /// The rows styled as the grand total, usually one.
  Iterable<ReportRow> get totals =>
      rows.where((r) => r.style == RowStyle.total);

  /// The same table, saying it was narrowed by [described].
  ReportTable withFilters(List<String> described) => described.isEmpty
      ? this
      : ReportTable(
          id: id,
          title: title,
          period: period,
          columns: columns,
          rows: rows,
          notes: notes,
          summary: summary,
          filters: [...filters, ...described],
        );

  /// The same table without its cost columns (M33), for a role that may not
  /// see what goods cost, and without its headline figures at cost (M34).
  ReportTable withoutCostColumns() {
    final keep = [
      for (var i = 0; i < columns.length; i++)
        if (!columns[i].isCost) i,
    ];
    final figures = [
      for (final f in summary)
        if (!f.isCost) f,
    ];
    if (keep.length == columns.length && figures.length == summary.length) {
      return this;
    }
    return ReportTable(
      id: id,
      title: title,
      period: period,
      columns: [for (final i in keep) columns[i]],
      rows: [
        for (final r in rows)
          ReportRow(
            [for (final i in keep) r.cells[i]],
            style: r.style,
            link: r.link,
          ),
      ],
      notes: notes,
      summary: figures,
      filters: filters,
    );
  }

  /// Whether every row but the totals is an ordinary line, so the lines can
  /// be put in any order without breaking a section apart (M33). A profit
  /// and loss, with its headings and subtotals, cannot be sorted; a list of
  /// bills can.
  bool get isSortable =>
      rows.every((r) => r.style == RowStyle.line || r.style == RowStyle.total);
}

/// How [now] compares with [before], in basis points of [before]: 2500 is
/// a quarter up, -1000 a tenth down. Null when there was nothing before to
/// compare with, because "up from nothing" is not a percentage (M33).
int? changeBp(Money now, Money before) => before.isZero
    ? null
    : _bp(now.inPaisa - before.inPaisa, before.inPaisa.abs());

/// The lines of [table] in the order of column [column], ascending or not,
/// with every total row kept at the foot where it was (M33).
///
/// The screen's to call and the table's to answer: sorting moves rows, it
/// adds nothing up. Blanks sort first going up. A table that is not
/// [ReportTable.isSortable] comes back as it was.
List<ReportRow> sortedRows(
  ReportTable table,
  int column, {
  required bool ascending,
}) {
  if (!table.isSortable) return table.rows;
  final lines = table.rows.where((r) => r.style == RowStyle.line).toList();
  final totals = table.rows.where((r) => r.style != RowStyle.line);
  int compare(Object? a, Object? b) {
    if (a == null || b == null) {
      return a == null ? (b == null ? 0 : -1) : 1;
    }
    return switch ((a, b)) {
      (final Money x, final Money y) => x.compareTo(y),
      (final Qty x, final Qty y) => x.compareTo(y),
      (final int x, final int y) => x.compareTo(y),
      _ => '$a'.toLowerCase().compareTo('$b'.toLowerCase()),
    };
  }

  // Stable: rows that compare equal keep the order the report gave them,
  // which for a list of bills is the order they were made.
  final indexed = [for (var i = 0; i < lines.length; i++) (i, lines[i])];
  indexed.sort((p, q) {
    final c = compare(p.$2.cells[column], q.$2.cells[column]);
    if (c != 0) return ascending ? c : -c;
    return p.$1.compareTo(q.$1);
  });
  return [for (final p in indexed) p.$2, ...totals];
}

/// A share of a whole in basis points, rounded half up; zero of zero is zero.
int shareBp(Money part, Money whole) => _bp(part.inPaisa, whole.inPaisa);

int _bp(int part, int whole) {
  if (whole == 0) return 0;
  final scaled = part * 10000;
  final den = whole;
  final q = scaled ~/ den;
  final r = scaled.remainder(den).abs() * 2;
  if (r >= den.abs()) return (scaled < 0) != (den < 0) ? q - 1 : q + 1;
  return q;
}

/// Basis points as a percentage with two places: 1250 is `12.50%`.
String formatBp(int bp) {
  final sign = bp < 0 ? '-' : '';
  final abs = bp.abs();
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}%';
}
