import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

/// A payment as a page the customer can be sent (M31).
void main() {
  const shop = ReceiptShop(
    name: 'Chishti Kiryana Store',
    city: 'Lahore',
    phone: '0300-1234567',
  );

  PaymentDetail payment({String status = 'cleared', String? reason}) =>
      PaymentDetail(
        id: 'pay-1',
        paymentNo: 'RCP-2627-0007',
        direction: 'in',
        partyId: 'party-1',
        partyName: 'Rashid Traders',
        amount: const Money.rupees(5000),
        mode: 'cheque',
        paymentAccountId: 'acct-1',
        paymentAccountName: 'Cheques',
        dateLocal: '2026-08-23',
        status: status,
        chequeNo: '004512',
        chequeBank: 'Meezan',
        enteredBy: 'Malik Sahib',
        cancelReason: reason,
        settled: const [
          SettledBill(
            documentId: 'bill-1',
            docNo: 'INV-2627-0042',
            docType: 'sale_invoice',
            dateLocal: '2026-08-01',
            sequence: 42,
            amount: Money.rupees(3000),
          ),
        ],
      );

  test('a payment receipt names the bills it paid and who took it', () async {
    final text = String.fromCharCodes(
      await paymentReceiptPdf(payment(), shop: shop, compress: false),
    );

    expect(text.substring(0, 5), '%PDF-');
    for (final word in [
      'RCP-2627-0007',
      // Word by word: the page sets each word as its own run.
      'Rashid',
      'Traders',
      '5,000.00',
      'INV-2627-0042',
      '3,000.00',
      '2,000.00',
      '004512',
      'Malik',
    ]) {
      expect(text, contains(word), reason: '"$word" is not on the page');
    }
    expect(text, isNot(contains('CANCELLED')));
  });

  test('a cancelled payment prints marked, with its reason', () async {
    final text = String.fromCharCodes(
      await paymentReceiptPdf(
        payment(status: 'void', reason: 'Counted twice'),
        shop: shop,
        compress: false,
      ),
    );
    expect(text, contains('CANCELLED'));
    expect(text, contains('Counted'));
    expect(text, contains('twice'));
  });

  test('a payment receipt file is named after its number, safely', () {
    expect(paymentReceiptFileName('RCP-2627-0007'), 'RCP-2627-0007.pdf');
    expect(paymentReceiptFileName('../x/'), 'x.pdf');
  });
}
