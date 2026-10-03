import 'dart:io';

import 'package:bazaar_ledger/features/collections/sheet_paper.dart';
import 'package:bazaar_ledger/features/khata/statement.dart';
import 'package:bazaar_ledger/features/printing/pdf_font.dart';
import 'package:bazaar_ledger/features/printing/text_rasteriser.dart';
import 'package:bazaar_ledger/l10n/app_strings_ur.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:pk_platform/virtual_printer.dart';

/// Urdu on every paper the shop hands over (M62).
///
/// EasyKhata's PDFs are complained of as unreadable, and the market's
/// Pakistani apps are asked again and again for Urdu that reads as Urdu. A
/// PDF is read on the customer's phone, so its face has to travel inside
/// it (M2's PdfUnicodeFont), and Urdu is cursive: a font alone prints a
/// row of separate letters unless the run is set right to left, which is
/// where the pdf package joins them. So each document below is made the way
/// the app makes it — the same builder, the same call, the font the app
/// loads from its own assets — with Urdu names in the fields that carry
/// names, and Roman Urdu where the shop writes it, and then read back:
///
/// * the Noto Naskh face is embedded (the file carries it), and
/// * every Urdu letter put in is in the file as a joined form (Arabic
///   Presentation Forms), and no letter is in it bare, which is what a run
///   left in the default direction looks like — boxes on some viewers,
///   disconnected letters on the rest.
///
/// Each field gets letters no other field has (ش in the customer's name, چ
/// in the item's, گ in the address, پ in the supplier's, ع in the recovery
/// man's), so a field the document dropped or set the wrong way is named.
///
/// What this found: the report PDF set its title, its period line and its
/// notes in the default direction, so a party statement for "رشید ٹریڈرز"
/// printed the name in its title as loose letters, and so did the expiry
/// return note for its supplier, in its title and in the sentence under the
/// table. They are set as the cells and the filters line always were now.
const _shop = 'الفلاح سٹور';
const _customer = 'رشید ٹریڈرز';
const _address = 'گلبرگ لاہور';
const _item = 'چاول باسمتی';
const _supplier = 'پنجاب ملز';
const _collector = 'نعیم';
const _route = 'غلہ منڈی';

/// The joined forms of each letter used, from the Unicode Arabic
/// Presentation Forms blocks: isolated, final, initial, medial.
const _forms = <String, List<int>>{
  'ش': [0xFEB5, 0xFEB6, 0xFEB7, 0xFEB8],
  'چ': [0xFB7A, 0xFB7B, 0xFB7C, 0xFB7D],
  'گ': [0xFB92, 0xFB93, 0xFB94, 0xFB95],
  'پ': [0xFB56, 0xFB57, 0xFB58, 0xFB59],
  'ع': [0xFEC9, 0xFECA, 0xFECB, 0xFECC],
  'غ': [0xFECD, 0xFECE, 0xFECF, 0xFED0],
  'ٹ': [0xFB66, 0xFB67, 0xFB68, 0xFB69],
  'ف': [0xFED1, 0xFED2, 0xFED3, 0xFED4],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppServices shop;
  late String firmId;
  late Uint8List font;
  late String rashid;
  late PostedSale bill;
  late String receiptId;
  late String order;

  setUpAll(() async {
    // The face the app loads for every PDF it shares, from its own assets.
    font = (await PdfUnicodeFont.bytes())!;
    expect(
      font,
      File('assets/fonts/NotoNaskhArabic-Regular.ttf').readAsBytesSync(),
    );

    shop = await openInMemoryServices(
      clock: FixedClock(DateTime.utc(2026, 9, 15, 6)),
    );
    await shop.setUpShop(
      shopName: _shop,
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    firmId = (await shop.queries.currentFirm())!.id;
    final accounts = await shop.queries.paymentAccounts(firmId);
    final cash = accounts.firstWhere((a) => a.modeLabel == 'cash').id;
    final pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs').id;
    rashid = await shop.catalogue.addParty(
      shop.actorNow(),
      const PartyDraft(
        name: _customer,
        phone: '0300-4471203',
        addressLine1: _address,
        group: _route,
      ),
    );
    final mills = await shop.catalogue.addParty(
      shop.actorNow(),
      const PartyDraft(name: _supplier, partyType: 'supplier'),
    );
    final rice = await shop.catalogue.addItem(
      shop.actorNow(),
      ItemDraft(
        name: _item,
        baseUnitId: pcs,
        saleRate: Rate.rupees(2500),
        tracksStock: false,
      ),
    );
    SaleLineDraft riceLine(int n) => SaleLineDraft(
      itemId: rice,
      itemName: _item,
      qty: Qty.units(n),
      baseQty: Qty.units(n),
      unitId: pcs,
      unitCode: 'pcs',
      rate: Rate.rupees(2500),
    );
    bill = await shop.postSale(
      shop.actorNow(),
      SaleDraft(
        partyId: rashid,
        partyName: _customer,
        lines: [riceLine(2)],
        tenders: [
          TenderDraft(
            paymentAccountId: cash,
            mode: 'cash',
            amount: const Money.rupees(1000),
          ),
        ],
      ),
    );
    final paid = await shop.recordReceipt(
      shop.actorNow(),
      ReceiptDraft(
        partyId: rashid,
        amount: const Money.rupees(1500),
        mode: 'cash',
        paymentAccountId: cash,
        notes: 'Baqi agle hafte',
      ),
    );
    receiptId = paid.paymentId;
    order = (await shop.orders.place(
      OrderDraft(
        kind: OrderKind.purchase,
        partyId: mills,
        partyName: _supplier,
        lines: [
          OrderLineDraft(
            itemId: rice,
            itemName: _item,
            qty: Qty.units(20),
            baseQty: Qty.units(20),
            unitId: pcs,
            unitCode: 'pcs',
            rate: Rate.rupees(2100),
          ),
        ],
      ),
    )).id;
  });

  tearDownAll(() => shop.close());

  group('Urdu on every paper', () {
    test('a bill, in each of the four designs', () async {
      for (final theme in BillTheme.values) {
        final design = BillDesign(theme: theme);
        final paper = (await shop.billPaper(
          bill.documentId,
          design: design,
        ))!.receipt;
        final pdf = await shop.receipts.toPdf(
          paper,
          unicodeFont: font,
          design: design,
        );
        _readsAsUrdu(pdf, ['ٹ', 'ف', 'ش', 'چ', 'گ'], '$theme');
        // Roman Urdu stays in the page's own Latin face.
        expect(_words(pdf), contains('Shukriya!'), reason: '$theme');
      }
    });

    test('the customer\'s statement', () async {
      final party = (await shop.queries.partyById(firmId, rashid))!;
      final table = await statementFor(
        shop,
        party,
        span: StatementSpan.thisMonth,
        owedToUs: true,
      );
      final pdf = await reportToPdf(table, shopName: _shop, unicodeFont: font);
      _readsAsUrdu(pdf, ['ٹ', 'ف', 'ش'], 'statement');
    });

    test('a report, its rows and what it was narrowed by', () async {
      final day = ReportPeriod.day(const BusinessDate('2026-09-15'));
      for (final filters in [
        ReportFilters.none,
        ReportFilters(partyId: rashid, partyName: _customer),
      ]) {
        final table = await shop.reports.run(
          ReportKind.saleReport,
          firmId: firmId,
          period: day,
          today: day.to,
          filters: filters,
        );
        final pdf = await reportToPdf(
          table,
          shopName: _shop,
          unicodeFont: font,
        );
        _readsAsUrdu(pdf, ['ٹ', 'ف', 'ش'], 'sale report $filters');
      }
      final items = await shop.reports.run(
        ReportKind.salesByItem,
        firmId: firmId,
        period: day,
        today: day.to,
      );
      _readsAsUrdu(
        await reportToPdf(items, shopName: _shop, unicodeFont: font),
        ['چ'],
        'sales by item',
      );
    });

    test('a payment receipt', () async {
      final payment = (await shop.queries.paymentDetail(firmId, receiptId))!;
      final firm = (await shop.queries.currentFirm())!;
      final pdf = await paymentReceiptPdf(
        payment,
        shop: firm.toReceiptShop(),
        unicodeFont: font,
      );
      _readsAsUrdu(pdf, ['ٹ', 'ف', 'ش'], 'payment receipt');
    });

    test('an expiry return note to the supplier', () async {
      final table = expiryReturnNote(
        shopName: _shop,
        supplier: _supplier,
        date: const BusinessDate('2026-09-15'),
        done: ExpiryReturnDone(
          supplierName: _supplier,
          returnNos: const ['PRT-2627-0001'],
          batches: [
            ExpiringBatch(
              lotId: 'lot-1',
              itemId: 'item-1',
              itemName: _item,
              lotNo: 'B-2291',
              qty: Qty.units(10),
              unitCode: 'pcs',
              cost: Rate.rupees(200),
              expiry: const BusinessDate('2026-09-30'),
            ),
          ],
          credited: const Money.rupees(2000),
          refunded: Money.zero,
        ),
      );
      final pdf = await reportToPdf(table, shopName: _shop, unicodeFont: font);
      _readsAsUrdu(pdf, ['ٹ', 'ف', 'پ', 'چ'], 'expiry return note');
    });

    test('the recovery man\'s sheet', () async {
      final sheet = CollectionSheet(
        id: 'sheet-1',
        sheetNo: 'WS-2627-0001',
        dateLocal: '2026-09-15',
        collector: _collector,
        title: _route,
        lines: [
          SheetLine(
            lineNo: 1,
            partyId: rashid,
            partyName: _customer,
            phone: '0300-4471203',
            group: _route,
            due: const Money.rupees(2500),
            bills: [
              SheetBill(
                documentId: bill.documentId,
                docNo: bill.docNo,
                dateLocal: '2026-09-15',
                outstanding: const Money.rupees(2500),
              ),
            ],
          ),
        ],
      );
      final pdf = await reportToPdf(
        sheetTable(AppStringsUr(), sheet),
        shopName: _shop,
        unicodeFont: font,
      );
      _readsAsUrdu(pdf, ['ٹ', 'ف', 'ش', 'ع', 'غ'], 'wasooli sheet');
    });

    test('a purchase order to the supplier', () async {
      final paper = (await shop.billPaper(order))!.receipt;
      expect(paper.docTitle, 'Purchase Order');
      final pdf = await shop.receipts.toPdf(paper, unicodeFont: font);
      _readsAsUrdu(pdf, ['ٹ', 'ف', 'پ', 'چ'], 'purchase order');
    });

    test('the till roll still draws Urdu as joined script, the customer '
        'and the item as well as the shop', () async {
      const face = 'ProofNaskhM62';
      await (FontLoader(
        face,
      )..addFont(Future.value(ByteData.sublistView(font)))).load();
      const rasteriser = UiTextRasteriser(fontFamily: face);
      final paper = (await shop.billPaper(bill.documentId))!.receipt;
      for (final roll in [ReceiptPaper.mm80, ReceiptPaper.mm58]) {
        const renderer = ThermalReceiptRenderer();
        final drawn = await drawUnprintableLines(
          renderer,
          paper,
          roll,
          rasteriser: rasteriser,
        );
        expect(drawn.keys, contains(_shop.toUpperCase()));
        expect(drawn.keys.where((l) => l.contains(_customer)), isNotEmpty);
        expect(drawn.keys.where((l) => l.contains(_item)), isNotEmpty);
        final out = VirtualPrinter(
          dots: roll.dots,
        ).print(renderer.toThermalBytes(paper, paper: roll, drawn: drawn));
        expect(
          out.texts.where((t) => t.text.contains('?')),
          isEmpty,
          reason: 'a line the printer cannot spell went out as text',
        );
        expect(out.rasters, hasLength(drawn.length));
        expect(out.rasters.every((r) => r.hasInk), isTrue);
      }
    });
  });
}

/// [pdf] carries the Urdu face and sets every letter in [letters] joined,
/// with no letter of the Arabic block left bare.
void _readsAsUrdu(Uint8List pdf, List<String> letters, String what) {
  final raw = String.fromCharCodes(pdf);
  expect(raw, contains('FontFile2'), reason: '$what embeds no font');
  expect(raw, contains('NotoNaskhArabic'), reason: '$what: not the Urdu face');
  final mapped = _mappedCodepoints(pdf);
  for (final letter in letters) {
    expect(
      mapped.intersection(_forms[letter]!.toSet()),
      isNotEmpty,
      reason: '$what: no joined $letter in the file',
    );
  }
  expect(
    mapped.where((c) => c >= 0x0600 && c <= 0x06FF),
    isEmpty,
    reason:
        '$what: a letter went in bare — a run set left to right, which '
        'prints as loose letters or boxes',
  );
}

/// The PDF's text, its content streams inflated.
String _words(Uint8List pdf) {
  final out = StringBuffer(String.fromCharCodes(pdf));
  for (final stream in _streams(pdf)) {
    out.write(String.fromCharCodes(stream));
  }
  return out.toString();
}

Iterable<List<int>> _streams(Uint8List bytes) sync* {
  final text = String.fromCharCodes(bytes);
  for (final match in RegExp(r'stream\r?\n').allMatches(text)) {
    final end = text.indexOf('endstream', match.end);
    if (end < 0) continue;
    try {
      yield ZLibDecoder().convert(bytes.sublist(match.end, end));
    } on Object {
      continue;
    }
  }
}

/// Every Unicode codepoint the PDF's embedded subsets claim to draw, from
/// their ToUnicode maps (see pk_platform's urdu_pdf_test for why this is
/// the assertion that matters).
Set<int> _mappedCodepoints(Uint8List bytes) {
  final found = <int>{};
  for (final stream in _streams(bytes)) {
    final body = String.fromCharCodes(stream);
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
