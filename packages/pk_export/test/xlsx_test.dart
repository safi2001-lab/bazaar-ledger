import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_export/pk_export.dart';
import 'package:pk_import/pk_import.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

ReportTable _table() => ReportTable(
  id: 'sales_by_item',
  title: 'Sales by item',
  period: ReportPeriod(
    const BusinessDate('2026-09-01'),
    const BusinessDate('2026-09-30'),
  ),
  columns: const [
    ReportColumn('Item', CellKind.text),
    ReportColumn('Qty', CellKind.qty),
    ReportColumn('Sales', CellKind.money),
    ReportColumn('Margin', CellKind.percent),
    ReportColumn('Bills', CellKind.count),
  ],
  rows: [
    ReportRow([
      'Oil, 5L "Dalda" & <Sufi>',
      Qty.raw(2500),
      const Money.rupees(123456, 5),
      2000,
      3,
    ]),
    ReportRow([
      '=HYPERLINK("x")',
      Qty.units(1),
      const Money.paisa(-4050),
      -125,
      1,
    ]),
    ReportRow(['چاول', Qty.units(2), Money.zero, 0, null]),
    ReportRow([
      'Total',
      null,
      const Money.rupees(123416),
      1999,
      4,
    ], style: RowStyle.total),
  ],
  notes: const ['Sales are before tax.'],
).withFilters(const ['Party: Rashid Traders']);

void main() {
  group('xlsx', () {
    test('the workbook opens as the app\'s own import reads Excel, every '
        'figure where it was', () {
      final bytes = reportToXlsx(_table(), shopName: 'Chishti Kiryana Store');
      final rows = readSpreadsheet(bytes, fileName: 'report.xlsx').rows;
      expect(rows[0], ['Chishti Kiryana Store']);
      expect(rows[1], ['Sales by item']);
      expect(rows[2], ['Period', '2026-09-01 to 2026-09-30']);
      expect(rows[3], ['Party: Rashid Traders']);
      expect(rows[5], ['Item', 'Qty', 'Sales', 'Margin', 'Bills']);
      expect(rows[6], [
        'Oil, 5L "Dalda" & <Sufi>',
        '2.5',
        '123456.05',
        '0.2000',
        '3',
      ]);
      expect(rows[7], ['=HYPERLINK("x")', '1', '-40.50', '-0.0125', '1']);
      expect(rows[8].first, 'چاول');
      expect(rows[9].sublist(2), ['123416.00', '0.1999', '4']);
      expect(rows.last, ['Sales are before tax.']);
    });

    test('money is a number with two places, a share a percentage, and a '
        'name that looks like a formula stays text', () {
      final zip = ZipDecoder().decodeBytes(reportToXlsx(_table()));
      String part(String name) => utf8.decode(zip.findFile(name)!.content);
      final sheet = part('xl/worksheets/sheet1.xml');
      // Style 2 is money (#,##0.00), 6 a percentage, 3 money in bold.
      expect(sheet, contains('<c r="C6" s="2"><v>123456.05</v></c>'));
      expect(sheet, contains('<c r="D6" s="6"><v>0.2000</v></c>'));
      expect(sheet, contains('<c r="C9" s="3"><v>123416.00</v></c>'));
      expect(
        sheet,
        contains(
          't="inlineStr"><is><t xml:space="preserve">'
          '=HYPERLINK(&quot;x&quot;)</t>',
        ),
      );
      expect(sheet, isNot(contains('<f>')), reason: 'no formula, ever');
      expect(sheet, contains('state="frozen"'));
      expect(part('xl/styles.xml'), contains('numFmtId="4"'));
      expect(part('xl/workbook.xml'), contains('name="Sales by item"'));
      expect(part('[Content_Types].xml'), contains('spreadsheetml.sheet'));
    });

    test('the file is named for the report and its dates', () {
      expect(
        reportFileName(_table(), extension: 'xlsx'),
        'sales_by_item_2026-09-01_2026-09-30.xlsx',
      );
    });
  });

  group('filters in exports', () {
    test(
      'a narrowed report says what it was narrowed by, in every format',
      () async {
        final csv = reportToCsv(_table()).split('\r\n');
        expect(csv[2], 'Party: Rashid Traders');
        expect(csv[4], 'Item,Qty,Sales,Margin,Bills');
        final pdf = String.fromCharCodes(
          await reportToPdf(_table(), shopName: 'Chishti', compress: false),
        );
        // The page sets each word on its own, as it does every line.
        expect(pdf, contains('[(Party:)]'));
        expect(pdf, contains('[(Traders)]'));
      },
    );
  });
}
