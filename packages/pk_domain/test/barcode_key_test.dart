import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// One packet, two barcodes, depending on what read it.
///
/// This is not a theoretical tidiness problem. A shop will scan the same tin
/// of oil with a USB wedge in the morning and the phone camera in the
/// afternoon, and get twelve digits one time and thirteen the other, because
/// ML Kit reports UPC-A as the EAN-13 it formally is.
///
/// An exact-match lookup finds the item one way and not the other. Nothing
/// about that failure looks like a normalisation problem: it looks like the
/// item is missing, so the cashier adds it again by hand — and the catalogue
/// ends up carrying one packet twice, at two prices, with the stock split
/// between them.
void main() {
  test('a twelve-digit UPC also matches the EAN-13 a camera reports', () {
    expect(barcodeVariants('012345678905'), contains('0012345678905'));
  });

  test('a thirteen-digit EAN beginning with zero also matches its UPC', () {
    expect(barcodeVariants('0012345678905'), contains('012345678905'));
  });

  test('what was actually scanned always comes first', () {
    // Two items really can carry the twelve- and thirteen-digit forms of one
    // code. The one the scanner read is the right answer, and an inferred
    // variant must never outrank it.
    expect(barcodeVariants('012345678905').first, '012345678905');
    expect(barcodeVariants('0012345678905').first, '0012345678905');
  });

  test('an EAN-13 that does not begin with zero is left alone', () {
    // 890 is India, 896 is Pakistan. Neither has a UPC form, and inventing one
    // would be a lookup that matches the wrong packet.
    expect(barcodeVariants('8964000999999'), ['8964000999999']);
  });

  test('an EAN-8 is left alone', () {
    expect(barcodeVariants('96385074'), ['96385074']);
  });

  test('a shop code is never given a leading zero', () {
    // `CHAWAL-5KG` has no UPC form. Padding it would be inventing a barcode.
    expect(barcodeVariants('CHAWAL-5KG'), ['CHAWAL-5KG']);
  });

  test('leading zeros are not stripped in general', () {
    // `0123` and `123` are different shop codes and must stay different. Only
    // the UPC-A/EAN-13 leading zero is genuinely ambiguous.
    expect(barcodeVariants('0123'), ['0123']);
  });

  test('surrounding space is trimmed, because a wedge sends it', () {
    expect(barcodeVariants('  012345678905  ').first, '012345678905');
  });

  test('nothing scanned is nothing to look up', () {
    expect(barcodeVariants(''), isEmpty);
    expect(barcodeVariants('   '), isEmpty);
  });

  test('the variants never repeat', () {
    // A duplicate would put the same code twice in an IN clause. Harmless, but
    // it means the reasoning above has a hole in it.
    for (final code in const [
      '012345678905',
      '0012345678905',
      '8964000999999',
      'CHAWAL-5KG',
    ]) {
      final variants = barcodeVariants(code);
      expect(variants.toSet(), hasLength(variants.length), reason: code);
    }
  });
}
