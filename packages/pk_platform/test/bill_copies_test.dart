import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

/// A bill that looks like the shop's own (M51): the sheet it is, the
/// transporter's copy with no prices, the khata block, four PDF layouts,
/// and the shop's own payment QR — never one made here.
void main() {
  group('the transporter copy', _transporterTests);
  group('copy marks', _markTests);
  group('the khata block', _khataTests);
  group('PDF layouts', _layoutTests);
  group('the payment QR', _qrTests);
  group('bill pictures', _pictureTests);
}

const renderer = ThermalReceiptRenderer();

/// Every money figure on [bill], as the paper would print it. All of them
/// carry a thousands comma, so none can be mistaken for a coordinate inside
/// a PDF.
const moneyOnTheBill = [
  '2,450.00',
  '4,900.00',
  '6,200.00',
  '1,450.00',
  '12,550.00',
  '5,000.00',
  '7,550.00',
  '3,500.00',
  '11,050.00',
];

ReceiptData bill({
  ReceiptCopy? copy,
  bool reprint = false,
  bool cancelled = false,
  Money? before = const Money.rupees(3500),
  Uint8List? paymentQr,
  MonoBitmap? bankQr,
  List<String> footer = const ['Shukriya! Phir tashreef laayen'],
  String docTitle = 'Invoice',
  bool taxed = false,
}) {
  ReceiptLine line(String name, int qty, String unit, int rupees) {
    final amount = Money.rupees(rupees * qty);
    return ReceiptLine(
      name: name,
      qtyDisplay: '$qty',
      unitCode: unit,
      rate: Rate.rupees(rupees),
      amount: amount,
      tax: taxed
          ? ReceiptLineTax(
              valueExclTax: amount,
              salesTax: Money.paisa(amount.inPaisa * 18 ~/ 100),
              rateBp: 1800,
              hsCode: '1507.9000',
            )
          : null,
    );
  }

  return ReceiptData(
    shop: const ReceiptShop(
      name: 'Chishti Kiryana Store',
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
    docNo: 'INV-2627-0042',
    docTitle: docTitle,
    dateTimeLabel: '02-10-2026  4:30 PM',
    cashierName: 'Malik Sahib',
    customerName: 'Rashid Traders',
    customerPhone: copy == ReceiptCopy.transporter ? '0321-7654321' : null,
    customerAddress: 'Shop 5, Shah Alam Market, Lahore',
    customerNtn: '7654321-0',
    customerStrn: '1700000000011',
    lines: [
      line('Cooking Oil 5L', 2, 'pcs', 2450),
      line('Chawal Basmati', 1, 'bori', 6200),
      line('Ghee 16L', 1, 'tin', 1450),
    ],
    subtotal: const Money.rupees(12550),
    total: const Money.rupees(12550),
    tenders: const [
      ReceiptTender(label: 'Cash', amount: Money.rupees(5000), isCash: true),
    ],
    paid: const Money.rupees(5000),
    balance: const Money.rupees(7550),
    change: Money.zero,
    previousBalance: before,
    billOwed: before == null ? null : const Money.rupees(7550),
    footerLines: footer,
    bankQr: bankQr,
    paymentQr: paymentQr,
    fbrInvoiceNo: '182736-021025163000-0001',
    copy: copy,
    isReprint: reprint,
    isCancelled: cancelled,
    transport: const ReceiptTransport(
      transporter: 'Daewoo Cargo',
      vehicleNo: 'LES-1234',
      biltyNo: 'BT-88123',
      shipTo: 'Faisalabad adda',
    ),
  );
}

/// The words of a PDF written uncompressed, as one string.
Future<String> pdfText(
  ReceiptData data, {
  BillDesign design = const BillDesign(),
  Uint8List? unicodeFont,
}) async => String.fromCharCodes(
  await billPdf(
    data,
    design: design,
    unicodeFont: unicodeFont,
    compress: false,
  ),
);

/// A small black-and-white picture standing in for the QR a bank issued.
/// Deliberately not a QR: nothing here, test or not, makes one.
Uint8List checkerboard({int size = 64, bool clearBackground = false}) {
  final picture = img.Image(width: size, height: size, numChannels: 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final dark = (x ~/ 8 + y ~/ 8).isEven;
      picture.setPixelRgba(
        x,
        y,
        dark ? 0 : 255,
        dark ? 0 : 255,
        dark ? 0 : 255,
        clearBackground && !dark ? 0 : 255,
      );
    }
  }
  return Uint8List.fromList(img.encodePng(picture));
}

void _transporterTests() {
  test('carries no amount anywhere on 80mm, 42 and 58mm paper', () {
    for (final paper in ReceiptPaper.values) {
      final paperText = renderer
          .toPreview(bill(copy: ReceiptCopy.transporter), paper: paper)
          .join('\n');
      for (final amount in moneyOnTheBill) {
        expect(paperText, isNot(contains(amount)), reason: '$paper: $amount');
      }
      for (final word in [
        'Rs ',
        'TOTAL',
        'Subtotal',
        // With its space: "Cashier" is a name, not a tender.
        'Cash ',
        'BAQAYA',
        'baqaya',
        'Payment ke liye',
        'Raast',
        'PK36MEZN',
        'FBR',
      ]) {
        expect(paperText, isNot(contains(word)), reason: '$paper: $word');
      }
    }
  });

  test('names the goods, the buyer, where they go and the bilty', () {
    for (final paper in ReceiptPaper.values) {
      final lines = renderer.toPreview(
        bill(copy: ReceiptCopy.transporter),
        paper: paper,
      );
      final paperText = lines.join('\n');
      for (final word in [
        'TRANSPORTER / DELIVERY COPY',
        'qeemat ke baghair',
        'INV-2627-0042',
        'Rashid Traders',
        '0321-7654321',
        'Shah Alam Market',
        'Cooking Oil 5L',
        '2 pcs',
        '1 bori',
        'Daewoo Cargo',
        'LES-1234',
        'BT-88123',
        'Faisalabad adda',
        '3 item(s)',
      ]) {
        expect(paperText, contains(word), reason: '$paper: $word');
      }
      for (final line in lines) {
        expect(
          line.length,
          lessThanOrEqualTo(paper.columns),
          reason: '$paper overhangs: "$line"',
        );
      }
    }
  });

  test('sends no QR picture and no FBR code to the printer', () {
    final dots = pictureDots(checkerboard(), paperDots: 576)!;
    final withBoth = renderer.toThermalBytes(bill(bankQr: dots));
    final transporter = renderer.toThermalBytes(
      bill(copy: ReceiptCopy.transporter, bankQr: dots),
    );
    int rasters(List<int> bytes) {
      var n = 0;
      for (var i = 0; i + 2 < bytes.length; i++) {
        if (bytes[i] == 0x1D && bytes[i + 1] == 0x76 && bytes[i + 2] == 0x30) {
          n++;
        }
      }
      return n;
    }

    expect(rasters(withBoth), 2, reason: 'the QR and FBR code on the bill');
    expect(rasters(transporter), 0);
  });

  test('carries no amount anywhere in the PDF, whatever the layout', () async {
    for (final theme in BillTheme.values) {
      final text = await pdfText(
        bill(
          copy: ReceiptCopy.transporter,
          paymentQr: checkerboard(),
          taxed: true,
        ),
        design: BillDesign(theme: theme),
      );
      for (final amount in [...moneyOnTheBill, '882.00', '18%']) {
        expect(text, isNot(contains(amount)), reason: '$theme: $amount');
      }
      for (final word in ['TOTAL', 'Amount', 'Raast', 'Baqaya', 'KHATA']) {
        expect(text, isNot(contains('($word')), reason: '$theme: $word');
      }
      expect(text, isNot(contains(_image)), reason: '$theme: the QR');
      expect(text, contains('TRANSPORTER COPY'), reason: 'the file title');
      for (final word in ['Cooking', 'Daewoo', 'BT-88123', 'Rashid']) {
        expect(text, contains(word), reason: '$theme: $word');
      }
    }
  });
}

void _markTests() {
  test(
    'each sheet says which it is, on the roll and in the PDF title',
    () async {
      for (final copy in [
        ReceiptCopy.original,
        ReceiptCopy.duplicate,
        ReceiptCopy.triplicate,
      ]) {
        final paperText = renderer.toPreview(bill(copy: copy)).join('\n');
        expect(paperText, contains('** ${copy.mark} **'));
        final pdf = await renderer.toPdf(bill(copy: copy));
        expect(
          String.fromCharCodes(pdf),
          contains('Invoice INV-2627-0042 - ${copy.titleWord}'),
        );
      }
      final triplicate = renderer.toPreview(bill(copy: ReceiptCopy.triplicate));
      expect(triplicate.join('\n'), contains('TRIPLICATE / TEESRI COPY'));
      expect(triplicate.join('\n'), contains('TOTAL'));
    },
  );

  test('a sheet nobody chose prints as it always did', () async {
    final plain = renderer.toPreview(bill()).join('\n');
    for (final copy in ReceiptCopy.values) {
      expect(plain, isNot(contains(copy.mark)));
    }
    // M30's duplicate mark still comes from a printed original.
    final reprint = renderer.toPreview(bill(reprint: true)).join('\n');
    expect(reprint, contains('** DUPLICATE / DOBARA COPY **'));
    // And a chosen sheet wins over it.
    final chosen = renderer
        .toPreview(bill(reprint: true, copy: ReceiptCopy.triplicate))
        .join('\n');
    expect(chosen, contains('TRIPLICATE'));
    expect(chosen, isNot(contains('DUPLICATE')));
  });
}

void _khataTests() {
  test('prints pichhla baqaya, is bill and kul baqaya in place of the udhaar '
      'line', () {
    for (final paper in ReceiptPaper.values) {
      final lines = renderer.toPreview(bill(), paper: paper);
      String row(String label) => lines.firstWhere((l) => l.startsWith(label));
      expect(row('Pichhla baqaya').endsWith('3,500.00'), isTrue);
      expect(row('Is bill').endsWith('7,550.00'), isTrue);
      expect(row('KUL BAQAYA').endsWith('11,050.00'), isTrue);
      expect(
        lines.any((l) => l.startsWith('BAQAYA (udhaar)')),
        isFalse,
        reason: 'is bill IS the udhaar line; printing both says it twice',
      );
      for (final line in lines) {
        expect(line.length, lessThanOrEqualTo(paper.columns));
      }
    }
  });

  test('a later copy says its figures are the bill\'s own day', () {
    final first = renderer.toPreview(bill()).join('\n');
    final later = renderer
        .toPreview(bill(copy: ReceiptCopy.duplicate))
        .join('\n');
    expect(first, isNot(contains('bill ke din ka hisaab')));
    expect(later, contains('(bill ke din ka hisaab)'));
  });

  test('a cancelled bill asks for nothing', () {
    final paperText = renderer.toPreview(bill(cancelled: true)).join('\n');
    expect(paperText, isNot(contains('KUL BAQAYA')));
    expect(paperText, isNot(contains('Pichhla baqaya')));
  });

  test('an advance the shop holds prints as a minus', () {
    final lines = renderer.toPreview(bill(before: const Money.rupees(-2000)));
    expect(
      lines.firstWhere((l) => l.startsWith('Pichhla baqaya')),
      endsWith('-2,000.00'),
    );
    expect(
      lines.firstWhere((l) => l.startsWith('KUL BAQAYA')),
      endsWith('5,550.00'),
    );
  });

  test('without a block the bill keeps its own udhaar line', () {
    final lines = renderer.toPreview(bill(before: null));
    expect(lines.any((l) => l.startsWith('BAQAYA (udhaar)')), isTrue);
    expect(lines.any((l) => l.startsWith('KUL BAQAYA')), isFalse);
  });

  test('the khata block and the shop\'s footer reach the PDF', () async {
    final text = await pdfText(
      bill(footer: const ['Bika hua maal wapas nahi hoga']),
      design: const BillDesign(theme: BillTheme.modern),
    );
    for (final word in ['Pichhla', 'Kul', '3,500.00', '11,050.00', 'Bika']) {
      expect(text, contains(word), reason: word);
    }
  });
}

void _layoutTests() {
  test('every layout renders on A5 and A4, one page for a short bill and '
      'paginating a long one', () async {
    final long = [
      // Enough that even the compact layout on A4 needs a second sheet.
      for (var i = 0; i < 90; i++)
        ReceiptLine(
          name: 'Item number ${i + 1} with a reasonably long name',
          qtyDisplay: '1',
          unitCode: 'pcs',
          rate: const Rate.rupees(250),
          amount: const Money.rupees(250),
        ),
    ];
    for (final theme in BillTheme.values) {
      for (final page in BillPageSize.values) {
        final design = BillDesign(
          theme: theme,
          pageSize: page,
          accent: BillAccent.maroon,
        );
        final short = String.fromCharCodes(
          await billPdf(bill(paymentQr: checkerboard()), design: design),
        );
        expect(short.substring(0, 5), '%PDF-');
        expect(_pageCount(short), 1, reason: '$theme on $page');

        final many = String.fromCharCodes(
          await billPdf(
            ReceiptData(
              shop: const ReceiptShop(name: 'Chishti Kiryana Store'),
              docNo: 'INV-1',
              dateTimeLabel: '02-10-2026',
              cashierName: 'Malik',
              lines: long,
              subtotal: const Money.rupees(22500),
              total: const Money.rupees(22500),
              tenders: const [],
              paid: Money.zero,
              balance: Money.zero,
              change: Money.zero,
            ),
            design: design,
          ),
        );
        expect(
          _pageCount(many),
          greaterThan(1),
          reason: '$theme on $page clipped a long bill instead of paginating',
        );
      }
    }
  });

  test('the tax invoice carries every particular s.23 asks for', () async {
    final text = await pdfText(
      bill(taxed: true),
      design: const BillDesign(theme: BillTheme.taxInvoice),
    );
    // Serial number and date.
    for (final word in ['INV-2627-0042', '02-10-2026']) {
      expect(text, contains(word), reason: word);
    }
    // What it is.
    for (final word in ['SALES', 'TAX', 'INVOICE']) {
      expect(text, contains('($word'), reason: word);
    }
    // The supplier's name, address and registration numbers.
    for (final word in [
      'SELLER',
      'Chishti',
      'Anarkali',
      'NTN',
      '1234567-8',
      'STRN',
      '3277876123456',
    ]) {
      expect(text, contains(word), reason: 'seller: $word');
    }
    // The recipient's.
    for (final word in [
      'BUYER',
      'Rashid',
      'Shah',
      'Alam',
      '7654321-0',
      '1700000000011',
    ]) {
      expect(text, contains(word), reason: 'buyer: $word');
    }
    // Description and quantity, value excluding tax, the rate, the sales tax
    // and the value including it, line by line.
    for (final word in [
      'Cooking',
      'Description',
      'Qty',
      'excl.',
      'Rate',
      'Sales',
      'incl.',
      'HS',
      '1507.9000',
      '(pcs)',
      '4,900.00',
      '18%',
      '882.00',
      '5,782.00',
      '6,200.00',
      '1,116.00',
      '7,316.00',
    ]) {
      expect(text, contains(word), reason: 'lines: $word');
    }
  });

  test(
    'further tax has a column of its own, and each row adds across',
    () async {
      final taxed = bill(taxed: true);
      final first = taxed.lines.first;
      final withFurther = taxed.copyWith(
        lines: [
          first.withTax(
            ReceiptLineTax(
              valueExclTax: first.amount,
              salesTax: const Money.rupees(882),
              furtherTax: const Money.rupees(196),
              rateBp: 1800,
            ),
          ),
          ...taxed.lines.skip(1),
        ],
      );
      const design = BillDesign(theme: BillTheme.taxInvoice);
      final plain = await pdfText(taxed, design: design);
      final text = await pdfText(withFurther, design: design);
      expect(plain, isNot(contains('(Further')));
      expect(text, contains('(Further'));
      // 4,900 + 882 + 196.
      for (final figure in ['882.00', '196.00', '5,978.00']) {
        expect(text, contains(figure), reason: figure);
      }
      expect(
        text,
        isNot(contains('1,078.00')),
        reason: 'folded into sales tax',
      );
    },
  );

  test('a quotation in the tax layout is not called a tax invoice', () async {
    final text = await pdfText(
      bill(docTitle: 'Quotation', taxed: true),
      design: const BillDesign(theme: BillTheme.taxInvoice),
    );
    expect(text, contains('(QUOTATION'));
    expect(text, isNot(contains('(INVOICE')));
  });

  test('an Urdu footer is joined in the PDF, like an Urdu shop name', () async {
    final font = Uint8List.fromList(
      File(
        '${Directory.current.path}/../../assets/fonts/NotoNaskhArabic-Regular.ttf',
      ).readAsBytesSync(),
    );
    final bytes = await billPdf(
      bill(footer: const ['شکریہ! پھر تشریف لائیں']),
      design: const BillDesign(theme: BillTheme.compact),
      unicodeFont: font,
    );
    final mapped = _mappedCodepoints(bytes);
    expect(mapped.where((c) => c >= 0xFB50 && c <= 0xFEFF), isNotEmpty);
    expect(
      mapped.where((c) => c >= 0x0600 && c <= 0x06FF),
      isEmpty,
      reason: 'a footer line was set left to right and came out unjoined',
    );
  });

  test('a tax rate prints as the 8th Schedule writes it', () {
    String label(int? bp) => ReceiptLineTax(
      valueExclTax: Money.zero,
      salesTax: Money.zero,
      rateBp: bp,
    ).rateLabel;
    expect(label(1800), '18%');
    expect(label(850), '8.5%');
    expect(label(1275), '12.75%');
    expect(label(0), '0%');
    expect(label(null), '-');
  });
}

void _qrTests() {
  test(
    'the shop\'s own QR picture appears on the PDF when it has one',
    () async {
      for (final theme in BillTheme.values) {
        final text = String.fromCharCodes(
          await billPdf(
            bill(paymentQr: checkerboard()),
            design: BillDesign(theme: theme),
          ),
        );
        expect(text, contains(_image), reason: '$theme');
      }
    },
  );

  test(
    'without a picture there is no QR, only the alias and IBAN as text',
    () async {
      for (final theme in BillTheme.values) {
        final text = await pdfText(bill(), design: BillDesign(theme: theme));
        expect(text, isNot(contains(_image)), reason: '$theme drew a picture');
        expect(text, contains('03001234567'), reason: '$theme: the alias');
        expect(text, contains('PK36MEZN0001234567890101'), reason: 'the IBAN');
      }
    },
  );

  test('nothing in the bill renderers can draw a QR of their own', () {
    for (final file in [
      'lib/src/receipt/bill_pdf.dart',
      'lib/src/receipt/bill_pictures.dart',
      'lib/src/receipt/receipt_layout.dart',
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

  test('the QR goes on the till roll as dots only when it is handed dots', () {
    final dots = pictureDots(checkerboard(), paperDots: 576)!;
    int rasters(List<int> bytes) {
      var n = 0;
      for (var i = 0; i + 2 < bytes.length; i++) {
        if (bytes[i] == 0x1D && bytes[i + 1] == 0x76 && bytes[i + 2] == 0x30) {
          n++;
        }
      }
      return n;
    }

    // The picture for the PDF alone puts nothing on the roll; the FBR code
    // is the one raster either way.
    expect(
      rasters(renderer.toThermalBytes(bill(paymentQr: checkerboard()))),
      1,
    );
    expect(rasters(renderer.toThermalBytes(bill(bankQr: dots))), 2);
  });
}

void _pictureTests() {
  test('a logo with a clear background is laid on white, not black', () {
    final logo = prepareShopLogo(
      checkerboard(size: 600, clearBackground: true),
      id: 'firm-1',
    );
    expect(logo.bytes.length, lessThanOrEqualTo(ImageAttachment.maxBytes));
    expect(logo.width, lessThanOrEqualTo(400));
    final back = img.decodeImage(logo.bytes)!;
    // (8, 0) is in a clear square of the board.
    final pixel = back.getPixel(back.width ~/ 75 + 8 * back.width ~/ 600, 0);
    expect([pixel.r, pixel.g, pixel.b], [255, 255, 255]);
  });

  test('a QR screenshot is kept as a small grey PNG', () {
    final qr = preparePaymentQr(checkerboard(size: 1200), id: 'firm-1');
    expect(qr.mimeType, 'image/png');
    expect(qr.bytes.length, lessThanOrEqualTo(ImageAttachment.maxBytes));
    expect(qr.width, 800);
    expect(img.decodePng(qr.bytes)!.numChannels, 1);
  });

  test('something that is not a picture is refused in words', () {
    final notAPicture = Uint8List.fromList('%PDF-1.4 not a picture'.codeUnits);
    expect(
      () => prepareShopLogo(notAPicture, id: 'x'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => preparePaymentQr(notAPicture, id: 'x'),
      throwsA(isA<FormatException>()),
    );
    expect(pictureDots(notAPicture, paperDots: 384), isNull);
  });

  test('a picture becomes paper-width dots the printer accepts', () {
    final half = img.Image(width: 100, height: 100);
    img.fill(half, color: img.ColorRgb8(255, 255, 255));
    img.fillRect(
      half,
      x1: 0,
      y1: 0,
      x2: 49,
      y2: 99,
      color: img.ColorRgb8(0, 0, 0),
    );
    final dots = pictureDots(
      Uint8List.fromList(img.encodePng(half)),
      paperDots: 384,
      widthPercent: 50,
    )!;
    expect(dots.width, 384);
    expect(dots.bits.length, dots.bytesPerRow * dots.height);
    bool set(int x, int y) =>
        dots.bits[y * dots.bytesPerRow + (x >> 3)] & (0x80 >> (x & 7)) != 0;
    // Centred: the picture spans 96..288, its left half dark.
    expect(set(100, 50), isTrue);
    expect(set(280, 50), isFalse);
    expect(set(10, 50), isFalse, reason: 'outside the picture is paper');
    expect(() => EscPos().raster(dots), returnsNormally);
  });
}

/// An image XObject: a picture placed on the page. Not the ProcSet's
/// `/ImageB`, which every page names whether it holds a picture or not.
final _image = RegExp(r'/Subtype\s*/Image');

int _pageCount(String pdfText) {
  final match = RegExp(r'/Count (\d+)').firstMatch(pdfText);
  return match == null ? 0 : int.parse(match.group(1)!);
}

/// Every Unicode codepoint the PDF's embedded subsets claim to draw (see
/// urdu_pdf_test.dart for why this is the assertion that matters).
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
