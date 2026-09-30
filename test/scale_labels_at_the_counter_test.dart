import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// A weighing scale's label, from the counter.
String _label(String prefix, String plu, String value) {
  final body = '$prefix$plu$value';
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    final d = body.codeUnitAt(i) - 48;
    sum += i.isEven ? d : d * 3;
  }
  return '$body${(10 - sum % 10) % 10}';
}

Future<void> _scan(WidgetTester tester, String code) async {
  final field = find.widgetWithText(TextFormField, 'Talash karein').first;
  await tester.enterText(field, code);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

Future<void> _mutton(Harness app) async {
  final firm = app.services.identity!.firmId;
  final kg = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'kg');
  await app.services.catalogue.addItem(
    app.services.actorNow(),
    ItemDraft(
      name: 'Mutton',
      code: '42',
      baseUnitId: kg.id,
      saleRate: Rate.rupees(1200),
      openingStock: Qty.units(20),
    ),
  );
}

Future<int?> _sold(Harness app) => app.scalar<int>(
  "SELECT total_paisa FROM documents WHERE doc_type = 'sale_invoice'",
);

Future<void> _payCash(WidgetTester tester, String amount) async {
  await tapButton(tester, 'Paisay lein');
  await typeInto(tester, 'Diye gaye', amount);
  await tapButton(tester, 'Save karein');
}

void main() {
  testWidgets("a butcher's weight label rings up 1.500 kg", (tester) async {
    final app = await Harness.startWithShop(tester);
    await _mutton(app);
    await tapText(tester, 'Naya Bill');

    await _scan(tester, _label('21', '00042', '01500'));
    expect(find.text('Mutton'), findsOneWidget);
    await _payCash(tester, '1800');

    expect(await _sold(app), 180000, reason: '1.5 kg at Rs 1,200');
    final qty = await app.scalar<int>(
      'SELECT qty_thousandths FROM document_lines',
    );
    expect(qty, 1500);
  });

  testWidgets('a price label rings up what that price buys', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _mutton(app);
    await tapText(tester, 'Naya Bill');

    await _scan(tester, _label('23', '00042', '00600'));
    await _payCash(tester, '600');

    expect(await _sold(app), 60000);
    expect(
      await app.scalar<int>('SELECT qty_thousandths FROM document_lines'),
      500,
      reason: 'Rs 600 of Rs 1,200-a-kilo mutton is half a kilo',
    );
  });

  testWidgets('a label for a PLU the shop has not coded is said', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _mutton(app);
    await tapText(tester, 'Naya Bill');

    await _scan(tester, _label('21', '00077', '01500'));
    expect(
      find.text('Scale label par PLU 77 kisi maal ka code nahin'),
      findsOneWidget,
    );
  });

  testWidgets('the shop sets its scale labels up from Settings', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await openSettings(tester);
    await tapText(tester, 'Tarazu ke labels');
    await typeInto(tester, 'Wazan wale prefix (maslan 21, 22)', '20');
    await typeInto(tester, 'Qeemat wale prefix (maslan 23, 24)', '25, 26');
    await tapText(tester, '6');
    await tapButton(tester, 'Save karein');
    expect(find.text('Tarazu ke labels save ho gaye'), findsOneWidget);

    final format = await app.services.scaleFormat();
    expect(format.weightPrefixes, {'20'});
    expect(format.pricePrefixes, {'25', '26'});
    expect(format.pluDigits, 6);
  });
}
