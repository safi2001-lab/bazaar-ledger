import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// A sheet read into rows of text, as the shopkeeper typed it.
final class SheetRows {
  const SheetRows(this.rows);

  final List<List<String>> rows;
}

/// Thrown when a file cannot be read as a spreadsheet, in words.
final class ImportRefused implements Exception {
  const ImportRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Reads the first sheet of an `.xlsx` workbook, or a `.csv` file.
SheetRows readSpreadsheet(Uint8List bytes, {required String fileName}) {
  final name = fileName.toLowerCase();
  if (name.endsWith('.xls')) {
    throw const ImportRefused(
      'This is an old .xls file. Open it in Excel and save it as .xlsx or '
      '.csv, then import that.',
    );
  }
  final isZip = bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4b;
  if (name.endsWith('.xlsx') || isZip) return _readXlsx(bytes);
  return readCsv(_text(bytes));
}

String _text(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // Excel on Windows saves CSV in the machine's code page, not UTF-8.
    return latin1.decode(bytes);
  }
}

/// Reads CSV text: quoted fields, doubled quotes, commas or semicolons or
/// tabs, whichever the first line uses most.
SheetRows readCsv(String text) {
  var s = text;
  if (s.startsWith('﻿')) s = s.substring(1);
  final firstLine = s.split(RegExp(r'\r?\n')).first;
  final delimiter = [',', ';', '\t'].reduce(
    (a, b) => firstLine.split(a).length >= firstLine.split(b).length ? a : b,
  );

  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == delimiter) {
      row.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
    } else {
      field.write(c);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return SheetRows(rows);
}

SheetRows _readXlsx(Uint8List bytes) {
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(bytes);
  } on Object {
    throw const ImportRefused('This file is not an Excel workbook.');
  }
  String? read(String path) {
    final file = zip.findFile(path);
    if (file == null) return null;
    return utf8.decode(file.content);
  }

  XmlDocument parse(String xml) {
    try {
      return XmlDocument.parse(xml);
    } on Object {
      throw const ImportRefused('This workbook is damaged.');
    }
  }

  final workbook = read('xl/workbook.xml');
  if (workbook == null) {
    throw const ImportRefused('This file is not an Excel workbook.');
  }
  final firstSheet = parse(workbook).findAllElements('sheet').firstOrNull;
  if (firstSheet == null) {
    throw const ImportRefused('This workbook has no sheets.');
  }
  final relId = firstSheet.attributes
      .where((a) => a.name.local == 'id')
      .firstOrNull
      ?.value;
  var sheetPath = 'xl/worksheets/sheet1.xml';
  final rels = read('xl/_rels/workbook.xml.rels');
  if (relId != null && rels != null) {
    for (final r in parse(rels).findAllElements('Relationship')) {
      if (r.getAttribute('Id') != relId) continue;
      final target = r.getAttribute('Target') ?? '';
      sheetPath = target.startsWith('/')
          ? target.substring(1)
          : 'xl/${target.replaceFirst(RegExp(r'^\./'), '')}';
    }
  }

  final shared = <String>[];
  final sharedXml = read('xl/sharedStrings.xml');
  if (sharedXml != null) {
    for (final si in parse(sharedXml).findAllElements('si')) {
      shared.add(si.findAllElements('t').map((t) => t.innerText).join());
    }
  }

  final sheetXml = read(sheetPath);
  if (sheetXml == null) {
    throw const ImportRefused('This workbook has no sheets.');
  }
  final rows = <List<String>>[];
  for (final r in parse(sheetXml).findAllElements('row')) {
    final cells = <int, String>{};
    var next = 0;
    for (final c in r.findElements('c')) {
      final ref = c.getAttribute('r');
      final column = ref == null ? next : _columnIndex(ref);
      next = column + 1;
      final type = c.getAttribute('t');
      final value = c.getElement('v')?.innerText ?? '';
      cells[column] = switch (type) {
        's' => shared.elementAtOrNull(int.tryParse(value) ?? -1) ?? '',
        'inlineStr' => c.findAllElements('t').map((t) => t.innerText).join(),
        'b' => value == '1' ? 'TRUE' : 'FALSE',
        _ => value,
      };
    }
    if (cells.isEmpty) {
      rows.add(const []);
      continue;
    }
    final width = cells.keys.reduce((a, b) => a > b ? a : b) + 1;
    rows.add([for (var i = 0; i < width; i++) cells[i] ?? '']);
  }
  return SheetRows(rows);
}

/// `B7` → 1, `AA3` → 26.
int _columnIndex(String ref) {
  var n = 0;
  for (final unit in ref.codeUnits) {
    if (unit < 65 || unit > 90) break;
    n = n * 26 + (unit - 64);
  }
  return n - 1;
}
