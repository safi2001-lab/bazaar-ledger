import 'dart:io';
import 'dart:typed_data';

import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

/// Urdu in the PDF a customer is handed.
///
/// The thermal receipt and the shared PDF fail differently, and the PDF fails
/// worse. The thermal path degrades to question marks, which is visible and
/// complainable. The PDF degrades to nothing: Courier and Helvetica are Type 1
/// base fonts with no Unicode at all, so an Urdu shop name is not substituted,
/// it is skipped. The pdf package says so on stderr and carries on.
///
/// A PDF is read on somebody else's phone, so unlike the thermal path this
/// cannot be solved with the device's own fonts. The face has to travel inside
/// the file.
void main() {
  const renderer = ThermalReceiptRenderer();

  test('without a font, no face is embedded at all', () async {
    // The state this shipped in. Kept as a test rather than deleted, because
    // it is what makes the next one mean something: the difference between
    // the two is the whole feature.
    final bytes = await renderer.toPdf(_receipt(shopName: 'الفلاح'));

    expect(_ascii(bytes), isNot(contains('FontFile2')));
  });

  test('with one, it is embedded and named in the file', () async {
    final bytes = await renderer.toPdf(
      _receipt(shopName: 'الفلاح'),
      unicodeFont: _font(),
    );

    final text = _ascii(bytes);
    expect(text, contains('FontFile2'));
    expect(text, contains('NotoNaskhArabic'));
  });

  test('the letters are joined, not printed one by one', () async {
    // The assertion that matters, and the one a size check would miss.
    //
    // Arabic script is cursive: every letter has up to four contextual forms
    // and a word is drawn as one connected run. A font alone does not give
    // that — the pdf package applies its bidi and joining pass only when the
    // text direction is RTL, and text left at the default comes out as
    // isolated, unjoined letters in logical order. It is unreadable, and it
    // reads as a missing font rather than as a direction nobody set.
    //
    // So this looks at what the file actually maps: the embedded subset's
    // character map should name presentation forms in the U+FB50..U+FEFF
    // block, and not the bare letters in U+0600..U+06FF.
    final bytes = await renderer.toPdf(
      _receipt(shopName: 'الفلاح', itemName: 'چاول'),
      unicodeFont: _font(),
    );

    final mapped = _mappedCodepoints(bytes);
    expect(
      mapped,
      isNotEmpty,
      reason: 'the file embeds no Arabic-range glyphs at all',
    );
    expect(
      mapped.where((c) => c >= 0xFB50 && c <= 0xFEFF),
      isNotEmpty,
      reason:
          'every glyph is a bare letter, so the joining pass never ran and '
          'the word prints as disconnected shapes',
    );
    expect(
      mapped.where((c) => c >= 0x0600 && c <= 0x06FF),
      isEmpty,
      reason:
          'an unjoined letter reached the file, which is the shape of a run '
          'that was left in the default direction',
    );
  });

  test('an all-Latin receipt carries no embedded face', () async {
    // The font is 178 KB in the APK but only the used glyphs go into any one
    // document. A shop billing in Roman Urdu should pay nothing per bill.
    final withFont = await renderer.toPdf(_receipt(), unicodeFont: _font());
    final without = await renderer.toPdf(_receipt());

    expect(_ascii(withFont), isNot(contains('FontFile2')));
    expect(
      (withFont.length - without.length).abs(),
      lessThan(512),
      reason: 'a Latin-only bill grew, so the whole face is being embedded',
    );
  });

  test('one Urdu bill costs kilobytes, not the whole face', () async {
    final bytes = await renderer.toPdf(
      _receipt(shopName: 'الفلاح سٹور', itemName: 'چاول ٹوٹہ'),
      unicodeFont: _font(),
    );

    expect(
      bytes.length,
      lessThan(_font().length),
      reason:
          'the receipt is larger than the font it borrows from, so the '
          'subsetting is not happening and every shared bill carries 178 KB',
    );
  });

  test('the money columns keep their tabular font', () async {
    // A fallback, not a replacement. Courier is here because its figures are
    // fixed-width, which is the entire reason a column of amounts lines up.
    // Swapping the document over to a proportional face for the sake of a
    // shop name would make every total on the page crooked.
    final bytes = await renderer.toPdf(
      _receipt(shopName: 'الفلاح'),
      unicodeFont: _font(),
    );

    expect(_ascii(bytes), contains('Courier'));
  });
}

Uint8List _font() => Uint8List.fromList(
  File(
    '${Directory.current.path}/../../assets/fonts/NotoNaskhArabic-Regular.ttf',
  ).readAsBytesSync(),
);

String _ascii(Uint8List bytes) => String.fromCharCodes(bytes);

/// Every Unicode codepoint the PDF's embedded subsets claim to draw.
///
/// A PDF font carries a `ToUnicode` CMap so a reader can copy text back out
/// of it, and its entries are exactly the characters that were drawn. The
/// streams are deflated, so this inflates what it can and ignores what it
/// cannot rather than assuming a compression setting.
Set<int> _mappedCodepoints(Uint8List bytes) {
  final found = <int>{};
  final text = _ascii(bytes);
  final pattern = RegExp(r'stream\r?\n');

  for (final match in pattern.allMatches(text)) {
    final end = text.indexOf('endstream', match.end);
    if (end < 0) continue;
    final raw = bytes.sublist(match.end, end);

    List<int> inflated;
    try {
      inflated = ZLibDecoder().convert(raw);
    } on Object {
      continue;
    }

    final body = String.fromCharCodes(inflated);
    for (final block in RegExp(
      r'beginbfchar(.*?)endbfchar',
      dotAll: true,
    ).allMatches(body)) {
      for (final pair in RegExp(
        r'<[0-9A-Fa-f]{4}>\s*<([0-9A-Fa-f]{4,})>',
      ).allMatches(block.group(1)!)) {
        final value = int.parse(pair.group(1)!.substring(0, 4), radix: 16);
        if (value != 0) found.add(value);
      }
    }
  }
  return found;
}

ReceiptData _receipt({
  String shopName = 'Chishti Kiryana Store',
  String itemName = 'Cooking Oil 5L',
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
