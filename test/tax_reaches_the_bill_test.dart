import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// The tax pack, from the screen.
void main() {
  testWidgets('a shop registered from the tax screen charges 18% on the bill', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Ghee 1kg', rupees: 1000);

    await openSettings(tester);
    await tapText(tester, 'Tax');
    await tapText(tester, 'Dukaan sales tax mein registered hai');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    await _ringUpGhee(tester);
    expect(find.text('Rs 1,180.00'), findsWidgets);
    await typeInto(tester, 'Diye gaye', '1180');
    await tapButton(tester, 'Save karein');

    final bill = await app.rowsOf(
      'SELECT tax_paisa, total_paisa, tax_rule_version FROM documents '
      "WHERE doc_type = 'sale_invoice'",
    );
    expect(bill.single['tax_paisa'], 18000);
    expect(bill.single['total_paisa'], 118000);
    expect(bill.single['tax_rule_version'], 'pk-2026-27-v1');
  });

  testWidgets('an unregistered shop charges no tax at all', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Ghee 1kg', rupees: 1000);

    await _ringUpGhee(tester);
    expect(find.text('Rs 1,000.00'), findsWidgets);
    expect(find.text('Rs 1,180.00'), findsNothing);
  });

  testWidgets('further tax is added for a named unregistered business', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.services.updateFirm({'is_sales_tax_registered': 1});
    await app.seedItem(name: 'Ghee 1kg', rupees: 1000);
    await app.seedParty(name: 'Bilal Store');

    await _ringUpGhee(tester);
    await tapText(tester, 'Aam gahak');
    await tapText(tester, 'Bilal Store');

    expect(find.text('Rs 1,220.00'), findsWidgets);
  });

  testWidgets('Tajir Dost is one per cent of the month, less the bijli tax', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Ghee 1kg', rupees: 1000);
    await _ringUpGhee(tester);
    await typeInto(tester, 'Diye gaye', '1000');
    await tapButton(tester, 'Save karein');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await openSettings(tester);
    await tapText(tester, 'Tax');
    expect(find.text('Rs 10.00'), findsWidgets);
    await typeInto(tester, 'Bijli ke bill par kata hua tax', '4');
    expect(find.text('Rs 6.00'), findsOneWidget);
  });
}

Future<void> _ringUpGhee(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Naya Bill');
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    'Ghee',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
  await tapButton(tester, 'Paisay lein');
}
