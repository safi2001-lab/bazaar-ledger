import 'dart:io';

import 'package:bazaar_ledger/features/printing/bill_design_preview.dart';
import 'package:bazaar_ledger/features/sales/receipt_offer.dart';
import 'package:bazaar_ledger/features/settings/bill_design_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// The customer's receipt, offered the moment money moves (M70), and more
/// bills to choose from, driven through the app on a real database.
///
/// A bill saved at the counter, money taken on the khata, goods taken back
/// and a supplier paid each offer the party a WhatsApp message in their own
/// language with what moved and where the khata stands now — and for a
/// bill its PDF or picture. "Kabhi nahi" is never asked again, a walk-in or
/// a party with no number never is, "Khud bhejein" opens the chat by itself
/// and nothing is ever sent without a person pressing Send. WhatsApp and
/// the share sheet are stood in for at their platform seams, so what is
/// asserted is what the app handed over.
final _whatsapp = _WhatsAppOnThePhone();
final _sheet = _FakeShareSheet();

void main() {
  setUpAll(() {
    UrlLauncherPlatform.instance = _whatsapp;
    SharePlatform.instance = _sheet;
  });
  setUp(() {
    _whatsapp.reset();
    _sheet.reset();
  });

  group('the receipt offered', () {
    testWidgets('a bill saved at the counter offers its receipt in the '
        'customer\'s language, with what they owe now, and the send is on '
        'the bill\'s history', (tester) async {
      final app = await Harness.startWithShop(tester);
      final rashid = await _customer(app, owed: 1000);
      await app.services.udhaar.setReminderPrefs(
        rashid,
        const ReminderPrefs(language: ReminderLanguage.english),
      );
      await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);

      await _ringUp(tester, customer: 'Rashid Traders');

      expect(find.text('Rashid Traders ko raseed bhejein?'), findsOneWidget);
      // Before anything is sent, the words are on the screen as they will go.
      expect(find.textContaining('Your balance now'), findsOneWidget);

      await tapButton(tester, 'WhatsApp par raseed');
      expect(_whatsapp.opened, hasLength(1));
      final chat = Uri.parse(_whatsapp.opened.single);
      expect(chat.scheme, 'whatsapp', reason: 'never a browser to wa.me');
      expect(chat.queryParameters['phone'], '923004471203');
      final bill = (await app.rowsOf(
        "SELECT id, doc_no FROM documents WHERE doc_type = 'sale_invoice'",
      )).single;
      expect(
        chat.queryParameters['text'],
        allOf(
          contains('Assalam-o-Alaikum Rashid Traders'),
          contains('bill ${bill['doc_no']}, total Rs 2,500.00'),
          contains('Paid: Rs 2,500.00'),
          contains('Your balance now: Rs 1,000.00'),
        ),
      );
      expect(find.text('Rashid Traders ko raseed bhejein?'), findsNothing);

      final history = await app.services.audit.history(
        RecordRef.document(bill['id']! as String),
      );
      expect(
        history.where((e) => e.actionCode == SharedVia.whatsapp.action),
        hasLength(1),
        reason: 'the bill\'s history does not say it was sent',
      );
    });

    testWidgets('money taken on the khata offers a receipt in Urdu with what '
        'is still owed, recorded on the payment', (tester) async {
      final app = await Harness.startWithShop(tester);
      final rashid = await _customer(app, owed: 5000);
      await app.services.udhaar.setReminderPrefs(
        rashid,
        const ReminderPrefs(language: ReminderLanguage.urdu),
      );

      await _openKhata(tester, 'Rashid Traders');
      await _receive(tester, '3000');

      expect(find.text('Rashid Traders ko raseed bhejein?'), findsOneWidget);
      // A payment has no bill to attach.
      expect(find.text('Bill ki PDF'), findsNothing);
      await tapButton(tester, 'WhatsApp par raseed');

      final text = Uri.parse(_whatsapp.opened.single).queryParameters['text']!;
      final payment = (await app.rowsOf(
        "SELECT id, payment_no FROM payments WHERE direction = 'in'",
      )).single;
      expect(
        text,
        allOf(
          contains('السلام علیکم Rashid Traders'),
          contains('3,000.00 روپے وصول ہو گئے'),
          contains('رسید ${payment['payment_no']}'),
          contains('آپ کا کل بقایا اب: 2,000.00 روپے'),
        ),
      );
      final history = await app.services.audit.history(
        RecordRef.payment(payment['id']! as String),
      );
      expect(
        history.where((e) => e.actionCode == SharedVia.whatsapp.action),
        hasLength(1),
      );
    });

    testWidgets('goods taken back offer the receipt, and Kabhi nahi is '
        'never asked again', (tester) async {
      final app = await Harness.startWithShop(tester);
      final rashid = await _customer(app);
      await _sellOnUdhaar(app, rashid, qty: 5, rupees: 150);

      await _openBill(tester);
      await _takeBack(tester, reason: 'Kharab nikla');

      expect(find.text('Rashid Traders ko raseed bhejein?'), findsOneWidget);
      expect(
        find.textContaining('Aap ka kul baqaya ab: Rs 600.00'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Kabhi nahi'));
      await tester.pumpAndSettle();
      expect(find.text('Rashid Traders ko raseed bhejein?'), findsNothing);
      expect(await app.services.receiptOfferOf(rashid), ReceiptOffer.never);
      expect(_whatsapp.opened, isEmpty, reason: 'nothing was sent');

      await _takeBack(tester, reason: 'Ek aur kharab');
      expect(find.text('Rashid Traders ko raseed bhejein?'), findsNothing);
      expect(
        await app.scalar<int>(
          "SELECT COUNT(*) FROM documents WHERE doc_type = 'sale_return'",
        ),
        2,
        reason: 'the return itself was never in question',
      );
    });

    testWidgets('a supplier paid is offered the voucher with what the shop '
        'still owes them', (tester) async {
      final app = await Harness.startWithShop(tester);
      await _supplierOwed(app, rupees: 1500);

      await _openKhata(tester, 'Punjab Rice Mills');
      await tapText(tester, 'Paisay dein');
      await tester.enterText(find.byType(TextFormField).first, '1000');
      await tester.pumpAndSettle();
      await tapButton(tester, 'Payment save karein');

      expect(find.text('Punjab Rice Mills ko raseed bhejein?'), findsOneWidget);
      await tapButton(tester, 'WhatsApp par raseed');
      expect(
        Uri.parse(_whatsapp.opened.single).queryParameters['text'],
        allOf(
          contains('Chishti Kiryana Store ki taraf se Rs 1,000.00 ada kiye'),
          contains('Hamara baqaya ab: Rs 500.00'),
        ),
      );
    });

    testWidgets('Khud bhejein set in Settings opens the chat by itself; a '
        'walk-in and a customer with no number are never offered one', (
      tester,
    ) async {
      final app = await Harness.startWithShop(tester);
      await _customer(app, owed: 5000);
      await app.services.catalogue.addParty(
        app.services.actorNow(),
        const PartyDraft(
          name: 'Bashir Sahib',
          openingBalance: Money.rupees(2000),
        ),
      );
      await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);

      await tester.pumpAndSettle();
      await openSettings(tester);
      await tapText(tester, 'Gahak ko raseed');
      await tapText(tester, 'Khud bhejein');
      expect(await app.services.receiptOfferDefault(), ReceiptOffer.auto);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await _openKhata(tester, 'Rashid Traders');
      await _receive(tester, '1000');
      expect(
        find.text('Rashid Traders ko raseed bhejein?'),
        findsNothing,
        reason: 'nobody is asked: the chat opened by itself',
      );
      expect(_whatsapp.opened, hasLength(1));
      expect(
        Uri.parse(_whatsapp.opened.single).queryParameters['text'],
        contains('Aap ka kul baqaya ab: Rs 4,000.00'),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // No number, nothing to open and nothing to ask.
      await _openKhata(tester, 'Bashir Sahib');
      await _receive(tester, '500');
      expect(find.text('Bashir Sahib ko raseed bhejein?'), findsNothing);
      expect(_whatsapp.opened, hasLength(1));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // A walk-in's bill.
      await _ringUp(tester);
      expect(find.textContaining('ko raseed bhejein?'), findsNothing);
      expect(_whatsapp.opened, hasLength(1));
    });

    testWidgets('a bill\'s PDF goes from the offer and is written on its '
        'history; a party\'s own choice is kept on their form', (tester) async {
      final app = await Harness.startWithShop(tester);
      final rashid = await _customer(app);
      await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);

      await _ringUp(tester, customer: 'Rashid Traders');
      await tester.tap(find.text('Bill ki PDF'));
      await _settleWhileBusy(tester);

      final bill = (await app.rowsOf(
        "SELECT id, doc_no FROM documents WHERE doc_type = 'sale_invoice'",
      )).single;
      expect(_sheet.paths.single, endsWith('${bill['doc_no']}.pdf'));
      expect(
        String.fromCharCodes(File(_sheet.paths.single).readAsBytesSync()),
        contains('Invoice ${bill['doc_no']}'),
      );
      final history = await app.services.audit.history(
        RecordRef.document(bill['id']! as String),
      );
      expect(
        history.where((e) => e.actionCode == SharedVia.pdf.action),
        hasLength(1),
      );

      // On the customer's own form, beside their reminder language.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _openKhata(tester, 'Rashid Traders');
      await tester.tap(find.byTooltip('Gahak ki tafseel'));
      await tester.pumpAndSettle();
      final never = find.widgetWithText(ChoiceChip, 'Kabhi nahi');
      await tester.scrollUntilVisible(
        never,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(never);
      await tester.pumpAndSettle();
      expect(await app.services.receiptOfferOf(rashid), ReceiptOffer.never);
    });

    test('a receipt never goes through a browser, and the app holds no way '
        'to send one by itself', () {
      // On the code, not the comments, which explain at length what is not
      // done.
      final code = File('lib/features/sales/receipt_offer.dart')
          .readAsStringSync()
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, contains('whatsapp://send'));
      for (final never in ['wa.me', 'api.whatsapp.com', 'sms:', 'http']) {
        expect(code, isNot(contains(never)), reason: never);
      }
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      // Asked for, not mentioned: the manifest's comments say why it is not.
      expect(
        RegExp(r'<uses-permission[^>]*SEND_SMS').hasMatch(manifest),
        isFalse,
      );
    });

    testWidgets('the offer fits a small phone at 200%', (tester) async {
      await tester.runAsync(loadRealFont);
      tester.view
        ..physicalSize = const Size(720, 1600)
        ..devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });

      final app = await Harness.startWithShop(tester);
      await _customer(app);
      await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
      await _ringUp(tester, customer: 'Rashid Traders');

      expect(find.byType(ReceiptOfferSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
      final sheetList = find
          .descendant(
            of: find.byType(ReceiptOfferSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      for (var i = 0; i < 4; i++) {
        await tester.drag(sheetList, const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      expect(find.text('Abhi nahi'), findsOneWidget);
    });
  });

  group('more bills to choose from', () {
    testWidgets('every design is a picture of its page; the bill book, a '
        'quotation of its own and the big total are kept and drawn', (
      tester,
    ) async {
      final app = await Harness.startWithShop(tester);
      await tester.pumpAndSettle();
      await openSettings(tester);
      await tapText(tester, 'Bill ka design');

      // Two to a row, every one of the eight, the shop's own name on each.
      await _scrollTo(tester, find.text('Halka'));
      final thumbnails = find.byType(BillDesignThumbnail, skipOffstage: false);
      expect(thumbnails, findsNWidgets(BillTheme.values.length));

      for (final name in ['Bill book', 'Landscape (wholesale)', 'Nafees']) {
        await _scrollTo(tester, find.text(name));
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
      }
      // Chosen last: the bill book.
      await _scrollTo(tester, find.text('Bill book'));
      await tester.tap(find.text('Bill book'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Stationer ki bill book jaisa'),
        findsOneWidget,
      );

      // A quotation in a design of its own.
      await _scrollTo(tester, find.text('Quotation ka design'));
      await tester.tap(find.text('Quotation ka design'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Nafees'));
      await tester.pumpAndSettle();

      // The till slip with its total large, as the printer gets it.
      await _scrollTo(tester, find.text('Bara total'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Bara total'));
      await tester.pumpAndSettle();
      final slip = find.text('Thermal slip');
      await _scrollTo(tester, slip);
      await tester.tap(slip);
      await tester.pumpAndSettle();
      expect(find.textContaining('T O T A L'), findsOneWidget);

      await tapButton(tester, 'Save karein');
      final design = await app.services.billDesign();
      expect(design.theme, BillTheme.ruled);
      expect(design.slip, ReceiptSlip.bigTotal);
      expect(design.documentThemes, {'quotation': BillTheme.elegant});

      // A bill goes out as the bill book; a quotation as its own.
      final rashid = await _customer(app);
      final sale = await _sellOnUdhaar(app, rashid, qty: 1, rupees: 900);
      final quotation = await app.services.saveQuotation(
        app.services.actorNow(),
        await _draft(app, rashid),
      );
      final billPaper = await app.services.billPaper(sale.documentId);
      final quotationPaper = await app.services.billPaper(quotation.id);
      expect(billPaper!.design.theme, BillTheme.ruled);
      expect(quotationPaper!.design.theme, BillTheme.elegant);
      expect(quotationPaper.receipt.slip, ReceiptSlip.bigTotal);
      final pdf = String.fromCharCodes(
        await app.services.receipts.toPdf(
          quotationPaper.receipt,
          design: quotationPaper.design,
        ),
      );
      expect(pdf, contains('/Times-Roman'), reason: 'the elegant page');
    });
  });
}

Future<String> _customer(Harness app, {int owed = 0}) =>
    app.services.catalogue.addParty(
      app.services.actorNow(),
      PartyDraft(
        name: 'Rashid Traders',
        phone: '0300-4471203',
        openingBalance: Money.rupees(owed),
      ),
    );

Future<void> _supplierOwed(Harness app, {required int rupees}) async {
  final actor = app.services.actorNow();
  final millId = await app.services.catalogue.addParty(
    actor,
    const PartyDraft(
      name: 'Punjab Rice Mills',
      partyType: 'supplier',
      phone: '0321-7654321',
    ),
  );
  final riceId = await app.seedItem(name: 'Chawal Basmati', rupees: 150);
  final pcs = (await app.services.queries.units(
    actor.firmId,
  )).firstWhere((u) => u.code == 'pcs');
  await app.services.recordPurchase(
    app.services.actorNow(),
    PurchaseDraft(
      partyId: millId,
      lines: [
        PurchaseLineDraft(
          itemId: riceId,
          itemName: 'Chawal Basmati',
          qty: Qty.units(10),
          baseQty: Qty.units(10),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees ~/ 10),
        ),
      ],
    ),
  );
}

Future<SaleDraft> _draft(Harness app, String partyId, {int qty = 1}) async {
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');
  final itemId = await app.seedItem(name: 'Chawal Basmati', rupees: 150);
  return SaleDraft(
    partyId: partyId,
    lines: [
      SaleLineDraft(
        itemId: itemId,
        itemName: 'Chawal Basmati',
        qty: Qty.units(qty),
        baseQty: Qty.units(qty),
        unitId: pcs.id,
        unitCode: 'pcs',
        rate: Rate.rupees(150),
      ),
    ],
    tenders: const [],
  );
}

Future<PostedSale> _sellOnUdhaar(
  Harness app,
  String partyId, {
  required int qty,
  required int rupees,
}) async {
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');
  final itemId = await app.seedItem(name: 'Chawal Basmati', rupees: rupees);
  return app.services.postSale(
    app.services.actorNow(),
    SaleDraft(
      partyId: partyId,
      partyName: 'Rashid Traders',
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: 'Chawal Basmati',
          qty: Qty.units(qty),
          baseQty: Qty.units(qty),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
        ),
      ],
      tenders: const [],
    ),
  );
}

/// One tin of oil at the counter, saved for [customer] or for a walk-in.
Future<void> _ringUp(WidgetTester tester, {String? customer}) async {
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
  if (customer != null) {
    await tapText(tester, 'Aam gahak');
    await tapText(tester, customer);
  }
  await tapButton(tester, 'Save karein');
  await tester.pumpAndSettle();
}

Future<void> _openKhata(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Gahak');
  await tapText(tester, name);
}

Future<void> _receive(WidgetTester tester, String amount) async {
  await tapText(tester, 'Paisay wasool karein');
  await tester.enterText(find.byType(TextFormField).first, amount);
  await tester.pumpAndSettle();
  await tapText(tester, 'Wasooli save karein');
  await tester.pumpAndSettle();
}

Future<void> _openBill(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Farokht');
  await tester.tap(find.textContaining('INV-').first);
  await tester.pumpAndSettle();
}

Future<void> _takeBack(WidgetTester tester, {required String reason}) async {
  await tester.tap(find.byTooltip('Wapas lein'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Shamil karein').first);
  await tester.pumpAndSettle();
  await typeInto(tester, 'Wajah', reason);
  await tapText(tester, 'Wapsi save karein');
  await tester.pumpAndSettle();
}

/// The bill design screen's own list, not the home screen's beneath it.
Finder get _designList => find
    .descendant(
      of: find.byType(BillDesignScreen),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  for (final step in const [300.0, -300.0]) {
    if (target.evaluate().isNotEmpty) break;
    try {
      await tester.scrollUntilVisible(
        target,
        step,
        scrollable: _designList,
        maxScrolls: 40,
      );
    } on StateError {
      // Not that way; the other.
    }
  }
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
}

/// Lets a share finish, which takes both a clock and a disk.
Future<void> _settleWhileBusy(WidgetTester tester) async {
  for (var round = 0; round < 40; round++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump();
}

/// WhatsApp, installed, recording every chat it was asked to open.
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
