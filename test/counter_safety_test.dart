import 'package:bazaar_ledger/design/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// The ways a counter can go wrong that cost real money.
///
/// Each of these was found by an adversarial audit rather than by use, which
/// is the point: a cashier who accidentally rings a bill twice does not report
/// a bug, they report that the app is wrong about the day's takings, six weeks
/// later, with no idea which bill.
void main() {
  testWidgets('tapping charge twice in one frame writes one invoice',
      (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);

    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    await _addToCart(tester, 'Cooking Oil');

    await tapButton(tester, 'Paisay lein');

    // Two taps at the same point with no frame between them. Tapped by
    // coordinate rather than by finder, because after the first tap the sheet
    // is gone and re-resolving the finder would fail rather than reproduce
    // what a fast cashier's thumb actually does. The button's own disabled
    // state only takes effect on the next build, so the guard has to be the
    // first statement in the handler and not something set after an await.
    final save = find
        .ancestor(
          of: find.textContaining('Save karein'),
          matching: find.byType(BlButton),
        )
        .first;
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    final spot = tester.getCenter(save);
    await tester.tapAt(spot);
    await tester.tapAt(spot);
    await tester.pumpAndSettle();

    expect(
      await app.countIn('documents'),
      1,
      reason: 'one cart is one invoice, however fast the cashier taps',
    );
    expect(await app.countIn('payments'), 1);
    expect(await app.countIn('journal_entries'), 1);
  });

  testWidgets('a committed sale always empties the cart', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);

    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    await _addToCart(tester, 'Cooking Oil');
    await tapButton(tester, 'Paisay lein');
    await tapButton(tester, 'Save karein');

    expect(await app.countIn('documents'), 1);

    // Saving lands on the receipt, with the counter closed behind it.
    expect(find.textContaining('INV-2627-0001'), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Back at the counter, and it is empty. The cart used to be cleared
    // through `ref` after the await, so a sheet dismissed mid-write left a
    // committed sale with the goods still on the screen — and the shopkeeper
    // rang the same bill again.
    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    expect(find.text('Bill abhi khali hai'), findsOneWidget);
    expect(find.text('Cooking Oil 5L'), findsNothing);
  });

  testWidgets('part-paid cash is recorded as part-paid', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 5000);

    // A customer who owes anything has to be named, so give the shop one.
    final firm = await app.services.queries.currentFirm();
    await app.services.catalogue.addParty(
      app.services.actorNow(),
      const PartyDraft(name: 'Bilal General Store', phone: '03001234567'),
    );
    expect(firm, isNotNull);

    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    await _addToCart(tester, 'Cooking Oil');
    await tapButton(tester, 'Paisay lein');

    // Pick the customer.
    await tester.tap(find.text('Aam gahak'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bilal General Store').first);
    await tester.pumpAndSettle();

    // Rs 3,000 against a Rs 5,000 bill. The screen says 2,000 remaining; the
    // books used to say the bill was settled in full.
    await typeInto(tester, 'Diye gaye', '3000');
    expect(find.text('2,000.00'), findsOneWidget, reason: 'shown as remaining');

    await tapButton(tester, 'Save karein');

    final doc = await app.rowsOf(
      'SELECT total_paisa, paid_paisa, balance_paisa FROM documents',
    );
    expect(doc, hasLength(1));
    expect(doc.single['total_paisa'], 500000);
    expect(
      doc.single['paid_paisa'],
      300000,
      reason: 'what the customer actually handed over',
    );
    expect(
      doc.single['balance_paisa'],
      200000,
      reason: 'and the rest is on their khata',
    );

    final payment = await app.rowsOf(
      'SELECT amount_paisa, change_paisa FROM payments',
    );
    expect(payment.single['amount_paisa'], 300000);
    expect(payment.single['change_paisa'], 0);

    // The books still balance, at exact integer equality.
    final balance = await app.rowsOf(
      'SELECT SUM(debit_paisa) d, SUM(credit_paisa) c FROM journal_lines',
    );
    expect(balance.single['d'], balance.single['c']);
  });

  testWidgets('a bill left owing has to name the customer', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 5000);

    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    await _addToCart(tester, 'Cooking Oil');
    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '3000');
    await tapButton(tester, 'Save karein');

    expect(
      find.text('Udhaar ke liye gahak chunna zaroori hai'),
      findsWidgets,
      reason: 'there is no such thing as an anonymous debtor',
    );
    expect(await app.countIn('documents'), 0);
  });

  testWidgets('an archived item cannot be scanned back onto a bill',
      (tester) async {
    final app = await Harness.startWithShop(tester);
    final itemId = await app.seedItem(
      name: 'Cooking Oil 5L',
      rupees: 2500,
      barcode: '8964000112233',
    );

    await app.services.catalogue
        .archiveItem(app.services.actorNow(), itemId);

    final scanned = await app.services.queries.itemByBarcode(
      (await app.services.queries.currentFirm())!.id,
      '8964000112233',
    );
    expect(
      scanned,
      isNull,
      reason: 'an item hidden from search must be hidden from the scanner too',
    );
  });

  testWidgets('editing an archived item does not put it back on the counter',
      (tester) async {
    final app = await Harness.startWithShop(tester);
    final firm = (await app.services.queries.currentFirm())!;
    final itemId = await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    final units = await app.services.queries.units(firm.id);

    await app.services.catalogue
        .archiveItem(app.services.actorNow(), itemId);

    // A price correction on an archived item is a legitimate thing to do; it
    // must not silently restock the shelf.
    await app.services.catalogue.updateItem(
      app.services.actorNow(),
      itemId,
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: units.first.id,
        saleRate: Rate.rupees(2600),
      ),
    );

    final active = await app.scalar<int>(
      'SELECT is_active FROM items LIMIT 1',
    );
    expect(active, 0);
    expect(
      await app.services.queries.searchItems(firm.id, query: 'Cooking'),
      isEmpty,
    );
  });

  testWidgets('a customer with only an opening balance cannot be hidden',
      (tester) async {
    final app = await Harness.startWithShop(tester);
    final partyId = await app.services.catalogue.addParty(
      app.services.actorNow(),
      PartyDraft(
        name: 'Bilal General Store',
        openingBalance: Money.rupees(5000),
      ),
    );

    // The archive guard used to sum only the documents, so a customer
    // carrying pre-app udhaar was told they "owe 0" and hidden along with
    // their balance.
    await expectLater(
      app.services.catalogue
          .archiveParty(app.services.actorNow(), partyId),
      throwsA(isA<StateError>()),
    );
  });
}

Future<void> _addToCart(WidgetTester tester, String query) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    query,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
}
