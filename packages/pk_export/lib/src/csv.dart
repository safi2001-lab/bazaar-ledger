import 'dart:convert';

import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';

/// A report as CSV, the file every accountant's spreadsheet opens.
///
/// The title and period first, then what it was narrowed by if anything
/// (M33), then the table as it stands on screen, then its notes. Money is
/// written as a plain number with two places and no grouping, so a
/// spreadsheet reads it as a number and its SUM agrees with the report's own
/// total; the total rows are written too, and marked.
String reportToCsv(ReportTable table) {
  final lines = <List<String>>[
    [table.title],
    ['Period', table.period.label],
    for (final f in table.filters) [_text(f)],
    [],
    [for (final c in table.columns) c.title],
    for (final row in table.rows)
      [
        for (var i = 0; i < table.columns.length; i++)
          _cell(row.cells[i], table.columns[i].kind),
      ],
    if (table.notes.isNotEmpty) [],
    for (final note in table.notes) [_text(note)],
  ];
  return '${lines.map((l) => l.map(_quote).join(',')).join('\r\n')}\r\n';
}

/// [reportToCsv] as UTF-8 bytes with a byte-order mark, without which Excel
/// reads an Urdu item name as mojibake.
List<int> reportToCsvBytes(ReportTable table) => [
  0xEF,
  0xBB,
  0xBF,
  ...utf8.encode(reportToCsv(table)),
];

/// `profit_and_loss_2026-09-01_2026-09-30.csv`.
String reportFileName(ReportTable table, {String extension = 'csv'}) {
  final p = table.period;
  final dates = p.isOneDay ? p.from.value : '${p.from.value}_${p.to.value}';
  return '${table.id}_$dates.$extension';
}

String _cell(Object? cell, CellKind kind) => switch (cell) {
  null => '',
  final Money m => _plainMoney(m),
  final Qty q => _plainQty(q),
  final int bp when kind == CellKind.percent => formatBp(bp),
  final String s => _text(s),
  _ => '$cell',
};

/// `-1234.50`: no grouping, two places.
String _plainMoney(Money m) {
  final sign = m.isNegative ? '-' : '';
  final paisa = m.inPaisa.abs();
  return '$sign${paisa ~/ 100}.${(paisa % 100).toString().padLeft(2, '0')}';
}

/// `12.5`: as many places as it needs, none for a whole number.
String _plainQty(Qty q) {
  final sign = q.isNegative ? '-' : '';
  final t = q.inThousandths.abs();
  final frac = (t % 1000)
      .toString()
      .padLeft(3, '0')
      .replaceAll(RegExp(r'0+$'), '');
  return frac.isEmpty ? '$sign${t ~/ 1000}' : '$sign${t ~/ 1000}.$frac';
}

/// A text cell a spreadsheet will not run as a formula. An item named
/// `=HYPERLINK(...)` is text in the shop and must stay text in the file.
String _text(String s) => s.isNotEmpty && '=+-@\t\r'.contains(s[0]) ? "'$s" : s;

String _quote(String field) {
  if (!field.contains(RegExp('[",\r\n]'))) return field;
  return '"${field.replaceAll('"', '""')}"';
}
