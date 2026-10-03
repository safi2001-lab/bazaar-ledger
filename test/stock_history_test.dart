import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// "There should be forty and there are thirty-one."
///
/// The query has eight tests of its own covering ordering, paging and the
/// running balance. This checks the part those cannot: that a shopkeeper
/// standing in front of an item can open the history and read what happened,
/// with the reason beside each correction.
///
/// A balance a shopkeeper cannot explain is a balance they do not trust, and a
/// shopkeeper who does not trust the number goes back to the paper register.
void main() {
  testWidgets('an item shows where its stock went', (tester) async {
    final app = await Harness.startWithShop(tester);
    final itemId = await _stock(app, name: 'Cooking Oil 5L', opening: 40);

    // Nine tins broke.
    await app.services.catalogue.adjustStock(
      app.services.actorNow(),
      StockAdjustmentDraft.counted(
        itemId: itemId,
        counted: Qty.units(31),
        reason: 'Nau tin toot gaye',
      ),
    );

    await tester.pumpAndSettle();
    await tapText(tester, 'Maal');
    await tapText(tester, 'Cooking Oil 5L');
    await tester.tap(find.byTooltip('Stock ki tafseel').first);
    await tester.pumpAndSettle();

    // The correction, with the reason a person typed — because no bill
    // explains it.
    expect(find.text('Durusti'), findsOneWidget);
    expect(
      find.text('Nau tin toot gaye'),
      findsOneWidget,
      reason:
          'the history shows a number changed and not why, which is a '
          'balance a shopkeeper cannot explain',
    );

    // And the opening balance underneath it.
    expect(find.text('Shuruaati stock'), findsOneWidget);
  });

  testWidgets('an item nothing has happened to says so', (tester) async {
    final app = await Harness.startWithShop(tester);
    // A service: no stock, so no movements at all.
    await app.services.catalogue.addItem(
      app.services.actorNow(),
      ItemDraft(
        name: 'Silai',
        baseUnitId: await _pcs(app),
        saleRate: Rate.rupees(150),
        tracksStock: false,
      ),
    );

    await tester.pumpAndSettle();
    await tapText(tester, 'Maal');
    await tapText(tester, 'Silai');
    await tester.pumpAndSettle();

    // An item that carries no stock has no history button, because it can
    // never have a history. Offering one that always says "nothing" is a
    // control that teaches a shopkeeper to ignore controls.
    expect(find.byTooltip('Stock ki tafseel'), findsNothing);
  });

  testWidgets('a sale appears in the history with its bill number', (
    tester,
  ) async {
    // The other half of the answer. A correction carries a reason; a sale
    // carries a document number a shopkeeper can look up in the sales list.
    final app = await Harness.startWithShop(tester);
    final itemId = await _stock(app, name: 'Cooking Oil 5L', opening: 40);

    await tester.pumpAndSettle();
    await tapText(tester, 'Naya Bill');
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Talash karein').first,
      'Cooking Oil',
    );
    // The counter's search is debounced at 250ms.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pumpAndSettle();

    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '2000');
    await tester.pumpAndSettle();
    await tapButton(tester, 'Save karein');
    await tester.pumpAndSettle();

    final movements = await app.services.queries.stockMovements(
      app.services.identity!.firmId,
      itemId,
    );
    expect(movements.first.txnType, 'sale');
    expect(
      movements.first.docNo,
      startsWith('INV-'),
      reason:
          'the movement does not name the bill that caused it, so there '
          'is no way back from a number to the sale',
    );
  });
}

Future<String> _pcs(Harness app) async {
  final units = await app.services.queries.units(app.services.identity!.firmId);
  return units.firstWhere((u) => u.code == 'pcs').id;
}

Future<String> _stock(
  Harness app, {
  required String name,
  required int opening,
}) async => app.services.catalogue.addItem(
  app.services.actorNow(),
  ItemDraft(
    name: name,
    baseUnitId: await _pcs(app),
    saleRate: Rate.rupees(1450),
    openingStock: Qty.units(opening),
    openingRate: Rate.rupees(1200),
  ),
);
