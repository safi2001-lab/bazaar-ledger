import 'dart:typed_data';

import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

void main() {
  const renderer = ThermalReceiptRenderer();

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
  }) =>
      ReceiptData(
        shop: shop ??
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
        lines: lines ??
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
        subtotal: const Money.rupees(5525),
        total: total,
        tenders: tenders ??
            const [
              ReceiptTender(label: 'Cash', amount: Money.rupees(6000)),
            ],
        paid: paid,
        balance: balance,
        change: change,
        isReprint: reprint,
        footerLines: const ['Shukriya! Phir tashreef laayen'],
      );

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
      expect(
        lines.any((l) => l.contains('98,765,432.10')),
        isTrue,
      );
      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(48));
      }
    });
  });

  group('58mm layout', () {
    test('every line is exactly 32 columns or shorter', () {
      final lines =
          renderer.toPreview(receipt(), paper: ReceiptPaper.mm58);
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

    test('ends with a full cut', () {
      final bytes = renderer.toThermalBytes(receipt());
      expect(bytes.sublist(bytes.length - 3), [0x1D, 0x56, 0x00]);
    });

    test('kicks the drawer only when asked', () {
      const kick = [0x1B, 0x70, 0x00, 0x19, 0xFA];
      expect(
        _contains(renderer.toThermalBytes(receipt()), kick),
        isFalse,
      );
      expect(
        _contains(
          renderer.toThermalBytes(receipt(), openDrawer: true),
          kick,
        ),
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
        expect(b, lessThan(0x100));
      }
    });

    test('prints the shop name once, not twice', () {
      final bytes = renderer.toThermalBytes(receipt());
      final text = String.fromCharCodes(bytes);
      expect(
        'CHISHTI KIRYANA STORE'.allMatches(text).length,
        1,
      );
    });
  });

  group('PDF', () {
    test('produces a real, non-trivial document', () async {
      final bytes = await renderer.toPdf(receipt());
      expect(bytes.length, greaterThan(2048));
      expect(String.fromCharCodes(bytes.sublist(0, 5)), '%PDF-');
      // Trailer present, so the file is complete rather than truncated.
      final tail = String.fromCharCodes(
        bytes.sublist(bytes.length - 64),
      );
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
