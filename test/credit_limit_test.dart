import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// The credit limit, which until now blocked nothing.
///
/// It was set in the party editor, shown as a chip on two screens, and
/// enforced nowhere: a shop could put a customer on Rs 50,000 and watch them
/// reach Rs 200,000 without the app mentioning it once. A limit that does not
/// stop anything is decoration, and decoration that looks like a control is
/// worse than none — the shopkeeper believes they set something.
///
/// It stops the sale at the tender sheet, which is the moment before the
/// goods leave, and it can be overridden by name. It is their shop.
void main() {
  testWidgets('a sale that would cross the limit is stopped', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _customer(app, limit: const Money.rupees(5000));
    await _stock(app);

    await _sellOnUdhaar(tester, rupees: 8000);

    expect(find.text('Udhaar ki hadd se ziyada'), findsOneWidget);
    expect(
      await app.rowsOf('SELECT id FROM documents'),
      isEmpty,
      reason: 'the bill was posted anyway, past a limit the shop set',
    );
  });

  testWidgets('it names the limit and where the bill would land', (
    tester,
  ) async {
    // A warning that says only "over the limit" makes the shopkeeper go and
    // look both numbers up with a customer standing there.
    final app = await Harness.startWithShop(tester);
    await _customer(app, limit: const Money.rupees(5000));
    await _stock(app);

    await _sellOnUdhaar(tester, rupees: 8000);

    expect(find.textContaining('5,000.00'), findsWidgets);
    expect(find.textContaining('8,000.00'), findsWidgets);
  });

  testWidgets('the shopkeeper can go past it, deliberately', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _customer(app, limit: const Money.rupees(5000));
    await _stock(app);

    await _sellOnUdhaar(tester, rupees: 8000);
    await tapText(tester, 'Phir bhi udhaar dein');
    await tester.pumpAndSettle();
    await tapText(tester, 'Save karein');
    await tester.pumpAndSettle();

    final documents = await app.rowsOf('SELECT balance_paisa FROM documents');
    expect(
      documents,
      hasLength(1),
      reason: 'the override did nothing, so the limit is a wall not a warning',
    );
    expect(documents.single['balance_paisa'], 800000);
  });

  testWidgets('a sale inside the limit is never interrupted', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _customer(app, limit: const Money.rupees(50000));
    await _stock(app);

    await _sellOnUdhaar(tester, rupees: 8000);

    expect(find.text('Udhaar ki hadd se ziyada'), findsNothing);
    expect(await app.rowsOf('SELECT id FROM documents'), hasLength(1));
  });

  testWidgets('a customer with no limit is never interrupted', (tester) async {
    // Most shops set none. The check must be free for them.
    final app = await Harness.startWithShop(tester);
    await _customer(app, limit: null);
    await _stock(app);

    await _sellOnUdhaar(tester, rupees: 80000);

    expect(find.text('Udhaar ki hadd se ziyada'), findsNothing);
    expect(await app.rowsOf('SELECT id FROM documents'), hasLength(1));
  });

  testWidgets('a cash sale is never checked against a credit limit', (
    tester,
  ) async {
    // Nothing is owed, so there is nothing to be over.
    final app = await Harness.startWithShop(tester);
    await _customer(app, limit: const Money.rupees(1));
    await _stock(app);

    await tester.pumpAndSettle();
    await tapText(tester, 'Naya Bill');
    await tester.pumpAndSettle();
    await _addToCart(tester);
    await tapButton(tester, 'Paisay lein');
    await tester.pumpAndSettle();
    await typeInto(tester, 'Diye gaye', '10000');
    await tester.pumpAndSettle();
    await tapButton(tester, 'Save karein');
    await tester.pumpAndSettle();

    expect(find.text('Udhaar ki hadd se ziyada'), findsNothing);
    expect(await app.rowsOf('SELECT id FROM documents'), hasLength(1));
  });

  testWidgets('what the shop is holding comes off what is owed', (
    tester,
  ) async {
    // A customer who paid Rs 5,000 against Rs 3,000 of bills used to read as
    // settled, with the Rs 2,000 the shop owes them invisible in the one
    // place anybody would look. The limit was checked against that figure
    // too, so it was wrong in the same direction.
    final app = await Harness.startWithShop(tester);
    final partyId = await _customer(app, limit: null);
    await _stock(app);
    await _sellOnUdhaar(tester, rupees: 3000);

    await app.services.recordReceipt(
      app.services.actorNow(),
      ReceiptDraft(
        partyId: partyId,
        amount: const Money.rupees(5000),
        mode: 'cash',
        paymentAccountId: (await app.services.queries.paymentAccounts(
          app.services.identity!.firmId,
        )).firstWhere((a) => a.isDefault).id,
      ),
    );

    final party = await app.services.queries.partyById(
      app.services.identity!.firmId,
      partyId,
    );

    expect(
      party!.balance,
      const Money.rupees(-2000),
      reason: 'the advance the shop is holding is not in the balance',
    );
  });
}

Future<String> _customer(Harness app, {required Money? limit}) =>
    app.services.catalogue.addParty(
      app.services.actorNow(),
      PartyDraft(
        name: 'Rashid Traders',
        partyType: 'customer',
        creditLimit: limit,
      ),
    );

Future<void> _stock(Harness app) async {
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');

  await app.services.catalogue.addItem(
    app.services.actorNow(),
    ItemDraft(
      name: 'Cooking Oil 5L',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(1000),
      openingStock: Qty.units(500),
    ),
  );
}

/// Rings up [rupees] on udhaar and taps Save, stopping wherever it stops.
Future<void> _sellOnUdhaar(WidgetTester tester, {required int rupees}) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Naya Bill');
  await tester.pumpAndSettle();
  for (var i = 0; i < rupees ~/ 1000; i++) {
    await _addToCart(tester);
  }

  await tapButton(tester, 'Paisay lein');
  await tester.pumpAndSettle();

  // The customer row shows the walk-in label until somebody is picked.
  await tapText(tester, 'Aam gahak');
  await tester.pumpAndSettle();
  await tapText(tester, 'Rashid Traders');
  await tester.pumpAndSettle();

  await tester.tap(find.byType(SwitchListTile).first);
  await tester.pumpAndSettle();

  await tapButton(tester, 'Save karein');
  await tester.pumpAndSettle();
}

Future<void> _addToCart(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    'Cooking',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
}
