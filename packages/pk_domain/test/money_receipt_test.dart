import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// The customer's receipt when money moves, and the design that now keeps
/// a till slip and a layout for each paper (M70), without a database.
void main() {
  group('the receipt message', _messageTests);
  group('the design kept', _designTests);
}

const _sale = MoneyMoved(
  kind: MoneyMove.sale,
  documentId: 'd1',
  number: 'INV-2627-0042',
  amount: Money.rupees(5525),
  paid: Money.rupees(1000),
);

const _received = MoneyMoved(
  kind: MoneyMove.received,
  paymentId: 'p1',
  number: 'RCPT-2627-0007',
  amount: Money.rupees(3000),
);

String _say(
  MoneyMoved event, {
  Money balance = const Money.rupees(1525),
  ReminderLanguage language = ReminderLanguage.romanUrdu,
}) => moneyReceiptMessage(
  event,
  name: 'Rashid Traders',
  shop: 'Chishti Kiryana Store',
  balanceNow: balance,
  language: language,
);

void _messageTests() {
  test('a bill says what was billed, what was paid and the khata now, in '
      'each of the three languages', () {
    expect(
      _say(_sale),
      'Assalam-o-Alaikum Rashid Traders,\n'
      'Chishti Kiryana Store: bill INV-2627-0042, kul Rs 5,525.00.\n'
      'Ada kiye: Rs 1,000.00.\n'
      'Aap ka kul baqaya ab: Rs 1,525.00.\n'
      'Shukriya.',
    );
    final english = _say(_sale, language: ReminderLanguage.english);
    for (final words in [
      'bill INV-2627-0042, total Rs 5,525.00',
      'Paid: Rs 1,000.00',
      'Your balance now: Rs 1,525.00',
      'Thank you.',
    ]) {
      expect(english, contains(words));
    }
    final urdu = _say(_sale, language: ReminderLanguage.urdu);
    for (final words in [
      'السلام علیکم Rashid Traders',
      'بل INV-2627-0042',
      '5,525.00 روپے',
      'ادا کیے: 1,000.00 روپے',
      'آپ کا کل بقایا اب: 1,525.00 روپے',
      'شکریہ',
    ]) {
      expect(urdu, contains(words));
    }
    expect(urdu, isNot(contains('Rs ')), reason: 'rupees in its own script');
  });

  test('money taken says so, a cheque as a cheque, and a clear khata is '
      'said to be clear', () {
    expect(
      _say(_received),
      contains('Rs 3,000.00 wusool ho gaye, raseed RCPT-2627-0007'),
    );
    final cheque = MoneyMoved(
      kind: MoneyMove.received,
      paymentId: 'p2',
      number: 'RCPT-2627-0008',
      amount: const Money.rupees(3000),
      byCheque: true,
    );
    expect(_say(cheque), contains('Rs 3,000.00 ka cheque mil gaya'));
    expect(_say(_received, balance: Money.zero), contains('hisaab saaf hai'));
    expect(
      _say(_received, balance: const Money.rupees(-500)),
      contains('jama: Rs 500.00'),
      reason: 'an advance is the customer\'s money, not a minus they owe',
    );
  });

  test('goods back say what was handed back; a supplier is told what the '
      'shop still owes them', () {
    final back = _say(
      const MoneyMoved(
        kind: MoneyMove.saleReturn,
        documentId: 'r1',
        number: 'SR-2627-0003',
        amount: Money.rupees(800),
        paid: Money.rupees(300),
      ),
    );
    expect(back, contains('maal wapas liya, SR-2627-0003, Rs 800.00'));
    expect(back, contains('Wapas diye: Rs 300.00'));

    const paid = MoneyMoved(
      kind: MoneyMove.paidSupplier,
      paymentId: 'p9',
      number: 'PV-2627-0011',
      amount: Money.rupees(20000),
    );
    expect(
      _say(paid, balance: const Money.rupees(15000)),
      allOf(
        contains('Rs 20,000.00 ada kiye, voucher PV-2627-0011'),
        contains('Hamara baqaya ab: Rs 15,000.00'),
      ),
    );
    expect(_say(paid, balance: Money.zero), contains('Hisaab saaf.'));
  });

  test('a choice is kept by its name, and anything else is the shop\'s', () {
    for (final offer in ReceiptOffer.values) {
      expect(ReceiptOffer.tryParse(offer.name), offer);
    }
    for (final junk in [null, '', 'sometimes']) {
      expect(ReceiptOffer.tryParse(junk), isNull);
    }
    expect(receiptOfferPartyKey('p1'), 'receipt.offer.party.p1');
  });
}

void _designTests() {
  test('the slip and each paper\'s layout are kept and read back exactly', () {
    const design = BillDesign(
      theme: BillTheme.ruled,
      accent: BillAccent.green,
      slip: ReceiptSlip.bigTotal,
      documentThemes: {
        'quotation': BillTheme.elegant,
        'delivery_challan': BillTheme.landscape,
      },
    );
    final kept = BillDesign.fromJson(design.toJson());
    expect(kept, design);
    expect(kept.themeFor('sale_invoice'), BillTheme.ruled);
    expect(kept.themeFor('quotation'), BillTheme.elegant);
    expect(kept.themeFor('purchase_order'), BillTheme.ruled);
    expect(kept.forDocument('delivery_challan').theme, BillTheme.landscape);
    expect(kept.forDocument('delivery_challan').slip, ReceiptSlip.bigTotal);
    expect(kept.forDocument(null), same(kept));
  });

  test('a design kept before M70, or one a later version wrote, still '
      'reads', () {
    final old = BillDesign.fromJson(
      '{"theme":"modern","accent":"blue","page":"a4"}',
    );
    expect(old.slip, ReceiptSlip.standard);
    expect(old.documentThemes, isEmpty);
    final later = BillDesign.fromJson(
      '{"theme":"vintage","slip":"tiny",'
      '"themes":{"quotation":"vintage","sale_order":"minimal",'
      '"delivery_challan":"minimal"}}',
    );
    expect(later.theme, BillTheme.classic);
    expect(later.slip, ReceiptSlip.standard);
    expect(later.documentThemes, {'delivery_challan': BillTheme.minimal});
  });

  test('only the tax invoice and the landscape page carry s.23\'s '
      'particulars', () {
    expect(
      [
        for (final t in BillTheme.values)
          if (t.carriesTaxParticulars) t,
      ],
      [BillTheme.taxInvoice, BillTheme.landscape],
    );
  });

  test('dressing a bill carries the shop\'s slip to the till roll', () {
    const base = ReceiptData(
      shop: ReceiptShop(name: 'Chishti Kiryana Store'),
      docNo: 'INV-1',
      dateTimeLabel: '02-10-2026',
      cashierName: 'Malik',
      lines: [],
      subtotal: Money.zero,
      total: Money.zero,
      tenders: [],
      paid: Money.zero,
      balance: Money.zero,
      change: Money.zero,
    );
    expect(dressBill(base).slip, ReceiptSlip.standard);
    expect(
      dressBill(base, design: const BillDesign(slip: ReceiptSlip.compact)).slip,
      ReceiptSlip.compact,
    );
  });
}
