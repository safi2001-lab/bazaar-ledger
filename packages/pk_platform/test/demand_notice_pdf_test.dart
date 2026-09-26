import 'dart:io';

import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

/// The demand notice as paper.
///
/// What is asserted is what an advocate or a magistrate checks first: that
/// the page names this cheque and this amount, and carries the section it is
/// served under. The words themselves are asserted in pk_domain; this proves
/// they reach the page.
void main() {
  const notice = DemandNotice(
    shopName: 'Chishti Kiryana Store',
    shopCity: 'Lahore',
    partyName: 'Rashid Traders',
    partyCity: 'Lahore',
    chequeNo: '004512',
    bank: 'Meezan Bank',
    chequeDate: BusinessDate('2026-10-11'),
    amount: Money.rupees(45000),
    bouncedOn: BusinessDate('2026-10-12'),
    returnReason: 'Funds insufficient',
    issuedOn: BusinessDate('2026-10-14'),
  );

  test('a demand notice renders as a PDF naming the cheque', () async {
    final bytes = await demandNoticePdf(notice, compress: false);
    final text = String.fromCharCodes(bytes);

    expect(text.substring(0, 5), '%PDF-');
    expect(text, contains('Demand notice, cheque 004512'));
    for (final word in ['004512', '45,000.00/-', '489-F', 'Meezan']) {
      expect(text, contains(word), reason: '"$word" is not on the page');
    }
  });

  test(
    'a demand notice with an Urdu name carries the face to draw it',
    () async {
      final font = File(
        '../../assets/fonts/NotoNaskhArabic-Regular.ttf',
      ).readAsBytesSync();
      const urdu = DemandNotice(
        shopName: 'چشتی کریانہ سٹور',
        partyName: 'راشد ٹریڈرز',
        chequeNo: '004512',
        amount: Money.rupees(45000),
        bouncedOn: BusinessDate('2026-10-12'),
        issuedOn: BusinessDate('2026-10-14'),
      );

      final text = String.fromCharCodes(
        await demandNoticePdf(urdu, unicodeFont: font, compress: false),
      );
      expect(text, contains('NotoNaskhArabic'));
    },
  );

  test('a demand notice file is named after the cheque, safely', () {
    expect(demandNoticeFileName(notice), 'notice-004512.pdf');
    const odd = DemandNotice(
      shopName: 'Chishti Kiryana Store',
      partyName: 'Rashid Traders',
      chequeNo: '../12/34',
      amount: Money.rupees(1),
      bouncedOn: BusinessDate('2026-10-12'),
      issuedOn: BusinessDate('2026-10-14'),
    );
    expect(demandNoticeFileName(odd), 'notice-12_34.pdf');
  });
}
