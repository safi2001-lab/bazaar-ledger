import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// What the shelves are worth, above the list of what is on them.
///
/// The query has eleven tests of its own, including the arithmetic ones. These
/// check the two things that matter on screen: that the valuation a shopkeeper
/// reads is the one at cost, and that a shop with nothing wrong shows no
/// alarming chips.
void main() {
  testWidgets('the item list shows what the stock is worth, at cost', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    // Twenty tins bought at Rs 300, priced at Rs 600.
    await _stock(app, name: 'Cooking Oil 5L', units: 20, cost: 300);

    await tester.pumpAndSettle();
    await tapText(tester, 'Maal');
    await tester.pumpAndSettle();

    expect(find.text('Stock ki qeemat'), findsOneWidget);
    expect(
      find.text('6,000.00'),
      findsWidgets,
      reason:
          'the shelf is shown at what it would sell for, which counts '
          'profit the shop has not made',
    );
    expect(find.text('12,000.00'), findsNothing);
  });

  testWidgets('a shop with nothing wrong shows no warnings', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _stock(app, name: 'Cooking Oil 5L', units: 20, cost: 300);

    await tester.pumpAndSettle();
    await tapText(tester, 'Maal');
    await tester.pumpAndSettle();

    // Chips that are always present are chips nobody reads.
    expect(find.textContaining('kam'), findsNothing);
    expect(find.textContaining('khatam'), findsNothing);
  });

  testWidgets('what is low and what is gone are counted apart', (tester) async {
    // Two different problems with two different answers: "order more" and
    // "you have none".
    final app = await Harness.startWithShop(tester);
    await _stock(app, name: 'Low', units: 3, cost: 100, floor: 5);
    final gone = await _stock(app, name: 'Gone', units: 10, cost: 100);
    await app.services.catalogue.adjustStock(
      app.services.actorNow(),
      StockAdjustmentDraft.counted(
        itemId: gone,
        counted: Qty.zero,
        reason: 'Sab bik gaya',
      ),
    );

    await tester.pumpAndSettle();
    await tapText(tester, 'Maal');
    await tester.pumpAndSettle();

    expect(find.text('1 kam'), findsOneWidget);
    expect(find.text('1 khatam'), findsOneWidget);
  });

  testWidgets('a brand new shop is not shown an empty valuation', (
    tester,
  ) async {
    // A zero above an empty list is a number nobody needs to read, and it
    // makes the first screen a shopkeeper sees look like a spreadsheet.
    await Harness.startWithShop(tester);

    await tester.pumpAndSettle();
    await tapText(tester, 'Maal');
    await tester.pumpAndSettle();

    expect(find.text('Stock ki qeemat'), findsNothing);
  });
}

Future<String> _stock(
  Harness app, {
  required String name,
  required int units,
  required int cost,
  int floor = 0,
}) async {
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');

  return app.services.catalogue.addItem(
    app.services.actorNow(),
    ItemDraft(
      name: name,
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(cost * 2),
      openingStock: Qty.units(units),
      openingRate: Rate.rupees(cost),
      minStock: Qty.units(floor),
    ),
  );
}
