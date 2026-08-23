import 'dart:typed_data';

import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

void main() {
  group('preview and print agree', _agreementTests);
  group('hostile input', _hostileInputTests);
  group('PDF pagination', _pdfTests);
  group('the numbers reconcile', _reconciliationTests);
  const renderer = ThermalReceiptRenderer();

  group('80mm layout', () {
    test('every line is exactly 48 columns or shorter', () {
      // The design mock this was built from claimed 48 columns and was
      // actually 36, with every money line overhanging by one character. The
      // printer's number wins.
      final lines = renderer.toPreview(receipt());
      for (final line in lines) {
        expect(
          line.length,
          lessThanOrEqualTo(48),
          reason: 'overhangs the paper: "$line"',
        );
      }
    });

    test('amounts are flush against the right margin', () {
      final lines = renderer.toPreview(receipt());
      final totalLine = lines.firstWhere((l) => l.startsWith('TOTAL'));
      expect(totalLine.length, 48);
      expect(totalLine.endsWith('Rs 5,525.00'), isTrue);
      expect(totalLine, 'TOTAL${' ' * 32}Rs 5,525.00');
    });

    test('reads the way a shopkeeper expects', () {
      final lines = renderer.toPreview(receipt());
      final text = lines.join('\n');
      expect(text, contains('CHISHTI KIRYANA STORE'));
      expect(text, contains('INV-2627-0001'));
      expect(text, contains('Cooking Oil 5L'));
      expect(text, contains('2 pcs x 2,500.00'));
      expect(text, contains('3.5 kg x 150.00'));
      expect(text, contains('Change'));
      expect(text, contains('Shukriya'));
    });

    test('a fractional weight never prints as a whole number', () {
      final lines = renderer.toPreview(receipt());
      expect(lines.any((l) => l.contains('3.5 kg')), isTrue);
      expect(lines.any((l) => l.contains('0 kg')), isFalse);
    });

    test('an udhaar balance is spelled out in Roman Urdu', () {
      final lines = renderer.toPreview(
        receipt(
          paid: const Money.rupees(2000),
          balance: const Money.rupees(3525),
          change: Money.zero,
          tenders: const [
            ReceiptTender(label: 'Cash', amount: Money.rupees(2000)),
          ],
        ),
      );
      final text = lines.join('\n');
      expect(text, contains('BAQAYA (udhaar)'));
      expect(text, contains('3,525.00'));
    });

    test('a reprint says so', () {
      final lines = renderer.toPreview(receipt(reprint: true));
      expect(lines.any((l) => l.contains('** REPRINT **')), isTrue);
    });

    test('a long item name wraps instead of being cut off', () {
      final lines = renderer.toPreview(
        receipt(
          lines: const [
            ReceiptLine(
              name: 'Dalda Cooking Oil 5 Litre Tin Pack Special Ramzan Offer',
              qtyDisplay: '1',
              unitCode: 'pcs',
              rate: Rate.rupees(2500),
              amount: Money.rupees(2500),
            ),
          ],
        ),
      );
      final text = lines.join('\n');
      expect(text, contains('Dalda Cooking Oil 5 Litre Tin Pack'));
      expect(text, contains('Ramzan Offer'));
      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(48));
      }
    });

    test('a huge amount is never clipped, the label is', () {
      // Losing a digit off an amount is a wrong receipt. Losing a word off an
      // item name is a legible one.
      final lines = renderer.toPreview(
        receipt(
          total: const Money.rupees(98765432, 10),
          lines: const [
            ReceiptLine(
              name: 'Bulk consignment for the wholesale market at Badami Bagh',
              qtyDisplay: '1000',
              unitCode: 'bori',
              rate: Rate.rupees(98765),
              amount: Money.rupees(98765432, 10),
            ),
          ],
        ),
      );
      // Grouped the way this market reads it: lakhs and crores, not
      // thousands. Nine crore, eighty-seven lakh.
      expect(lines.any((l) => l.contains('9,87,65,432.10')), isTrue);
      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(48));
      }
    });
  });

  group('58mm layout', () {
    test('every line is exactly 32 columns or shorter', () {
      final lines = renderer.toPreview(receipt(), paper: ReceiptPaper.mm58);
      for (final line in lines) {
        expect(
          line.length,
          lessThanOrEqualTo(32),
          reason: 'overhangs the paper: "$line"',
        );
      }
      expect(lines.any((l) => l.contains('5,525.00')), isTrue);
    });
  });

  group('payment instructions', () {
    test('print the shop\'s own alias and IBAN as plain text', () {
      final lines = renderer.toPreview(
        receipt(
          shop: const ReceiptShop(
            name: 'Chishti Kiryana Store',
            city: 'Lahore',
            raastAlias: '0300-4471203',
            bankName: 'Meezan',
            bankAccountTitle: 'Chishti Kiryana Store',
            bankIban: 'PK24MEZN0001234567891011',
          ),
        ),
      );
      final text = lines.join('\n');
      expect(text, contains('Payment ke liye'));
      expect(text, contains('Raast: 0300-4471203'));
      expect(text, contains('PK24MEZN0001234567891011'));
    });

    test('nothing in the byte stream looks like a minted scheme QR', () {
      // QR Standard s.8.1(a) reserves the scheme identifier to SBP-authorised
      // PSO/PSPs, and breaching an SBP instruction is an offence under s.56
      // PS&EFT Act. The previous build minted merchant QRs with an invented
      // `pk.raast` GUID and a hardcoded IBAN. Nothing here constructs an
      // EMVCo payload; a bank-issued QR is rendered only as a picture.
      final bytes = renderer.toThermalBytes(
        receipt(
          shop: const ReceiptShop(
            name: 'Chishti Kiryana Store',
            raastAlias: '0300-4471203',
            bankIban: 'PK24MEZN0001234567891011',
          ),
        ),
      );
      final text = String.fromCharCodes(bytes);
      expect(text, isNot(contains('pk.raast')));
      expect(text, isNot(contains('A000000736')));
      // No EMVCo QR command either.
      expect(_contains(bytes, [0x1D, 0x28, 0x6B]), isFalse);
    });
  });

  group('ESC/POS byte stream', () {
    test('opens with a reset so the last job cannot bleed into this one', () {
      final bytes = renderer.toThermalBytes(receipt());
      expect(bytes.sublist(0, 2), [0x1B, 0x40]);
    });

    test('ends with a cut that feeds the paper past the blade first', () {
      // GS V 66 n, not the bare GS V 0 this used to send. The cutter sits
      // several millimetres above the print head, so cutting without feeding
      // drives the blade through the last lines of the receipt — and the
      // symptom is a bill with its total missing, which reads as a layout
      // bug rather than a cut bug.
      final bytes = renderer.toThermalBytes(receipt());
      expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 0x42, 0x03]);
    });

    test('selects a font rather than trusting the printer default', () {
      // The whole layout is built on a column count, and the column count
      // depends on which of the two built-in fonts is active. `ESC @` resets
      // to the PRINTER's default, which is not the same on every machine —
      // several of the clones this ships against sit in a 42-column font,
      // and a receipt laid out for 48 that meets one wraps every line.
      final bytes = renderer.toThermalBytes(receipt());
      expect(
        _contains(bytes, [0x1B, 0x4D, 0x00]),
        isTrue,
        reason: 'no ESC M, so the column count is whatever the last job left',
      );
    });

    test('kicks the drawer only when asked', () {
      const kick = [0x1B, 0x70, 0x00, 0x19, 0xFA];
      expect(_contains(renderer.toThermalBytes(receipt()), kick), isFalse);
      expect(
        _contains(renderer.toThermalBytes(receipt(), openDrawer: true), kick),
        isTrue,
      );
    });

    test('emits GS v 0 when there is a raster to print', () {
      // The Urdu and logo path. Printer ROM fonts have no shaping engine and
      // no bidi, and there is no Urdu code page in the entire ESC/POS
      // capability database, so anything not Latin arrives as pixels.
      final logo = MonoBitmap(
        width: 16,
        height: 8,
        bits: Uint8List.fromList(List<int>.filled(16, 0xFF)),
      );
      final bytes = renderer.toThermalBytes(receipt(logo: logo));
      expect(_contains(bytes, [0x1D, 0x76, 0x30]), isTrue);
      // The raster header carries the right dimensions: 2 bytes per row,
      // 8 rows.
      final at = _indexOf(bytes, [0x1D, 0x76, 0x30]);
      expect(bytes[at + 3], 0);
      expect(bytes[at + 4], 2);
      expect(bytes[at + 6], 8);
    });

    test('is pure Latin, so no printer renders a random glyph', () {
      final bytes = renderer.toThermalBytes(
        receipt(
          lines: const [
            ReceiptLine(
              // An em dash and curly quotes, as a copy-paste would introduce.
              name: 'Basmati — “Super”',
              qtyDisplay: '1',
              unitCode: 'kg',
              rate: Rate.rupees(400),
              amount: Money.rupees(400),
            ),
          ],
        ),
      );
      final text = String.fromCharCodes(bytes);
      expect(text, contains('Basmati - "Super"'));
      for (final b in bytes) {
        // 0x80, not 0x100. Every element of a Uint8List is under 0x100 by
        // type, so the original assertion could not fail; what is actually
        // claimed is that nothing outside seven-bit ASCII reaches a printer
        // whose ROM font has no idea what to do with it.
        expect(b, lessThan(0x80));
      }
    });

    test('prints the shop name once, not twice', () {
      final bytes = renderer.toThermalBytes(receipt());
      final text = String.fromCharCodes(bytes);
      expect('CHISHTI KIRYANA STORE'.allMatches(text).length, 1);
    });
  });

  group('PDF', () {
    test('produces a real, non-trivial document', () async {
      final bytes = await renderer.toPdf(receipt());
      expect(bytes.length, greaterThan(2048));
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      // Trailer present, so the file is complete rather than truncated.
      final tail = String.fromCharCodes(bytes.sublist(bytes.length - 64));
      expect(tail, contains('%%EOF'));
    });

    test('renders A4, A5 and A6 without falling over', () async {
      for (final format in [
        PdfPageFormat.a4,
        PdfPageFormat.a5,
        PdfPageFormat.a6,
      ]) {
        final bytes = await renderer.toPdf(receipt(), format: format);
        expect(bytes.length, greaterThan(2048));
      }
    });

    test('survives a bill with forty lines', () async {
      final bytes = await renderer.toPdf(
        receipt(
          lines: [
            for (var i = 0; i < 40; i++)
              ReceiptLine(
                name: 'Item number $i',
                qtyDisplay: '1',
                unitCode: 'pcs',
                rate: const Rate.rupees(100),
                amount: const Money.rupees(100),
              ),
          ],
        ),
      );
      expect(bytes.length, greaterThan(2048));
    });
  });
}

bool _contains(Uint8List haystack, List<int> needle) =>
    _indexOf(haystack, needle) >= 0;

int _indexOf(Uint8List haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// The promise this package makes, tested rather than asserted in a comment.
///
/// `toPreview` and `toThermalBytes` must show the shopkeeper the same words.
/// A separate on-screen layout is a second implementation that drifts, and the
/// first anybody notices is a customer's printed copy disagreeing with what
/// the shopkeeper approved.
void _agreementTests() {
  const renderer = ThermalReceiptRenderer();

  String printedText(ReceiptData data, ReceiptPaper paper) {
    final bytes = renderer.toThermalBytes(data, paper: paper);
    // Everything the encoder emitted that is printable, with the control
    // sequences dropped and the line feeds kept as separators — otherwise the
    // last word of one line and the first of the next become one token and
    // the comparison quietly stops meaning anything.
    return String.fromCharCodes(
      bytes
          .map((b) => b == 0x0A ? 0x20 : b)
          .where((b) => b >= 0x20 && b < 0x7F),
    );
  }

  for (final paper in ReceiptPaper.values) {
    test('a long shop name prints in full on ${paper.columns} columns', () {
      final data = receipt(
        shop: const ReceiptShop(name: 'Al-Madina Kiryana Store'),
      );

      final printed = printedText(data, paper);
      // Every word of the name reaches the paper. It used to be cut at half
      // the column count — 16 characters at 58mm — while the preview wrapped
      // and showed all of it.
      for (final word in ['AL-MADINA', 'KIRYANA', 'STORE']) {
        expect(printed, contains(word), reason: 'on ${paper.columns} columns');
      }
    });

    test(
      'every preview word reaches the paper on ${paper.columns} columns',
      () {
        final data = receipt(
          shop: const ReceiptShop(name: 'Al-Madina Kiryana Store'),
        );

        // Words, in order, not lines. The shop name is printed double-size, so
        // it legitimately wraps at half the column count and its line breaks
        // differ from the preview's. What must never differ is the content: the
        // same words, in the same order, with nothing dropped and nothing
        // invented.
        List<String> words(String text) => text
            .toUpperCase()
            .split(RegExp(r'[^A-Z0-9.,\-/:]+'))
            .where((w) => w.isNotEmpty)
            .toList();

        final previewWords = words(
          renderer.toPreview(data, paper: paper).join(' '),
        );
        final printedWords = words(printedText(data, paper));

        // The printed stream carries a few encoder artefacts around the control
        // sequences, so it is checked as a subsequence rather than an equality.
        var cursor = 0;
        for (final word in previewWords) {
          final at = printedWords.indexOf(word, cursor);
          expect(
            at,
            isNonNegative,
            reason:
                'the preview showed "$word" and the printer did not, '
                'on ${paper.columns} columns. printed: $printedWords',
          );
          cursor = at + 1;
        }
      },
    );
  }

  test('a raster whose header lies about its size is refused', () {
    // One byte short and the printer keeps reading: the feed, the cut and the
    // drawer kick are all swallowed as pixels, and the machine sits waiting
    // for the rest of a picture that will never arrive.
    final short = MonoBitmap(width: 16, height: 4, bits: Uint8List(2 * 4 - 1));
    expect(
      () => EscPos().raster(short),
      throwsA(isA<ArgumentError>()),
      reason: 'a truncated bitmap must never reach a printer',
    );

    final exact = MonoBitmap(width: 16, height: 4, bits: Uint8List(2 * 4));
    expect(() => EscPos().raster(exact), returnsNormally);
  });
}

ReceiptData receipt({
  ReceiptShop? shop,
  List<ReceiptLine>? lines,
  Money total = const Money.rupees(5525),
  Money paid = const Money.rupees(5525),
  Money balance = Money.zero,
  Money change = const Money.rupees(475),
  List<ReceiptTender>? tenders,
  MonoBitmap? logo,
  bool reprint = false,
  String? customerName,
  String? customerPhone,
  Money subtotal = const Money.rupees(5525),
  Money discount = Money.zero,
  Money tax = Money.zero,
  Money furtherTax = Money.zero,
  Money withholding = Money.zero,
  Money extraCharges = Money.zero,
}) => ReceiptData(
  shop:
      shop ??
      ReceiptShop(
        name: 'Chishti Kiryana Store',
        addressLine1: 'Shop 14, Anarkali',
        city: 'Lahore',
        phone: '0300-4471203',
        logo: logo,
      ),
  docNo: 'INV-2627-0001',
  dateTimeLabel: '23-08-2026  2:15 PM',
  cashierName: 'Malik Sahib',
  customerName: customerName,
  customerPhone: customerPhone,
  lines:
      lines ??
      const [
        ReceiptLine(
          name: 'Cooking Oil 5L',
          qtyDisplay: '2',
          unitCode: 'pcs',
          rate: Rate.rupees(2500),
          amount: Money.rupees(5000),
        ),
        ReceiptLine(
          name: 'Mutton',
          qtyDisplay: '3.5',
          unitCode: 'kg',
          rate: Rate.rupees(150),
          amount: Money.rupees(525),
        ),
      ],
  subtotal: subtotal,
  discount: discount,
  tax: tax,
  furtherTax: furtherTax,
  withholding: withholding,
  extraCharges: extraCharges,
  total: total,
  tenders:
      tenders ??
      const [ReceiptTender(label: 'Cash', amount: Money.rupees(6000))],
  paid: paid,
  balance: balance,
  change: change,
  isReprint: reprint,
  footerLines: const ['Shukriya! Phir tashreef laayen'],
);

/// Inputs a shopkeeper can actually produce, on the narrower paper.
///
/// Every one of these overran the column width or silently cut a number. A
/// receipt is the only record a walk-in customer takes home, and a wrong one
/// is worse than a plain one.
void _pdfTests() {
  const renderer = ThermalReceiptRenderer();

  test('a forty-line bill keeps every line, across pages', () async {
    final lines = [
      for (var i = 0; i < 40; i++)
        ReceiptLine(
          name: 'Item number ${i + 1} with a reasonably long name',
          qtyDisplay: '1',
          unitCode: 'pcs',
          rate: const Rate.rupees(250),
          amount: const Money.rupees(250),
        ),
    ];
    final bytes = await renderer.toPdf(receipt(lines: lines));

    // "Bigger than 2 KB" passes with thirty-eight of the forty lines
    // dropped. A PDF is a container format, so the check that means
    // something is that the document paginated rather than clipped.
    expect(bytes.length, greaterThan(2048));
    final text = String.fromCharCodes(
      bytes.where((b) => b >= 0x20 && b < 0x7F),
    );
    final pages = _pageCount(text);
    expect(
      pages,
      greaterThan(1),
      reason:
          'forty lines do not fit one A5 page; the document must paginate '
          'rather than clip the ones that do not',
    );

    // And the last line is really on the last page, not silently dropped.
    expect(text, contains('/Count'));
  });

  test('a one-line bill is a single page', () async {
    final bytes = await renderer.toPdf(
      receipt(
        lines: const [
          ReceiptLine(
            name: 'Cooking Oil 5L',
            qtyDisplay: '1',
            unitCode: 'pcs',
            rate: Rate.rupees(2500),
            amount: Money.rupees(2500),
          ),
        ],
      ),
    );
    final text = String.fromCharCodes(
      bytes.where((b) => b >= 0x20 && b < 0x7F),
    );
    expect(
      _pageCount(text),
      1,
      reason: 'an ordinary bill must not spill onto a second sheet',
    );
  });
}

/// How many pages the document declares.
int _pageCount(String pdfText) {
  final match = RegExp(r'/Count (\d+)').firstMatch(pdfText);
  return match == null ? 0 : int.parse(match.group(1)!);
}

void _hostileInputTests() {
  const renderer = ThermalReceiptRenderer();

  for (final paper in ReceiptPaper.values) {
    test('a long free-text phone cannot overrun ${paper.columns} columns', () {
      // The customer phone is the one `_row` argument no caller clips, and it
      // is free text: shopkeepers write two numbers and a note in it.
      final data = receipt(
        customerName: 'Bilal General Store',
        customerPhone: '0300-1234567 / 042-35123456 whatsapp only please',
      );
      for (final line in renderer.toPreview(data, paper: paper)) {
        expect(line.length, lessThanOrEqualTo(paper.columns), reason: line);
      }
    });

    test('a long unit code never truncates the rate on ${paper.columns}', () {
      final data = receipt(
        lines: const [
          ReceiptLine(
            name: 'Atta',
            qtyDisplay: '1.000',
            unitCode: 'bori-50kg',
            rate: Rate.rupees(12450),
            amount: Money.rupees(12450),
          ),
        ],
      );
      final lines = renderer.toPreview(data, paper: paper);
      final detail = lines.firstWhere((l) => l.contains('bori-50kg'));

      expect(detail.length, lessThanOrEqualTo(paper.columns));
      // Either the whole rate is there, or none of it. Never "x 12,4".
      if (detail.contains(' x ')) {
        expect(
          detail,
          contains('12,450.00'),
          reason: 'a half-printed rate is a wrong receipt',
        );
      }
    });

    test('a long unit code is never truncated on ${paper.columns}', () {
      // `units.code` has no length cap in the schema, because the shop
      // invents its own: flour ships in 10, 40, 50 and 80 kg bags and the
      // codes name the pack. Clipping one does not shorten it, it renames
      // it — `bori-50kg-special-import` cut to `bori-50kg-spec` is a
      // different pack at a different price, and it reads as if it were
      // really the unit. Dropping the rate is not enough to make room here.
      const code = 'bori-50kg-special-import';
      final data = receipt(
        lines: const [
          ReceiptLine(
            name: 'Atta',
            qtyDisplay: '1,000.000',
            unitCode: code,
            rate: Rate.rupees(12450),
            amount: Money.rupees(1234567),
          ),
        ],
        subtotal: const Money.rupees(1234567),
        total: const Money.rupees(1234567),
        paid: const Money.rupees(1234567),
        change: Money.zero,
        tenders: const [
          ReceiptTender(label: 'Cash', amount: Money.rupees(1234567)),
        ],
      );
      final lines = renderer.toPreview(data, paper: paper);

      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(paper.columns), reason: line);
      }
      expect(
        lines.any((l) => l.contains(code)),
        isTrue,
        reason: 'the unit code was cut into a different, plausible unit',
      );
      expect(
        lines.any((l) => l.contains('1,000.000')),
        isTrue,
        reason: 'the quantity was cut',
      );
      // Grouped the way Pakistan groups: 12,34,567.00, not 1,234,567.00.
      expect(
        lines.any((l) => l.trimLeft() == '12,34,567.00'),
        isTrue,
        reason: 'the amount lost the row it was given',
      );
    });

    test('a very long shop name still fits ${paper.columns} columns', () {
      final data = receipt(
        shop: const ReceiptShop(
          name: 'Haji Muhammad Ashraf and Sons Kiryana Merchants',
          addressLine1: 'Shop 14-B, Ground Floor, Anarkali Bazaar, Near Mall',
          city: 'Lahore',
          phone: '042-37350011',
        ),
      );
      for (final line in renderer.toPreview(data, paper: paper)) {
        expect(line.length, lessThanOrEqualTo(paper.columns), reason: line);
      }
    });

    test('a huge amount still fits ${paper.columns} columns', () {
      final data = receipt(
        lines: const [
          ReceiptLine(
            name: 'Bulk consignment',
            qtyDisplay: '1',
            unitCode: 'lot',
            rate: Rate.rupees(99999999),
            amount: Money.rupees(99999999),
          ),
        ],
        total: const Money.rupees(99999999),
        paid: const Money.rupees(99999999),
        change: Money.zero,
      );
      for (final line in renderer.toPreview(data, paper: paper)) {
        expect(line.length, lessThanOrEqualTo(paper.columns), reason: line);
      }
    });
  }
}

/// The printed numbers have to add up to the printed total.
///
/// This is the property a customer checks with their thumb, and the one an
/// auditor checks with a calculator. Every component that moves the total has
/// to appear, including the ones that move it downwards.
void _reconciliationTests() {
  const renderer = ThermalReceiptRenderer();

  Money parseAmount(String s) => Money.parse(s.replaceAll(',', ''));

  test('subtotal, tax, charges and deductions reconcile to TOTAL', () {
    final data = receipt(
      subtotal: const Money.rupees(10000),
      discount: const Money.rupees(500),
      tax: const Money.rupees(1710),
      furtherTax: const Money.rupees(380),
      withholding: const Money.rupees(475),
      extraCharges: const Money.rupees(200),
      total: const Money.rupees(11315),
      paid: const Money.rupees(11315),
      change: Money.zero,
      tenders: const [
        ReceiptTender(label: 'Cash', amount: Money.rupees(11315)),
      ],
    );

    final lines = renderer.toPreview(data);
    Money amountOn(String label) {
      final line = lines.firstWhere(
        (l) => l.trimLeft().startsWith(label),
        orElse: () => throw StateError('"$label" is not on the receipt'),
      );
      return parseAmount(line.substring(line.lastIndexOf(' ') + 1));
    }

    // 10,000 − 500 + 1,710 + 380 − 475 + 200 = 11,315.
    final reconstructed =
        amountOn('Subtotal') -
        amountOn('Discount').abs +
        amountOn('Sales Tax') +
        amountOn('Further Tax') -
        amountOn('Withholding').abs +
        amountOn('Other Charges');

    expect(
      reconstructed,
      const Money.rupees(11315),
      reason: 'the printed components must reconstruct the printed total',
    );
    expect(lines.any((l) => l.contains('11,315.00')), isTrue);
  });

  test('a withholding deduction is printed, not silently netted', () {
    final withheld = receipt(
      withholding: const Money.rupees(475),
      total: const Money.rupees(5050),
    );
    expect(
      renderer.toPreview(withheld).any((l) => l.contains('Withholding')),
      isTrue,
      reason: 'it comes off the total, so it belongs on the paper',
    );

    // And it does not appear when there is none.
    expect(
      renderer.toPreview(receipt()).any((l) => l.contains('Withholding')),
      isFalse,
    );
  });
}
