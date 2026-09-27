import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

void main() {
  group('gs1', () {
    test('a medicine pack gives its product, batch and expiry', () {
      final d = parseGs1('01089601234567891726123110B1234\u001d21SN0001');
      expect(d!.gtin, '08960123456789');
      expect(d.ean13, '8960123456789');
      expect(d.expiry, const BusinessDate('2026-12-31'));
      expect(d.batch, 'B1234');
      expect(d.serial, 'SN0001');
    });

    test('a label printed for people is read the same', () {
      final d = parseGs1('(01)08960123456789(17)270600(10)LOT-7');
      expect(d!.batch, 'LOT-7');
      expect(
        d.expiry,
        const BusinessDate('2027-06-30'),
        reason: 'day 00 is the end of the month',
      );
    });

    test('the scanner prefix is dropped', () {
      expect(parseGs1(']d2010896012345678910B9')!.batch, 'B9');
    });

    test('an ordinary barcode or an IMEI is not GS1', () {
      expect(parseGs1('8964000000017'), isNull);
      expect(parseGs1('356938035643809'), isNull);
      expect(parseGs1('SUGAR-1KG'), isNull);
    });
  });
}
