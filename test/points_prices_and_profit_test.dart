import 'dart:io';

import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/design/components.dart';
import 'package:bazaar_ledger/features/reports/report_shelf.dart';
import 'package:bazaar_ledger/features/sales/receipt_screen.dart';
import 'package:bazaar_ledger/features/settings/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// Points that bring a customer back, a price list of their own, and the
/// profit on the bill while it is being made (M66), driven by taps against
/// a real database.
///
/// The shopkeeper this is for keeps a stamp card for his regulars, the rate
/// he agreed with Haji Sahib in his head, and works out his margin on the
/// back of the parchi. Here the counter does all three.
void main() {
  // Measured in a real font, as the other small-phone checks are.
  setUpAll(loadRealFont);

  testWidgets('the owner sets the shop\'s points in Settings, a bill earns '
      'them on what was paid, and the khata and the Loyalty report show '
      'them', (tester) async {
    final app = await Harness.startWithShop(
      tester,
      overrides: [
        reportShelfDirectoryProvider.overrideWith(
          (ref) async => Directory.systemTemp.createTempSync('m66_shelf'),
        ),
      ],
    );
    final oil = await _oil(app);
    final haji = await _party(app, 'Haji Sahib');

    await openSettings(tester);
    await tapText(tester, 'Loyalty points aur munafa');
    // 1 point per Rs 100; 100 points are Rs 50; half a bill at most.
    await typeInto(tester, 'Points', '1');
    await typeInto(tester, 'Har itne Rs par', '100');
    await typeInto(tester, 'Itne points', '100');
    await typeInto(tester, 'Itne Rs ke barabar', '50');
    await tapButton(tester, 'Save karein');
    expect(find.text('Loyalty ka qaida save — agle bill se'), findsOneWidget);
    final rule = (await app.services.loyalty.rules()).current!;
    expect(rule.earnPer, const Money.rupees(100));
    expect(rule.redeemValue, const Money.rupees(50));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Rs 2,550 paid at the counter, and Rs 2,000 on udhaar not yet paid.
    await _sell(app, oil, haji, qty: 3, rate: 850, paid: 2550);
    await _sell(app, oil, haji, qty: 2, rate: 1000);
    ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    ).bumpRefresh();
    await tester.pumpAndSettle();

    await tapText(tester, 'Gahak');
    await tapText(tester, 'Haji Sahib');
    expect(find.text('Loyalty points: 25 (Rs 12.50)'), findsOneWidget);
    expect(find.text('Mile 25 · istemal 0 · khatam 0'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tapText(tester, 'Report');
    await tapText(tester, 'Loyalty points');
    expect(find.text('Haji Sahib'), findsWidgets);
    expect(find.text('Points given'), findsOneWidget);
  });

  testWidgets('a cashier uses a customer\'s points on the payment sheet as a '
      'discount past their own 5%, sees no profit anywhere, and the bill '
      'says what was used and earned', (tester) async {
    final app = await Harness.startWithShop(tester);
    final oil = await _oil(app);
    final haji = await _party(app, 'Haji Sahib');
    await app.services.loyalty.saveRule(const LoyaltyRule(from: '2000-01-01'));
    // Rs 30,000 paid: 300 points.
    await _sell(app, oil, haji, qty: 30, rate: 1000, paid: 30000);
    await _signInBilal(tester, app);

    await _openCounter(tester);
    await _ring(tester, 'Cooking');
    await _clearSearch(tester);
    expect(find.textContaining('Munafa'), findsNothing);
    await _openLine(tester);
    expect(find.textContaining('munafa'), findsNothing);
    expect(find.text('Is gahak ke liye yehi rate rakhein'), findsNothing);
    await tapButton(tester, 'Ho gaya');

    await tapButton(tester, 'Paisay lein');
    await tapText(tester, 'Aam gahak');
    await tapText(tester, 'Haji Sahib');
    expect(find.text('Loyalty: 300 points (Rs 150.00)'), findsOneWidget);
    expect(find.textContaining('Munafa'), findsNothing);
    await tapText(tester, 'Points istemal karein');
    await typeInto(tester, 'Kitne points', '120');
    await tapButton(tester, 'Points lagayein');
    // Rs 60 off a Rs 1,000 bill: 6%, past a cashier's own 5%.
    expect(find.text('120 points istemal: Rs 60.00 kam'), findsOneWidget);
    expect(find.text('Rs 940.00'), findsWidgets);
    await typeInto(tester, 'Diye gaye', '940');
    await tapButton(tester, 'Save karein');
    await tester.pumpAndSettle();

    final bill = await app.rowsOf(
      'SELECT bill_discount_paisa d, total_paisa t FROM documents '
      "WHERE doc_type = 'sale_invoice' ORDER BY created_at_utc DESC LIMIT 1",
    );
    expect(bill.single, {'d': 6000, 't': 94000});
    expect(
      await app.scalar<int>(
        "SELECT COUNT(*) FROM settings WHERE setting_key LIKE 'loyalty.redeemed.%'",
      ),
      1,
    );
    expect(
      (await app.services.loyalty.standingOf(haji)).outstanding,
      300 - 120 + 9,
    );
    expect(find.byType(ReceiptScreen), findsOneWidget);
    expect(
      find.textContaining('120 points istemal hue (Rs 60.00)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Is bill par 9 points mile - Kul 189 points'),
      findsOneWidget,
    );
    expect(
      await app.scalar<int>(
        'SELECT SUM(debit_paisa) - SUM(credit_paisa) FROM journal_lines '
        'WHERE deleted_at_utc IS NULL',
      ),
      0,
      reason: 'the books balance',
    );
  });

  testWidgets(
    'a customer\'s own price, set from their details, wins over their '
    'wholesale price and a lower slab, loses to a price typed, and one is '
    'kept from the counter line',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      final cheeni = await app.services.catalogue.addItem(
        app.services.actorNow(),
        ItemDraft(
          name: 'Cheeni 1kg',
          baseUnitId: await _pcs(app),
          saleRate: Rate.rupees(150),
          wholesaleRate: Rate.rupees(140),
          openingStock: Qty.units(100),
          openingRate: Rate.rupees(120),
        ),
      );
      await app.services.saveItemScheme(
        ItemScheme(
          itemId: cheeni,
          slabs: [QtySlab(from: Qty.units(10), rate: const Rate.rupees(130))],
        ),
      );
      await app.services.catalogue.addItem(
        app.services.actorNow(),
        ItemDraft(
          name: 'Atta 10kg',
          baseUnitId: await _pcs(app),
          saleRate: Rate.rupees(1500),
          openingStock: Qty.units(20),
          openingRate: Rate.rupees(1200),
        ),
      );
      final haji = await _party(app, 'Haji Sahib', tier: PriceTier.wholesale);
      await tester.pumpAndSettle();

      // From his details: Cheeni at Rs 135.
      await tapText(tester, 'Gahak');
      await tapText(tester, 'Haji Sahib');
      await tester.tap(find.byTooltip('Gahak ki tafseel'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Gahak ke apne rate');
      await tapButton(tester, 'Cheez ka rate rakhein');
      await tapText(tester, 'Cheeni 1kg');
      await typeInto(tester, 'Rate (fi pcs)', '135');
      await tapButton(tester, 'Save karein');
      expect(find.text('Rs 135.00 fi pcs'), findsOneWidget);
      // And on his khata from now on.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Apne rate: 1 cheezen'), findsOneWidget);
      for (var i = 0; i < 2; i++) {
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      await _openCounter(tester);
      await tester.tap(find.byTooltip('Bill kis ke naam'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Haji Sahib');
      await _ring(tester, 'Cheeni');
      await _clearSearch(tester);
      await _setQty(tester, 'Tadaad (pcs)', '12');
      // Twelve reach the Rs 130 slab and his wholesale price is Rs 140: his
      // own Rs 135 is what he pays.
      expect(find.text('Haji Sahib ka rate'), findsOneWidget);
      expect(find.text('Rs 1,620.00'), findsWidgets);

      await _openLine(tester);
      await typeInto(tester, 'Qeemat', '132');
      await tapButton(tester, 'Ho gaya');
      expect(find.text('Haji Sahib ka rate'), findsNothing);
      expect(find.text('Rs 1,584.00'), findsWidgets);

      // Atta at his wholesale (no wholesale price: Rs 1,500), typed Rs 1,400
      // and kept as his from the line.
      await _ring(tester, 'Atta');
      await _clearSearch(tester);
      await tester.tap(
        find
            .ancestor(of: find.byType(BlQty), matching: find.byType(InkWell))
            .last,
      );
      await tester.pumpAndSettle();
      await typeInto(tester, 'Qeemat', '1400');
      await tapButton(tester, 'Is gahak ke liye yehi rate rakhein');
      expect(find.text('Haji Sahib ke liye rate rakh diya'), findsOneWidget);
      expect(find.text('Haji Sahib ka rate'), findsOneWidget);
      final kept = await app.services.loyalty.pricesOf(haji);
      expect(
        kept.rates.values,
        containsAll([Rate.rupees(135), Rate.rupees(1400)]),
      );

      await tapButton(tester, 'Paisay lein');
      await typeInto(tester, 'Diye gaye', '2984');
      await tapButton(tester, 'Save karein');
      await tester.pumpAndSettle();
      final lines = await app.rowsOf(
        'SELECT item_name_snapshot n, rate_milli_paisa r, discount_paisa d '
        'FROM document_lines ORDER BY line_no',
      );
      expect(lines, [
        {'n': 'Cheeni 1kg', 'r': Rate.rupees(132).inMilliPaisa, 'd': 0},
        {'n': 'Atta 10kg', 'r': Rate.rupees(1400).inMilliPaisa, 'd': 0},
      ]);
    },
  );

  testWidgets('the owner sees the bill\'s profit at the counter and on the '
      'payment sheet, a line below cost in red, and turns it off in '
      'Settings', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _oil(app);
    await tester.pumpAndSettle();

    await _openCounter(tester);
    await _ring(tester, 'Cooking');
    await _clearSearch(tester);
    expect(find.text('Munafa Rs 200.00 (20%)'), findsOneWidget);
    await _openLine(tester);
    expect(find.text('Is cheez par munafa Rs 200.00 (20%)'), findsOneWidget);
    await typeInto(tester, 'Qeemat', '700');
    await tapButton(tester, 'Ho gaya');
    expect(find.text('Qeemat se kam'), findsNWidgets(2));
    expect(find.text('Munafa Rs -100.00 (-14.3%)'), findsOneWidget);

    await tapButton(tester, 'Paisay lein');
    expect(find.text('Munafa Rs -100.00 (-14.3%)'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Band karein').last);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await openSettings(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tapText(tester, 'Loyalty points aur munafa');
    await tapText(tester, 'Counter par bill ka munafa dikhayein');
    expect(await app.services.loyalty.marginShown(), isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await _openCounter(tester);
    expect(find.textContaining('Munafa'), findsNothing);
    expect(find.text('Qeemat se kam'), findsNothing);
  });

  testWidgets('at 200% on a small phone the points and own prices on the '
      'khata, the price list and the loyalty settings fit', (tester) async {
    final app = await Harness.startWithShop(tester);
    final oil = await _oil(app);
    final haji = await _party(app, 'Haji Sahib General Store Shah Alam');
    await app.services.loyalty.saveRule(const LoyaltyRule(from: '2000-01-01'));
    await _sell(app, oil, haji, qty: 30, rate: 1000, paid: 30000);
    await app.services.loyalty.setPartyPrice(haji, oil, Rate.rupees(950));
    _useASmallPhone(tester);
    await tester.pumpAndSettle();

    await openSettings(tester);
    await tapText(tester, 'Loyalty points aur munafa');
    _expectNothingPaintsOffScreen(tester);
    for (var i = 0; i < 2; i++) {
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    await tapText(tester, 'Gahak');
    await tapText(tester, 'Haji Sahib General Store Shah Alam');
    expect(find.textContaining('Loyalty points: 300'), findsOneWidget);
    _expectNothingPaintsOffScreen(tester);
    await tapText(tester, 'Apne rate: 1 cheezen');
    expect(find.text('Rs 950.00 fi pcs'), findsOneWidget);
    _expectNothingPaintsOffScreen(tester);
  });

  testWidgets('at 200% on a small phone the own price and the profit on the '
      'counter and the points on the payment sheet fit', (tester) async {
    final app = await Harness.startWithShop(tester);
    final oil = await _oil(app);
    final haji = await _party(app, 'Haji Sahib General Store Shah Alam');
    await app.services.loyalty.saveRule(const LoyaltyRule(from: '2000-01-01'));
    await _sell(app, oil, haji, qty: 30, rate: 1000, paid: 30000);
    await app.services.loyalty.setPartyPrice(haji, oil, Rate.rupees(950));
    _useASmallPhone(tester);
    await tester.pumpAndSettle();

    await _openCounter(tester);
    await tester.tap(find.byTooltip('Bill kis ke naam'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Haji Sahib General Store Shah Alam');
    await _ring(tester, 'Cooking');
    await _clearSearch(tester);
    expect(
      find.text('Haji Sahib General Store Shah Alam ka rate'),
      findsOneWidget,
    );
    expect(find.textContaining('Munafa Rs 150.00'), findsOneWidget);
    _expectNothingPaintsOffScreen(tester);

    await tapButton(tester, 'Paisay lein');
    await tapText(tester, 'Points istemal karein');
    expect(find.text('Points lagayein'), findsOneWidget);
    _expectNothingPaintsOffScreen(tester);
    await tapButton(tester, 'Points lagayein');
    expect(find.textContaining('points istemal: Rs'), findsOneWidget);
    _expectNothingPaintsOffScreen(tester);
  });
}

Future<String> _pcs(Harness app) async => (await app.services.queries.units(
  app.services.identity!.firmId,
)).firstWhere((u) => u.code == 'pcs').id;

/// Rs 1,000 a tin, bought at Rs 800.
Future<String> _oil(Harness app) async => app.services.catalogue.addItem(
  app.services.actorNow(),
  ItemDraft(
    name: 'Cooking Oil 5L',
    baseUnitId: await _pcs(app),
    saleRate: Rate.rupees(1000),
    openingStock: Qty.units(100),
    openingRate: Rate.rupees(800),
  ),
);

Future<String> _party(
  Harness app,
  String name, {
  PriceTier tier = PriceTier.retail,
}) => app.services.catalogue.addParty(
  app.services.actorNow(),
  PartyDraft(name: name, priceTier: tier),
);

/// A bill already in the books, [paid] of it in cash at the counter.
Future<void> _sell(
  Harness app,
  String itemId,
  String partyId, {
  required int qty,
  required int rate,
  int paid = 0,
}) async {
  final firm = app.services.identity!.firmId;
  final cash = (await app.services.queries.paymentAccounts(
    firm,
  )).firstWhere((a) => a.modeLabel == 'cash');
  await app.services.postSale(
    app.services.actorNow(),
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: 'Cooking Oil 5L',
          qty: Qty.units(qty),
          baseQty: Qty.units(qty),
          unitId: await _pcs(app),
          unitCode: 'pcs',
          rate: Rate.rupees(rate),
        ),
      ],
      tenders: [
        if (paid > 0)
          TenderDraft(
            paymentAccountId: cash.id,
            mode: 'cash',
            amount: Money.rupees(paid),
          ),
      ],
    ),
  );
}

/// The owner's PIN, Bilal hired as a cashier, and Bilal signed in through
/// the lock screen.
Future<void> _signInBilal(WidgetTester tester, Harness app) async {
  final services = app.services;
  await services.setPin(services.currentUser!.id, '1947');
  await services.addStaff(name: 'Bilal', role: Role.cashier, pin: '2468');
  ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).first),
  ).bumpRefresh();
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Taala lagayein'));
  await tester.pumpAndSettle();
  await tapText(tester, 'Bilal · Cashier');
  await typeInto(tester, 'PIN', '2468');
  await tapButton(tester, 'Kholein');
  expect(services.currentUser?.role, Role.cashier);
}

Future<void> _openCounter(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Naya Bill').first);
  await tester.pumpAndSettle();
}

Future<void> _ring(WidgetTester tester, String query) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    query,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
}

Future<void> _clearSearch(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    '',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// Taps the quantity of the first line, which opens its editor.
Future<void> _openLine(WidgetTester tester) async {
  await tester.tap(
    find.ancestor(of: find.byType(BlQty), matching: find.byType(InkWell)).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _setQty(WidgetTester tester, String label, String qty) async {
  await _openLine(tester);
  await typeInto(tester, label, qty);
  await tapButton(tester, 'Ho gaya');
  await tester.pumpAndSettle();
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

