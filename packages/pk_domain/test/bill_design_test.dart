import 'dart:typed_data';

import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// How a shop's bills look, and what goes on them (M51), without a
/// database: the design as it is kept, and the rules that dress a receipt.
void main() {
  group('the bill design', () {
    test('is kept and read back exactly', () {
      const design = BillDesign(
        theme: BillTheme.taxInvoice,
        accent: BillAccent.maroon,
        pageSize: BillPageSize.a4,
        showPreviousBalance: false,
        qrOnThermal: true,
        footerLines: ['شکریہ! پھر تشریف لائیں', 'Goods once sold'],
      );
      expect(BillDesign.fromJson(design.toJson()), design);
    });

    test('anything it cannot read falls back, and never fails a bill', () {
      for (final junk in [null, '', 'not json', '[1,2]', '{"theme": 7}']) {
        expect(BillDesign.fromJson(junk), const BillDesign(), reason: junk);
      }
      final partial = BillDesign.fromJson(
        '{"theme":"modern","accent":"chartreuse","page":"a3"}',
      );
      expect(partial.theme, BillTheme.modern);
      expect(partial.accent, BillAccent.ink);
      expect(partial.pageSize, BillPageSize.a5);
      expect(partial.showPreviousBalance, isTrue);
      expect(partial.footerLines, BillDesign.defaultFooter);
    });

    test('a footer is trimmed, blank lines dropped, four lines at most', () {
      final tidy = BillDesign.tidyFooter([
        '  Shukriya  ',
        '',
        '   ',
        'two',
        'three',
        'four',
        'five',
      ]);
      expect(tidy, ['Shukriya', 'two', 'three', 'four']);
      expect(
        BillDesign.tidyFooter(['x' * 200]).single.length,
        BillDesign.footerLineMax,
      );
    });
  });

  group('dressing a bill', () {
    ReceiptData base({
      List<String> footer = const [BillDesign.defaultThanks],
      Money balance = const Money.rupees(4525),
    }) => ReceiptData(
      shop: const ReceiptShop(name: 'Chishti Kiryana Store'),
      docNo: 'INV-1',
      dateTimeLabel: '02-10-2026',
      cashierName: 'Malik',
      customerName: 'Rashid Traders',
      lines: const [
        ReceiptLine(
          name: 'Cooking Oil 5L',
          qtyDisplay: '2',
          unitCode: 'pcs',
          rate: Rate.rupees(2450),
          amount: Money.rupees(4900),
        ),
      ],
      subtotal: const Money.rupees(4900),
      total: const Money.rupees(4900),
      tenders: const [],
      paid: const Money.rupees(375),
      balance: balance,
      change: Money.zero,
      footerLines: footer,
    );

    BillExtras extras({
      String docType = 'sale_invoice',
      String? partyId = 'party-1',
      KhataAtBill? khata = const KhataAtBill(
        before: Money.rupees(1000),
        thisBill: Money.rupees(4525),
      ),
      List<ReceiptLineTax> taxes = const [],
    }) => BillExtras(
      docType: docType,
      partyId: partyId,
      partyPhone: '0300-4471203',
      partyAddress: 'Shop 5, Shah Alam',
      khata: khata,
      lineTaxes: taxes,
      transport: const ReceiptTransport(biltyNo: 'BT-1'),
    );

    test('the shop\'s footer replaces the thank-you line and nothing else', () {
      final dressed = dressBill(
        base(
          footer: const [
            'Valid for 7 days',
            BillDesign.defaultThanks,
            'Bazaar Ledger app se banaya gaya',
          ],
        ),
        extras: extras(),
        design: const BillDesign(
          footerLines: ['Bika hua maal wapas nahi hoga', 'شکریہ'],
        ),
      );
      expect(dressed.footerLines, [
        'Valid for 7 days',
        'Bika hua maal wapas nahi hoga',
        'شکریہ',
        'Bazaar Ledger app se banaya gaya',
      ]);

      // A purchase bill shown back has no thank-you line, and gets no
      // footer of the shop's own.
      final purchase = dressBill(
        base(footer: const ['Supplier bill: PRM/771']),
        extras: extras(docType: 'purchase_bill'),
        design: const BillDesign(footerLines: ['Shop footer']),
      );
      expect(purchase.footerLines, ['Supplier bill: PRM/771']);
    });

    test('the khata block goes only on a sale to a named customer, when '
        'there is something to say and the shop wants it', () {
      final shown = dressBill(base(), extras: extras());
      expect(shown.khata!.before, const Money.rupees(1000));
      expect(shown.khata!.thisBill, const Money.rupees(4525));
      expect(shown.khata!.after, const Money.rupees(5525));

      expect(
        dressBill(base(), extras: extras(partyId: null)).khata,
        isNull,
        reason: 'a walk-in has no khata',
      );
      expect(
        dressBill(base(), extras: extras(docType: 'quotation')).khata,
        isNull,
        reason: 'a quotation is owed by nobody',
      );
      expect(
        dressBill(
          base(),
          extras: extras(),
          design: const BillDesign(showPreviousBalance: false),
        ).khata,
        isNull,
        reason: 'the owner turned it off',
      );
      expect(
        dressBill(
          base(balance: Money.zero),
          extras: extras(
            khata: const KhataAtBill(before: Money.zero, thisBill: Money.zero),
          ),
        ).khata,
        isNull,
        reason: 'a regular who owes nothing gets no 0.00 / 0.00 / 0.00',
      );
    });

    test('the buyer\'s phone goes on the transporter\'s copy only', () {
      final plain = dressBill(base(), extras: extras());
      final transporter = dressBill(
        base(),
        extras: extras(),
        copy: ReceiptCopy.transporter,
      );
      expect(plain.customerPhone, isNull);
      expect(transporter.customerPhone, '0300-4471203');
      expect(transporter.customerAddress, 'Shop 5, Shah Alam');
      expect(transporter.transport.biltyNo, 'BT-1');
      expect(transporter.showsMoney, isFalse);
    });

    test('line taxes are read in only when every line has one', () {
      const tax = ReceiptLineTax(
        valueExclTax: Money.rupees(4900),
        salesTax: Money.rupees(882),
        rateBp: 1800,
      );
      expect(
        dressBill(base(), extras: extras(taxes: const [tax])).lines.single.tax,
        tax,
      );
      expect(
        dressBill(
          base(),
          extras: extras(taxes: const [tax, tax]),
        ).lines.single.tax,
        isNull,
        reason: 'a tax column shifted by one line is worse than none',
      );
    });

    test('the pictures are the ones handed in, and nothing else', () {
      final logo = Uint8List.fromList([1, 2, 3]);
      final qr = Uint8List.fromList([4, 5, 6]);
      final dressed = dressBill(
        base(),
        extras: extras(),
        logo: logo,
        paymentQr: qr,
      );
      expect(dressed.shop.logoImage, logo);
      expect(dressed.paymentQr, qr);
      expect(dressed.bankQr, isNull, reason: 'no dots unless handed dots');
      final bare = dressBill(base(), extras: extras());
      expect(bare.shop.logoImage, isNull);
      expect(bare.paymentQr, isNull);
    });

    test('the message beside a transporter\'s copy names no amount', () {
      final message = transportMessage(
        dressBill(base(), extras: extras(), copy: ReceiptCopy.transporter),
      );
      expect(message, contains('INV-1'));
      expect(message, contains('Rashid Traders'));
      expect(message, contains('Bilty no: BT-1'));
      expect(message, isNot(contains('Rs')));
      expect(message, isNot(contains('4,900')));
      expect(message, isNot(contains('4,525')));
    });
  });
}
