import 'package:pk_domain/pk_domain.dart';
import 'package:pk_export/pk_export.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

void main() {
  final day = ReportPeriod.day(const BusinessDate('2026-10-02'));

  DayBookEntry entry(String no, String type, int amount, {int moneyIn = 0}) =>
      DayBookEntry(
        date: const BusinessDate('2026-10-02'),
        entryNo: no,
        sourceType: type,
        narration: '',
        amount: Money.rupees(amount),
        reference: no,
        party: 'Rashid',
        moneyIn: Money.rupees(moneyIn),
      );

  group('slip', () {
    test('the day book fits the roll: figures against the edge, every line '
        'the paper\'s width', () {
      final lines = reportToSlip(
        dayBook(day, [
          entry('INV-1', 'sale', 2500, moneyIn: 2500),
          entry('INV-2', 'sale', 4000),
        ]),
        width: 32,
        shopName: 'Chishti Kiryana Store',
      );
      expect(lines.first.text, 'Chishti Kiryana Store');
      expect(lines.first.centred, isTrue);
      expect(lines[1].text, 'Day Book');
      expect(
        lines.map((l) => l.text),
        contains('Money in                2,500.00'),
      );
      expect(lines.every((l) => l.text.length <= 32), isTrue);
      final total = lines.where((l) => l.bold && l.text.contains('2 entries'));
      expect(total, hasLength(1));
    });

    test('a two-column report prints each line as label and amount', () {
      final lines = reportToSlip(
        profitAndLoss(day, [
          const AccountMovement(
            code: '4100',
            name: 'Sales',
            type: 'income',
            systemKey: 'sales',
            debit: Money.zero,
            credit: Money.rupees(2500),
          ),
        ]),
        width: 48,
      );
      expect(
        lines.map((l) => l.text),
        contains('Net profit                              2,500.00'),
      );
    });

    test('a long report prints its figures and totals and sends the rest to '
        'the PDF', () {
      final lines = reportToSlip(
        dayBook(day, [
          for (var i = 0; i < 50; i++) entry('INV-$i', 'sale', 100),
        ]),
        width: 42,
      );
      expect(lines.where((l) => l.text.startsWith('INV-')), isEmpty);
      expect(
        lines.map((l) => l.text),
        contains('50 rows: the full list is in the PDF.'),
      );
    });
  });
}
