import 'dart:io';
import 'dart:typed_data';

import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

import 'bill_copies_test.dart' show bill, checkerboard, moneyOnTheBill;
import 'receipt_test.dart' show receipt;

/// More bills to choose from (M70): four PDF layouts beside M51's four —
/// a landscape page for wholesale, the ruled bill book, a serif page and a
/// bare one — and two till slips beside the one every bill has printed:
/// compact, and the total printed large.
void main() {
  group('the new PDF designs', _pdfTests);
  group('the till slips', _slipTests);
}

const renderer = ThermalReceiptRenderer();

const m70Designs = [
  BillTheme.landscape,
  BillTheme.ruled,
  BillTheme.elegant,
  BillTheme.minimal,
];

final _font = Uint8List.fromList(
  File(
    '${Directory.current.path}/../../assets/fonts/NotoNaskhArabic-Regular.ttf',
  ).readAsBytesSync(),
);

/// [bill] from a shop whose name is in Urdu, as a shop types it.
ReceiptData urduShop({bool taxed = true, ReceiptCopy? copy}) =>
    bill(taxed: taxed, paymentQr: checkerboard(), copy: copy).copyWith(
      shop: const ReceiptShop(
        name: 'الفلاح کریانہ سٹور',
        addressLine1: 'Shop 14, Anarkali',
        city: 'Lahore',
        phone: '0300-4471203',
        ntn: '1234567-8',
        strn: '3277876123456',
        raastAlias: '03001234567',
        bankName: 'Meezan',
        bankAccountTitle: 'Chishti Kiryana',
        bankIban: 'PK36MEZN0001234567890101',
      ),
    );

/// The words of a PDF written uncompressed.
Future<String> words(ReceiptData data, BillDesign design) async =>
    String.fromCharCodes(
      await billPdf(data, design: design, unicodeFont: _font, compress: false),
    );

void _pdfTests() {
  test('each new design renders a real PDF with the shop\'s Urdu name '
      'joined, on A5 and A4', () async {
    for (final theme in m70Designs) {
      for (final page in BillPageSize.values) {
        final bytes = await billPdf(
          urduShop(),
          design: BillDesign(theme: theme, pageSize: page),
          unicodeFont: _font,
        );
        expect(
          String.fromCharCodes(bytes.take(5)),
          '%PDF-',
          reason: '$theme $page',
        );
        final mapped = _mappedCodepoints(bytes);
        expect(
          mapped.where((c) => c >= 0xFB50 && c <= 0xFEFF),
          isNotEmpty,
          reason: '$theme $page: the Urdu name is not on the page',
        );
        expect(
          mapped.where((c) => c >= 0x0600 && c <= 0x06FF),
          isEmpty,
          reason: '$theme $page: the Urdu name was set left to right, unjoined',
        );
        expect(_pageCount(String.fromCharCodes(bytes)), 1);
      }
    }
  });

  test('the four are four different pages', () async {
    final text = {
      for (final theme in m70Designs)
        theme: await words(urduShop(), BillDesign(theme: theme)),
    };
    // The landscape page is on its side.
    final box = RegExp(
      r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)\s*\]',
    ).firstMatch(text[BillTheme.landscape]!)!;
    expect(
      double.parse(box.group(1)!),
      greaterThan(double.parse(box.group(2)!)),
      reason: 'the landscape page is taller than it is wide',
    );
    // The bill book: M/s on its line, the total in words, a line to sign.
    for (final word in [
      '(M/s',
      '(Signature',
      '(E.',
      '(Particulars',
      'Twelve',
    ]) {
      expect(text[BillTheme.ruled], contains(word), reason: 'ruled: $word');
    }
    // The elegant page is set in Times, and only it.
    expect(text[BillTheme.elegant], contains('/Times-Roman'));
    expect(text[BillTheme.elegant], contains('(Amount'));
    for (final theme in [
      BillTheme.landscape,
      BillTheme.ruled,
      BillTheme.minimal,
    ]) {
      expect(text[theme], isNot(contains('/Times-Roman')), reason: '$theme');
    }
    // The bare page's quiet column heads.
    for (final word in ['(ITEM', '(QTY', '(RATE', '(AMOUNT']) {
      expect(text[BillTheme.minimal], contains(word), reason: word);
    }
    // And none of them is another's page.
    final pages = text.values.toSet();
    expect(pages, hasLength(4));
  });

  test('the landscape page carries every particular s.23 asks for, for a '
      'registered seller', () async {
    final text = await words(
      urduShop(),
      const BillDesign(theme: BillTheme.landscape),
    );
    for (final word in ['(SALES', '(TAX', '(INVOICE']) {
      expect(text, contains(word), reason: word);
    }
    for (final word in [
      // Serial number and date.
      'INV-2627-0042',
      '02-10-2026',
      // The supplier's address and registration numbers.
      'SELLER',
      'Anarkali',
      '1234567-8',
      '3277876123456',
      // The recipient's.
      'BUYER',
      'Rashid',
      'Shah',
      '7654321-0',
      '1700000000011',
      // Every line: HS code, quantity, unit, rate, the value before tax,
      // the rate, the tax, and the value with it.
      'HS',
      '1507.9000',
      'Description',
      '(pcs)',
      'Disc.',
      'excl.',
      'Tax',
      'incl.',
      '4,900.00',
      '18%',
      '882.00',
      '5,782.00',
      '6,200.00',
      '1,116.00',
      '7,316.00',
    ]) {
      expect(text, contains(word), reason: word);
    }
  });

  test('the landscape page of an unregistered shop is an invoice, with '
      'gross, discount and net', () async {
    final unregistered = bill().copyWith(
      shop: const ReceiptShop(name: 'Chishti Kiryana Store', city: 'Lahore'),
    );
    final text = await words(
      unregistered,
      const BillDesign(theme: BillTheme.landscape),
    );
    expect(text, isNot(contains('(SALES')));
    expect(text, contains('(INVOICE'));
    for (final word in ['(Gross', '(Disc.', '(Net', '(Unit', '4,900.00']) {
      expect(text, contains(word), reason: word);
    }
    expect(text, isNot(contains('(Value')), reason: 'no tax columns');
  });

  test('a quotation is never called a tax invoice, and a transporter\'s '
      'copy carries no money, in any new design', () async {
    for (final theme in m70Designs) {
      final quotation = await words(
        bill(docTitle: 'Quotation', taxed: true),
        BillDesign(theme: theme),
      );
      expect(quotation, contains('(QUOTATION'), reason: '$theme');
      expect(quotation, isNot(contains('(SALES')), reason: '$theme');

      final transporter = await words(
        urduShop(copy: ReceiptCopy.transporter),
        BillDesign(theme: theme),
      );
      for (final amount in [...moneyOnTheBill, '882.00', '18%']) {
        expect(transporter, isNot(contains(amount)), reason: '$theme $amount');
      }
      for (final word in ['(TOTAL', '(Amount', '(Raast', '(KHATA', '(FBR']) {
        expect(transporter, isNot(contains(word)), reason: '$theme $word');
      }
      for (final word in ['Cooking', 'Daewoo', 'BT-88123', 'Rashid']) {
        expect(transporter, contains(word), reason: '$theme $word');
      }
    }
  });

  test('a cancelled bill is marked, and the khata of a later copy says it '
      'is the bill\'s own day, in every new design', () async {
    for (final theme in m70Designs) {
      final cancelled = await words(
        bill(cancelled: true),
        BillDesign(theme: theme),
      );
      expect(cancelled, contains('(CANCELLED'), reason: '$theme');
      final later = await words(
        bill(copy: ReceiptCopy.duplicate),
        BillDesign(theme: theme),
      );
      expect(later, contains('DUPLICATE'), reason: '$theme');
      expect(later, contains('ke'), reason: '$theme: bill ke din ka hisaab');
      expect(later, contains('11,050.00'), reason: '$theme: kul baqaya');
    }
  });

  test('nothing in the new renderers can draw a QR of their own', () {
    for (final file in [
      'lib/src/receipt/bill_pdf_designs.dart',
      'lib/src/receipt/receipt_slip.dart',
    ]) {
      final code = File(file)
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final word in ['Barcode', 'qrCode', 'QrCode', 'package:barcode']) {
        expect(code, isNot(contains(word)), reason: '$file: $word');
      }
    }
  });
}

/// Receipts a shopkeeper can produce, the hostile ones M2 to M59 found
/// included, for every slip on every paper.
List<(String, ReceiptData)> get _battery => [
  ('the M51 bill', bill()),
  ('a transporter copy', bill(copy: ReceiptCopy.transporter)),
  ('a cancelled bill', bill(cancelled: true)),
  ('an advance held', bill(before: const Money.rupees(-2000))),
  ('no khata block', bill(before: null)),
  ('the counter receipt', receipt()),
  (
    'a long free-text phone',
    receipt(
      customerName: 'Bilal General Store',
      customerPhone: '0300-1234567 / 042-35123456 whatsapp only please',
    ),
  ),
  (
    'a long unit code',
    receipt(
      lines: const [
        ReceiptLine(
          name: 'Atta',
          qtyDisplay: '1,000.000',
          unitCode: 'bori-50kg-special-import',
          rate: Rate.rupees(12450),
          amount: Money.rupees(1234567),
        ),
      ],
      subtotal: const Money.rupees(1234567),
      total: const Money.rupees(1234567),
      paid: const Money.rupees(1234567),
      change: Money.zero,
    ),
  ),
  (
    'a huge amount',
    receipt(
      lines: const [
        ReceiptLine(
          name: 'Bulk consignment',
          qtyDisplay: '1',
          unitCode: 'lot',
          rate: Rate.rupees(99999999),
          amount: Money.rupees(99999999),
        ),
      ],
      subtotal: const Money.rupees(99999999),
      total: const Money.rupees(99999999),
      paid: const Money.rupees(99999999),
      change: Money.zero,
    ),
  ),
  (
    'a very long shop name',
    receipt(
      shop: const ReceiptShop(
        name: 'Haji Muhammad Ashraf and Sons Kiryana Merchants',
        addressLine1: 'Shop 14-B, Ground Floor, Anarkali Bazaar, Near Mall',
        city: 'Lahore',
        phone: '042-37350011',
      ),
    ),
  ),
  (
    'an Urdu item, packs, a phone with IMEIs and a discount',
    receipt(
      lines: const [
        ReceiptLine(
          name: 'چاول باسمتی',
          qtyDisplay: '2',
          unitCode: 'kg',
          rate: Rate.rupees(300),
          amount: Money.rupees(600),
        ),
        ReceiptLine(
          name: 'Surf Excel 1kg',
          qtyDisplay: '53',
          unitCode: 'pcs',
          rate: Rate.rupees(40),
          amount: Money.rupees(2120),
          qtyWords: '2 ctn 5 pc',
          discount: Money.rupees(20),
        ),
        ReceiptLine(
          name: 'Samsung Galaxy A15 128GB with a long name that wraps',
          qtyDisplay: '1',
          unitCode: 'pcs',
          rate: Rate.rupees(42000),
          amount: Money.rupees(42000),
          details: ['IMEI 1: 356938035643809', 'Warranty till 3 Apr 2027'],
        ),
      ],
      subtotal: const Money.rupees(44720),
      discount: const Money.rupees(20),
      total: const Money.rupees(44700),
      paid: const Money.rupees(44700),
      change: Money.zero,
    ),
  ),
];

List<String> _slip(ReceiptData d, ReceiptSlip slip, ReceiptPaper paper) =>
    renderer.toPreview(d.copyWith(slip: slip), paper: paper);

void _slipTests() {
  test('no line of either slip overhangs 48, 42 or 32 columns', () {
    for (final (name, data) in _battery) {
      for (final slip in ReceiptSlip.values) {
        for (final paper in ReceiptPaper.values) {
          for (final line in _slip(data, slip, paper)) {
            expect(
              line.length,
              lessThanOrEqualTo(paper.columns),
              reason: '$name, $slip on ${paper.columns}: "$line"',
            );
          }
        }
      }
    }
  });

  test('the compact slip says every word and figure the standard one does, '
      'on less paper', () {
    // What compact drops on purpose: the rules, the column heads, the labels
    // of the number and date it puts on one row, and a Subtotal that is the
    // total.
    const dropped = {'Item', 'Amount', 'Qty', 'Bill', 'No', 'Date'};
    for (final (name, data) in _battery) {
      for (final paper in ReceiptPaper.values) {
        final standard = _slip(data, ReceiptSlip.standard, paper);
        final compact = _slip(data, ReceiptSlip.compact, paper);
        Map<String, int> count(List<String> lines) {
          final out = <String, int>{};
          for (final word in lines.join(' ').split(RegExp(r'\s+'))) {
            if (word.isEmpty || RegExp(r'^[-=]+$').hasMatch(word)) continue;
            out[word] = (out[word] ?? 0) + 1;
          }
          return out;
        }

        final had = count(standard);
        final has = count(compact);
        for (final MapEntry(key: word, value: n) in had.entries) {
          if (dropped.contains(word) || word == 'Subtotal') continue;
          // A Subtotal equal to the total is said once, as the total.
          final allowed = data.subtotal == data.total ? n - 1 : n;
          expect(
            has[word] ?? 0,
            greaterThanOrEqualTo(allowed < 0 ? 0 : allowed),
            reason: '$name on ${paper.columns}: "$word" went missing',
          );
        }
        expect(
          compact.length,
          lessThan(standard.length),
          reason: '$name on ${paper.columns}: no paper saved',
        );
      }
    }
  });

  test('the compact slip puts an item on one line where it fits whole, and '
      'keeps two where it does not', () {
    final lines = _slip(bill(), ReceiptSlip.compact, ReceiptPaper.mm80);
    expect(
      lines,
      contains('Cooking Oil 5L 2 pcs x 2,450.00${' ' * 9}4,900.00'),
    );
    expect(lines, contains('INV-2627-0042${' ' * 17}02-10-2026 4:30 PM'));
    expect(lines.any((l) => l.startsWith('Item ')), isFalse);
    // On 58 mm the same line does not fit whole, and stays as two.
    final narrow = _slip(bill(), ReceiptSlip.compact, ReceiptPaper.mm58);
    expect(narrow, contains('Cooking Oil 5L'));
    expect(
      narrow.any((l) => l.trimLeft().startsWith('2 pcs x 2,450.00')),
      isTrue,
    );
  });

  test('the compact slip prints the shop name in the printer\'s own size, '
      'the standard one twice the size', () {
    final standard = renderer.toThermalBytes(bill());
    final compact = renderer.toThermalBytes(
      bill().copyWith(slip: ReceiptSlip.compact),
    );
    expect(_has(standard, const [0x1D, 0x21, 0x11]), isTrue);
    expect(_has(compact, const [0x1D, 0x21, 0x11]), isFalse);
    expect(compact.length, lessThan(standard.length));
    expect(_ascii(compact), contains('CHISHTI KIRYANA STORE'));
  });

  test('the big total slip prints the total and what is owed twice the '
      'size, each on a line of its own', () {
    final data = bill().copyWith(slip: ReceiptSlip.bigTotal);
    final lines = renderer.toPreview(data);
    expect(lines.map((l) => l.trim()), contains('T O T A L'));
    expect(lines.map((l) => l.trim()), contains('R s   1 2 , 5 5 0 . 0 0'));
    expect(lines.map((l) => l.trim()), contains('K U L   B A Q A Y A'));
    expect(lines.map((l) => l.trim()), contains('R s   1 1 , 0 5 0 . 0 0'));
    expect(lines.any((l) => l.startsWith('TOTAL ')), isFalse);

    final bytes = renderer.toThermalBytes(data);
    for (final big in ['TOTAL', 'Rs 12,550.00', 'KUL BAQAYA', 'Rs 11,050.00']) {
      final at = _indexOf(bytes, big.codeUnits);
      expect(at, isNonNegative, reason: big);
      // Twice the width and the height (GS ! 0x11), then back (GS ! 0).
      final before = bytes.sublist(0, at);
      final lastBig = _lastIndexOf(before, const [0x1D, 0x21, 0x11]);
      final lastNormal = _lastIndexOf(before, const [0x1D, 0x21, 0x00]);
      expect(lastBig, greaterThan(lastNormal), reason: '$big is not large');
    }
    // The bill's own udhaar, where there is no khata block.
    final udhaar = renderer.toPreview(
      bill(before: null).copyWith(slip: ReceiptSlip.bigTotal),
    );
    expect(
      udhaar.map((l) => l.trim()),
      contains('B A Q A Y A   ( u d h a a r )'),
    );
  });

  test('a figure too long for half the paper stays in its row', () {
    final huge = receipt(
      lines: const [
        ReceiptLine(
          name: 'Bulk consignment',
          qtyDisplay: '1',
          unitCode: 'lot',
          rate: Rate.rupees(99999999),
          amount: Money.rupees(99999999),
        ),
      ],
      subtotal: const Money.rupees(99999999),
      total: const Money.rupees(99999999),
      paid: const Money.rupees(99999999),
      change: Money.zero,
    ).copyWith(slip: ReceiptSlip.bigTotal);
    // Rs 9,99,99,999.00 is seventeen characters: over half of 32.
    final narrow = renderer.toPreview(huge, paper: ReceiptPaper.mm58);
    expect(narrow.any((l) => l.startsWith('TOTAL')), isTrue);
    expect(narrow.any((l) => l.trim() == 'T O T A L'), isFalse);
    // And half of 48 holds it.
    final wide = renderer.toPreview(huge);
    expect(wide.any((l) => l.trim() == 'T O T A L'), isTrue);
  });

  test('an Urdu line on a slip is still drawn, never typed', () {
    final urdu = receipt(
      lines: const [
        ReceiptLine(
          name: 'چاول',
          qtyDisplay: '2',
          unitCode: 'kg',
          rate: Rate.rupees(300),
          amount: Money.rupees(600),
        ),
      ],
      subtotal: const Money.rupees(600),
      total: const Money.rupees(600),
      paid: const Money.rupees(600),
      change: Money.zero,
    );
    for (final slip in ReceiptSlip.values) {
      final data = urdu.copyWith(slip: slip);
      final needed = renderer.unprintableLines(data);
      final shown = renderer.toPreview(data);
      expect(needed.where((l) => l.contains('چاول')), isNotEmpty);
      // Every line asked to be drawn is a line the slip prints.
      for (final line in needed) {
        expect(shown, contains(line), reason: '$slip: $line');
      }
    }
  });

  test('a slip nobody chose prints exactly as every bill printed before', () {
    for (final (name, data) in _battery) {
      for (final paper in ReceiptPaper.values) {
        expect(
          renderer.toPreview(data, paper: paper),
          ReceiptLayout(paper: paper).render(data),
          reason: '$name on ${paper.columns}',
        );
      }
    }
  });
}

bool _has(List<int> bytes, List<int> sequence) =>
    _indexOf(bytes, sequence) >= 0;

int _indexOf(List<int> bytes, List<int> sequence) {
  outer:
  for (var i = 0; i + sequence.length <= bytes.length; i++) {
    for (var j = 0; j < sequence.length; j++) {
      if (bytes[i + j] != sequence[j]) continue outer;
    }
    return i;
  }
  return -1;
}

int _lastIndexOf(List<int> bytes, List<int> sequence) {
  var last = -1;
  outer:
  for (var i = 0; i + sequence.length <= bytes.length; i++) {
    for (var j = 0; j < sequence.length; j++) {
      if (bytes[i + j] != sequence[j]) continue outer;
    }
    last = i;
  }
  return last;
}

String _ascii(List<int> bytes) =>
    String.fromCharCodes(bytes.where((b) => b >= 0x20 && b < 0x7F));

int _pageCount(String pdfText) {
  final match = RegExp(r'/Count (\d+)').firstMatch(pdfText);
  return match == null ? 0 : int.parse(match.group(1)!);
}

/// Every Unicode codepoint the PDF's embedded subsets claim to draw, as
/// bill_copies_test reads them.
Set<int> _mappedCodepoints(Uint8List bytes) {
  final found = <int>{};
  final text = String.fromCharCodes(bytes);
  for (final match in RegExp(r'stream\r?\n').allMatches(text)) {
    final end = text.indexOf('endstream', match.end);
    if (end < 0) continue;
    List<int> inflated;
    try {
      inflated = ZLibDecoder().convert(bytes.sublist(match.end, end));
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
