import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A workbook as Excel writes one: shared strings, numbers as Excel keeps
/// them, a sheet named something other than sheet1, and an empty row left
/// out of the file the way Excel leaves it out.
Uint8List xlsxOf(List<List<Object>> rows) {
  final strings = <String>[];
  String column(int c) => c < 26
      ? String.fromCharCode(65 + c)
      : 'A${String.fromCharCode(65 + c - 26)}';
  String cell(int r, int c, Object v) {
    final ref = '${column(c)}${r + 1}';
    if (v is num) return '<c r="$ref"><v>$v</v></c>';
    strings.add('$v');
    return '<c r="$ref" t="s"><v>${strings.length - 1}</v></c>';
  }

  final sheet = StringBuffer(
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<sheetData>',
  );
  for (final (r, row) in rows.indexed) {
    if (row.every((v) => v == '')) continue;
    sheet.write('<row r="${r + 1}">');
    for (final (c, v) in row.indexed) {
      if (v == '') continue;
      sheet.write(cell(r, c, v));
    }
    sheet.write('</row>');
  }
  sheet.write('</sheetData></worksheet>');
  final shared = StringBuffer('<sst>');
  for (final s in strings) {
    shared.write('<si><t>${const HtmlEscape().convert(s)}</t></si>');
  }
  shared.write('</sst>');

  final archive = Archive();
  void add(String name, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  add(
    'xl/workbook.xml',
    '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="Export" sheetId="1" r:id="rId3"/></sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<Relationships><Relationship Id="rId3" Target="worksheets/export.xml"/></Relationships>',
  );
  add('xl/sharedStrings.xml', shared.toString());
  add('xl/worksheets/export.xml', sheet.toString());
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
