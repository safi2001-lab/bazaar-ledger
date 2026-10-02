import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// A bill sent again, and the search that finds it (M30).
void main() {
  ReceiptData receipt({
    String docTitle = 'Invoice',
    String? customer = 'Rashid Traders',
    Money paid = const Money.rupees(1000),
    Money balance = const Money.rupees(4525),
  }) => ReceiptData(
    shop: const ReceiptShop(name: 'Chishti Kiryana Store'),
    docNo: 'INV-2627-0042',
    docTitle: docTitle,
    dateTimeLabel: '01-10-2026  2:05 PM',
    customerName: customer,
    cashierName: 'Malik Sahib',
    lines: const [],
    subtotal: const Money.rupees(5525),
    total: const Money.rupees(5525),
    tenders: const [],
    paid: paid,
    balance: balance,
    change: Money.zero,
  );

  group('the message beside a bill', () {
    test('says whose bill, which one, what day, and what is still owed', () {
      final message = billMessage(receipt());
      expect(message, startsWith('Assalam-o-Alaikum Rashid Traders,'));
      expect(message, contains('Chishti Kiryana Store se bill INV-2627-0042'));
      expect(message, contains('01-10-2026'));
      expect(message, contains('Kul: Rs 5,525.00'));
      expect(message, contains('Ada kiye: Rs 1,000.00'));
      expect(message, contains('Baqi: Rs 4,525.00'));
    });

    test('a bill paid in full says nothing is owed by not asking', () {
      final message = billMessage(
        receipt(paid: const Money.rupees(5525), balance: Money.zero),
      );
      expect(message, contains('Ada kiye: Rs 5,525.00'));
      expect(message, isNot(contains('Baqi')));
    });

    test('a quotation is not a bill and has nothing paid against it', () {
      final message = billMessage(
        receipt(docTitle: 'Quotation', paid: Money.zero, balance: Money.zero),
      );
      expect(message, contains('se quotation INV-2627-0042'));
      expect(message, contains('Kul: Rs 5,525.00'));
      expect(message, isNot(contains('Ada kiye')));
    });

    test('a cancelled bill says so and asks for nothing', () {
      final message = billMessage(receipt().copyWith(isCancelled: true));
      expect(message, contains('mansookh'));
      expect(message, isNot(contains('Baqi')));
      expect(message, isNot(contains('Ada kiye')));
    });

    test('a walk-in is greeted without a name', () {
      final message = billMessage(receipt(customer: null));
      expect(message, startsWith('Assalam-o-Alaikum,'));
    });
  });

  group('what a search could mean', () {
    test('an amount, however it is written', () {
      for (final typed in ['5525', '5,525', 'Rs 5525', 'rs. 5,525']) {
        expect(SaleSearch.parse(typed).paisa, (552500, 552599), reason: typed);
      }
      expect(SaleSearch.parse('5525.5').paisa, (552550, 552550));
      expect(SaleSearch.parse('5525.05').paisa, (552505, 552505));
      expect(SaleSearch.parse('Rashid').paisa, isNull);
      expect(SaleSearch.parse('INV-0042').paisa, isNull);
    });

    test('a phone number, without the 0 or the 92 in front', () {
      for (final typed in [
        '0300-4471203',
        '+92 300 4471203',
        '923004471203',
        '3004471203',
      ]) {
        expect(
          SaleSearch.parse(typed).phoneDigits,
          '3004471203',
          reason: typed,
        );
      }
      expect(SaleSearch.parse('4471').phoneDigits, '4471');
      expect(
        SaleSearch.parse('012').phoneDigits,
        isNull,
        reason: 'too short to be anybody\'s number',
      );
      expect(SaleSearch.parse('Rashid').phoneDigits, isNull);
    });

    test('two filters that say the same thing are the same filter', () {
      expect(
        const SaleFilter(query: ' rashid '),
        const SaleFilter(query: 'rashid'),
      );
      expect(
        SaleFilter.none.between(const BusinessDate('2026-10-01'), null),
        isNot(SaleFilter.none),
      );
      expect(SaleFilter.none.isNone, isTrue);
      expect(
        SaleFilter.none.copyWith(standing: SaleStanding.udhaar).isNone,
        isFalse,
      );
    });
  });
}
