import 'package:bazaar_ledger/design/components.dart';
import 'package:bazaar_ledger/features/pos/cart.dart';
import 'package:bazaar_ledger/features/pos/pos_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// Never sold into thin air, and packed by the carton, through the screens
/// (M53).
///
/// The rule is enforced beneath every screen (`pk_data`'s tests prove the
/// refusal); what these prove is that the counter says it first, in the
/// shopkeeper's words, at the moment a line goes past the shelf — "Stock
/// sirf 600 kg hai — phir bhi bechein?" — and that the owner can give an
/// item its carton and its rule in the editor, and the shop its rule in
/// Settings, and that the counter and a delivery then count in cartons.
void main() {
  testWidgets(
    'an item set to ask asks at the counter as the line goes past the shelf: '
    'no takes it back, yes sells it',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      await _item(app, 'Atta Chakki', unit: 'kg', onHand: 600, rupees: 120);

      await _openCounter(tester);
      await _ring(tester, 'Atta');
      expect(find.text('Stock kam hai'), findsNothing, reason: 'a kilo fits');

      await _setQty(tester, 'Tadaad (kg)', '700');
      expect(
        find.text('Stock sirf 600 kg hai — phir bhi bechein?'),
        findsOneWidget,
      );
      expect(find.text('Atta Chakki: bill par 700 kg'), findsOneWidget);
      await tester.tap(find.text('Nahi'));
      await tester.pumpAndSettle();
      expect(_cart(tester).lines.single.qty, Qty.one, reason: 'put back');

      await _setQty(tester, 'Tadaad (kg)', '700');
      await tester.tap(find.text('Haan, bechein'));
      await tester.pumpAndSettle();
      expect(_cart(tester).lines.single.qty, Qty.units(700));

      // Asked once: saving the bill does not ask again for the same 700 kg.
      await tapButton(tester, 'Paisay lein');
      await typeInto(tester, 'Diye gaye', '84000');
      await tapButton(tester, 'Save karein');
      await tester.pumpAndSettle();
      expect(find.text('Stock kam hai'), findsNothing);

      expect(
        await app.scalar<int>(
          "SELECT COUNT(*) FROM documents WHERE doc_type = 'sale_invoice'",
        ),
        1,
      );
      expect(
        await app.scalar<int>(
          'SELECT SUM(qty_delta_thousandths) FROM stock_ledger',
        ),
        -100000,
        reason: 'sold knowingly below nothing',
      );
    },
  );

  testWidgets(
    'an item set to refuse is refused at the counter in words, and the line '
    'goes back',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      await _item(
        app,
        'Desi Ghee',
        onHand: 2,
        rupees: 650,
        rule: NegativeStock.block,
      );

      await _openCounter(tester);
      await _ring(tester, 'Ghee');
      await _ring(tester, 'Ghee');
      expect(_cart(tester).lines.single.qty, Qty.units(2));
      expect(find.text('Stock se zyada nahi bik sakta'), findsNothing);

      await _ring(tester, 'Ghee');
      expect(find.text('Stock se zyada nahi bik sakta'), findsOneWidget);
      expect(
        find.textContaining('Stock sirf 2 pcs hai — is se zyada nahi bikta.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Theek hai'));
      await tester.pumpAndSettle();
      expect(_cart(tester).lines.single.qty, Qty.units(2));
    },
  );

  testWidgets(
    'the owner gives an item a carton of 24 and its own rule; the counter '
    'sells it by the carton and 24 pieces leave the shelf',
    (tester) async {
      final app = await Harness.startWithShop(tester);
      await app.seedItem(name: 'Gala Biscuit', rupees: 50);
      await tester.pumpAndSettle();

      await tapText(tester, 'Maal');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Gala Biscuit').first);
      await tester.pumpAndSettle();

      await tapText(tester, 'Aur tafseel');
      await tapText(tester, 'Pack jorein');
      await typeInto(tester, '1 carton mein kitne pcs?', '24');
      await tester.tap(find.widgetWithText(FilledButton, 'Shamil karein'));
      await tester.pumpAndSettle();
      expect(find.text('1 carton = 24 pcs'), findsOneWidget);

      final rule = find.byType(DropdownButtonFormField<NegativeStock?>);
      await tester.ensureVisible(rule);
      await tester.pumpAndSettle();
      await tester.tap(rule);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Na bechein').last);
      await tester.pumpAndSettle();
      await tapButton(tester, 'Save karein');

      expect(
        await app.rowsOf(
          'SELECT factor_thousandths f FROM unit_conversions '
          'WHERE item_id IS NOT NULL AND deleted_at_utc IS NULL',
        ),
        [
          {'f': 24000},
        ],
      );
      expect(
        await app.scalar<String>('SELECT negative_stock FROM items'),
        'block',
      );

      await tester.pageBack();
      await _openCounter(tester);
      await _ring(tester, 'Gala');
      await _openLine(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'carton'));
      await tester.pumpAndSettle();
      expect(find.text('Rs 1,200.00'), findsWidgets, reason: '24 x Rs 50');

      await tapButton(tester, 'Paisay lein');
      await typeInto(tester, 'Diye gaye', '1200');
      await tapButton(tester, 'Save karein');
      await tester.pumpAndSettle();

      final line = await app.rowsOf(
        'SELECT unit_code_snapshot u, qty_thousandths q, '
        'base_qty_thousandths b FROM document_lines',
      );
      expect(line.single, {'u': 'carton', 'q': 1000, 'b': 24000});
      expect(
        await app.scalar<int>(
          'SELECT SUM(qty_delta_thousandths) FROM stock_ledger',
        ),
        76000,
      );
    },
  );

  testWidgets('a delivery is entered by the carton and puts 240 pieces on '
      'the shelf', (tester) async {
    final app = await Harness.startWithShop(tester);
    final carton = await _unit(app, 'carton');
    await _item(
      app,
      'Gala Biscuit',
      onHand: 0,
      rupees: 50,
      packs: [ItemPack(unitId: carton, size: Qty.units(24))],
    );
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

    await tester.tap(find.widgetWithText(ChoiceChip, 'carton · 24 pcs'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Tadaad (carton)', '10');
    await typeInto(tester, 'Kharid qeemat', '9600');
    await tester.tap(find.text('Cheez shamil karein').last);
    await tester.pumpAndSettle();
    await tapText(tester, 'Kharidari save karein');
    await tester.pumpAndSettle();

    final line = await app.rowsOf(
      'SELECT dl.unit_code_snapshot u, dl.qty_thousandths q, '
      'dl.base_qty_thousandths b FROM document_lines dl '
      'JOIN documents d ON d.id = dl.document_id '
      "WHERE d.doc_type = 'purchase_bill'",
    );
    expect(line.single, {'u': 'carton', 'q': 10000, 'b': 240000});
    expect(
      await app.scalar<int>(
        'SELECT SUM(qty_delta_thousandths) FROM stock_ledger',
      ),
      240000,
    );
    expect(
      await app.scalar<int>('SELECT avg_cost_milli_paisa FROM items'),
      Rate.rupees(40).inMilliPaisa,
      reason: 'Rs 960 a carton is Rs 40 a piece',
    );
  });

  testWidgets("the owner sets the shop's own rule in Settings", (tester) async {
    final app = await Harness.startWithShop(tester);
    await openSettings(tester);
    await tapText(tester, 'Stock khatam ho to');
    expect(find.text('Pehle poochein'), findsOneWidget);

    await tester.tap(find.text('Na bechein'));
    await tester.pumpAndSettle();
    expect(
      await app.scalar<String>(
        "SELECT setting_value FROM settings WHERE setting_key = 'stock.negative'",
      ),
      'block',
    );
  });

  group('at 200% on a small phone', () {
    setUpAll(loadRealFont);

    testWidgets('the question at the counter and the refusal fit', (
      tester,
    ) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      await _item(app, 'Basmati Chawal Super Kernel Purana', onHand: 0);
      await _item(
        app,
        'Desi Ghee Khalis Punjab',
        onHand: 0,
        rule: NegativeStock.block,
      );

      await _openCounter(tester);
      await _ring(tester, 'Basmati');
      expect(find.text('Stock kam hai'), findsOneWidget);
      _expectNothingPaintsOffScreen(tester);
      await tester.tap(find.text('Haan, bechein'));
      await tester.pumpAndSettle();

      await _ring(tester, 'Ghee');
      expect(find.text('Stock se zyada nahi bik sakta'), findsOneWidget);
      _expectNothingPaintsOffScreen(tester);
    });

    testWidgets("an item's rule and packs, and the shop's rule, fit", (
      tester,
    ) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      final carton = await _unit(app, 'carton');
      await _item(
        app,
        'Gala Biscuit',
        onHand: 10,
        packs: [ItemPack(unitId: carton, size: Qty.units(24))],
      );
      await tester.pumpAndSettle();

      await tapText(tester, 'Maal');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Gala Biscuit').first);
      await tester.pumpAndSettle();
      await tapText(tester, 'Aur tafseel');
      await tester.ensureVisible(find.text('1 carton = 24 pcs'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
      await tapText(tester, 'Pack jorein');
      _expectNothingPaintsOffScreen(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openSettings(tester);
      await tapText(tester, 'Stock khatam ho to');
      _expectNothingPaintsOffScreen(tester);
    });
  });
}

// ---------------------------------------------------------------------------

Future<String> _unit(Harness app, String code) async =>
    (await app.services.queries.units(
      app.services.identity!.firmId,
    )).firstWhere((u) => u.code == code).id;

Future<String> _item(
  Harness app,
  String name, {
  String unit = 'pcs',
  int onHand = 0,
  int rupees = 100,
  NegativeStock? rule,
  List<ItemPack>? packs,
}) async => app.services.catalogue.addItem(
  app.services.actorNow(),
  ItemDraft(
    name: name,
    baseUnitId: await _unit(app, unit),
    saleRate: Rate.rupees(rupees),
    openingStock: Qty.units(onHand),
    openingRate: Rate.rupees(rupees - 10),
    negativeStock: rule,
    packs: packs,
  ),
);

Cart _cart(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(PosScreen)),
).read(cartProvider);

Future<void> _openCounter(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Naya Bill');
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

