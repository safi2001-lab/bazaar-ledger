import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';

/// One line of a report printed on the counter's receipt printer (M33).
final class SlipLine {
  const SlipLine(this.text, {this.bold = false, this.centred = false});

  final String text;
  final bool bold;
  final bool centred;
}

/// A report laid out for a roll of receipt paper [width] characters wide
/// (M33): the shop, the report and its period, what it was narrowed by, its
/// headline figures, and then its rows, each as its words on one line and
/// its figures under them, right-aligned.
///
/// For the short reports a shop prints at the counter: today's day book,
/// the cash flow, the profit and loss. A report longer than [maxRows] prints
/// its figures and totals only and says the full list is in the PDF, rather
/// than running a metre of paper off the roll.
List<SlipLine> reportToSlip(
  ReportTable table, {
  required int width,
  String shopName = '',
  int maxRows = 40,
}) {
  final rule = SlipLine('-' * width);
  final columns = table.columns;
  final lines = table.rows.where((r) => r.style == RowStyle.line).length;
  final full = lines <= maxRows;

  return [
    if (shopName.isNotEmpty) SlipLine(shopName, bold: true, centred: true),
    SlipLine(table.title, bold: true, centred: true),
    SlipLine(table.period.label, centred: true),
    for (final f in table.filters) SlipLine(f, centred: true),
    rule,
    if (table.summary.isNotEmpty) ...[
      for (final f in table.summary)
        SlipLine(
          _pair(
            f.label,
            f.amount != null ? f.amount!.amountOnly : '${f.count ?? 0}',
            width,
          ),
        ),
      rule,
    ],
    for (final row in table.rows)
      if (full || row.style != RowStyle.line) ..._row(row, columns, width),
    if (!full) ...[
      rule,
      SlipLine('$lines rows: the full list is in the PDF.', centred: true),
    ],
    rule,
  ];
}

List<SlipLine> _row(ReportRow row, List<ReportColumn> columns, int width) {
  final strong = row.style != RowStyle.line;
  final words = <String>[];
  final figures = <(String, String)>[];
  for (var i = 0; i < columns.length; i++) {
    final cell = row.cells[i];
    if (cell == null) continue;
    final column = columns[i];
    if (column.kind == CellKind.text) {
      if (cell is String && cell.trim().isNotEmpty) words.add(cell.trim());
    } else {
      figures.add((column.title, _figure(cell, column.kind)));
    }
  }
  if (row.style == RowStyle.heading) {
    return [SlipLine(_cut(words.join(' '), width), bold: true)];
  }
  // Plain spaces: a receipt printer's own font has no middle dot.
  final label = words.join(' ');
  if (figures.length == 1) {
    return [SlipLine(_pair(label, figures.single.$2, width), bold: strong)];
  }
  return [
    if (label.isNotEmpty) SlipLine(_cut(label, width), bold: strong),
    for (final (title, value) in figures)
      SlipLine(_pair('  $title', value, width), bold: strong),
  ];
}

String _figure(Object cell, CellKind kind) => switch (cell) {
  final Money m => m.amountOnly,
  final Qty q => q.display,
  final int bp when kind == CellKind.percent => formatBp(bp),
  _ => '$cell',
};

/// [left] and [right] on one line, the right hard against the edge and the
/// left cut short to make room.
String _pair(String left, String right, int width) {
  final room = width - right.length - 1;
  if (room <= 0) return _cut(right, width);
  final l = left.length > room ? left.substring(0, room) : left;
  return '$l${' ' * (width - l.length - right.length)}$right';
}

String _cut(String s, int width) =>
    s.length > width ? s.substring(0, width) : s;
