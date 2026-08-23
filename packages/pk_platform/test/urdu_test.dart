import 'dart:convert';
import 'dart:typed_data';

import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

/// Urdu on a receipt.
///
/// A thermal printer draws text from a ROM font chosen by a code page: 256
/// glyphs, no shaping engine, no bidirectional algorithm, no fallback. The
/// community ESC/POS capability database lists seventy encodings and not one
/// is Urdu. So there is no byte sequence this app could send that would put
/// Urdu on paper, and the only remaining route is a picture.
///
/// The guarantee these hold is the one the ledger row states: Urdu is
/// rasterised, and never sent as code page bytes. The second half matters as
/// much as the first — CP1256 is the near miss that contains most of the
/// letters, and reaching for it produces disconnected isolated forms printed
/// backwards, which reads as a printer fault rather than as a bug here.
void main() {
  const renderer = ThermalReceiptRenderer();

  group('what the printer font can say', () {
    test('plain ASCII can be typed', () {
      expect(isPrintableLatin('TOTAL           Rs 5,525.00'), isTrue);
      expect(isPrintableLatin('Chawal 5kg x 150.00'), isTrue);
    });

    test('the characters the encoder folds still count as typeable', () {
      // Rasterising a line because it holds a curly apostrophe would be a
      // picture where crisp font text would do, and a picture is an order of
      // magnitude more bytes down a 9600-baud serial link.
      expect(isPrintableLatin('Shopkeeper’s copy'), isTrue);
      expect(isPrintableLatin('Sub—total'), isTrue);
      expect(isPrintableLatin('Rs 5,525.00'), isTrue);
    });

    test('Urdu cannot', () {
      expect(isPrintableLatin('چاول'), isFalse);
      expect(
        isPrintableLatin('الفلاح سٹور'),
        isFalse,
      );
      // Mixed, which is the normal case: an item name beside its price.
      expect(isPrintableLatin('چاول        1,450.00'), isFalse);
    });

    test('Urdu-only letters count, not just the Arabic ones', () {
      // CP1256 is Arabic. Even if shaping and bidi were free, it has no
      // U+0679 U+0688 U+0691 U+06BA U+06D2 and no Urdu U+06C1 — so much of any
      // real Urdu word is missing from the one code page that looks like it
      // might work.
      for (final letter in [
        'ٹ',
        'ڈ',
        'ڑ',
        'ں',
        'ے',
        'ہ',
      ]) {
        expect(isPrintableLatin(letter), isFalse, reason: letter);
      }
    });
  });

  group('finding what has to be drawn', () {
    test('an all-Latin receipt needs no pictures at all', () {
      // The whole template is Roman Urdu in Latin script and every money row
      // is digits, so the common receipt takes the fast path end to end.
      expect(renderer.unprintableLines(_receipt()), isEmpty);
    });

    test('an Urdu shop name is found', () {
      final needed = renderer.unprintableLines(
        _receipt(shopName: 'الفلاح سٹور'),
      );
      expect(needed, isNotEmpty);
      expect(needed.any((l) => l.contains('الفلاح')), isTrue);
    });

    test('an Urdu item name is found, and its price line is not', () {
      // The layout already gives an item two lines — the name on its own,
      // then quantity and rate below it — because names in this market are
      // long. That split is worth more than it looks here: the picture holds
      // only the name, and the money row stays crisp font text in the same
      // tabular column as every other item on the bill.
      final needed = renderer.unprintableLines(
        _receipt(itemName: 'چاول ٹوٹہ'),
      );
      expect(needed, contains('چاول ٹوٹہ'));
      expect(
        needed.any((l) => l.contains('1,450.00')),
        isFalse,
        reason:
            'a money row was dragged into a picture, so it no longer lines '
            'up with the amounts above and below it',
      );
    });

    test('a mixed line is kept whole, so bidi is decided once', () {
      // `Customer            محمد اسلم` is the real mixed case: a Latin label
      // and an Urdu value on one line. Splitting it here and reassembling
      // after would be this package deciding the order of an RTL run and an
      // LTR one, which is exactly the judgement it is not qualified to make.
      final needed = renderer.unprintableLines(
        _receipt(customerName: 'محمد اسلم'),
      );
      final line = needed.firstWhere((l) => l.contains('محمد'));
      expect(line, contains('Customer'));
    });

    test('a blank line is never asked for', () {
      final needed = renderer.unprintableLines(
        _receipt(shopName: 'الفلاح'),
      );
      expect(needed.any((l) => l.trim().isEmpty), isFalse);
    });
  });

  group('what reaches the printer', () {
    test('no Urdu byte is ever emitted, even with no pictures supplied', () {
      // The load-bearing one. With nothing to draw with, the encoder must
      // still refuse to spell it.
      final bytes = renderer.toThermalBytes(
        _receipt(
          shopName: 'الفلاح سٹور',
          itemName: 'چاول ٹوٹہ',
        ),
      );

      const urdu = 'الفلاح';
      expect(
        _contains(bytes, utf8.encode(urdu)),
        isFalse,
        reason: 'UTF-8 down the wire prints as mojibake on every printer',
      );
      expect(
        _contains(bytes, _cp1256(urdu)),
        isFalse,
        reason:
            'CP1256 is the near miss: the letters exist, so it looks like it '
            'works, and what comes out is isolated forms printed backwards',
      );
    });

    test('a supplied picture is sent as GS v 0 and the text is not', () {
      final data = _receipt(itemName: 'چاول ٹوٹہ');
      final line = renderer.unprintableLines(
        data,
      ).firstWhere((l) => l.contains('چاول'));

      final plain = renderer.toThermalBytes(data);
      final drawn = renderer.toThermalBytes(data, drawn: {line: _ink(576, 40)});

      const gsV0 = [0x1D, 0x76, 0x30, 0x00];
      expect(_count(plain, gsV0), 0);
      expect(_count(drawn, gsV0), 1);

      // And the question marks the encoder would have substituted are gone,
      // because that line no longer goes through the text path at all.
      expect(_contains(plain, ascii.encode('????')), isTrue);
      expect(_contains(drawn, ascii.encode('????')), isFalse);
    });

    test('an undrawn Urdu line degrades to question marks, not to garbage', () {
      // Legibly wrong beats illegibly wrong. A shopkeeper who sees ????? where
      // their shop name should be has a complaint somebody can act on; one who
      // sees random glyphs concludes the printer is broken and returns it.
      final bytes = renderer.toThermalBytes(
        _receipt(shopName: 'الفلاح'),
      );
      for (var i = 0; i < bytes.length; i++) {
        expect(
          bytes[i],
          lessThanOrEqualTo(0x7E),
          reason: 'byte $i is 0x${bytes[i].toRadixString(16)}, outside ASCII',
        );
      }
    });

    test('the drawn shop name replaces the big text, not adds to it', () {
      final data = _receipt(
        shopName: 'الفلاح سٹور',
      );
      final name = data.shop.name.toUpperCase();
      final bytes = renderer.toThermalBytes(data, drawn: {name: _ink(576, 60)});

      // GS ! n, the double-size command. Printing the picture AND the text
      // would put the shop name on the receipt twice, once as pixels and once
      // as question marks.
      expect(_count(bytes, [0x1D, 0x21]), 0);
      expect(_count(bytes, [0x1D, 0x76, 0x30, 0x00]), 1);
      expect(_contains(bytes, ascii.encode('???')), isFalse);
    });

    test('a Latin receipt is untouched by the whole mechanism', () {
      // The fast path has to stay byte-identical, or every existing proof
      // about the receipt stream is now proving something else.
      expect(
        renderer.toThermalBytes(_receipt()),
        renderer.toThermalBytes(_receipt(), drawn: const {}),
      );
      expect(
        _count(renderer.toThermalBytes(_receipt()), [0x1D, 0x76, 0x30, 0x00]),
        0,
      );
    });
  });
}

/// A bitmap of solid ink, sized so [EscPos.raster] accepts it.
MonoBitmap _ink(int width, int height) {
  final bytesPerRow = (width + 7) ~/ 8;
  final bits = Uint8List(bytesPerRow * height);
  bits.fillRange(0, bits.length, 0xFF);
  return MonoBitmap(width: width, height: height, bits: bits);
}

/// CP1256, enough of it for the fixture this asserts against.
Uint8List _cp1256(String text) {
  const map = <int, int>{
    0x0627: 0xC7, // alef
    0x0644: 0xE1, // lam
    0x0641: 0xDD, // feh
    0x062D: 0xCD, // hah
  };
  return Uint8List.fromList([
    for (final rune in text.runes)
      if (map[rune] case final byte?) byte else rune & 0x7F,
  ]);
}

bool _contains(List<int> haystack, List<int> needle) =>
    _count(haystack, needle) > 0;

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

ReceiptData _receipt({
  String shopName = 'Chishti Kiryana Store',
  String itemName = 'Cooking Oil 5L',
  String? customerName,
}) => ReceiptData(
  shop: ReceiptShop(
    name: shopName,
    addressLine1: 'Shop 14, Anarkali',
    city: 'Lahore',
    phone: '0300-4471203',
  ),
  docNo: 'INV-2627-0001',
  dateTimeLabel: '23-08-2026  2:15 PM',
  cashierName: 'Malik Sahib',
  customerName: customerName,
  lines: [
    ReceiptLine(
      name: itemName,
      qtyDisplay: '1',
      unitCode: 'pcs',
      rate: const Rate.rupees(1450),
      amount: const Money.rupees(1450),
    ),
  ],
  subtotal: const Money.rupees(1450),
  total: const Money.rupees(1450),
  paid: const Money.rupees(1450),
  balance: Money.zero,
  change: Money.zero,
  tenders: const [ReceiptTender(label: 'Cash', amount: Money.rupees(1450))],
);
