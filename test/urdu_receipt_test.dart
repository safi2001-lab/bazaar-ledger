import 'package:bazaar_ledger/features/printing/text_rasteriser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// Drawing the lines a printer cannot spell.
///
/// ## What a host test can and cannot prove here
///
/// It can prove the mechanism: that a picture comes back, that it is the
/// width the paper is, that its byte count matches what `GS v 0` declares,
/// that the encoder accepts it, and that the base direction follows the first
/// strong character rather than being forced one way.
///
/// It cannot prove the glyphs are right. `flutter_test` substitutes a test
/// font that draws every character as a filled box, so this suite would pass
/// identically if the shaping were wrong, the bidi reversed, or the font
/// missing — all it sees is ink. Urdu rendering fidelity is a Tier C claim:
/// it needs a handset with the system Naskh font and a look at the paper.
/// That is recorded as such rather than implied by a green tick here.
void main() {
  const rasteriser = UiTextRasteriser();

  test('a picture comes back at the width of the paper', () async {
    final bitmap = await rasteriser.rasterise(
      'الفلاح سٹور',
      widthDots: ReceiptPaper.mm80.dots,
    );

    expect(bitmap.width, 576);
    expect(bitmap.height, greaterThan(0));
  });

  test('its byte count is exactly what GS v 0 will declare', () async {
    // The header says widthBytes x height and the printer counts them. One
    // byte short and it keeps reading: the feed, the cut and the drawer kick
    // are all consumed as image data, and the machine sits waiting for the
    // rest of a picture that never arrives, mid-job, with a customer at the
    // counter. `EscPos.raster` refuses a mismatch, so this asserts it accepts.
    final bitmap = await rasteriser.rasterise(
      'محمد اسلم',
      widthDots: ReceiptPaper.mm58.dots,
    );

    expect(bitmap.bits.length, bitmap.bytesPerRow * bitmap.height);
    expect(
      () => EscPos().raster(bitmap),
      returnsNormally,
      reason: 'the encoder refused the bitmap this rasteriser produced',
    );
  });

  test('there is ink on it', () async {
    // A blank strip is the failure that looks like success everywhere else:
    // the receipt prints, the cut lands, and the shop name is a gap.
    final bitmap = await rasteriser.rasterise('الفلاح', widthDots: 384);

    expect(
      bitmap.bits.any((b) => b != 0),
      isTrue,
      reason: 'the strip came back blank, which prints as white space',
    );
  });

  test('a blank string still produces a legal bitmap', () async {
    // Not reachable through `unprintableLines`, which skips blank lines — but
    // a zero height would be a command the printer waits on forever, so the
    // clamp is asserted rather than trusted.
    final bitmap = await rasteriser.rasterise('', widthDots: 384);

    expect(bitmap.height, greaterThanOrEqualTo(1));
    expect(() => EscPos().raster(bitmap), returnsNormally);
  });

  test('a long line grows taller rather than being clipped', () async {
    // The layout wraps at column counts that mean nothing for a proportional
    // script, so a long Urdu name reaches this as one string and the text
    // engine does the wrapping. It has to grow the strip, not crop it.
    final short = await rasteriser.rasterise('چاول', widthDots: 384);
    final long = await rasteriser.rasterise(
      'چاول ٹوٹہ باسمتی خاص درجہ اول پرانا ذخیرہ شدہ',
      widthDots: 384,
    );

    expect(long.height, greaterThan(short.height));
  });

  test('a wider roll gets a wider picture, not a scaled one', () async {
    final narrow = await rasteriser.rasterise('الفلاح سٹور', widthDots: 384);
    final wide = await rasteriser.rasterise('الفلاح سٹور', widthDots: 576);

    expect(narrow.width, 384);
    expect(wide.width, 576);
    // Same point size on both, so the same words take no more rows on the
    // wider roll. A rasteriser that scaled to fit would print a 58mm-sized
    // shop name on 80mm paper.
    expect(wide.height, lessThanOrEqualTo(narrow.height));
  });

  test('the whole receipt path ends in raster, not question marks', () async {
    // The join between the two halves: the pure package names the lines, this
    // one draws them, and the bytes that come out carry the picture and not
    // the substitution.
    const renderer = ThermalReceiptRenderer();
    final data = _receipt(shopName: 'الفلاح سٹور');
    final needed = renderer.unprintableLines(data);
    expect(needed, isNotEmpty);

    final drawn = <String, MonoBitmap>{};
    for (final line in needed) {
      drawn[line] = await rasteriser.rasterise(
        line,
        widthDots: ReceiptPaper.mm80.dots,
      );
    }

    final bytes = renderer.toThermalBytes(data, drawn: drawn);

    expect(_count(bytes, [0x1D, 0x76, 0x30, 0x00]), needed.length);
    expect(_count(bytes, '???'.codeUnits), 0);
    for (final byte in bytes) {
      expect(byte, lessThanOrEqualTo(0xFF));
    }
  });
}

int _count(List<int> haystack, List<int> needle) {
  var found = 0;
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    found++;
  }
  return found;
}

ReceiptData _receipt({required String shopName}) => ReceiptData(
  shop: ReceiptShop(
    name: shopName,
    addressLine1: 'Shop 14, Anarkali',
    city: 'Lahore',
    phone: '0300-4471203',
  ),
  docNo: 'INV-2627-0001',
  dateTimeLabel: '23-08-2026  2:15 PM',
  cashierName: 'Malik Sahib',
  lines: const [
    ReceiptLine(
      name: 'Cooking Oil 5L',
      qtyDisplay: '1',
      unitCode: 'pcs',
      rate: Rate.rupees(1450),
      amount: Money.rupees(1450),
    ),
  ],
  subtotal: const Money.rupees(1450),
  total: const Money.rupees(1450),
  paid: const Money.rupees(1450),
  balance: Money.zero,
  change: Money.zero,
  tenders: const [ReceiptTender(label: 'Cash', amount: Money.rupees(1450))],
);
