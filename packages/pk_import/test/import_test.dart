import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pk_import/pk_import.dart';
import 'package:pk_money/pk_money.dart';
import 'package:test/test.dart';

/// A workbook as Excel writes one: shared strings, numbers as Excel keeps
/// them, a sheet named something other than sheet1.
Uint8List _xlsx(List<List<Object>> rows) {
  final strings = <String>[];
  String cell(int r, int c, Object v) {
    final ref = '${String.fromCharCode(65 + c)}${r + 1}';
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
        '<sheets><sheet name="Items" sheetId="1" r:id="rId3"/></sheets></workbook>',
  );
  add(
    'xl/_rels/workbook.xml.rels',
    '<Relationships><Relationship Id="rId3" Target="worksheets/items.xml"/></Relationships>',
  );
  add('xl/sharedStrings.xml', shared.toString());
  add('xl/worksheets/items.xml', sheet.toString());
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  group('import', () {
    test('an Excel item list is read with prices and stock', () {
      final sheet = readSpreadsheet(
        _xlsx([
          [
            'Item name*',
            'Item code',
            'Sale price',
            'Purchase price',
            'Opening quantity',
            'Unit',
          ],
          ['Sugar 1kg', 'SG1', 160, 140, 25, 'kg'],
          ['Tapal Danedar 95g', '', 159.99999999999997, 120.5, '', 'pcs'],
        ]),
        fileName: 'items.xlsx',
      );
      final plan = planItems(sheet);
      expect(plan.problems, isEmpty);
      expect(plan.rows, hasLength(2));
      final (line, sugar) = plan.rows.first;
      expect(line, 2);
      expect(sugar.name, 'Sugar 1kg');
      expect(sugar.code, 'SG1');
      expect(sugar.salePrice, const Money.rupees(160));
      expect(sugar.purchasePrice, const Money.rupees(140));
      expect(sugar.openingStock, Qty.units(25));
      expect(sugar.unit, 'kg');
      final tapal = plan.rows.last.$2;
      expect(tapal.salePrice, const Money.rupees(160));
      expect(tapal.purchasePrice, Money.parse('120.50'));
      expect(tapal.openingStock, Qty.zero);
      expect(plan.columns['salePrice'], 'Sale price');
    });

    test('rows that cannot come in are named, and the rest still do', () {
      final plan = planItems(
        readCsv(
          'Name,Price,Stock\n'
          'Ghee 1kg,650,10\n'
          ',100,1\n'
          'Rice 5kg,,4\n'
          'Ghee 1kg,640,2\n'
          'Daal,300,lots\n'
          '\n'
          'Atta 10kg,"1,250",3\n',
        ),
      );
      expect(plan.rows.map((r) => r.$2.name), ['Ghee 1kg', 'Atta 10kg']);
      expect(plan.rows.last.$2.salePrice, const Money.rupees(1250));
      expect(plan.problems.map((p) => p.line), [3, 4, 5, 6]);
      expect(plan.problems[1].message, contains('no sale price'));
      expect(plan.problems[2].message, contains('twice'));
    });

    test('a khata list is read with balances, suppliers and phones', () {
      final plan = planParties(
        readCsv(
          '﻿Party Name;Phone No.;Opening Balance;Party Type\r\n'
          'Rashid Traders;0300-1234567;4500;Supplier\r\n'
          '"Bilal ""Chacha"" Store";0321 7654321;-200;Customer\r\n'
          'Naveed;;;\r\n',
        ),
      );
      expect(plan.problems, isEmpty);
      final [(_, rashid), (_, bilal), (_, naveed)] = plan.rows;
      expect(rashid.isSupplier, isTrue);
      expect(rashid.balance, const Money.rupees(4500));
      expect(rashid.phone, '0300-1234567');
      expect(bilal.name, 'Bilal "Chacha" Store');
      expect(bilal.isSupplier, isFalse);
      expect(bilal.balance, const Money.rupees(-200));
      expect(naveed.balance, Money.zero);
    });

    test('a sheet with no headings it knows is refused in words', () {
      expect(
        () => planItems(readCsv('a,b,c\n1,2,3\n')),
        throwsA(
          isA<ImportRefused>().having(
            (e) => e.reason,
            'reason',
            contains('Sale price'),
          ),
        ),
      );
      expect(
        () => readSpreadsheet(Uint8List(8), fileName: 'old.xls'),
        throwsA(
          isA<ImportRefused>().having(
            (e) => e.reason,
            'reason',
            contains('.xlsx'),
          ),
        ),
      );
    });

    test('numbers are read as Excel keeps them, to the paisa', () {
      expect(excelNumber('159.99999999999997', 2), '160.00');
      expect(excelNumber('120.505', 2), '120.51');
      expect(excelNumber('1.5E3', 2), '1500.00');
      expect(excelNumber('2.5E-2', 3), '0.025');
      expect(excelNumber('7', 0), '7');
      expect(excelNumber('-0.001', 2), '0.00');
      expect(excelNumber('Rs 1,250', 2), 'Rs 1,250');
    });
  });
}
