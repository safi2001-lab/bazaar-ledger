import 'package:pk_domain/pk_domain.dart';
import 'package:pk_export/pk_export.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

void main() {
  group('pdf', () {
    final table = profitAndLoss(
      ReportPeriod(
        const BusinessDate('2026-09-01'),
        const BusinessDate('2026-09-30'),
      ),
      [
        const AccountMovement(
          code: '4100',
          name: 'Sales',
          type: 'income',
          systemKey: 'sales',
          debit: Money.zero,
          credit: Money.rupees(2500),
        ),
        const AccountMovement(
          code: '6100',
          name: 'Rent',
          type: 'expense',
          systemKey: 'rent',
          debit: Money.rupees(500),
          credit: Money.zero,
        ),
      ],
    );

    test('a report is a page headed with the shop and the period', () async {
      final bytes = await reportToPdf(
        table,
        shopName: 'Chishti Kiryana Store',
        compress: false,
      );
      final text = String.fromCharCodes(bytes);
      expect(text, startsWith('%PDF'));
      expect(text, contains('Chishti Kiryana Store'));
      expect(text, contains('Profit and Loss'));
      expect(text, contains('2026-09-01 to 2026-09-30'));
      // Table cells are set a word at a time.
      for (final word in ['Net', 'profit', 'Rent', '2,000.00', 'Page']) {
        expect(text, contains(word), reason: '"$word" is not on the page');
      }
    });

    test('the file is named for the report and its dates', () {
      expect(
        reportFileName(table, extension: 'pdf'),
        'profit_and_loss_2026-09-01_2026-09-30.pdf',
      );
    });
  });
}
