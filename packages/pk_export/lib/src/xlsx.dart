import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';

/// A report as an Excel workbook (M33), the file an accountant asks for by
/// name.
///
/// Written by hand rather than through a spreadsheet package: an `.xlsx` is
/// a zip of six small XML files, the zip is the `archive` package the app
/// already carries for reading workbooks in, and a spreadsheet library
/// would add to the APK to write what fits on a page here.
///
/// The sheet is the table as computed. Money is a real number with two
/// places, so a SUM over a column agrees with the report's own total, and
/// it is written from the paisa as digits, never through a float. A share
/// is a percentage, a quantity a plain number. Text is an inline string,
/// which Excel never runs as a formula, so an item named `=HYPERLINK(...)`
/// stays the name it is. Headings, subtotals and totals are bold, the
/// column titles stay on screen while the rows scroll, and the title,
/// period, any filters and the notes travel with the figures.
Uint8List reportToXlsx(ReportTable table, {String shopName = ''}) {
  final sheet = _Sheet();
  if (shopName.isNotEmpty) sheet.row([_Cell.text(shopName, bold: true)]);
  sheet.row([_Cell.text(table.title, bold: true)]);
  sheet.row([_Cell.text('Period'), _Cell.text(table.period.label)]);
  for (final f in table.filters) {
    sheet.row([_Cell.text(f)]);
  }
  sheet.row(const []);
  final headerRow = sheet.row([
    for (final c in table.columns) _Cell.text(c.title, bold: true),
  ]);
  for (final r in table.rows) {
    final strong = r.style != RowStyle.line;
    sheet.row([
      for (var i = 0; i < table.columns.length; i++)
        _Cell.of(r.cells[i], table.columns[i].kind, bold: strong),
    ]);
  }
  if (table.notes.isNotEmpty) sheet.row(const []);
  for (final note in table.notes) {
    sheet.row([_Cell.text(note)]);
  }

  final widths = [
    for (var i = 0; i < table.columns.length; i++)
      _width([
        table.columns[i].title,
        for (final r in table.rows) _plain(r.cells[i], table.columns[i].kind),
      ]),
  ];

  final archive = Archive()
    ..addFile(ArchiveFile.string('[Content_Types].xml', _contentTypes))
    ..addFile(ArchiveFile.string('_rels/.rels', _rootRels))
    ..addFile(
      ArchiveFile.string('xl/workbook.xml', _workbook(_sheetName(table.title))),
    )
    ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', _workbookRels))
    ..addFile(ArchiveFile.string('xl/styles.xml', _styles))
    ..addFile(
      ArchiveFile.string(
        'xl/worksheets/sheet1.xml',
        sheet.xml(widths: widths, frozenRows: headerRow),
      ),
    );
  // A fixed timestamp inside the zip, so the same report is the same bytes.
  return ZipEncoder().encodeBytes(archive, modified: DateTime.utc(2026));
}

/// One cell: its XML and its style.
final class _Cell {
  const _Cell._(this.body, this.style, {this.isText = false});

  /// Words, as an inline string.
  factory _Cell.text(String s, {bool bold = false}) =>
      _Cell._(_escape(s), bold ? _Style.boldText : _Style.text, isText: true);

  /// A cell of a report column of [kind].
  factory _Cell.of(Object? value, CellKind kind, {required bool bold}) =>
      switch (value) {
        null => _Cell._('', _Style.text),
        final Money m => _Cell._(
          _decimal(m.inPaisa, 2),
          bold ? _Style.boldMoney : _Style.money,
        ),
        final Qty q => _Cell._(
          _trimmed(_decimal(q.inThousandths, 3)),
          bold ? _Style.boldNumber : _Style.number,
        ),
        final int bp when kind == CellKind.percent => _Cell._(
          _decimal(bp, 4),
          bold ? _Style.boldPercent : _Style.percent,
        ),
        final int n => _Cell._('$n', bold ? _Style.boldCount : _Style.count),
        _ => _Cell.text('$value', bold: bold),
      };

  /// Escaped text for an inline string, or the digits of a number; empty
  /// for a blank.
  final String body;
  final int style;
  final bool isText;
}

/// The cell styles, by their index in `styles.xml`.
abstract final class _Style {
  static const text = 0;
  static const boldText = 1;
  static const money = 2;
  static const boldMoney = 3;
  static const number = 4;
  static const boldNumber = 5;
  static const percent = 6;
  static const boldPercent = 7;
  static const count = 8;
  static const boldCount = 9;
}

final class _Sheet {
  final _rows = <List<_Cell>>[];

  /// Adds a row and returns its number, counting from one.
  int row(List<_Cell> cells) {
    _rows.add(cells);
    return _rows.length;
  }

  String xml({required List<int> widths, required int frozenRows}) {
    final b = StringBuffer()
      ..write(_xmlHead)
      ..write(
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/'
        '2006/main">',
      )
      ..write('<sheetViews><sheetView workbookViewId="0">')
      ..write(
        '<pane ySplit="$frozenRows" topLeftCell="A${frozenRows + 1}" '
        'activePane="bottomLeft" state="frozen"/>',
      )
      ..write('</sheetView></sheetViews>');
    if (widths.isNotEmpty) {
      b.write('<cols>');
      for (var i = 0; i < widths.length; i++) {
        b.write(
          '<col min="${i + 1}" max="${i + 1}" width="${widths[i]}" '
          'customWidth="1"/>',
        );
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (var r = 0; r < _rows.length; r++) {
      b.write('<row r="${r + 1}">');
      final cells = _rows[r];
      for (var c = 0; c < cells.length; c++) {
        final cell = cells[c];
        final ref = '${_column(c)}${r + 1}';
        if (cell.body.isEmpty) {
          if (cell.style != _Style.text) {
            b.write('<c r="$ref" s="${cell.style}"/>');
          }
          continue;
        }
        if (cell.isText) {
          b.write(
            '<c r="$ref" s="${cell.style}" t="inlineStr"><is>'
            '<t xml:space="preserve">${cell.body}</t></is></c>',
          );
        } else {
          b.write('<c r="$ref" s="${cell.style}"><v>${cell.body}</v></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }
}

/// `A`, `B`, ... `Z`, `AA`: the column letters for index [i] from zero.
String _column(int i) {
  var n = i + 1;
  final letters = <int>[];
  while (n > 0) {
    letters.add(65 + (n - 1) % 26);
    n = (n - 1) ~/ 26;
  }
  return String.fromCharCodes(letters.reversed);
}

/// [units] of 10^-[places] as a decimal: `-1234.50` for -123450 paisa.
String _decimal(int units, int places) {
  final sign = units < 0 ? '-' : '';
  var scale = 1;
  for (var i = 0; i < places; i++) {
    scale *= 10;
  }
  final abs = units.abs();
  final whole = abs ~/ scale;
  final frac = (abs % scale).toString().padLeft(places, '0');
  return '$sign$whole.$frac';
}

/// `12.500` as `12.5`, and `3.000` as `3`.
String _trimmed(String decimal) {
  if (!decimal.contains('.')) return decimal;
  final cut = decimal.replaceAll(RegExp(r'0+$'), '');
  return cut.endsWith('.') ? cut.substring(0, cut.length - 1) : cut;
}

/// A cell as it reads, for sizing its column.
String _plain(Object? value, CellKind kind) => switch (value) {
  null => '',
  final Money m => m.amountOnly,
  final Qty q => q.display,
  final int bp when kind == CellKind.percent => formatBp(bp),
  _ => '$value',
};

/// A column wide enough for its longest cell, within reason.
int _width(Iterable<String> cells) {
  var longest = 8;
  for (final c in cells) {
    if (c.length > longest) longest = c.length;
  }
  return longest > 48 ? 50 : longest + 2;
}

/// Text made safe for XML: the five specials escaped, and the control
/// characters XML 1.0 forbids dropped, so a stray one in an item name
/// cannot make Excel call the whole workbook damaged.
String _escape(String s) {
  final b = StringBuffer();
  for (final unit in s.runes) {
    switch (unit) {
      case 0x26:
        b.write('&amp;');
      case 0x3C:
        b.write('&lt;');
      case 0x3E:
        b.write('&gt;');
      case 0x22:
        b.write('&quot;');
      case 0x27:
        b.write('&apos;');
      case 0x09 || 0x0A || 0x0D:
        b.writeCharCode(unit);
      default:
        if (unit >= 0x20) b.writeCharCode(unit);
    }
  }
  return b.toString();
}

/// A sheet name Excel accepts: at most 31 characters, none of `[]:*?/\`.
String _sheetName(String title) {
  final clean = title.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  final name = clean.isEmpty ? 'Report' : clean;
  return _escape(name.length > 31 ? name.substring(0, 31) : name);
}

const _xmlHead = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

const _contentTypes =
    '$_xmlHead'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/'
    'content-types">'
    '<Default Extension="rels" ContentType="application/'
    'vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/'
    'vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/'
    'vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/'
    'vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '</Types>';

const _rootRels =
    '$_xmlHead'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/officeDocument" '
    'Target="xl/workbook.xml"/>'
    '</Relationships>';

String _workbook(String sheetName) =>
    '$_xmlHead'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/'
    'main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/'
    'relationships">'
    '<sheets><sheet name="$sheetName" sheetId="1" r:id="rId1"/></sheets>'
    '</workbook>';

const _workbookRels =
    '$_xmlHead'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/'
    'relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/worksheet" '
    'Target="worksheets/sheet1.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>';

/// Ten styles: text, money (`#,##0.00`), a plain number, a percentage
/// (`0.00%`) and a whole count, each plain and bold.
const _styles =
    '$_xmlHead'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/'
    'main">'
    '<fonts count="2">'
    '<font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font>'
    '</fonts>'
    '<fills count="2"><fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill></fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/>'
    '</border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" '
    'borderId="0"/></cellStyleXfs>'
    '<cellXfs count="10">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" '
    'applyFont="1"/>'
    '<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" '
    'applyNumberFormat="1"/>'
    '<xf numFmtId="4" fontId="1" fillId="0" borderId="0" xfId="0" '
    'applyNumberFormat="1" applyFont="1"/>'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" '
    'applyFont="1"/>'
    '<xf numFmtId="10" fontId="0" fillId="0" borderId="0" xfId="0" '
    'applyNumberFormat="1"/>'
    '<xf numFmtId="10" fontId="1" fillId="0" borderId="0" xfId="0" '
    'applyNumberFormat="1" applyFont="1"/>'
    '<xf numFmtId="1" fontId="0" fillId="0" borderId="0" xfId="0" '
    'applyNumberFormat="1"/>'
    '<xf numFmtId="1" fontId="1" fillId="0" borderId="0" xfId="0" '
    'applyNumberFormat="1" applyFont="1"/>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/>'
    '</cellStyles>'
    '</styleSheet>';
