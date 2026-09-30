import 'package:bazaar_ledger/design/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Making masala packs from bulk spice, from the Items screen.
void main() {
  Future<void> choose(WidgetTester tester, Key key, String item) async {
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(item).last);
    await tester.pumpAndSettle();
  }

  testWidgets('ten packs of masala are made from bulk spice', (tester) async {
    final app = await Harness.startWithShop(tester);
    final firm = app.services.identity!.firmId;
    final units = await app.services.queries.units(firm);
    final kg = units.firstWhere((u) => u.code == 'kg');
    await app.services.catalogue.addItem(
      app.services.actorNow(),
      ItemDraft(
        name: 'Red chilli',
        baseUnitId: kg.id,
        saleRate: Rate.rupees(1200),
        openingStock: Qty.units(5),
        openingRate: Rate.rupees(800),
      ),
    );
    await app.seedItem(name: 'Mirch masala 100g', rupees: 150, openingStock: 0);

    await tester.tap(find.text('Maal').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Banana (recipe)'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Abhi koi recipe nahin. Jo cheez aap khud banate hain, us ki recipe '
        'likhein.',
      ),
      findsOneWidget,
    );

    await tapText(tester, 'Nayi recipe');
    await typeInto(tester, 'Recipe ka naam', 'Mirch masala');
    await choose(tester, const ValueKey('output'), 'Mirch masala 100g');
    await typeInto(tester, 'Ek batch mein kitna', '10');
    await typeInto(tester, 'Mazdoori aur packing (Rs)', '50');
    await choose(tester, const ValueKey('component-0'), 'Red chilli');
    await typeInto(tester, 'Ek batch mein', '1');
    await tapButton(tester, 'Save karein');

    expect(find.text('Ek batch: 10 pcs Mirch masala 100g'), findsOneWidget);
    await tapButton(tester, 'Banayein');
    await typeInto(tester, 'Kitne batch', '2');
    // The sheet's own button, above the card's.
    await tester.tap(
      find
          .ancestor(
            of: find.text('Banayein').last,
            matching: find.byType(BlButton),
          )
          .first,
    );
    await tester.pumpAndSettle();

    final made = await app.scalar<int>(
      'SELECT SUM(qty_delta_thousandths) FROM stock_ledger s '
      "JOIN items i ON i.id = s.item_id WHERE i.name = 'Mirch masala 100g'",
    );
    expect(made, 20000);
    final left = await app.scalar<int>(
      'SELECT SUM(qty_delta_thousandths) FROM stock_ledger s '
      "JOIN items i ON i.id = s.item_id WHERE i.name = 'Red chilli'",
    );
    expect(left, 3000);
    final health = await app.services.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  });
}
