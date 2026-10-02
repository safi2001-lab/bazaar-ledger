import 'dart:io';

import 'package:bazaar_ledger/features/sales/sales_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support/harness.dart';

/// A bill found again and sent again, whenever it is wanted (M30).
///
/// What shopkeepers testing the app reported: "when we make an invoice there
/// is a share option, but if we want to share the invoice later we can't."
/// The share lived on the screen that opens after a sale, and the only way
/// back to an old bill was a newest-first list with no search.
///
/// These drive the real list, against real bills in a real database: find
/// the bill by its customer, narrow the list, and send it from its row as a
/// PDF, a picture, into the customer's WhatsApp chat, or to the printer.
/// WhatsApp and the share sheet are other applications; each is stood in for
/// at its platform seam, so what is asserted is what this app handed over.
final _sheet = _FakeShareSheet();
final _whatsapp = _WhatsAppOnThePhone();

void main() {
  setUpAll(() {
    SharePlatform.instance = _sheet;
    UrlLauncherPlatform.instance = _whatsapp;
  });
  setUp(() {
    _sheet.reset();
    _whatsapp.reset();
  });

  testWidgets('a past bill is found by its customer and sent again as a PDF '
      'from its row', (tester) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await _customer(app, 'Rashid Traders', '0300-4471203');
    final bilal = await _customer(app, 'Bilal General Store', '0321 7654321');
    final his = await _sell(app, 'Cooking Oil 5L', 5525, rashid, paid: 1000);
    final other = await _sell(app, 'Chawal Basmati', 1200, bilal);
    final walkIn = await _sell(app, 'Cheeni', 300, null);

    await _openSales(tester);
    for (final bill in [his, other, walkIn]) {
      expect(find.text(bill.docNo), findsOneWidget);
    }

    await _search(tester, 'rashid');
    expect(find.text(his.docNo), findsOneWidget);
    expect(find.text(other.docNo), findsNothing);
    expect(find.text(walkIn.docNo), findsNothing);

    // By the end of the customer's number, the way it is read off a phone.
    await _search(tester, '4471203');
    expect(find.text(his.docNo), findsOneWidget);
    expect(find.text(other.docNo), findsNothing);

    // By the amount, as a customer says it on the phone.
    await _search(tester, '1200');
    expect(find.text(other.docNo), findsOneWidget);
    expect(find.text(his.docNo), findsNothing);

    await _search(tester, 'rashid');
    await _sendFromRow(tester, 'PDF bhejein');

    expect(
      _sheet.paths,
      hasLength(1),
      reason: 'the bill never reached the share sheet from the list',
    );
    final bytes = File(_sheet.paths.single).readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(String.fromCharCodes(bytes), contains('Invoice ${his.docNo}'));
    expect(
      _sheet.texts.single,
      allOf(contains('Rashid Traders'), contains('Baqi: Rs 4,525.00')),
      reason:
          'the file arrived with nothing beside it to say whose bill it is '
          'or what is still owed',
    );
  });

  testWidgets('the list narrows to what is owed, what was cancelled, and a '
      'period, and says so when nothing matches', (tester) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await _customer(app, 'Rashid Traders', '0300-4471203');
    final owed = await _sell(app, 'Cooking Oil 5L', 5525, rashid, paid: 1000);
    final paid = await _sell(app, 'Cheeni', 300, null);
    final cancelled = await _sell(app, 'Chawal Basmati', 800, rashid);
    await app.services.voidDocument(
      app.services.actorNow(),
      documentId: cancelled.documentId,
      reason: 'Dobara ring ho gaya',
    );

    await _openSales(tester);

    Future<void> onlyShows(PostedSale bill) async {
      for (final each in [owed, paid, cancelled]) {
        expect(
          find.text(each.docNo),
          each == bill ? findsOneWidget : findsNothing,
          reason: each.docNo,
        );
      }
    }

    await _chip(tester, 'Udhaar wale');
    await onlyShows(owed);
    await _chip(tester, 'Mansookh kiye');
    await onlyShows(cancelled);
    await _chip(tester, 'Ada ho chuke');
    await onlyShows(paid);

    await _chip(tester, 'Sab bill');
    await _chip(tester, 'Aaj');
    for (final bill in [owed, paid, cancelled]) {
      expect(find.text(bill.docNo), findsOneWidget);
    }

    // Every bill here is today's, so last month has none of them — and the
    // list says it found nothing, not that the shop has never made a bill.
    await _chip(tester, 'Pichhle mahine');
    expect(find.text('Is talash par koi bill nahi'), findsOneWidget);
    expect(find.text('Abhi koi bill nahi bana'), findsNothing);

    await tapButton(tester, 'Sab bill dikhayein');
    for (final bill in [owed, paid, cancelled]) {
      expect(find.text(bill.docNo), findsOneWidget);
    }
  });

  testWidgets('a bill goes into its customer\'s own WhatsApp chat with the '
      'amounts written out', (tester) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await _customer(app, 'Rashid Traders', '0300-4471203');
    final his = await _sell(app, 'Cooking Oil 5L', 5525, rashid, paid: 1000);

    await _openSales(tester);
    await _sendFromRow(tester, 'WhatsApp par bhejein');

    expect(_whatsapp.opened, hasLength(1));
    final chat = Uri.parse(_whatsapp.opened.single);
    expect(chat.scheme, 'whatsapp', reason: 'never a browser to wa.me');
    expect(
      chat.queryParameters['phone'],
      '923004471203',
      reason: '0300-4471203 handed over as typed opens a chat with nobody',
    );
    expect(
      chat.queryParameters['text'],
      allOf(
        contains(his.docNo),
        contains('Chishti Kiryana Store'),
        contains('Kul: Rs 5,525.00'),
        contains('Ada kiye: Rs 1,000.00'),
        contains('Baqi: Rs 4,525.00'),
      ),
    );
    expect(_sheet.paths, isEmpty, reason: 'it went to the chat, not a sheet');

    // And from the bill itself, opened from the list.
    await tapText(tester, his.docNo);
    await tester.tap(find.widgetWithText(InkWell, 'WhatsApp'));
    await _settleWhileBusy(tester);
    expect(_whatsapp.opened, hasLength(2));
    expect(
      Uri.parse(_whatsapp.opened.last).queryParameters['phone'],
      '923004471203',
    );
  });

  testWidgets('a bill with nobody to message goes through the share sheet, '
      'and says why', (tester) async {
    final app = await Harness.startWithShop(tester);
    final walkIn = await _sell(app, 'Cheeni', 300, null);

    await _openSales(tester);
    await tester.tap(find.byTooltip('Bhejein'));
    await tester.pumpAndSettle();
    expect(find.text('Number nahi hai, PDF share sheet se jayegi'), findsOne);
    await tester.tap(find.text('WhatsApp par bhejein'));
    await _settleWhileBusy(tester);

    expect(_whatsapp.opened, isEmpty, reason: 'there is no chat to open');
    expect(_sheet.paths.single, endsWith('${walkIn.docNo}.pdf'));
    expect(
      find.text('Is gahak ka WhatsApp number nahi, PDF share sheet se bheji'),
      findsOneWidget,
    );
  });

  testWidgets('a bill goes as a picture of its paper', (tester) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await _customer(app, 'Rashid Traders', '0300-4471203');
    final his = await _sell(app, 'Cooking Oil 5L', 5525, rashid, paid: 1000);

    await _openSales(tester);
    await _sendFromRow(tester, 'Tasveer bhejein');

    expect(_sheet.paths, hasLength(1));
    expect(_sheet.paths.single, endsWith('${his.docNo}.png'));
    final bytes = await tester.runAsync(
      () => File(_sheet.paths.single).readAsBytes(),
    );
    expect(bytes!.take(4), [0x89, 0x50, 0x4E, 0x47], reason: 'not a PNG');
    final picture = img.decodePng(bytes)!;

    // Every line the printer would print is in the picture: it is the same
    // paper, drawn rather than burnt, at thirty points a line.
    final firmId = app.services.identity!.firmId;
    final printed = app.services.receipts.toPreview(
      (await app.services.queries.receiptFor(firmId, his.documentId))!,
    );
    expect(picture.height, greaterThanOrEqualTo(printed.length * 30));

    // Black on white whatever the phone's theme: a dark-mode bill would
    // reach the customer as a black rectangle with grey writing.
    final corner = picture.getPixel(0, 0);
    expect([corner.r, corner.g, corner.b], [255, 255, 255]);
    var inked = 0;
    for (final pixel in picture) {
      if (pixel.r < 128) inked++;
    }
    expect(inked, greaterThan(0), reason: 'a blank page was sent');

    expect(_sheet.texts.single, contains('Baqi: Rs 4,525.00'));
  });

  testWidgets('the row prints the bill, and asking again prints nothing more', (
    tester,
  ) async {
    final printer = _RecordingPrinter();
    final app = await Harness.startWithShop(tester, transports: [printer]);
    await app.services.printing.saveSettings(
      app.services.actorNow(),
      const PrinterSettings(
        transportKind: 'tcp',
        address: '192.168.1.50:9100',
        name: 'Counter printer',
      ),
    );
    final bill = await _sell(app, 'Cooking Oil 5L', 5525, null);

    await _openSales(tester);
    for (var ask = 0; ask < 2; ask++) {
      await tester.tap(find.byTooltip('Bhejein'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Printer par bhejein'));
      await tester.pumpAndSettle();
    }

    expect(
      printer.jobs,
      hasLength(1),
      reason:
          'the row prints through the same door as the receipt screen, '
          'where a second ask for the same copy is the same job',
    );
    expect(
      String.fromCharCodes(
        printer.jobs.single.where((b) => b >= 32 && b < 127),
      ),
      contains(bill.docNo),
    );
  });

  testWidgets('a cancelled bill goes out marked cancelled, and a printed one '
      'as the duplicate', (tester) async {
    final printer = _RecordingPrinter();
    final app = await Harness.startWithShop(tester, transports: [printer]);
    await app.services.printing.saveSettings(
      app.services.actorNow(),
      const PrinterSettings(
        transportKind: 'tcp',
        address: '192.168.1.50:9100',
        name: 'Counter printer',
      ),
    );
    final rashid = await _customer(app, 'Rashid Traders', '0300-4471203');
    final printed = await _sell(app, 'Cooking Oil 5L', 5525, null);
    final cancelled = await _sell(app, 'Cheeni', 800, rashid);
    await app.services.voidDocument(
      app.services.actorNow(),
      documentId: cancelled.documentId,
      reason: 'Ghalti se bana',
    );

    await _openSales(tester);
    await _sendFromRow(tester, 'PDF bhejein', of: cancelled.docNo);
    expect(
      String.fromCharCodes(File(_sheet.paths.last).readAsBytesSync()),
      contains('${cancelled.docNo} - CANCELLED'),
      reason: 'a cancelled bill sent on reads like one still owed',
    );
    expect(_sheet.texts.last, contains('mansookh'));
    expect(_sheet.texts.last, isNot(contains('Baqi')));

    // The original goes to paper at the counter; what is sent after it is
    // the duplicate, as the second sheet of a carbon book is.
    await tester.tap(_sendButtonOf(printed.docNo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Printer par bhejein'));
    await tester.pumpAndSettle();
    expect(printer.jobs, hasLength(1));
    await _sendFromRow(tester, 'PDF bhejein', of: printed.docNo);
    expect(
      String.fromCharCodes(File(_sheet.paths.last).readAsBytesSync()),
      allOf(
        contains('${printed.docNo} - DUPLICATE'),
        isNot(contains('CANCELLED')),
      ),
    );
  });

  testWidgets('a delivery opens to be read, and goes on as a PDF titled '
      'Purchase Bill', (tester) async {
    final app = await Harness.startWithShop(tester);
    final firmId = (await app.services.queries.currentFirm())!.id;
    final mill = await app.services.catalogue.addParty(
      app.services.actorNow(),
      const PartyDraft(
        name: 'Punjab Rice Mills',
        partyType: 'supplier',
        phone: '0301-5550123',
      ),
    );
    final rice = await app.seedItem(name: 'Chawal Basmati', rupees: 150);
    final pcs = (await app.services.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs');
    await app.services.recordPurchase(
      app.services.actorNow(),
      PurchaseDraft(
        partyId: mill,
        supplierBillNo: 'PRM/771',
        lines: [
          PurchaseLineDraft(
            itemId: rice,
            itemName: 'Chawal Basmati',
            qty: Qty.units(10),
            baseQty: Qty.units(10),
            unitId: pcs.id,
            unitCode: 'pcs',
            rate: Rate.rupees(120),
          ),
        ],
      ),
    );
    final docNo = await app.scalar<String>(
      "SELECT doc_no FROM documents WHERE doc_type = 'purchase_bill'",
    );

    await tester.pumpAndSettle();
    await tapText(tester, 'Kharidari');
    await tapText(tester, 'Punjab Rice Mills');

    // Opened, not sent back: the delivery itself, with what is still owed.
    expect(find.text(docNo!), findsOneWidget);
    expect(find.text('1,200.00 dena hai'), findsOneWidget);
    expect(find.text('Supplier ko maal wapas'), findsNothing);
    final paper = app.services.receipts.toPreview(
      (await app.services.queries.receiptFor(
        firmId,
        (await app.rowsOf(
              "SELECT id FROM documents WHERE doc_type = 'purchase_bill'",
            )).single['id']!
            as String,
      ))!,
    );
    expect(
      paper,
      allOf(
        contains(contains('Supplier')),
        contains(contains('Purchase No')),
        contains(contains('Supplier bill: PRM/771')),
      ),
    );
    expect(
      paper.any((l) => l.contains('Customer')),
      isFalse,
      reason: 'a delivery read back as though the shop sold the mill its rice',
    );

    await tester.tap(find.text('PDF bhejein'));
    await _settleWhileBusy(tester);
    final bytes = File(_sheet.paths.single).readAsBytesSync();
    expect(String.fromCharCodes(bytes), contains('Purchase Bill $docNo'));
    expect(_sheet.texts.single, contains('kharidari ka bill $docNo'));
  });

  testWidgets('a quotation opens to be read and goes as a picture', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);

    await tester.pumpAndSettle();
    await tapText(tester, 'Naya Bill');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Talash karein').first,
      'Cooking',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Paisay lein');
    await tapButton(tester, 'Quotation banayein');
    final docNo = await app.scalar<String>('SELECT doc_no FROM documents');
    // "Quotation saved" sits over the foot of every screen for four seconds,
    // which is where the send buttons are, for a shopkeeper as for a test.
    await tester.pump(const Duration(seconds: 5));
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tapText(tester, 'Quotation');
    await tapText(tester, 'Aam gahak');
    await tapButton(tester, 'Poora dekhein');
    expect(find.text(docNo!), findsOneWidget, reason: 'the quotation opened');

    await tester.tap(find.widgetWithText(InkWell, 'Tasveer'));
    await _settleWhileBusy(tester);
    expect(_sheet.paths.single, endsWith('$docNo.png'));
    expect(_sheet.texts.single, contains('quotation $docNo'));
    expect(
      _sheet.texts.single,
      isNot(contains('Ada kiye')),
      reason: 'nothing is paid against a quotation',
    );
  });

  test(
    'this week starts on Monday, and last month ends on its own last day',
    () {
      // 1 October 2026 is a Thursday.
      const thursday = BusinessDate('2026-10-01');
      expect(salesPeriodRange(SalesPeriod.thisWeek, thursday), (
        const BusinessDate('2026-09-28'),
        thursday,
      ));
      expect(
        salesPeriodRange(
          SalesPeriod.thisWeek,
          const BusinessDate('2026-10-04'),
        ),
        (const BusinessDate('2026-09-28'), const BusinessDate('2026-10-04')),
        reason: 'Sunday is the end of the week, not the start of the next',
      );
      expect(
        salesPeriodRange(
          SalesPeriod.thisMonth,
          const BusinessDate('2026-10-02'),
        ),
        (const BusinessDate('2026-10-01'), const BusinessDate('2026-10-02')),
      );
      expect(
        salesPeriodRange(
          SalesPeriod.lastMonth,
          const BusinessDate('2026-03-15'),
        ),
        (const BusinessDate('2026-02-01'), const BusinessDate('2026-02-28')),
      );
      expect(
        salesPeriodRange(
          SalesPeriod.lastMonth,
          const BusinessDate('2026-01-10'),
        ),
        (const BusinessDate('2025-12-01'), const BusinessDate('2025-12-31')),
        reason: 'January\'s last month is last year\'s December',
      );
      expect(salesPeriodRange(SalesPeriod.all, thursday), (null, null));
    },
  );

  test('a bill is never sent through a browser', () {
    // On the code, not the comments: the comments explain at length why
    // wa.me is not used, and a test that reads prose as configuration fires
    // on its own documentation.
    final code = File('lib/features/sales/send_bill.dart')
        .readAsStringSync()
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    expect(code, contains('whatsapp://send'));
    expect(code, isNot(contains('wa.me')));
    expect(code, isNot(contains('api.whatsapp.com')));
  });
}

Future<void> _openSales(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Farokht');
  await tester.pumpAndSettle();
}

/// Types into the search box and waits out its quarter-second pause.
Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Bill talash karein'),
    text,
  );
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// Taps a filter chip, scrolling its row to it first: the period chips run
/// past the edge of the screen.
Future<void> _chip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(ChoiceChip, label);
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

/// The send button on the only row in the list, then [way] in its sheet.
Future<void> _sendFromRow(WidgetTester tester, String way, {String? of}) async {
  await tester.tap(of == null ? find.byTooltip('Bhejein') : _sendButtonOf(of));
  await tester.pumpAndSettle();
  await tester.tap(find.text(way));
  await _settleWhileBusy(tester);
}

/// The send button on the row of bill [docNo], when there is more than one.
Finder _sendButtonOf(String docNo) => find.descendant(
  of: find.ancestor(of: find.text(docNo), matching: find.byType(SaleRowTile)),
  matching: find.byTooltip('Bhejein'),
);

Future<String> _customer(Harness app, String name, String phone) => app
    .services
    .catalogue
    .addParty(app.services.actorNow(), PartyDraft(name: name, phone: phone));

/// One line of [item] at [rupees], [paid] of it in cash — all of it unless
/// said — to [partyId], or to a walk-in when null.
Future<PostedSale> _sell(
  Harness app,
  String item,
  int rupees,
  String? partyId, {
  int? paid,
}) async {
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');
  final cash = (await app.services.queries.paymentAccounts(
    firm,
  )).firstWhere((a) => a.modeLabel == 'cash');
  final itemId = await app.seedItem(name: item, rupees: rupees);
  final party = partyId == null
      ? null
      : await app.services.queries.partyById(firm, partyId);
  final taken = paid ?? rupees;
  return app.services.postSale(
    app.services.actorNow(),
    SaleDraft(
      partyId: partyId,
      partyName: party?.name,
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: item,
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
        ),
      ],
      tenders: [
        if (taken > 0)
          TenderDraft(
            paymentAccountId: cash.id,
            mode: 'cash',
            amount: Money.rupees(taken),
          ),
      ],
    ),
  );
}

/// Lets a share finish, which takes both a clock and a disk.
///
/// See receipt_shares_as_pdf_test: the button spins while the document is
/// drawn, so `pumpAndSettle` never returns, and the drawing and the file are
/// real work a fake clock does not advance.
Future<void> _settleWhileBusy(WidgetTester tester) async {
  for (var round = 0; round < 40; round++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump();
}

/// Stands in for the system share sheet and records what it was handed.
final class _FakeShareSheet extends SharePlatform {
  final paths = <String>[];
  final texts = <String>[];

  void reset() {
    paths.clear();
    texts.clear();
  }

  @override
  Future<ShareResult> share(ShareParams params) async {
    paths.addAll((params.files ?? const []).map((f) => f.path));
    if (params.text case final text?) texts.add(text);
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

/// Stands in for WhatsApp being installed: it answers the `whatsapp://`
/// scheme and records each chat it was asked to open.
final class _WhatsAppOnThePhone extends UrlLauncherPlatform {
  final opened = <String>[];

  void reset() => opened.clear();

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => url.startsWith('whatsapp://');

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return true;
  }
}

final class _RecordingPrinter implements PrinterTransport {
  final jobs = <List<int>>[];

  @override
  String get kind => 'tcp';

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<List<PrinterTarget>> discover({Duration? timeout}) async => const [];

  @override
  Future<void> send(PrinterTarget target, List<int> bytes) async {
    jobs.add(bytes);
  }
}
