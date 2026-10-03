import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

/// M61 on paper: the tax invoice of a service paid part by card and part in
/// cash says both rates it was taxed at, and how the line was split between
/// them, rather than the higher rate beside an amount that blends the two.
void main() {
  const bridal = ReceiptLine(
    name: 'Bridal makeup',
    qtyDisplay: '1',
    unitCode: 'pcs',
    rate: Rate.rupees(1000),
    amount: Money.rupees(1000),
    tax: ReceiptLineTax(
      valueExclTax: Money.rupees(1000),
      salesTax: Money.paisa(12297),
      rateBp: 1600,
      hsCode: '9802.1000',
      rateParts: [
        ReceiptRatePart(
          code: 'PRA_STD',
          rateBp: 1600,
          base: Money.paisa(53704),
        ),
        ReceiptRatePart(
          code: 'PRA_CARD',
          rateBp: 800,
          base: Money.paisa(46296),
        ),
      ],
    ),
  );

  const bill = ReceiptData(
    shop: ReceiptShop(name: 'Lahore Hair Studio'),
    docNo: 'INV-2627-0009',
    dateTimeLabel: '03-10-2026  6:15 PM',
    cashierName: 'Bilal',
    lines: [bridal],
    subtotal: Money.rupees(1000),
    tax: Money.paisa(12297),
    total: Money.paisa(112297),
    tenders: [
      ReceiptTender(label: 'Card', amount: Money.rupees(500)),
      ReceiptTender(label: 'Cash', amount: Money.paisa(62297)),
    ],
    paid: Money.paisa(112297),
    balance: Money.zero,
    change: Money.zero,
    serviceTaxes: [
      ReceiptTaxLine(label: 'PRA 16%', amount: Money.paisa(8593)),
      ReceiptTaxLine(label: 'PRA 8% (card)', amount: Money.paisa(3704)),
    ],
  );

  group('a split service on a tax invoice', () {
    test(
      'the PDF says both rates in the Rate column, and the split under the line',
      () async {
        final text = String.fromCharCodes(
          await billPdf(
            bill,
            design: const BillDesign(theme: BillTheme.taxInvoice),
            compress: false,
          ),
        );
        // The PDF sets each word on its own.
        expect(text, contains('[(16%)]TJ'));
        expect(text, contains('[(/)]TJ'));
        expect(text, contains('[(537.04,)]TJ'), reason: 'the split note');
        expect(text, contains('[(462.96)]TJ'), reason: 'the split note');
      },
    );

    test('a bill not printed as a tax invoice carries no split note', () async {
      final text = String.fromCharCodes(
        await billPdf(bill, design: const BillDesign(), compress: false),
      );
      expect(text, isNot(contains('[(537.04,)]TJ')));
    });
  });
}
