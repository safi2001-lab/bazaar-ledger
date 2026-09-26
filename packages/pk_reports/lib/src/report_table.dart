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
}

/// One column of a report.
final class ReportColumn {
  const ReportColumn(this.title, this.kind);

  final String title;
  final CellKind kind;

  bool get isNumeric => kind != CellKind.text;
}

/// How a row reads: an ordinary line, a heading over a section, or a total.
enum RowStyle { line, heading, subtotal, total }

/// One row. Each cell is a [String], a [Money], a [Qty], an [int] percent in
/// basis points, or null for a blank, matching its column's [CellKind].
final class ReportRow {
  const ReportRow(this.cells, {this.style = RowStyle.line});

  /// A heading across the table.
  ReportRow.heading(String title, int width)
    : cells = [title, ...List<Object?>.filled(width - 1, null)],
      style = RowStyle.heading;

  final List<Object?> cells;
  final RowStyle style;
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
          CellKind.percent => cell is int,
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

  /// The rows styled as the grand total, usually one.
  Iterable<ReportRow> get totals =>
      rows.where((r) => r.style == RowStyle.total);
}

/// A share of a whole in basis points, rounded half up; zero of zero is zero.
int shareBp(Money part, Money whole) {
  if (whole.isZero) return 0;
  final scaled = part.inPaisa * 10000;
  final den = whole.inPaisa;
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
