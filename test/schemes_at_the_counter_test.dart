import 'package:bazaar_ledger/design/components.dart';
import 'package:bazaar_ledger/features/pos/cart.dart';
import 'package:bazaar_ledger/features/pos/cart_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// Bonus and slabs at the counter, driven by taps (M43).
///
/// The shopkeeper this is for does the scheme on a calculator beside the
/// till today: counts the soaps, works out the free one, writes "1 muft"
/// on the parchi, and takes two rupees off the dozen. Here the counter does
/// all of it as the lines are rung, says so on the screen, and lets the
/// cashier take any of it off.
void main() {
  // Measured in a real font, as the other small-phone checks are: the test
  // font's square glyphs make every line wider than any phone would.
  setUpAll(loadRealFont);

  testWidgets('ten soaps rung put the free one under the line; the cashier '
      'takes it off and puts it back, and the bill carries it', (tester) async {
    final app = await Harness.startWithShop(tester);
    final soap = await _item(app, 'Lux Soap', rupees: 100);
    await app.services.saveItemScheme(
      ItemScheme(
        itemId: soap,
        bonus: BonusRule(buy: Qty.units(10), free: Qty.units(1)),
      ),
    );

    await _openCounter(tester);
    await _ring(tester, 'Lux');
    await _clearSearch(tester);
    expect(find.text('Scheme 10+1'), findsOneWidget);

    await _setQty(tester, 'Tadaad (pcs)', '10');
    expect(find.text('Bonus / muft: Lux Soap 1 pcs'), findsOneWidget);

    await tester.tap(find.byTooltip('Bonus hatayein'));
    await tester.pumpAndSettle();
    expect(find.text('Bonus / muft: Lux Soap 1 pcs'), findsNothing);
    expect(find.text('Bonus hata diya: Lux Soap 1 pcs'), findsOneWidget);
    await tapText(tester, 'Wapas lagayein');
    expect(find.text('Bonus / muft: Lux Soap 1 pcs'), findsOneWidget);

    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '1000');
    await tapButton(tester, 'Save karein');
    await tester.pumpAndSettle();

    final lines = await app.rowsOf(
      'SELECT is_free_item f, base_qty_thousandths b, line_total_paisa t '
      'FROM document_lines ORDER BY line_no',
    );
    expect(lines, [
      {'f': 0, 'b': 10000, 't': 100000},
      {'f': 1, 'b': 1000, 't': 0},
    ]);
    expect(await app.scalar<int>('SELECT total_paisa FROM documents'), 100000);
    expect(
      await app.scalar<int>(
        'SELECT SUM(qty_delta_thousandths) FROM stock_ledger',
      ),
      89000,
      reason: 'a hundred on the shelf, eleven gone',
    );
  });

  test('what the cashier took off survives the app being killed, and a '
      'draft from before schemes reads as every scheme on', () {
    const item = ItemSummary(
      id: 'soap',
      name: 'Lux Soap',
      unitId: 'u-pcs',
      unitCode: 'pcs',
      unitDecimals: 0,
      saleRate: Rate.rupees(100),
      stockOnHand: Qty.zero,
      tracksStock: true,
    );
    final cart = Cart(
      lines: [CartLine(item: item, qty: Qty.units(10), rate: Rate.rupees(100))],
      bonusWaived: const {'soap'},
      slabWaived: true,
    );
    final back = CartDraft.decode(CartDraft.encode(cart))!;
    expect(back.bonusWaived, {'soap'});
    expect(back.slabWaived, isTrue);

    final plain = CartDraft.decode(CartDraft.encode(Cart(lines: cart.lines)))!;
    expect(plain.bonusWaived, isEmpty);
    expect(plain.slabWaived, isFalse);
  });

  testWidgets('a bonus the cashier took off stays off on the bill', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final soap = await _item(app, 'Lux Soap', rupees: 100);
    await app.services.saveItemScheme(
      ItemScheme(
        itemId: soap,
        bonus: BonusRule(buy: Qty.units(10), free: Qty.units(1)),
      ),
    );
    await _openCounter(tester);
    await _ring(tester, 'Lux');
    await _clearSearch(tester);
    await _setQty(tester, 'Tadaad (pcs)', '10');
    await tester.tap(find.byTooltip('Bonus hatayein'));
    await tester.pumpAndSettle();

    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '1000');
    await tapButton(tester, 'Save karein');
    await tester.pumpAndSettle();

    expect(
      await app.scalar<int>('SELECT COUNT(*) FROM document_lines'),
      1,
      reason: 'no free line',
    );
  });

  testWidgets('a dozen reaches the slab price, eleven go back above it, and '
      'a carton is priced from the slab exactly', (tester) async {
    final app = await Harness.startWithShop(tester);
    final carton = await _unit(app, 'carton');
    final oil = await _item(
      app,
      'Dalda Oil 1L',
      rupees: 50,
      onHand: 500,
      packs: [ItemPack(unitId: carton, size: Qty.units(24))],
    );
    await app.services.saveItemScheme(
      ItemScheme(
        itemId: oil,
        slabs: [
          QtySlab(from: Qty.units(12), rate: const Rate.rupees(46)),
          QtySlab(from: Qty.units(24), rate: const Rate.rupees(44)),
        ],
      ),
    );

    await _openCounter(tester);
    await _ring(tester, 'Dalda');
    await _clearSearch(tester);
    await _setQty(tester, 'Tadaad (pcs)', '12');
    expect(find.text('Rs 552.00'), findsWidgets, reason: '12 x Rs 46');
    await _setQty(tester, 'Tadaad (pcs)', '11');
    expect(find.text('Rs 550.00'), findsWidgets, reason: '11 x Rs 50');

    await _openLine(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'carton'));
    await tester.pumpAndSettle();
    await _setQty(tester, 'Tadaad (carton)', '1');
    expect(
      find.text('Rs 1,056.00'),
      findsWidgets,
      reason: 'a carton is 24 pieces at the carton slab, Rs 44',
    );

    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '1056');
    await tapButton(tester, 'Save karein');
    await tester.pumpAndSettle();
    final line = await app.rowsOf(
      'SELECT rate_milli_paisa r, base_qty_thousandths b FROM document_lines',
    );
    expect(line.single, {
      'r': const Rate.rupees(1056).inMilliPaisa,
      'b': 24000,
    });
  });

  testWidgets('a price the cashier typed stands whatever the quantity', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final oil = await _item(app, 'Dalda Oil 1L', rupees: 50, onHand: 500);
    await app.services.saveItemScheme(
      ItemScheme(
        itemId: oil,
        slabs: [QtySlab(from: Qty.units(12), rate: const Rate.rupees(46))],
      ),
    );
    await _openCounter(tester);
    await _ring(tester, 'Dalda');
    await _clearSearch(tester);
    await _openLine(tester);
    await typeInto(tester, 'Qeemat', '48');
    await tapButton(tester, 'Ho gaya');
    await _setQty(tester, 'Tadaad (pcs)', '12');
    expect(find.text('Rs 576.00'), findsWidgets, reason: '12 x Rs 48');
  });

  testWidgets('the payment sheet says the shop\'s discount on a big bill, '
      'takes it off on a tap, and the bill carries what was shown', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _item(app, 'Lux Soap', rupees: 100);
    await app.services.saveBillSlabs([
      BillSlab(from: const Money.rupees(1000), percentBp: 200),
    ]);

    await _openCounter(tester);
    await _ring(tester, 'Lux');
    await _clearSearch(tester);
    await _setQty(tester, 'Tadaad (pcs)', '8');
    await tapButton(tester, 'Paisay lein');
    expect(
      find.text('Rs 200.00 ka aur saman lein to bill par 2% discount'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Band karein').last);
    await tester.pumpAndSettle();

    await _setQty(tester, 'Tadaad (pcs)', '20');
    await tapButton(tester, 'Paisay lein');
    expect(
      find.text('Bill par 2% discount (Rs 1,000.00 se upar)'),
      findsOneWidget,
    );
    expect(find.text('Rs 1,960.00'), findsWidgets);

    await tapText(tester, 'Hatayein');
    expect(find.text('2% bill discount hata diya'), findsOneWidget);
    expect(find.text('Rs 2,000.00'), findsWidgets);
    await tapText(tester, 'Wapas lagayein');

    await typeInto(tester, 'Diye gaye', '1960');
    await tapButton(tester, 'Save karein');
    await tester.pumpAndSettle();
    final bill = await app.rowsOf(
      'SELECT bill_discount_paisa d, total_paisa t FROM documents '
      "WHERE doc_type = 'sale_invoice'",
    );
    expect(bill.single, {'d': 4000, 't': 196000});
  });

  testWidgets('the owner gives an item a 10+1 and a dozen price from its '
      'editor, and Settings lists it beside the shop\'s bill slab', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final soap = await _item(app, 'Lux Soap', rupees: 50);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Maal').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Lux Soap').first);
    await tester.pumpAndSettle();
    await tapText(tester, 'Aur tafseel');
    await tapText(tester, 'Scheme (10+1) aur tadaad par rate');
    await typeInto(tester, 'Itne lein (pcs)', '10');
    await typeInto(tester, 'Itne muft (pcs)', '1');
    expect(find.text('Har 10 pcs par 1 pcs Lux Soap muft'), findsOneWidget);
    await typeInto(tester, 'Kam az kam (pcs)', '12');
    await typeInto(tester, 'Rate (fi pcs)', '46');
    await tapButton(tester, 'Save karein');

    final kept = ItemScheme.fromJson(
      soap,
      await app.scalar<String>(
        "SELECT setting_value FROM settings WHERE setting_key LIKE 'scheme.item.%'",
      ),
    );
    expect(kept.bonus, BonusRule(buy: Qty.units(10), free: Qty.units(1)));
    expect(kept.slabs, [
      QtySlab(from: Qty.units(12), rate: const Rate.rupees(46)),
    ]);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openSettings(tester);
    await tapText(tester, 'Scheme aur slab');
    expect(find.text('Lux Soap'), findsOneWidget);
    expect(find.text('Bonus 10+1 · 1 rate slab'), findsOneWidget);

    await typeInto(tester, 'Bill kam az kam (Rs)', '5000');
    await typeInto(tester, 'Discount %', '2.5');
    await tapButton(tester, 'Save karein');
    expect(
      BillSlab.listFromJson(
        await app.scalar<String>(
          "SELECT setting_value FROM settings WHERE setting_key = 'scheme.bill_slabs'",
        ),
      ),
      [BillSlab(from: const Money.rupees(5000), percentBp: 250)],
    );
  });

  testWidgets('a delivery\'s 10+1 is typed on the line, the average falls, '
      'and the free goods are a row of their own', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _item(app, 'Lux Soap', rupees: 100);
    await app.services.catalogue.addParty(
      app.services.actorNow(),
      const PartyDraft(name: 'Unilever Depot', partyType: 'supplier'),
    );
    await tester.pumpAndSettle();

    await tapText(tester, 'Kharidari');
    await tapText(tester, 'Nayi kharidari');
    await tapText(tester, 'Supplier chunein');
    await tapText(tester, 'Unilever Depot');
    await tapText(tester, 'Cheez shamil karein');
    await typeInto(tester, 'Talash karein', 'Lux');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tapText(tester, 'Lux Soap');
    await typeInto(tester, 'Tadaad (pcs)', '10');
    await typeInto(tester, 'Kharid qeemat', '1000');
    await typeInto(tester, 'Muft / bonus (pcs)', '1');
    await tester.tap(find.text('Cheez shamil karein').last);
    await tester.pumpAndSettle();
    expect(find.text('+ 1 pcs muft'), findsOneWidget);
    await tapText(tester, 'Kharidari save karein');
    await tester.pumpAndSettle();

    final rows = await app.rowsOf(
      'SELECT dl.is_free_item f, dl.base_qty_thousandths b, '
      'dl.line_total_paisa t FROM document_lines dl '
      'JOIN documents d ON d.id = dl.document_id '
      "WHERE d.doc_type = 'purchase_bill' ORDER BY dl.line_no",
    );
    expect(rows, [
      {'f': 0, 'b': 10000, 't': 100000},
      {'f': 1, 'b': 1000, 't': 0},
    ]);
    // A hundred at Rs 60 opening, then eleven for Rs 1,000: Rs 7,000 over
    // 111 pieces.
    expect(
      await app.scalar<int>('SELECT avg_cost_milli_paisa FROM items'),
      divideRounded(700000 * 1000, 111, RoundingMode.halfUp),
    );
  });

  testWidgets('at 200% on a small phone the bonus under a line, the bill '
      'slab and the scheme screen fit', (tester) async {
    final app = await Harness.startWithShop(tester);
    final soap = await _item(app, 'Lux Soap Beauty Bar Pink 150g', rupees: 100);
    await app.services.saveItemScheme(
      ItemScheme(
        itemId: soap,
        bonus: BonusRule(buy: Qty.units(10), free: Qty.units(1)),
        slabs: [QtySlab(from: Qty.units(12), rate: const Rate.rupees(95))],
      ),
    );
    await app.services.saveBillSlabs([
      BillSlab(from: const Money.rupees(1000), percentBp: 200),
    ]);
    _useASmallPhone(tester);
    await tester.pumpAndSettle();

    await openSettings(tester);
    await tapText(tester, 'Scheme aur slab');
    _expectNothingPaintsOffScreen(tester);
    await tapText(tester, 'Lux Soap Beauty Bar Pink 150g');
    expect(
      find.text('Har 10 pcs par 1 pcs Lux Soap Beauty Bar Pink 150g muft'),
      findsOneWidget,
    );
    _expectNothingPaintsOffScreen(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await _openCounter(tester);
    await _ring(tester, 'Lux');
    await _clearSearch(tester);
    await _setQty(tester, 'Tadaad (pcs)', '10');
    expect(find.byTooltip('Bonus hatayein'), findsOneWidget);
    _expectNothingPaintsOffScreen(tester);
    await tapButton(tester, 'Paisay lein');
    expect(find.text('Hatayein'), findsOneWidget);
    _expectNothingPaintsOffScreen(tester);
  });
}

Future<String> _unit(Harness app, String code) async =>
    (await app.services.queries.units(
      app.services.identity!.firmId,
    )).firstWhere((u) => u.code == code).id;

Future<String> _item(
  Harness app,
  String name, {
  int rupees = 100,
  int onHand = 100,
  List<ItemPack>? packs,
}) async => app.services.catalogue.addItem(
  app.services.actorNow(),
  ItemDraft(
    name: name,
    baseUnitId: await _unit(app, 'pcs'),
    saleRate: Rate.rupees(rupees),
    openingStock: Qty.units(onHand),
    openingRate: Rate.rupees(rupees * 6 ~/ 10),
    packs: packs,
  ),
);

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

