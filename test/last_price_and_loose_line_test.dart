import 'dart:io';

import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/design/components.dart';
import 'package:bazaar_ledger/features/home/home_screen.dart';
import 'package:bazaar_ledger/features/pos/cart_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// The last price this customer paid is on the counter, and a loose sale
/// needs no item (M37).
///
/// A wholesaler's customer says "same as last time"; the counter now shows
/// what last time was, beside the line, and one tap makes it the price. A
/// kiryana sells a kilo of onions out of the sack; the counter now sells it
/// as what the cashier calls it and what it comes to, without making an item
/// a typo would leave in the catalogue for ever.
///
/// Every test drives the real screens against a real database, then reads
/// the rows back.
void main() {
  testWidgets(
    "a customer's last prices are theirs, newest first, and a tap puts one "
    'on the line',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      final oil = await _oil(app);
      final rashid = await _party(app, 'Rashid Traders', PriceTier.wholesale);
      final bilal = await _party(app, 'Bilal General Store', PriceTier.retail);
      await _soldBefore(app, oil, rashid, 2400);
      await _soldBefore(app, oil, bilal, 2000); // somebody else's price
      await _soldBefore(app, oil, rashid, 2350);

      await _openCounter(tester);
      await _billTo(tester, 'Rashid Traders');
      expect(
        find.text('Rashid Traders ka bill abhi khali hai'),
        findsOneWidget,
      );
      await _ring(tester, 'Cooking');
      expect(find.text('Rashid Traders ka bill'), findsOneWidget);

      // The price list stands: a wholesale customer is charged wholesale
      // until the cashier picks an old price. Beside the line, last time.
      expect(find.text('× 2,300.00'), findsOneWidget);
      expect(
        find.textContaining('Pichhli dafa 2,350.00 ·'),
        findsOneWidget,
        reason: 'the price he paid last time is not beside the line',
      );

      await _openLine(tester);
      expect(find.text('Is gahak ko pichhli dafa'), findsOneWidget);
      final newer = tester.getTopLeft(find.text('2,350.00')).dy;
      final older = tester.getTopLeft(find.text('2,400.00')).dy;
      expect(newer, lessThan(older), reason: 'newest first');
      expect(
        find.text('2,000.00'),
        findsNothing,
        reason: "another customer's price was offered to this one",
      );

      await tester.tap(find.text('2,400.00'));
      await tester.pumpAndSettle();
      expect(find.text('Is gahak ko pichhli dafa'), findsNothing);
      expect(find.text('× 2,400.00'), findsOneWidget);

      await tapButton(tester, 'Paisay lein');
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      await tapButton(tester, 'Save karein');

      final bills = await app.rowsOf(
        'SELECT party_id, total_paisa FROM documents '
        "WHERE doc_type = 'sale_invoice' ORDER BY created_at_utc DESC",
      );
      expect(bills.first['party_id'], rashid);
      expect(bills.first['total_paisa'], 240000);
    },
  );

  testWidgets(
    "an old price tapped by a cashier keeps the customer's standing discount "
    'a percentage',
    (tester) async {
      // Rashid is on 5% off everything, which a cashier may ring (M22). The
      // line editor used to write the discount back as the rupees it came
      // to at the old price, so a lower old price kept the old rupees —
      // more than 5% of the new one — and the till refused the bill.
      final app = await Harness.startWithShop(tester);
      final oil = await _oil(app);
      final rashid = await app.services.catalogue.addParty(
        app.services.actorNow(),
        const PartyDraft(name: 'Rashid Traders', defaultDiscountBp: 500),
      );
      await _soldBefore(app, oil, rashid, 2300);
      await _signInBilal(tester, app);

      await _openCounter(tester);
      await _billTo(tester, 'Rashid Traders');
      await _ring(tester, 'Cooking');
      expect(find.text('Riayat −125.00'), findsOneWidget);
      await _openLine(tester);
      await tester.tap(find.text('2,300.00'));
      await tester.pumpAndSettle();
      expect(find.text('× 2,300.00'), findsOneWidget);
      expect(find.text('Riayat −115.00'), findsOneWidget);

      await tapButton(tester, 'Paisay lein');
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      await tapButton(tester, 'Save karein');

      final bills = await app.rowsOf(
        "SELECT total_paisa FROM documents WHERE doc_type = 'sale_invoice' "
        'ORDER BY created_at_utc DESC',
      );
      expect(bills, hasLength(2), reason: 'the till refused the bill');
      expect(bills.first['total_paisa'], 218500);
    },
  );

  testWidgets(
    'the owner sees what the goods last came in at; a cashier never sees a '
    'cost',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      final oil = await _oil(app);
      final rashid = await _party(app, 'Rashid Traders', PriceTier.retail);
      await _soldBefore(app, oil, rashid, 2450);
      await _boughtBefore(app, oil, 2100);

      // The owner.
      await _openCounter(tester);
      await _billTo(tester, 'Rashid Traders');
      await _ring(tester, 'Cooking');
      await _openLine(tester);
      expect(find.text('Is gahak ko pichhli dafa'), findsOneWidget);
      expect(
        find.textContaining('Aakhri khareed 2,100.00 · Faisal Oil Mills'),
        findsOneWidget,
      );
      await tester.tap(find.text('Ho gaya'));
      await tester.pumpAndSettle();
      await _openLoose(tester);
      expect(find.textContaining('laagat maloom nahi'), findsOneWidget);
      await tester.tap(find.byTooltip('Band karein').last);
      await tester.pumpAndSettle();

      // Bilal, at the same counter with the same bill.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await _signInBilal(tester, app);
      await _openCounter(tester);
      expect(find.text('× 2,500.00'), findsOneWidget, reason: 'the bill held');
      await _openLine(tester);
      expect(
        find.text('Is gahak ko pichhli dafa'),
        findsOneWidget,
        reason: 'what a customer paid is not a cost; the cashier quotes it',
      );
      expect(find.textContaining('Aakhri khareed'), findsNothing);
      expect(find.textContaining('2,100.00'), findsNothing);
      await tester.tap(find.text('Ho gaya'));
      await tester.pumpAndSettle();
      await _openLoose(tester);
      expect(find.textContaining('laagat maloom nahi'), findsNothing);
    },
  );

  testWidgets(
    'a loose line sells, prints, totals and survives a kill, and leaves the '
    'stock as it was',
    (tester) async {
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
      final oil = await _oil(app);

      await _openCounter(tester);
      await _search(tester, 'Pyaz');
      await tapText(tester, "'Pyaz' khula bechein (cheez nahi banegi)");
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Kya hai (marzi se)').last,
            )
            .controller!
            .text,
        'Pyaz',
        reason: 'what was searched for came with it',
      );
      await _typeOnTop(tester, 'Qeemat (fi unit, ya poori raqam)', '120');
      await _typeOnTop(tester, 'Tadaad', '2.5');
      await tester.tap(find.widgetWithText(ChoiceChip, 'kg').last);
      await tester.pumpAndSettle();
      expect(find.text('Raqam: 300.00'), findsOneWidget);
      await _tapOnTop(tester, 'Bill mein daalein');

      expect(find.text('Pyaz'), findsOneWidget);
      expect(find.text('Khula maal · stock nahi'), findsOneWidget);
      expect(await app.countIn('items'), 1, reason: 'an item was made of it');

      // Killed here: the draft is on disk, and it comes back a loose line.
      await tester.pump(const Duration(milliseconds: 50));
      final saved = await app.services.drafts.read(cartDraftSlot);
      final restored = CartDraft.decode(saved!)!;
      final line = restored.lines.single;
      expect(line.isLoose, isTrue);
      expect(line.item.name, 'Pyaz');
      expect(line.qty, Qty.parse('2.5'));
      expect(line.sellingUnitCode, 'kg');
      expect(restored.subtotal, const Money.rupees(300));
      expect(line.toDraft().itemId, isNull, reason: 'it came back an item');

      // A tin of oil on the same bill, and the money.
      await _ring(tester, 'Cooking');
      await tapButton(tester, 'Paisay lein');
      await typeInto(tester, 'Diye gaye', '3000');
      await tapButton(tester, 'Save karein');

      final bill = (await app.rowsOf(
        "SELECT id, total_paisa FROM documents WHERE doc_type = 'sale_invoice'",
      )).single;
      expect(bill['total_paisa'], 280000);
      final loose = (await app.rowsOf(
        'SELECT id, item_name_snapshot, cost_paisa FROM document_lines '
        'WHERE item_id IS NULL',
      )).single;
      expect(loose['item_name_snapshot'], 'Pyaz');
      expect(loose['cost_paisa'], 0);

      // Stock: the oil's tin left, and nothing else moved.
      expect(
        await app.scalar<int>(
          'SELECT COUNT(*) FROM stock_ledger WHERE document_line_id = '
          "'${loose['id']}'",
        ),
        0,
      );
      expect(
        await app.scalar<int>(
          'SELECT SUM(qty_delta_thousandths) FROM stock_ledger '
          "WHERE item_id = '$oil'",
        ),
        49000,
      );

      // The books balance, and the onions are in the sales.
      expect(
        await app.scalar<int>(
          'SELECT SUM(debit_paisa) - SUM(credit_paisa) FROM journal_lines',
        ),
        0,
      );
      expect(
        await app.scalar<int>(
          'SELECT SUM(jl.credit_paisa - jl.debit_paisa) FROM journal_lines jl '
          "JOIN accounts a ON a.id = jl.account_id WHERE a.system_key = 'sales'",
        ),
        280000,
      );

      // And onto paper, by its name, at its amount.
      await tapButton(tester, 'Printer par bhejein');
      final paper = String.fromCharCodes(
        printer.jobs.single.where((b) => (b >= 32 && b < 127) || b == 10),
      );
      expect(paper, contains('Pyaz'));
      expect(paper, contains('2.5 kg x 120.00'));
      expect(paper, contains('300.00'));
      expect(paper, contains('2,800.00'));
    },
  );

  testWidgets('a loose line is not kept on a quotation', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _openCounter(tester);
    await _openLoose(tester);
    await _typeOnTop(tester, 'Kya hai (marzi se)', 'Rassi');
    await _typeOnTop(tester, 'Qeemat (fi unit, ya poori raqam)', '80');
    await _tapOnTop(tester, 'Bill mein daalein');

    await tapButton(tester, 'Paisay lein');
    await tapButton(tester, 'Quotation banayein');
    expect(
      find.text(
        'Khula maal quotation ya challan par nahi ja sakta. Is ki cheez '
        'banayein, ya abhi bill banayein.',
      ),
      findsOneWidget,
    );
    expect(await app.countIn('documents'), 0);
  });

  testWidgets('a shop reporting to FBR is told why there is no loose line', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.services.updateFirm({
      'is_sales_tax_registered': 1,
      'ntn': '1234567-8',
    });
    await app.services.fbr.save(
      const FbrSettings(enabled: true, token: 'pral-token'),
    );

    await _openCounter(tester);
    await _openLoose(tester);
    expect(
      find.textContaining('FBR ko har line ka HS code chahiye'),
      findsOneWidget,
    );
    expect(find.text('Bill mein daalein'), findsNothing);
  });

  testWidgets(
    "a supplier's last prices are on the delivery, a tap from the cost",
    (tester) async {
      final app = await Harness.startWithShop(tester);
      final oil = await _oil(app);
      await _boughtBefore(app, oil, 2050);
      await _boughtBefore(app, oil, 2100);
      await _boughtBefore(app, oil, 1900, from: 'Sasta Oil Depot');

      await tester.pumpAndSettle();
      await tapText(tester, 'Kharidari');
      await tapText(tester, 'Nayi kharidari');
      await tapText(tester, 'Supplier chunein');
      await tapText(tester, 'Faisal Oil Mills');
      await tapText(tester, 'Cheez shamil karein');
      await _typeOnTop(tester, 'Talash karein', 'Cooking');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tapText(tester, 'Cooking Oil 5L');

      expect(find.text('Is supplier se pichhli khareed'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('2,100.00')).dy,
        lessThan(tester.getTopLeft(find.text('2,050.00')).dy),
        reason: 'newest first',
      );
      expect(
        find.text('1,900.00'),
        findsNothing,
        reason: "another supplier's price",
      );

      await _typeOnTop(tester, 'Tadaad (pcs)', '10');
      await tester.tap(find.text('2,050.00'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.widgetWithText(TextFormField, 'Kharid qeemat').last,
            )
            .controller!
            .text,
        '20,500.00',
        reason: 'ten at the old price',
      );
      await tester.tap(find.text('Cheez shamil karein').last);
      await tester.pumpAndSettle();
      await tapText(tester, 'Kharidari save karein');

      final lines = await app.rowsOf(
        'SELECT dl.rate_milli_paisa FROM document_lines dl '
        'JOIN documents d ON d.id = dl.document_id '
        "WHERE d.doc_type = 'purchase_bill' ORDER BY d.created_at_utc DESC",
      );
      expect(lines.first['rate_milli_paisa'], Rate.rupees(2050).inMilliPaisa);
    },
  );

  group('at 200% on a small phone', () {
    setUpAll(_loadRealFont);

    testWidgets('the last prices and the loose sheet fit', (tester) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      final oil = await _oil(app);
      final rashid = await _party(
        app,
        'Chaudhry Muhammad Aslam Traders',
        PriceTier.wholesale,
      );
      await _soldBefore(app, oil, rashid, 124350);

      await _openCounter(tester);
      await _billTo(tester, 'Chaudhry Muhammad Aslam Traders');
      await _ring(tester, 'Cooking');
      _expectNothingPaintsOffScreen(tester);
      await _openLine(tester);
      _expectNothingPaintsOffScreen(tester);
      await tester.tap(find.text('Ho gaya'));
      await tester.pumpAndSettle();

      await _openLoose(tester);
      _expectNothingPaintsOffScreen(tester);
    });
  });
}

// ---------------------------------------------------------------------------

Future<String> _pcs(Harness app) async => (await app.services.queries.units(
  app.services.identity!.firmId,
)).firstWhere((u) => u.code == 'pcs').id;

Future<String> _oil(Harness app) async => app.services.catalogue.addItem(
  app.services.actorNow(),
  ItemDraft(
    name: 'Cooking Oil 5L',
    baseUnitId: await _pcs(app),
    saleRate: Rate.rupees(2500),
    wholesaleRate: Rate.rupees(2300),
    openingStock: Qty.units(50),
    openingRate: Rate.rupees(2000),
  ),
);

Future<String> _party(Harness app, String name, PriceTier tier) => app
    .services
    .catalogue
    .addParty(app.services.actorNow(), PartyDraft(name: name, priceTier: tier));

/// A bill already in the books: one tin to [partyId] at [rupees], on udhaar.
Future<void> _soldBefore(
  Harness app,
  String oil,
  String partyId,
  int rupees,
) async {
  await app.services.postSale(
    app.services.actorNow(),
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: oil,
          itemName: 'Cooking Oil 5L',
          qty: Qty.one,
          baseQty: Qty.one,
          unitId: await _pcs(app),
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
        ),
      ],
    ),
  );
}

/// A delivery already in the books: ten tins at [rupees] from [from].
Future<void> _boughtBefore(
  Harness app,
  String oil,
  int rupees, {
  String from = 'Faisal Oil Mills',
}) async {
  final firm = app.services.identity!.firmId;
  final known = await app.services.queries.searchParties(firm, query: from);
  final supplier = known.isNotEmpty
      ? known.first.id
      : await app.services.catalogue.addParty(
          app.services.actorNow(),
          PartyDraft(name: from, partyType: 'supplier'),
        );
  await app.services.recordPurchase(
    app.services.actorNow(),
    PurchaseDraft(
      partyId: supplier,
      lines: [
        PurchaseLineDraft(
          itemId: oil,
          itemName: 'Cooking Oil 5L',
          qty: Qty.units(10),
          baseQty: Qty.units(10),
          unitId: await _pcs(app),
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
        ),
      ],
    ),
  );
}

Future<void> _openCounter(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Naya Bill').first);
  await tester.pumpAndSettle();
}

/// Names the customer from the counter's own button, before any goods.
Future<void> _billTo(WidgetTester tester, String name) async {
  await tester.tap(find.byTooltip('Bill kis ke naam'));
  await tester.pumpAndSettle();
  await tapText(tester, name);
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    text,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

Future<void> _ring(WidgetTester tester, String query) async {
  await _search(tester, query);
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
}

/// Taps the quantity of the first line, which opens its editor.
Future<void> _openLine(WidgetTester tester) async {
  await tester.tap(
    find.ancestor(of: find.byType(BlQty), matching: find.byType(InkWell)).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _openLoose(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Khula maal'));
  await tester.pumpAndSettle();
}

Future<void> _typeOnTop(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextFormField, label).last;
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

Future<void> _tapOnTop(WidgetTester tester, String label) async {
  final button = find
      .ancestor(of: find.text(label), matching: find.byType(BlButton))
      .last;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// The owner's PIN, Bilal hired as a cashier, and Bilal signed in through
/// the lock screen.
Future<void> _signInBilal(WidgetTester tester, Harness app) async {
  final services = app.services;
  await services.setPin(services.currentUser!.id, '1947');
  await services.addStaff(name: 'Bilal', role: Role.cashier, pin: '2468');
  ProviderScope.containerOf(
    tester.element(find.byType(HomeScreen)),
  ).bumpRefresh();
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Taala lagayein'));
  await tester.pumpAndSettle();
  await tapText(tester, 'Bilal · Cashier');
  await typeInto(tester, 'PIN', '2468');
  await tapButton(tester, 'Kholein');
  expect(services.currentUser?.role, Role.cashier);
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

/// 360x800 dp with the font at 200%, as `large_text_test.dart` lays it out.
void _useASmallPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(720, 1600)
    ..devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

void _expectNothingPaintsOffScreen(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  for (final element in find.byType(Text).evaluate()) {
    final box = element.renderObject! as RenderBox;
    if (!box.hasSize || box.size.isEmpty) continue;
    final left = box.localToGlobal(Offset.zero).dx;
    final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
    expect(
      right,
      lessThanOrEqualTo(width + 0.5),
      reason:
          '"${(element.widget as Text).data}" is painted from $left to '
          '$right on a $width dp screen',
    );
    expect(left, greaterThanOrEqualTo(-0.5), reason: 'painted off the left');
  }
}

Future<void> _loadRealFont() async {
  final candidates = [
    'C:/Windows/Fonts/segoeui.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
    return;
  }
  fail('no real font found to measure text with');
}
