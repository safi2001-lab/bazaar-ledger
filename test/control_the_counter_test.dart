import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/design/components.dart';
import 'package:bazaar_ledger/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// Control the way a wholesaler runs it (M68), driven by taps against a
/// real database: credit rules at the payment sheet and on the customer,
/// the owner's control settings, the random stock check, and a salesman's
/// bill paid at the cashier's counter.
void main() {
  // Measured in a real font, as the other small-phone checks are.
  setUpAll(loadRealFont);

  testWidgets('a credit rule set to block stops udhaar at the payment sheet, '
      'says which rule, and the owner lets one bill through with a reason', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 1000);
    await _rashid(app, limit: const Money.rupees(5000));
    await app.services.credit.setDefaults(
      const CreditDefaults(limitMode: CreditMode.block),
    );

    await _ringOnUdhaar(tester, tins: 6);

    expect(find.text('Is gahak ka udhaar band hai'), findsOneWidget);
    expect(find.text('Udhaar ki hadd se ziyada'), findsOneWidget);
    expect(find.textContaining('6,000.00'), findsWidgets);
    expect(await _sales(app), 0);

    // Not pumpAndSettle while the prompt is up: the sheet underneath shows
    // a spinner, which never settles.
    final allow = find.ancestor(
      of: find.text('Malik ki ijazat (PIN)'),
      matching: find.byType(BlButton),
    );
    await tester.ensureVisible(allow);
    await tester.pumpAndSettle();
    await tester.tap(allow);
    await _frames(tester);
    expect(find.text('Malik ki ijazat'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Wajah (zaroori)').last,
      'Purana gahak',
    );
    await tester.pump();
    await tester.tap(
      find
          .ancestor(
            of: find.text('Ijazat dein'),
            matching: find.byType(BlButton),
          )
          .last,
    );
    await _frames(tester);
    await tester.pumpAndSettle();

    expect(await _sales(app), 1);
    final log = await app.rowsOf(
      'SELECT summary FROM audit_log '
      "WHERE action_code = 'CREDIT_RULE_OVERRIDDEN'",
    );
    expect(log.single['summary'], contains('Purana gahak'));
    expect(log.single['summary'], contains('Malik Sahib'));
  });

  testWidgets('a customer\'s own credit rules are set from their editor, and '
      'the counter holds the next bill to them', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 1000);
    final rashid = await _rashid(app, limit: null);

    await tapText(tester, 'Gahak');
    await tapText(tester, 'Rashid Traders');
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await tapText(tester, 'Udhaar ke qaide');
    expect(find.text('Kisi bill par kuch baqi nahi'), findsOneWidget);

    // The most bills: their own, one, and a block.
    await tapText(tester, 'Apna');
    await typeInto(tester, 'Udhaar par ziyada se ziyada bill', '1');
    await tester.ensureVisible(find.text('Rok').at(1));
    await tester.tap(find.text('Rok').at(1));
    await tester.pumpAndSettle();
    // A temporary limit, for the week.
    await typeInto(tester, 'Waqti hadd, Rs', '50000');
    await tapButton(tester, 'Save karein');

    final own = await app.services.credit.rulesOf(rashid);
    expect(own.maxOpenBills, 1);
    expect(own.billsMode, CreditMode.block);
    expect(own.tempLimit, const Money.rupees(50000));
    final today = BusinessDate.now(app.services.clock);
    expect(own.tempUntil, today.addDays(7));
    expect(
      find.textContaining('Rs 50,000.00 ${shortDate(today.addDays(7).value)}'),
      findsOneWidget,
      reason: 'the editor says the temporary limit and its day',
    );

    // One bill on udhaar already: the next is held at the counter.
    await _sellOnUdhaar(app, rashid);
    for (var i = 0; i < 3; i++) {
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await _ringOnUdhaar(tester, tins: 1);
    expect(find.text('Is gahak ka udhaar band hai'), findsOneWidget);
    expect(find.text('Is samait 2 bill udhaar par; hadd 1'), findsOneWidget);
    expect(await _sales(app), 1);
  });

  testWidgets('the owner sets the shop\'s credit rules, days that close by '
      'themselves, the random check and cashier mode in Settings', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final services = app.services;
    await services.setPin(services.currentUser!.id, '1947');
    final ali = await services.addStaff(
      name: 'Ali',
      role: Role.cashier,
      pin: '1111',
    );

    await openSettings(tester);
    await tapText(tester, 'Udhaar, din band aur counter ke qaide');

    await typeInto(tester, 'Udhaar par ziyada se ziyada bill', '3');
    await _tapNth(tester, 'Save karein', 0);
    expect((await services.credit.defaults()).maxOpenBills, 3);

    await tapText(tester, 'Khule dinon se purane din');
    await typeInto(tester, 'Kitne din khule rahein', '2');
    await _tapNth(tester, 'Save karein', 1);
    expect(
      await services.autoLock.rule(),
      const AutoLock(mode: AutoLockMode.olderThan, days: 2),
    );
    final through = BusinessDate.now(services.clock).addDays(-3);
    expect(find.text('${shortDate(through.value)} tak band'), findsOneWidget);

    await typeInto(tester, 'Har ginti mein cheezein', '4');
    await tapText(tester, 'Roz khud ginti chunein');
    await _tapNth(tester, 'Save karein', 2);
    expect(
      await services.stockChecks.rule(),
      const StockCheckRule(size: 4, daily: true),
    );

    await tapText(tester, 'Counter cashier mode mein chalayein');
    await tapText(tester, 'Ali');
    await _tapNth(tester, 'Save karein', 3);
    expect(
      await services.cashier.mode(),
      CashierMode(on: true, salesmen: {ali}),
    );
  });

  testWidgets('the random check: counted on the shelf, the difference shown '
      'with its value, and posted on the owner\'s word', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 1000);
    await app.services.stockChecks.setRule(const StockCheckRule(size: 1));
    await _refresh(tester);

    await tapText(tester, 'Stock ki ginti');
    await tapButton(tester, 'Abhi ginti ke liye cheezein chunein');
    expect(find.text('Cooking Oil 5L (pcs)'), findsOneWidget);
    await typeInto(tester, 'Shelf par', '97');
    await tapButton(tester, 'Ginti rakhein');

    expect(find.textContaining('Kitaab: 100'), findsOneWidget);
    // Three tins missing at Rs 600 each: the owner sees what it is worth.
    expect(find.text('Farq -3 (Rs -1,800.00)'), findsOneWidget);
    expect(
      await app.rowsOf(
        "SELECT id FROM stock_ledger WHERE reason = 'Random check'",
      ),
      isEmpty,
    );

    await tapButton(tester, 'Malik manzoor kare: farq kitaab mein');
    final moved = await app.rowsOf(
      'SELECT qty_delta_thousandths, value_delta_paisa FROM stock_ledger '
      "WHERE reason = 'Random check'",
    );
    expect(moved.single['qty_delta_thousandths'], -3000);
    expect(moved.single['value_delta_paisa'], -180000);
    expect(find.text('Kitaab mein'), findsOneWidget);
    expect(find.textContaining('Rs 1,800.00 kam'), findsOneWidget);
    final health = await app.services.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  });

  testWidgets('a salesman sends the bill to the cashier, it waits without '
      'moving stock, and the cashier takes the money from the queue', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final services = app.services;
    final oil = await app.seedItem(name: 'Cooking Oil 5L', rupees: 1000);
    await services.setPin(services.currentUser!.id, '1947');
    final ali = await services.addStaff(
      name: 'Ali',
      role: Role.cashier,
      pin: '1111',
    );
    final bilal = await services.addStaff(
      name: 'Bilal',
      role: Role.cashier,
      pin: '2222',
    );
    await services.cashier.setMode(CashierMode(on: true, salesmen: {ali}));
    await _refresh(tester);

    await _signInAs(tester, 'Ali', '1111');
    await tapText(tester, 'Naya Bill');
    await _addOil(tester);
    await _addOil(tester);
    expect(find.textContaining('Cashier ko bhejein'), findsOneWidget);
    await tapButton(tester, 'Cashier ko bhejein');
    await tester.tap(find.widgetWithText(BlButton, 'Cashier ko bhejein'));
    await tester.pumpAndSettle();

    expect(await _sales(app), 0);
    expect(
      await app.rowsOf(
        "SELECT id FROM stock_ledger WHERE item_id = '$oil' "
        "AND txn_type = 'sale'",
      ),
      isEmpty,
    );
    final queue = await services.cashier.queue();
    expect(queue.single.madeByName, 'Ali');

    await _signInAs(tester, 'Bilal', '2222');
    await tapText(tester, '1 bill cashier ke paas intezar mein');
    expect(find.textContaining('Ali ne'), findsOneWidget);
    await tapButton(tester, 'Paisay le kar bill banayein');
    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '2000');
    await tapButton(tester, 'Save karein');
    await tester.pumpAndSettle();

    final bill = await app.rowsOf(
      'SELECT created_by, salesperson_id, total_paisa FROM documents '
      "WHERE doc_type = 'sale_invoice'",
    );
    expect(bill.single['created_by'], bilal);
    expect(bill.single['salesperson_id'], ali);
    expect(bill.single['total_paisa'], 200000);
    expect(await services.cashier.queue(), isEmpty);
    expect(
      await app.rowsOf(
        "SELECT id FROM stock_ledger WHERE item_id = '$oil' "
        "AND txn_type = 'sale'",
      ),
      hasLength(1),
    );
  });

  testWidgets('at 200% on a small phone the payment sheet\'s credit rules, a '
      'customer\'s rules, the control settings, the random check and the '
      'cashier\'s queue fit', (tester) async {
    final app = await Harness.startWithShop(tester);
    final services = app.services;
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 1000);
    final rashid = await _rashid(app, limit: const Money.rupees(5000));
    await services.credit.setDefaults(
      const CreditDefaults(
        limitMode: CreditMode.block,
        maxOpenBills: 1,
        billsMode: CreditMode.warn,
      ),
    );
    await _sellOnUdhaar(app, rashid);
    await services.stockChecks.setRule(const StockCheckRule(size: 1));
    await services.stockChecks.pick();
    await services.cashier.setMode(const CashierMode(on: true));
    await services.cashier.hold(
      SaleDraft(
        partyId: rashid,
        partyName: 'Rashid Traders',
        lines: [
          SaleLineDraft(
            itemId: (await services.queries.searchItems(
              services.identity!.firmId,
              query: 'Cooking',
            )).single.id,
            itemName: 'Cooking Oil 5L',
            qty: Qty.units(1),
            baseQty: Qty.units(1),
            unitCode: 'pcs',
            rate: Rate.rupees(1000),
          ),
        ],
      ),
    );
    _useASmallPhone(tester);
    await _refresh(tester);
    await tester.pumpAndSettle();

    await openSettings(tester);
    await tapText(tester, 'Udhaar, din band aur counter ke qaide');
    _expectNothingPaintsOffScreen(tester);
    for (var i = 0; i < 2; i++) {
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    await tapText(tester, 'Stock ki ginti');
    _expectNothingPaintsOffScreen(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tapText(tester, 'Cashier counter');
    expect(find.text('Rashid Traders'), findsOneWidget);
    _expectNothingPaintsOffScreen(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tapText(tester, 'Gahak');
    await tapText(tester, 'Rashid Traders');
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await tapText(tester, 'Udhaar ke qaide');
    _expectNothingPaintsOffScreen(tester);
    for (var i = 0; i < 4; i++) {
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    await _ringOnUdhaar(tester, tins: 5);
    expect(find.text('Is gahak ka udhaar band hai'), findsOneWidget);
    _expectNothingPaintsOffScreen(tester);
  });
}

/// Rashid Traders, a customer on [limit].
Future<String> _rashid(Harness app, {required Money? limit}) =>
    app.services.catalogue.addParty(
      app.services.actorNow(),
      PartyDraft(
        name: 'Rashid Traders',
        partyType: 'customer',
        creditLimit: limit,
      ),
    );

/// A tin of oil on [party]'s khata, through the services.
Future<void> _sellOnUdhaar(Harness app, String party) async {
  final services = app.services;
  final oil = (await services.queries.searchItems(
    services.identity!.firmId,
    query: 'Cooking',
  )).single;
  await services.postSale(
    services.actorNow(),
    SaleDraft(
      partyId: party,
      partyName: 'Rashid Traders',
      lines: [
        SaleLineDraft(
          itemId: oil.id,
          itemName: oil.name,
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitCode: 'pcs',
          rate: Rate.rupees(1000),
        ),
      ],
    ),
  );
}

Future<int> _sales(Harness app) async =>
    await app.scalar<int>(
      "SELECT COUNT(*) FROM documents WHERE doc_type = 'sale_invoice'",
    ) ??
    0;

/// [tins] tins of oil for Rashid Traders on udhaar, and Save tapped.
Future<void> _ringOnUdhaar(WidgetTester tester, {required int tins}) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Naya Bill');
  for (var i = 0; i < tins; i++) {
    await _addOil(tester);
  }
  await tapButton(tester, 'Paisay lein');
  await tapText(tester, 'Aam gahak');
  await tapText(tester, 'Rashid Traders');
  await tester.tap(find.byType(SwitchListTile).first);
  await tester.pumpAndSettle();
  await tapButton(tester, 'Save karein');
  await tester.pumpAndSettle();
}

Future<void> _addOil(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    'Cooking',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
}

/// Taps the [index]th button labelled [label], scrolled into view.
Future<void> _tapNth(WidgetTester tester, String label, int index) async {
  final button = find.widgetWithText(BlButton, label).at(index);
  // The message bar from the Save before would cover the last one.
  ScaffoldMessenger.of(tester.element(button)).removeCurrentSnackBar();
  await Scrollable.ensureVisible(tester.element(button), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// Makes the screens read the books again, as a sale or a sync would.
Future<void> _refresh(WidgetTester tester) async {
  ProviderScope.containerOf(
    tester.element(find.byType(HomeScreen)),
  ).bumpRefresh();
  await tester.pumpAndSettle();
}

/// Lets a few frames through.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Locks the app and signs back in as [name].
Future<void> _signInAs(WidgetTester tester, String name, String pin) async {
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Taala lagayein'));
  await tester.pumpAndSettle();
  await tapText(tester, '$name · Cashier');
  await typeInto(tester, 'PIN', pin);
  await tapButton(tester, 'Kholein');
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

/// Every rendered piece of text still inside the screen it was drawn on.
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
