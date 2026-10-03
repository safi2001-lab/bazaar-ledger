import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/features/home/home_screen.dart';
import 'package:bazaar_ledger/features/khata/chase_screen.dart';
import 'package:bazaar_ledger/features/parties/quick_party_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// Every bill has a day it is due, and a customer's promise is kept on the
/// khata (M38).
///
/// Driven through the real screens against a real database: the khata says
/// when each bill falls due and how late it is, a term typed on the
/// customer's form moves those days, a promise written on the khata is on
/// the first screen on its day, and the chase list reads by how late or by
/// the day promised. Dates are worked from today, because the app reads
/// today from the phone's clock.
void main() {
  testWidgets('a bill on the khata says when it is due, and how late', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final aslam = await _customer(app, 'Aslam Karyana', creditDays: 15);
    await _bill(app, aslam, daysAgo: 24, rupees: 3000);
    await _bill(app, aslam, daysAgo: 5, rupees: 1200);

    await _openKhata(tester, 'Aslam Karyana');

    expect(find.text('15 din ka udhaar'), findsOneWidget);
    expect(find.text('9 din der'), findsOneWidget);
    expect(find.text('${shortDate(_day(10))} tak'), findsOneWidget);
  });

  testWidgets('a credit term typed on the customer form moves the days '
      'their open bills are due', (tester) async {
    final app = await Harness.startWithShop(tester);
    final aslam = await _customer(app, 'Aslam Karyana');
    await _bill(app, aslam, daysAgo: 20, rupees: 3000);

    await _openKhata(tester, 'Aslam Karyana');
    // No term of his own: the shop's usual month.
    expect(find.text('Aam muddat, 30 din'), findsOneWidget);
    expect(find.text('${shortDate(_day(10))} tak'), findsOneWidget);

    await tester.tap(find.byTooltip('Gahak ki tafseel'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Khaali chhorein to 30 din. Badalne se khule billon ki aakhri '
        'tareekh bhi badlegi.',
      ),
      findsOneWidget,
    );
    await typeInto(tester, 'Udhaar kitne din ka (marzi se)', '7');
    await tapButton(tester, 'Save karein');
    await tester.pumpAndSettle();

    expect(find.text('7 din ka udhaar'), findsOneWidget);
    expect(find.text('13 din der'), findsOneWidget);
    final saved = await app.rowsOf('SELECT credit_days FROM parties');
    expect(saved.single['credit_days'], 7);
  });

  testWidgets('a new customer made from the bill is given their days', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final navigator = Navigator.of(tester.element(find.byType(HomeScreen)));
    unawaitedPush(
      navigator,
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: QuickPartySheet(initialName: 'Bilal General Store'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await typeInto(tester, 'Udhaar kitne din ka (marzi se)', '400');
    await tapButton(tester, 'Save karein');
    expect(find.text('0 se 365 din ke darmiyan likhein'), findsOneWidget);

    await typeInto(tester, 'Udhaar kitne din ka (marzi se)', '15');
    await tapButton(tester, 'Save karein');
    await settleReal(
      tester,
      done: () => find.byType(QuickPartySheet).evaluate().isEmpty,
    );

    final saved = await app.rowsOf('SELECT name, credit_days FROM parties');
    expect(saved.single['name'], 'Bilal General Store');
    expect(saved.single['credit_days'], 15);
  });

  testWidgets('a promise written on the khata is on the first screen on '
      'its day, and leaves it once kept', (tester) async {
    final app = await Harness.startWithShop(tester);
    final aslam = await app.seedParty(name: 'Aslam Karyana', owedRupees: 5000);

    await _openKhata(tester, 'Aslam Karyana');
    await tapButton(tester, 'Wada likhein');
    await tapText(tester, 'Aaj · ${shortDate(_day(0))}');
    await typeInto(tester, 'Kitne ka kaha (marzi se)', '2000');
    await typeInto(
      tester,
      'Unhon ne kya kaha (marzi se)',
      'shaam ko beta aayega',
    );
    await tapButton(tester, 'Wada save karein');
    await settleReal(
      tester,
      until: find.text('Wada likh liya: ${shortDate(_day(0))}'),
    );

    expect(
      find.text('${shortDate(_day(0))} ko Rs 2,000.00 ka wada'),
      findsOneWidget,
    );
    expect(find.text('Aaj ka wada'), findsOneWidget);
    expect(find.text('"shaam ko beta aayega"'), findsOneWidget);
    expect(find.textContaining('Malik Sahib ne'), findsOneWidget);

    // Home, where the morning starts.
    await _home(tester);
    const line = '1 gahak ne aaj dene ka wada kiya · Rs 2,000.00';
    expect(find.text(line), findsOneWidget);
    await tapText(tester, line);
    expect(find.text('Aslam Karyana'), findsOneWidget);

    // He came: the promise is kept, and the line goes.
    await app.services.recordReceipt(
      app.services.actorNow(),
      ReceiptDraft(
        partyId: aslam,
        amount: const Money.rupees(2000),
        mode: 'cash',
        paymentAccountId: await _cash(app),
      ),
    );
    await _home(tester);
    expect(find.text(line), findsNothing);
    final kept = await app.services.udhaar.queries.promisesOf(
      app.services.identity!.firmId,
      aslam,
    );
    expect(kept.single.standingOn(_day(0)), PromiseStanding.kept);
  });

  testWidgets('the morning card counts what is due today and what is late, '
      'and opens the list narrowed to it', (tester) async {
    final app = await Harness.startWithShop(tester);
    final today = await _customer(app, 'Due Today', creditDays: 0);
    final late = await _customer(app, 'Late One', creditDays: 7);
    final calm = await _customer(app, 'Not Yet', creditDays: 30);
    await _bill(app, today, daysAgo: 0, rupees: 1500);
    await _bill(app, late, daysAgo: 20, rupees: 4000);
    await _bill(app, calm, daysAgo: 2, rupees: 900);

    await _home(tester);
    expect(
      find.text('1 gahak ka udhaar aaj dena hai · Rs 1,500.00'),
      findsOneWidget,
    );
    await tapText(tester, '1 gahak der se · Rs 4,000.00');

    expect(find.text('Late One'), findsOneWidget);
    expect(find.text('13 din der'), findsOneWidget);
    expect(find.text('Due Today'), findsNothing);
    expect(find.text('Not Yet'), findsNothing);
  });

  testWidgets('the chase list splits what is not yet due from what is late, '
      'and reads by the day promised', (tester) async {
    // Tall enough for the summary, the filters and all three names at once.
    tester.view
      ..physicalSize = const Size(800, 1800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = await Harness.startWithShop(tester);
    final first = await _customer(app, 'Ahmed Sons', creditDays: 30);
    final second = await _customer(app, 'Bashir Store', creditDays: 7);
    final third = await _customer(app, 'Chaudhry Mart', creditDays: 7);
    await _bill(app, first, daysAgo: 3, rupees: 1000); // not yet due
    await _bill(app, second, daysAgo: 10, rupees: 2000); // 3 days late
    await _bill(app, third, daysAgo: 60, rupees: 3000); // 53 days late
    await app.services.udhaar.recordPromise(
      PromiseDraft(partyId: first, promisedFor: _day(1)),
    );
    await app.services.udhaar.recordPromise(
      PromiseDraft(partyId: third, promisedFor: _day(5)),
    );

    await _openChase(tester);
    expect(find.text('Abhi waqt hai   1,000.00'), findsOneWidget);
    expect(find.text('1-30   2,000.00'), findsOneWidget);
    expect(find.text('31-60   3,000.00'), findsOneWidget);
    expect(_names(tester), ['Chaudhry Mart', 'Bashir Store', 'Ahmed Sons']);

    await tapText(tester, 'Wade ki tareekh se');
    expect(_names(tester), ['Ahmed Sons', 'Chaudhry Mart', 'Bashir Store']);

    await tapText(tester, 'Abhi waqt hai   1,000.00');
    expect(_names(tester), ['Ahmed Sons']);
  });

  group('at 200% on a small phone', () {
    setUpAll(loadRealFont);

    testWidgets('the khata with its due days and promise, and the promise '
        'sheet, fit', (tester) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      final name = await _customer(
        app,
        'Chaudhry Muhammad Aslam Karyana Store',
        creditDays: 15,
      );
      await _bill(app, name, daysAgo: 40, rupees: 123456);
      await _bill(app, name, daysAgo: 1, rupees: 4500);
      await app.services.udhaar.recordPromise(
        PromiseDraft(
          partyId: name,
          promisedFor: _day(6),
          amount: const Money.rupees(100000),
          note: 'tankhwah milte hi, pakka',
        ),
      );

      await _home(tester);
      _expectNothingPaintsOffScreen(tester);
      await _openKhata(tester, 'Chaudhry Muhammad Aslam Karyana Store');
      _expectNothingPaintsOffScreen(tester);
      await tapButton(tester, 'Naya wada');
      _expectNothingPaintsOffScreen(tester);
    });

    testWidgets('the chase list fits', (tester) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      final name = await _customer(
        app,
        'Chaudhry Muhammad Aslam Karyana Store',
        creditDays: 7,
      );
      await _bill(app, name, daysAgo: 120, rupees: 123456);
      await app.services.udhaar.recordPromise(
        PromiseDraft(
          partyId: name,
          promisedFor: _day(2),
          amount: const Money.rupees(100000),
        ),
      );
      await _openChase(tester);
      _expectNothingPaintsOffScreen(tester);
    });
  });
}

/// Today's business date, [offset] days on.
String _day(int offset) =>
    BusinessDate.now(const SystemClock()).addDays(offset).value;

void unawaitedPush(NavigatorState navigator, Route<void> route) {
  navigator.push(route).ignore();
}

List<String> _names(WidgetTester tester) {
  const names = {'Ahmed Sons', 'Bashir Store', 'Chaudhry Mart'};
  return tester
      .widgetList<Text>(
        find.descendant(
          of: find.byType(ChaseScreen),
          matching: find.byType(Text, skipOffstage: false),
        ),
      )
      .map((t) => t.data)
      .whereType<String>()
      .where(names.contains)
      .toList();
}

Future<void> _home(WidgetTester tester) async {
  final home = tester.element(find.byType(HomeScreen, skipOffstage: false));
  Navigator.of(home).popUntil((route) => route.isFirst);
  ProviderScope.containerOf(home).bumpRefresh();
  await tester.pumpAndSettle();
}

Future<void> _openKhata(WidgetTester tester, String name) async {
  await _home(tester);
  await tapText(tester, 'Gahak');
  await tapText(tester, name);
}

Future<void> _openChase(WidgetTester tester) async {
  await _home(tester);
  await tapText(tester, 'Gahak');
  await tester.tap(find.byTooltip('Udhaar wasooli'));
  await tester.pumpAndSettle();
}

Future<String> _cash(Harness app) async =>
    (await app.services.queries.paymentAccounts(
      app.services.identity!.firmId,
    )).firstWhere((a) => a.isDefault).id;

Future<String> _customer(Harness app, String name, {int? creditDays}) =>
    app.services.catalogue.addParty(
      app.services.actorNow(),
      PartyDraft(name: name, creditDays: creditDays),
    );

/// A bill of Rs [rupees] to [partyId], [daysAgo] days ago, all on udhaar.
Future<void> _bill(
  Harness app,
  String partyId, {
  required int daysAgo,
  required int rupees,
}) async {
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');
  final itemId = await app.services.catalogue.addItem(
    app.services.actorNow(),
    ItemDraft(
      name: 'Item $partyId $daysAgo $rupees',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(rupees),
      openingStock: Qty.units(10),
    ),
  );
  final day = BusinessDate(_day(-daysAgo));
  await app.services.postSale(
    ActorContext(
      firmId: firm,
      userId: app.services.identity!.userId,
      deviceId: app.services.identity!.deviceId,
      // Nine in the morning, Lahore: the same business day either way.
      startedAtUtc: DateTime.utc(day.year, day.month, day.day, 4),
    ),
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: 'Item',
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
        ),
      ],
      tenders: const [],
    ),
  );
}

/// A 360dp-wide phone with the font at 200%.
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

