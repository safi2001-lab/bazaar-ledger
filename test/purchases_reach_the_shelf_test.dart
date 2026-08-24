import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Entering a delivery, from the app.
///
/// `items.avg_cost_milli_paisa` was written once when an item was created and
/// never moved again, because nothing in `lib/` could move it. A costing
/// engine with no screen is the same failure as a printer with no button, and
/// this repository has already shipped that twice.
void main() {
  testWidgets('the shopkeeper can reach it from the home screen', (
    tester,
  ) async {
    await Harness.startWithShop(tester);
    await tester.pumpAndSettle();

    expect(find.text('Kharidari'), findsOneWidget);
  });

  testWidgets('a delivery entered on the screen moves the average', (
    tester,
  ) async {
    // The whole milestone, driven through the actual screens.
    final app = await Harness.startWithShop(tester);
    await _supplier(app);
    final riceId = await _item(app, purchaseRate: Rate.rupees(90));

    // Nothing, not the purchase rate. `DriftCatalogueWriter` only seeds an
    // average when the item is opened WITH stock, so a catalogue entry the
    // shop has never received starts at zero cost — and every margin on it
    // reads as pure profit until a delivery lands.
    expect(await _averageOf(app, riceId), const Rate.raw(0));

    await _openPurchase(tester);
    await _pickSupplier(tester);
    await _addLine(tester, qty: '10', cost: '1200');
    await tapText(tester, 'Kharidari save karein');
    await tester.pumpAndSettle();

    expect(
      await _averageOf(app, riceId),
      const Rate.rupees(120),
      reason:
          'the average is still what the item was opened at, so every margin '
          'this shop reads is a guess',
    );

    final documents = await app.rowsOf(
      "SELECT doc_type, total_paisa FROM documents WHERE doc_type = 'purchase_bill'",
    );
    expect(documents, hasLength(1));
    expect(documents.single['total_paisa'], 120000);
  });

  testWidgets('freight typed on the screen lands in the cost', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _supplier(app);
    final riceId = await _item(app, purchaseRate: Rate.rupees(100));

    await _openPurchase(tester);
    await _pickSupplier(tester);
    await _addLine(tester, qty: '10', cost: '1000');
    await typeInto(tester, 'Kiraya aur mazdoori', '200');
    await tester.pumpAndSettle();
    await tapText(tester, 'Kharidari save karein');
    await tester.pumpAndSettle();

    expect(
      await _averageOf(app, riceId),
      const Rate.rupees(120),
      reason: 'the rickshaw was free, apparently',
    );
  });

  testWidgets('a delivery with no supplier is refused in words', (
    tester,
  ) async {
    // A purchase with no party is stock that appeared from nowhere, and the
    // shop can neither pay nor query it.
    final app = await Harness.startWithShop(tester);
    await _supplier(app);
    await _item(app, purchaseRate: Rate.rupees(90));

    await _openPurchase(tester);
    await _addLine(tester, qty: '10', cost: '1200');
    await tapText(tester, 'Kharidari save karein');
    await tester.pumpAndSettle();

    expect(find.text('Supplier chunna zaroori hai'), findsOneWidget);
    expect(await app.rowsOf('SELECT id FROM documents'), isEmpty);
  });

  testWidgets('a delivery with nothing on it is refused in words', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _supplier(app);

    await _openPurchase(tester);
    await _pickSupplier(tester);
    await tapText(tester, 'Kharidari save karein');
    await tester.pumpAndSettle();

    expect(find.text('Abhi koi cheez nahi'), findsWidgets);
    expect(await app.rowsOf('SELECT id FROM documents'), isEmpty);
  });

  testWidgets('paying more than the bill is refused in words', (tester) async {
    // Money handed over beyond a bill is an advance to the supplier, not part
    // of what this delivery cost.
    final app = await Harness.startWithShop(tester);
    await _supplier(app);
    await _item(app, purchaseRate: Rate.rupees(90));

    await _openPurchase(tester);
    await _pickSupplier(tester);
    await _addLine(tester, qty: '10', cost: '1200');
    await typeInto(tester, 'Abhi diye', '5000');
    await tester.pumpAndSettle();
    await tapText(tester, 'Kharidari save karein');
    await tester.pumpAndSettle();

    expect(find.text('Bill se ziyada nahi de sakte'), findsOneWidget);
    expect(await app.rowsOf('SELECT id FROM documents'), isEmpty);
  });

  testWidgets('what is still owed reaches the supplier khata', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _supplier(app);
    await _item(app, purchaseRate: Rate.rupees(90));

    await _openPurchase(tester);
    await _pickSupplier(tester);
    await _addLine(tester, qty: '10', cost: '1200');
    await typeInto(tester, 'Abhi diye', '400');
    await tester.pumpAndSettle();
    await tapText(tester, 'Kharidari save karein');
    await tester.pumpAndSettle();

    final owed = await app.rowsOf(
      'SELECT COALESCE(SUM(jl.credit_paisa - jl.debit_paisa), 0) AS owed '
      'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      "WHERE a.system_key = 'accounts_payable'",
    );
    expect(owed.single['owed'], 80000);
  });
}

Future<void> _openPurchase(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Kharidari');
  await tester.pumpAndSettle();
}

Future<void> _pickSupplier(WidgetTester tester) async {
  await tapText(tester, 'Supplier chunein');
  await tester.pumpAndSettle();
  await tapText(tester, 'Punjab Rice Mills');
  await tester.pumpAndSettle();
}

Future<void> _addLine(
  WidgetTester tester, {
  required String qty,
  required String cost,
}) async {
  // The screen's own button, which is the first one with this label.
  await tapText(tester, 'Cheez shamil karein');
  await tester.pumpAndSettle();

  await typeInto(tester, 'Talash karein', 'Chawal');
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tapText(tester, 'Chawal Basmati');
  await tester.pumpAndSettle();

  // By label, not by index. The purchase screen underneath the sheet has
  // three fields of its own, so `find.byType(TextFormField).at(0)` types the
  // quantity into the supplier's bill number — which is what the first
  // version of this did, and why nothing was ever saved.
  await typeInto(tester, 'Tadaad (pcs)', qty);
  await typeInto(tester, 'Kharid qeemat', cost);

  // The sheet's button, which is the LAST one with this label: the screen's
  // own is still mounted underneath.
  await tester.tap(find.text('Cheez shamil karein').last);
  await tester.pumpAndSettle();
}

Future<String> _supplier(Harness app) => app.services.catalogue.addParty(
  app.services.actorNow(),
  const PartyDraft(name: 'Punjab Rice Mills', partyType: 'supplier'),
);

Future<String> _item(Harness app, {required Rate purchaseRate}) async {
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');

  return app.services.catalogue.addItem(
    app.services.actorNow(),
    ItemDraft(
      name: 'Chawal Basmati',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(150),
      purchaseRate: purchaseRate,
      openingRate: purchaseRate,
    ),
  );
}

Future<Rate> _averageOf(Harness app, String itemId) async => Rate.raw(
  (await app.rowsOf(
        "SELECT avg_cost_milli_paisa AS a FROM items WHERE id = '$itemId'",
      )).single['a']!
      as int,
);
