import 'dart:convert';

import 'package:pk_domain/pk_domain.dart';
import 'package:pk_export/pk_export.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

ReportTable _table({List<ReportRow>? rows, List<String> notes = const []}) =>
    ReportTable(
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
      ],
      rows:
          rows ??
          [
            ReportRow([
              'Oil, 5L "Dalda"',
              Qty.raw(2500),
              const Money.rupees(123456, 5),
              2000,
            ]),
            ReportRow([
              'Total',
              null,
              const Money.rupees(-40),
              -125,
            ], style: RowStyle.total),
          ],
      notes: notes,
    );

void main() {
  group('csv', () {
    test('money is a plain number a spreadsheet can add up', () {
      final lines = reportToCsv(_table()).split('\r\n');
      expect(lines[0], 'Sales by item');
      expect(lines[1], 'Period,2026-09-01 to 2026-09-30');
      expect(lines[3], 'Item,Qty,Sales,Margin');
      expect(lines[4], '"Oil, 5L ""Dalda""",2.5,123456.05,20.00%');
      expect(lines[5], 'Total,,-40.00,-1.25%');
    });

    test('a name that looks like a formula stays text', () {
      final csv = reportToCsv(
        _table(
          rows: [
            ReportRow(['=HYPERLINK("x")', Qty.units(1), Money.zero, 0]),
          ],
        ),
      );
      expect(csv, contains('"\'=HYPERLINK(""x"")",1,0.00,0.00%'));
    });

    test('the notes come after the table', () {
      final csv = reportToCsv(_table(notes: ['Before tax.']));
      expect(csv.trimRight().split('\r\n').last, 'Before tax.');
    });

    test('the file opens in Excel with Urdu intact', () {
      final bytes = reportToCsvBytes(
        _table(
          rows: [
            ReportRow(['چینی', Qty.units(1), Money.zero, 0]),
          ],
        ),
      );
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
      expect(utf8.decode(bytes.skip(3).toList()), contains('چینی'));
    });

    test('the file is named for the report and its dates', () {
      expect(
        reportFileName(_table()),
        'sales_by_item_2026-09-01_2026-09-30.csv',
      );
    });
  });
}
