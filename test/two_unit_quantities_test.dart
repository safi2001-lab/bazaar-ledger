import 'dart:io';

import 'package:bazaar_ledger/design/components.dart';
import 'package:bazaar_ledger/features/pos/cart.dart';
import 'package:bazaar_ledger/features/pos/pos_screen.dart';
import 'package:bazaar_ledger/features/reports/report_shelf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// M45 from the screen: an item kept in cartons of 24 shown as "2 ctn + 5
/// pcs" wherever its quantity is, typed as "2 ctn 5" at the counter and on
/// a delivery, and charged exactly.
///
/// Vyapar's most-agreed-with review of September 2026 (+403) is a carton
/// shown as "0.4756". Nothing here ever shows a decimal of a carton.
void main() {
  testWidgets('the counter shows fifty-three pieces of a carton-of-24 item as '
      '2 ctn + 5 pcs, and two cartons as 2 ctn', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _gala(app);

    await _openCounter(tester);
    await _ring(tester, 'Gala');
    expect(find.text('1 pcs'), findsOneWidget);

    await _setQty(tester, 'Tadaad (pcs)', '53');
    expect(find.text('2 ctn + 5 pcs'), findsOneWidget);
    expect(_cart(tester).lines.single.qty, Qty.units(53));

    // Sold by the carton: the line says cartons, where it used to print the
    // figure beside the piece ("2 pcs" for two cartons).
    await _setQty(tester, 'Tadaad (pcs)', '1');
    await _openLine(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'carton'));
    await tester.pumpAndSettle();
    await _setQty(tester, 'Tadaad (carton)', '2');
    expect(find.text('2 ctn'), findsOneWidget);
    expect(find.text('Rs 1,920.00'), findsWidgets, reason: '48 x Rs 40');
  });

  testWidgets('typing 2 ctn 5 at the counter puts exactly 53 pieces on the '
      'bill at the piece price, and the bill posts them', (tester) async {
    final app = await Harness.startWithShop(tester);
    final gala = await _gala(app);

    await _openCounter(tester);
    await _ring(tester, 'Gala');
    await _openLine(tester);
    await typeInto(tester, 'Tadaad (pcs)', '2 ctn 5');
    // Said back before anything is saved.
    expect(find.text('Yani 2 ctn + 5 pcs (53 pcs)'), findsOneWidget);
    await tapButton(tester, 'Ho gaya');
    await tester.pumpAndSettle();

    final line = _cart(tester).lines.single;
    expect(line.qty, Qty.units(53));
    expect(line.qty.inThousandths, 53000);
    expect(line.sellingUnitCode, 'pcs');
    expect(line.rate, Rate.rupees(40));
    expect(find.text('2 ctn + 5 pcs'), findsOneWidget);
    expect(find.text('Rs 2,120.00'), findsWidgets);

    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '2120');
    await tapButton(tester, 'Save karein');
    await tester.pumpAndSettle();

    final rows = await app.rowsOf(
      'SELECT unit_code_snapshot u, qty_thousandths q, '
      'base_qty_thousandths b, gross_paisa g FROM document_lines',
    );
    expect(rows.single, {'u': 'pcs', 'q': 53000, 'b': 53000, 'g': 212000});
    expect(await _onHand(app, gala), 100000 - 53000);
  });

  testWidgets('on a carton line, 3 ctn stays three cartons and 2 ctn 5 moves '
      'to pieces at Rs 960 / 24, exactly', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _gala(app);

    await _openCounter(tester);
    await _ring(tester, 'Gala');
    await _openLine(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'carton'));
    await tester.pumpAndSettle();

    await _setQty(tester, 'Tadaad (carton)', '3 ctn');
    var line = _cart(tester).lines.single;
    expect(line.sellingUnitCode, 'carton');
    expect(line.qty, Qty.units(3));
    expect(line.rate, Rate.rupees(960));
    expect(find.text('3 ctn'), findsOneWidget);

    await _setQty(tester, 'Tadaad (carton)', '2c 5p');
    line = _cart(tester).lines.single;
    expect(line.sellingUnitCode, 'pcs', reason: 'never 2.208 cartons');
    expect(line.qty, Qty.units(53));
    expect(line.rate, Rate.rupees(40));
    expect(line.net, Money.rupees(2120));
    expect(find.text('2 ctn + 5 pcs'), findsOneWidget);
  });

  testWidgets('a carton price that is no whole price a piece is refused in '
      'words, and the line is left as it was', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _gala(app);

    await _openCounter(tester);
    await _ring(tester, 'Gala');
    await _openLine(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'carton'));
    await tester.pumpAndSettle();

    await _openLine(tester);
    await typeInto(tester, 'Qeemat', '1000');
    await typeInto(tester, 'Tadaad (carton)', '2 ctn 5');
    await tapButton(tester, 'Ho gaya');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Rs 1,000.00 ka carton aik pcs ke poore paise'),
      findsOneWidget,
    );
    final line = _cart(tester).lines.single;
    expect(line.sellingUnitCode, 'carton');
    expect(line.qty, Qty.one);
    expect(line.rate, Rate.rupees(960));

    // And something that is not a quantity at all is said to be so.
    await typeInto(tester, 'Tadaad (carton)', '2 xyz');
    expect(find.textContaining('Samajh nahi aaya'), findsOneWidget);
  });

  testWidgets('the stepper adds a carton and a piece, and the carton '
      'calculator says the piece price under a carton price and the carton '
      'price under a piece price', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _gala(app);

    await _openCounter(tester);
    await _ring(tester, 'Gala');
    await _openLine(tester);
    expect(find.text('1 ctn = Rs 960.00'), findsOneWidget);

    await tester.tap(find.text('+1 ctn'));
    await tester.pumpAndSettle();
    expect(find.text('1 ctn + 1 pcs'), findsOneWidget, reason: 'in the box');
    await tester.tap(find.text('+1 pcs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+1 ctn'));
    await tester.pumpAndSettle();
    expect(find.text('Yani 2 ctn + 2 pcs (50 pcs)'), findsOneWidget);
    await tester.tap(find.text('−1 pcs'));
    await tester.pumpAndSettle();
    await tapButton(tester, 'Ho gaya');
    await tester.pumpAndSettle();
    expect(_cart(tester).lines.single.qty, Qty.units(49));
    expect(find.text('2 ctn + 1 pcs'), findsOneWidget);

    await _setQty(tester, 'Tadaad (pcs)', '1');
    await _openLine(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'carton'));
    await tester.pumpAndSettle();
    await _openLine(tester);
    expect(find.text('1 pcs = Rs 40.00'), findsOneWidget);
  });

  testWidgets('a delivery typed 10 ctn 5 puts 245 pieces on the shelf at the '
      'piece price, and the delivery says it in cartons', (tester) async {
    final app = await Harness.startWithShop(tester);
    final gala = await _gala(app, onHand: 0);
    await app.services.catalogue.addParty(
      app.services.actorNow(),
      const PartyDraft(name: 'Peek Freans Depot', partyType: 'supplier'),
    );
    await tester.pumpAndSettle();

    await tapText(tester, 'Kharidari');
    await tapText(tester, 'Nayi kharidari');
    await tapText(tester, 'Supplier chunein');
    await tapText(tester, 'Peek Freans Depot');
    await tapText(tester, 'Cheez shamil karein');
    await typeInto(tester, 'Talash karein', 'Gala');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tapText(tester, 'Gala Biscuit');

    await typeInto(tester, 'Tadaad (pcs)', '10 ctn 5');
    expect(find.text('Yani 10 ctn + 5 pcs (245 pcs)'), findsOneWidget);
    await typeInto(tester, 'Kharid qeemat', '9800');
    expect(
      find.text('1 ctn = Rs 960.00  ·  1 pcs = Rs 40.00'),
      findsOneWidget,
      reason: 'Rs 9,800 for 245 pieces is Rs 40 a piece, Rs 960 a carton',
    );
    await tester.tap(find.text('Cheez shamil karein').last);
    await tester.pumpAndSettle();
    expect(find.text('Yani 10 ctn + 5 pcs (245 pcs)'), findsOneWidget);

    await tapText(tester, 'Kharidari save karein');
    await tester.pumpAndSettle();

    final rows = await app.rowsOf(
      'SELECT dl.unit_code_snapshot u, dl.qty_thousandths q, '
      'dl.base_qty_thousandths b FROM document_lines dl '
      'JOIN documents d ON d.id = dl.document_id '
      "WHERE d.doc_type = 'purchase_bill'",
    );
    expect(rows.single, {'u': 'pcs', 'q': 245000, 'b': 245000});
    expect(await _onHand(app, gala), 245000);
    expect(
      await app.scalar<int>('SELECT avg_cost_milli_paisa FROM items'),
      Rate.rupees(40).inMilliPaisa,
    );
  });

  testWidgets('the item list, the shelf count, the item history and low '
      'stock read in cartons, and a shelf is counted as 1 ctn 7', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _gala(app, onHand: 53, minStock: 48);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Maal').first);
    await tester.pumpAndSettle();
    expect(find.text('2 ctn + 5 pcs mojood'), findsOneWidget);

    await tester.tap(find.textContaining('Gala Biscuit').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Stock ki tafseel'));
    await tester.pumpAndSettle();
    expect(find.text('2 ctn + 5 pcs'), findsOneWidget, reason: 'the opening');
    expect(find.text('Baqi: 2 ctn + 5 pcs'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Stock theek karein'));
    await tester.pumpAndSettle();
    expect(find.text('2 ctn + 5 pcs'), findsOneWidget, reason: 'on the shelf');
    await typeInto(tester, 'Ginti ke baad kitna hai', '1 ctn 7');
    await typeInto(tester, 'Wajah', 'Mahana ginti');
    await tapButton(tester, 'Theek karein');
    await tester.pumpAndSettle();
    expect(
      await app.scalar<int>(
        'SELECT SUM(qty_delta_thousandths) FROM stock_ledger',
      ),
      31000,
      reason: 'a carton and seven',
    );
  });

  testWidgets('low stock reads in cartons', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _gala(app, onHand: 29, minStock: 48);
    await tester.pumpAndSettle();

    await tapText(tester, 'Kam stock');
    expect(find.text('1 ctn + 5 pcs'), findsOneWidget);
    expect(find.text('Hadd: 2 ctn'), findsOneWidget);
  });

  testWidgets('the stock summary reads an item kept in cartons in cartons, '
      'and every other item as before', (tester) async {
    final dir = Directory.systemTemp.createTempSync('report_shelf');
    final app = await Harness.startWithShop(
      tester,
      overrides: [
        reportShelfDirectoryProvider.overrideWith((ref) async => dir),
      ],
    );
    await _gala(app, onHand: 53);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500, openingStock: 12);

    await tapText(tester, 'Report');
    await tester.scrollUntilVisible(find.text('Stock ka khulasa'), 200);
    await tapText(tester, 'Stock ka khulasa');

    expect(find.text('2 ctn + 5 pcs'), findsOneWidget);
    expect(find.text('12'), findsWidgets, reason: 'no pack, so the figure');
  });

  group('at 200% on a small phone', () {
    setUpAll(loadRealFont);

    testWidgets('the counter line, its quantity box with the stepper and the '
        'carton calculator fit', (tester) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      await _gala(app, name: 'Gala Biscuit Family Pack Special Offer');

      await _openCounter(tester);
      await _ring(tester, 'Gala');
      await _setQty(tester, 'Tadaad (pcs)', '2 ctn 5');
      expect(find.text('2 ctn + 5 pcs'), findsOneWidget);
      _expectNothingPaintsOffScreen(tester);

      await _openLine(tester);
      expect(find.text('+1 ctn'), findsOneWidget);
      _expectNothingPaintsOffScreen(tester);
    });

    testWidgets('the delivery picker, its quantity box with the stepper and '
        'the carton calculator fit', (tester) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      await _gala(app, name: 'Gala Biscuit Family Pack', onHand: 0);
      await app.services.catalogue.addParty(
        app.services.actorNow(),
        const PartyDraft(name: 'Peek Freans Depot', partyType: 'supplier'),
      );
      await tester.pumpAndSettle();

      await tapText(tester, 'Kharidari');
      await tapText(tester, 'Nayi kharidari');
      await tapText(tester, 'Supplier chunein');
      await tapText(tester, 'Peek Freans Depot');
      await tapText(tester, 'Cheez shamil karein');
      await typeInto(tester, 'Talash karein', 'Gala');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tapText(tester, 'Gala Biscuit Family Pack');
      await typeInto(tester, 'Tadaad (pcs)', '10 ctn 5');
      await typeInto(tester, 'Kharid qeemat', '9800');
      expect(find.text('+1 ctn'), findsOneWidget);
      _expectNothingPaintsOffScreen(tester);
    });

    testWidgets('the item list and the shelf count fit', (tester) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      await _gala(app, name: 'Gala Biscuit Family Pack', onHand: 1253);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Maal').first);
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
      await tester.tap(find.textContaining('Gala Biscuit').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Stock theek karein'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
    });
  });
}

// ---------------------------------------------------------------------------

/// Gala biscuits at Rs 40 a piece, in cartons of 24.
Future<String> _gala(
  Harness app, {
  String name = 'Gala Biscuit',
  int onHand = 100,
  int minStock = 0,
}) async {
  final units = await app.services.queries.units(app.services.identity!.firmId);
  String unit(String code) => units.firstWhere((u) => u.code == code).id;
  return app.services.catalogue.addItem(
    app.services.actorNow(),
    ItemDraft(
      name: name,
      baseUnitId: unit('pcs'),
      saleRate: Rate.rupees(40),
      openingStock: Qty.units(onHand),
      openingRate: Rate.rupees(30),
      minStock: Qty.units(minStock),
      packs: [ItemPack(unitId: unit('carton'), size: Qty.units(24))],
    ),
  );
}

Future<int> _onHand(Harness app, String itemId) async =>
    (await app.rowsOf(
          'SELECT COALESCE(SUM(qty_delta_thousandths), 0) q FROM stock_ledger '
          "WHERE item_id = '$itemId'",
        )).single['q']!
        as int;

Cart _cart(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(PosScreen)),
).read(cartProvider);

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

/// Taps the quantity of the first line, which opens its editor.
Future<void> _openLine(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    '',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
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

