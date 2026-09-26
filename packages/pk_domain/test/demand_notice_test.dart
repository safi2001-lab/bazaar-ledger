import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// The demand notice drawn up after a cheque bounces.
///
/// Every figure in it is one a court will read against the cheque and the
/// bank's return memo, so each is asserted exactly: the amount in figures
/// and in words, the dates, and the deadline to serve it.
void main() {
  group('an amount in words', () {
    test('counts in thousands, lakhs and crores', () {
      expect(
        rupeesInWords(const Money.rupees(45000)),
        'Rupees Forty-Five Thousand only',
      );
      expect(
        rupeesInWords(const Money.rupees(450000)),
        'Rupees Four Lakh Fifty Thousand only',
      );
      expect(
        rupeesInWords(const Money.rupees(12345678)),
        'Rupees One Crore Twenty-Three Lakh Forty-Five Thousand Six Hundred '
        'Seventy-Eight only',
      );
    });

    test('says the paisa when there are any', () {
      expect(
        rupeesInWords(Money.paisa(100050)),
        'Rupees One Thousand and Fifty Paisa only',
      );
    });

    test('says round figures without stray words', () {
      expect(rupeesInWords(const Money.rupees(100000)), 'Rupees One Lakh only');
      expect(
        rupeesInWords(const Money.rupees(1000)),
        'Rupees One Thousand only',
      );
      expect(
        rupeesInWords(const Money.rupees(110)),
        'Rupees One Hundred Ten only',
      );
      expect(rupeesInWords(Money.zero), 'Rupees Zero only');
    });

    test('above a hundred crore the crores are counted again', () {
      expect(
        rupeesInWords(const Money.rupees(1250000000)),
        'Rupees One Hundred Twenty-Five Crore only',
      );
    });
  });

  group('the notice', () {
    const notice = DemandNotice(
      shopName: 'Chishti Kiryana Store',
      shopCity: 'Lahore',
      partyName: 'Rashid Traders',
      partyAddress: 'Shop 14, Shah Alam Market',
      partyCity: 'Lahore',
      partyPhone: '0300 1234567',
      chequeNo: '004512',
      bank: 'Meezan Bank',
      chequeDate: BusinessDate('2026-10-11'),
      amount: Money.rupees(45000),
      bouncedOn: BusinessDate('2026-10-12'),
      returnReason: 'Funds insufficient',
      issuedOn: BusinessDate('2026-10-14'),
    );

    test('names the cheque, the bank, the date and the amount', () {
      expect(
        notice.paragraphs.first,
        'That you issued cheque No. 004512 dated 11 October 2026 drawn on '
        'Meezan Bank for Rs. 45,000.00/- (Rupees Forty-Five Thousand only) '
        'in favour of Chishti Kiryana Store towards the discharge of your '
        'liability.',
      );
    });

    test('carries the return memo in the bank own words', () {
      expect(
        notice.paragraphs[1],
        'That the said cheque was presented for payment and was returned '
        'unpaid by the bank on 12 October 2026 with the remarks '
        '"Funds insufficient".',
      );
    });

    test('gives the drawer fifteen days to pay', () {
      expect(notice.paragraphs.last, contains('within 15 days'));
      expect(notice.paragraphs.last, contains('Section 489-F PPC'));
    });

    test('must be served within thirty days of the bounce', () {
      expect(notice.serveBy, const BusinessDate('2026-11-11'));
      expect(notice.isLate, isFalse);
      const late = DemandNotice(
        shopName: 'Chishti Kiryana Store',
        partyName: 'Rashid Traders',
        chequeNo: '004512',
        amount: Money.rupees(45000),
        bouncedOn: BusinessDate('2026-10-12'),
        issuedOn: BusinessDate('2026-11-12'),
      );
      expect(late.isLate, isTrue);
    });

    test(
      'leaves out what the books do not know rather than printing blanks',
      () {
        const bare = DemandNotice(
          shopName: 'Chishti Kiryana Store',
          partyName: 'Rashid Traders',
          partyAddress: '  ',
          chequeNo: '004512',
          amount: Money.rupees(45000),
          bouncedOn: BusinessDate('2026-10-12'),
          issuedOn: BusinessDate('2026-10-14'),
        );
        expect(bare.to, ['Rashid Traders']);
        expect(
          bare.paragraphs.first,
          startsWith('That you issued cheque No. 004512 for Rs. 45,000.00/-'),
        );
        expect(bare.paragraphs[1], endsWith('on 12 October 2026.'));
      },
    );

    test('addresses the drawer with what the khata holds', () {
      expect(notice.to, [
        'Rashid Traders',
        'Shop 14, Shah Alam Market',
        'Lahore',
        'Phone: 0300 1234567',
      ]);
    });
  });
}
