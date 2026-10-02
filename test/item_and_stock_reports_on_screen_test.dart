import 'dart:io';

import 'package:bazaar_ledger/features/items/item_history_screen.dart';
import 'package:bazaar_ledger/features/reports/report_shelf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// The item and stock reports (M34), from the screen: the stock summary
/// opened from the hub, narrowed to what is on the shelf, an item opened to
/// its stock history; what to order; and the stock detail for the month.
void main() {
  testWidgets('the stock summary lists the shelf, narrows to what is in '
      'stock, and an item opens its history', (tester) async {
    final app = await Harness.startWithShop(tester, overrides: _ownShelf());
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500, openingStock: 12);
    await app.seedItem(name: 'Cheeni', rupees: 160, openingStock: 0);

    await tapText(tester, 'Report');
    await tester.scrollUntilVisible(find.text('Stock ka khulasa'), 200);
    await tapText(tester, 'Stock ka khulasa');

    expect(find.text('Abhi tak'), findsOneWidget, reason: 'as of now');
    expect(find.text('Cooking Oil 5L'), findsOneWidget);
    expect(find.text('Cheeni'), findsOneWidget);
    expect(find.text('12'), findsWidgets);

    await tester.tap(find.widgetWithText(FilterChip, 'Sirf mojood maal'));
    await tester.pumpAndSettle();
    expect(find.text('Cheeni'), findsNothing);
    expect(find.text('Cooking Oil 5L'), findsOneWidget);

    await tester.tap(find.text('Cooking Oil 5L'));
    await tester.pumpAndSettle();
    expect(find.byType(ItemHistoryScreen), findsOneWidget);
    expect(find.text('Cooking Oil 5L'), findsOneWidget);
  });

  testWidgets('the low stock summary says what to order', (tester) async {
    final app = await Harness.startWithShop(tester, overrides: _ownShelf());
    final services = app.services;
    final firm = (await services.queries.currentFirm())!;
    final pcs = (await services.queries.units(
      firm.id,
    )).firstWhere((u) => u.code == 'pcs');
    await services.catalogue.addItem(
      services.actorNow(),
      ItemDraft(
        name: 'Cheeni 1kg',
        baseUnitId: pcs.id,
        saleRate: Rate.rupees(160),
        openingStock: Qty.units(3),
        openingRate: Rate.rupees(140),
        minStock: Qty.units(10),
      ),
    );
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500, openingStock: 40);

    await tapText(tester, 'Report');
    await tester.scrollUntilVisible(find.text('Kam stock'), 200);
    await tapText(tester, 'Kam stock');

    expect(find.text('Cheeni 1kg'), findsOneWidget);
    expect(find.text('Cooking Oil 5L'), findsNothing, reason: 'no floor set');
    expect(find.text('Order'), findsOneWidget);
    expect(
      find.text('7'),
      findsWidgets,
      reason: 'short by seven, and seven to order',
    );
  });

  testWidgets('the stock detail opens on the month with every item\'s '
      'opening and closing', (tester) async {
    final app = await Harness.startWithShop(tester, overrides: _ownShelf());
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500, openingStock: 12);

    await tapText(tester, 'Report');
    await tester.scrollUntilVisible(find.text('Stock ki tafseel'), 200);
    await tapText(tester, 'Stock ki tafseel');

    expect(find.text('Is mahina'), findsOneWidget);
    expect(find.text('Cooking Oil 5L'), findsOneWidget);
    expect(
      find.text('Closing value'),
      findsNWidgets(2),
      reason: 'the tile over the table, and the column',
    );
    expect(
      find.text('12'),
      findsWidgets,
      reason: 'opened and closed on twelve',
    );
    expect(find.text('Total'), findsOneWidget);
  });
}

List<Override> _ownShelf() {
  final dir = Directory.systemTemp.createTempSync('report_shelf');
  return [reportShelfDirectoryProvider.overrideWith((ref) async => dir)];
}
