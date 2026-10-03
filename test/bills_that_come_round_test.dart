import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/features/pos/cart.dart';
import 'package:bazaar_ledger/features/pos/cart_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// The bills that come round every week or month, ready on the day (M63).
///
/// A hotel's milk every morning, a school canteen's Monday order, an
/// office's tea on the first: set up once from a bill, said on the home
/// screen on the day, put on the counter with one tap at the day's prices,
/// or made all at once on the customers' khatas. Days the app was not
/// opened are asked about, never made by themselves. All by taps, against a
/// real database, on a clock the test sets.
void main() {
  testWidgets('a bill is set to repeat every Monday from its dots, and kept', (
    tester,
  ) async {
    final app = await Harness.startWithShop(
      tester,
      clock: FixedClock(DateTime.utc(2026, 10, 3, 6)),
    );
    final old = await _soldToRashid(app);

    await tester.pumpAndSettle();
    await tapText(tester, 'Farokht');
    await tester.tap(find.text(old).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Aur'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Har hafte / Har mahine banayein').last);
    await tester.pumpAndSettle();

    expect(find.text('Naya baar baar ka bill'), findsOneWidget);
    expect(find.text('Rashid Traders ka bill'), findsOneWidget);
    expect(find.text('$old se naqal'), findsOneWidget);
    expect(find.text('Cooking Oil 5L'), findsOneWidget);
    await tapText(tester, 'Peer');
    await tapText(tester, 'Khud bana dein');
    await _reachAndTap(tester, 'Mehfooz karein');

    final kept = await app.services.recurring.all();
    expect(kept, hasLength(1));
    expect(kept.single.every, const RepeatEvery.weekly(DateTime.monday));
    expect(kept.single.mode, RecurringMode.automatic);
    expect(kept.single.lines.single.qty, Qty.units(2));
    expect(kept.single.startOn, BusinessDate('2026-10-04'));
  });

  testWidgets(
    "on its day Home says so, and 'Banayein' puts it on the counter at "
    "today's prices; saving it makes the bill and the card moves on",
    (tester) async {
      // Monday 5 October 2026.
      final app = await Harness.startWithShop(
        tester,
        clock: FixedClock(DateTime.utc(2026, 10, 5, 6)),
      );
      await _soldToRashid(app);
      final bill = await _keep(app, start: '2026-10-05');
      await _refresh(tester);

      expect(find.text('Aaj ke bill'), findsOneWidget);
      expect(find.text('Rashid Traders'), findsWidgets);
      expect(find.text('Aaj due'), findsOneWidget);

      await tapButton(tester, 'Banayein');
      expect(find.text('Rashid Traders ka 5 Oct wala bill'), findsOneWidget);
      // Rashid buys wholesale, and wholesale is Rs 2,300 today; the bill it
      // was copied from said Rs 2,400.
      expect(find.text('× 2,300.00'), findsOneWidget);

      await tapButton(tester, 'Paisay lein');
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();
      await tapButton(tester, 'Save karein');

      final bills = await app.rowsOf(
        'SELECT doc_no, total_paisa, balance_paisa FROM documents '
        "WHERE doc_type = 'sale_invoice' ORDER BY created_at_utc",
      );
      expect(bills, hasLength(2));
      expect(bills.last['total_paisa'], 460000);
      final kept = await app.services.recurring.byId(bill.id);
      expect(kept!.doneThrough, BusinessDate('2026-10-05'));
      final history = await app.services.recurring.history(bill.id);
      expect(history.single.docNo, bills.last['doc_no']);
      expect(history.single.byItself, isFalse);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Aaj ke bill'), findsNothing);
      expect(find.text('Baar baar ke bill: 1 · agla 12 Oct'), findsOneWidget);
    },
  );

  testWidgets(
    "'Sab bana dein' makes every bill set to make itself on the customers' "
    'khatas, and each khata rises by exactly its bill',
    (tester) async {
      final app = await Harness.startWithShop(
        tester,
        clock: FixedClock(DateTime.utc(2026, 10, 5, 6)),
      );
      await _soldToRashid(app);
      await _keep(app, start: '2026-10-05', mode: RecurringMode.automatic);
      final canteen = await app.seedParty(name: 'School Canteen');
      final oil = await app.scalar<String>('SELECT id FROM items');
      await _keep(
        app,
        party: canteen,
        partyName: 'School Canteen',
        start: '2026-10-05',
        mode: RecurringMode.automatic,
        item: oil,
        qty: 1,
      );
      final rashid = (await app.services.queries.searchParties(
        app.services.identity!.firmId,
        query: 'Rashid',
      )).single;
      final before = rashid.balance;
      await _refresh(tester);

      await tapButton(tester, 'Sab bana dein (2)');
      expect(
        find.textContaining('Rashid Traders · Rs 4,600.00'),
        findsOneWidget,
      );
      expect(
        find.textContaining('School Canteen · Rs 2,500.00'),
        findsOneWidget,
      );
      await tapButton(tester, 'Band karein');

      final firmId = app.services.identity!.firmId;
      expect(
        (await app.services.queries.partyById(firmId, rashid.id))!.balance -
            before,
        const Money.rupees(4600),
      );
      expect(
        (await app.services.queries.partyById(firmId, canteen))!.balance,
        const Money.rupees(2500),
      );
      expect(find.text('Aaj ke bill'), findsNothing);
      await _booksBalance(app);
    },
  );

  testWidgets(
    'days the app was not opened are listed and asked about, never made by '
    'themselves; only the latest makes one bill',
    (tester) async {
      final app = await Harness.startWithShop(
        tester,
        clock: FixedClock(DateTime.utc(2026, 10, 5, 6)),
      );
      await _soldToRashid(app);
      await _keep(
        app,
        start: '2026-10-02',
        every: const RepeatEvery.daily(),
        mode: RecurringMode.automatic,
      );
      await _refresh(tester);

      expect(
        find.text('4 din ke bill reh gaye (2 Oct – 5 Oct)'),
        findsOneWidget,
      );
      expect(find.textContaining('Sab bana dein'), findsNothing);
      expect(await _saleCount(app), 1, reason: 'only the bill copied from');

      await tapButton(tester, 'Poochhein');
      expect(find.text('Rashid Traders: 4 bill reh gaye'), findsOneWidget);
      expect(find.textContaining('2 Oct, 3 Oct, 4 Oct, 5 Oct'), findsOneWidget);
      await tapButton(tester, 'Sirf aakhri wala (5 Oct)');
      expect(
        find.textContaining('Rashid Traders · Rs 4,600.00'),
        findsOneWidget,
      );
      await tapButton(tester, 'Band karein');
      expect(await _saleCount(app), 2, reason: 'the latest, and only it');
      expect(find.text('Aaj ke bill'), findsNothing);
    },
  );

  testWidgets('a paused bill never comes due, and its page lists the bills '
      'it made, resumes it and ends it', (tester) async {
    final app = await Harness.startWithShop(
      tester,
      clock: FixedClock(DateTime.utc(2026, 10, 5, 6)),
    );
    await _soldToRashid(app);
    final bill = await _keep(
      app,
      start: '2026-10-05',
      mode: RecurringMode.automatic,
    );
    await app.services.recurring.make(bill, BusinessDate('2026-10-05'));
    await app.services.recurring.pause(bill.id);
    await _refresh(tester);

    expect(find.text('Aaj ke bill'), findsNothing);
    expect(find.textContaining('Baar baar ke bill'), findsNothing);

    // Reached from a khata, where a customer's repeating bills are listed.
    await _openKhata(tester, 'Rashid Traders');
    await tapText(tester, 'Ruka hua');
    expect(find.text('Rashid Traders ka bill'), findsOneWidget);
    expect(find.text('Ruka hua'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('5 Oct ka'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('IS KE BANE HUE BILL'), findsOneWidget);

    await tapButton(tester, 'Phir chalayein');
    expect(find.text('Aaj se phir chal raha hai'), findsOneWidget);
    expect((await app.services.recurring.byId(bill.id))!.paused, isFalse);
    await tapButton(tester, 'Khatam karein');
    await tester.tap(find.text('Khatam karein').last);
    await tester.pumpAndSettle();
    expect((await app.services.recurring.byId(bill.id))!.isEnded, isTrue);
    expect(find.text('Khatam'), findsWidgets);
  });

  testWidgets(
    "a customer's khata starts a repeating bill from their last bill",
    (tester) async {
      final app = await Harness.startWithShop(
        tester,
        clock: FixedClock(DateTime.utc(2026, 10, 3, 6)),
      );
      await _soldToRashid(app);
      await _refresh(tester);

      await _openKhata(tester, 'Rashid Traders');
      await tester.scrollUntilVisible(
        find.text('Naya baar baar ka bill'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tapButton(tester, 'Naya baar baar ka bill');
      expect(find.text('Naya baar baar ka bill'), findsOneWidget);
      expect(find.text('Cooking Oil 5L'), findsOneWidget);
      await tapText(tester, 'Har mahine');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Mahine ki tareekh (1-31)'),
        '1',
      );
      await tester.pumpAndSettle();
      await _reachAndTap(tester, 'Mehfooz karein');

      final kept = (await app.services.recurring.all()).single;
      expect(kept.every, const RepeatEvery.monthly(1));
      expect(kept.mode, RecurringMode.remind);
    },
  );

  testWidgets('at 200% on a small phone the card, a bill missed (let go, '
      'nothing made) and the set-up fit', (tester) async {
    final app = await Harness.startWithShop(
      tester,
      clock: FixedClock(DateTime.utc(2026, 10, 5, 6)),
    );
    await _soldToRashid(app);
    await _keep(
      app,
      start: '2026-10-02',
      every: const RepeatEvery.daily(),
      mode: RecurringMode.automatic,
    );
    await _keep(app, start: '2026-10-05');
    _useASmallPhone(tester);
    await _refresh(tester);

    await tester.scrollUntilVisible(
      find.text('Aaj ke bill'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    _expectNothingPaintsOffScreen(tester);
    await tapButton(tester, 'Poochhein');
    _expectNothingPaintsOffScreen(tester);
    await tapButton(tester, 'Koi nahi, chhor dein');
    expect(await _saleCount(app), 1, reason: 'let go, nothing made');
    await _reachAndTap(tester, 'Sab dekhein');
    _expectNothingPaintsOffScreen(tester);
    await tapText(tester, 'Rashid Traders');
    await _reachAndTap(tester, 'Badlein');
    _expectNothingPaintsOffScreen(tester);
  });

  group('a repeating bill on the counter', () {
    final mark = RecurringMark(
      billId: 'r1',
      forDate: BusinessDate('2026-10-05'),
      partyId: 'hotel',
      partyName: 'Hotel Al-Madina',
    );

    test('says which it is through the app being killed, and a draft '
        'without it is an ordinary bill', () {
      final back = CartDraft.decode(
        CartDraft.encode(
          Cart(partyId: 'hotel', partyName: 'Hotel Al-Madina', recurring: mark),
        ),
      )!;
      expect(back.recurring!.billId, 'r1');
      expect(back.recurring!.forDate, BusinessDate('2026-10-05'));
      final plain = CartDraft.decode(
        CartDraft.encode(
          const Cart(partyId: 'hotel', partyName: 'Hotel Al-Madina'),
        ),
      )!;
      expect(plain.recurring, isNull);
    });

    test('another customer named on the counter makes it an ordinary bill', () {
      final cart = Cart(
        partyId: 'hotel',
        partyName: 'Hotel Al-Madina',
        recurring: mark,
      );
      expect(cart.copyWith(billDiscount: Money.zero).recurring, mark);
      expect(cart.copyWith(partyId: 'hotel').recurring, mark);
      expect(cart.copyWith(partyId: 'canteen').recurring, isNull);
      expect(cart.copyWith(clearParty: true).recurring, isNull);
    });
  });
}

/// Two tins of oil to Rashid Traders, a wholesale customer, at Rs 2,400 —
/// a price somebody typed — on udhaar. Returns the bill's number.
Future<String> _soldToRashid(Harness app) async {
  final services = app.services;
  final firm = services.identity!.firmId;
  final pcs = (await services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');
  final oil = await services.catalogue.addItem(
    services.actorNow(),
    ItemDraft(
      name: 'Cooking Oil 5L',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(2500),
      wholesaleRate: Rate.rupees(2300),
      openingStock: Qty.units(50),
      openingRate: Rate.rupees(2000),
    ),
  );
  final rashid = await services.catalogue.addParty(
    services.actorNow(),
    const PartyDraft(name: 'Rashid Traders', priceTier: PriceTier.wholesale),
  );
  final sale = await services.postSale(
    services.actorNow(),
    SaleDraft(
      partyId: rashid,
      lines: [
        SaleLineDraft(
          itemId: oil,
          itemName: 'Cooking Oil 5L',
          qty: Qty.units(2),
          baseQty: Qty.units(2),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(2400),
        ),
      ],
    ),
  );
  return sale.docNo;
}

/// A repeating bill kept through the services, as the set-up screen keeps
/// it: two tins of oil for Rashid every Monday unless said otherwise.
Future<RecurringBill> _keep(
  Harness app, {
  String? party,
  String partyName = 'Rashid Traders',
  required String start,
  RepeatEvery every = const RepeatEvery.weekly(DateTime.monday),
  RecurringMode mode = RecurringMode.remind,
  String? item,
  int qty = 2,
}) async {
  final services = app.services;
  final firm = services.identity!.firmId;
  final pcs = (await services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');
  final partyId =
      party ??
      (await services.queries.searchParties(firm, query: 'Rashid')).single.id;
  final itemId = item ?? await app.scalar<String>('SELECT id FROM items');
  final bill = RecurringBill(
    id: services.recurring.newId(),
    partyId: partyId,
    partyName: partyName,
    lines: [
      RecurringLine(
        itemId: itemId,
        name: 'Cooking Oil 5L',
        qty: Qty.units(qty),
        unitId: pcs.id,
        unitCode: 'pcs',
        rate: Rate.rupees(2400),
      ),
    ],
    every: every,
    startOn: BusinessDate(start),
    mode: mode,
  );
  await services.recurring.save(bill);
  return bill;
}

Future<void> _refresh(WidgetTester tester) async {
  ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).first),
  ).bumpRefresh();
  await tester.pumpAndSettle();
}

Future<int> _saleCount(Harness app) async =>
    (await app.scalar<int>(
      "SELECT COUNT(*) FROM documents WHERE doc_type = 'sale_invoice' "
      "AND status = 'posted'",
    )) ??
    0;

Future<void> _openKhata(WidgetTester tester, String name) async {
  await tapText(tester, 'Gahak');
  await tapText(tester, name);
}

/// Taps the button [label] in a list built as it scrolls, bringing it into
/// the list first from wherever the list was left.
Future<void> _reachAndTap(WidgetTester tester, String label) async {
  final text = find.textContaining(label);
  if (text.evaluate().isEmpty) {
    final list = find.byType(Scrollable).first;
    await tester.drag(list, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(text, 200, scrollable: list);
  }
  await tapButton(tester, label);
}

Future<void> _booksBalance(Harness app) async {
  final row = await app.rowsOf(
    'SELECT COALESCE(SUM(debit_paisa), 0) AS d, '
    'COALESCE(SUM(credit_paisa), 0) AS c FROM journal_lines '
    'WHERE deleted_at_utc IS NULL',
  );
  expect(row.single['d'], row.single['c']);
  expect(await app.services.database.findLedgerImbalances(), isEmpty);
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
  }
}
