import 'dart:io';

import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// "Baqi chhor do": a balance settled with a discount or written off, with
/// the reason kept (M44).
///
/// Driven through the real khata, payment sheet and chase list against a
/// real database, and then read back out of the books: the bills settled,
/// the receivable down by exactly what was let go, the expense up by it,
/// and a cancellation putting it all back.
void main() {
  testWidgets('Rs 9,500 taken on Rs 10,000 with the rest let go settles '
      'every bill', (tester) async {
    _useATallScreen(tester);
    final app = await Harness.startWithShop(tester);
    final aslam = await _owes(app, 'Aslam Karyana', [6000, 4000]);

    await _openKhata(tester, 'Aslam Karyana');
    await tapText(tester, 'Paisay wasool karein');
    await typeInto(tester, 'Kitne paisay milay', '9500');
    await tapText(tester, 'Baqi chhor dein (riayat se hisaab saaf)');
    expect(find.text('Riayat: Rs 500.00, sab bill saaf'), findsOneWidget);
    await typeInto(tester, 'Riayat ki wajah (marzi se)', 'Purana gahak');
    await tapButton(tester, 'Wasooli save karein');
    await settleReal(
      tester,
      until: find.text('Rs 9,500.00 wasool, Rs 500.00 chhor diye'),
    );

    expect(await _balance(app, aslam), Money.zero);
    expect(await _net(app, 'settlement_discount'), const Money.rupees(500));
    expect(await _net(app, 'accounts_receivable'), Money.zero);
    expect(find.textContaining('Riayat SD-'), findsOneWidget);
    await _expectBooksBalance(app);
  });

  testWidgets('a cashier lets go up to their ceiling, and is told who can '
      'past it', (tester) async {
    _useATallScreen(tester);
    final app = await Harness.startWithShop(tester);
    final aslam = await _owes(app, 'Aslam Karyana', [10000]);
    await _signInAsCashier(tester, app);

    await _openKhata(tester, 'Aslam Karyana');
    // No write-off at the counter.
    expect(find.byTooltip('Doobi hui raqam likhein'), findsNothing);
    await tapText(tester, 'Paisay wasool karein');
    await typeInto(tester, 'Kitne paisay milay', '9000');
    await tapText(tester, 'Baqi chhor dein (riayat se hisaab saaf)');
    await tapButton(tester, 'Wasooli save karein');
    expect(
      find.text(
        'Itni riayat aap ki hadd se ziyada hai. Malik, manager ya '
        'accountant se karwayein.',
      ),
      findsOneWidget,
    );
    expect(await _balance(app, aslam), const Money.rupees(10000));

    // Five per cent is the counter's own to give.
    await typeInto(tester, 'Kitne paisay milay', '9500');
    await tapButton(tester, 'Wasooli save karein');
    await settleReal(
      tester,
      until: find.text('Rs 9,500.00 wasool, Rs 500.00 chhor diye'),
    );
    expect(await _balance(app, aslam), Money.zero);
    // And the service, which is what actually stands in the way.
    expect(
      () => app.services.udhaar.writeOff(
        aslam,
        reason: 'x',
        amount: const Money.rupees(1),
      ),
      throwsA(isA<PermissionDenied>()),
    );
  });

  testWidgets('a balance is written off with its reason, shows on the khata, '
      'and is cancelled back', (tester) async {
    _useATallScreen(tester);
    final app = await Harness.startWithShop(tester);
    final aslam = await _owes(app, 'Aslam Karyana', [3000, 2000]);

    await _openKhata(tester, 'Aslam Karyana');
    await tester.tap(find.byTooltip('Doobi hui raqam likhein'));
    await tester.pumpAndSettle();
    expect(find.text('Kul baqaya: Rs 5,000.00'), findsOneWidget);
    await tapButton(tester, 'Doobi hui raqam mein likh dein');
    expect(find.text('Wajah zaroori hai'), findsOneWidget);
    await tapText(tester, 'Gahak chala gaya');
    await tapButton(tester, 'Doobi hui raqam mein likh dein');
    await settleReal(
      tester,
      until: find.textContaining('doobi hui raqam mein likh diye'),
    );

    expect(await _balance(app, aslam), Money.zero);
    expect(await _net(app, 'bad_debts'), const Money.rupees(5000));
    final no =
        (await app.rowsOf(
              "SELECT payment_no FROM payments WHERE mode = 'adjustment'",
            )).single['payment_no']!
            as String;
    expect(no, startsWith('WO-'));

    // The line, opened: what it is and why; cancelled, never edited.
    await tapText(tester, 'Doobi hui raqam $no');
    expect(find.text('Gahak chala gaya'), findsOneWidget);
    expect(find.text('Tabdeeli karein'), findsNothing);
    expect(find.text('Raseed bhejein (PDF)'), findsNothing);
    await tapButton(tester, 'Mansookh karein');
    await tapText(tester, 'Galat entry');
    await tapButton(tester, 'Haan, mansookh karein');
    await settleReal(tester, until: find.text('$no mansookh ho gaya'));

    expect(await _balance(app, aslam), const Money.rupees(5000));
    expect(await _net(app, 'bad_debts'), Money.zero);
    await _expectBooksBalance(app);
  });

  testWidgets('the bills picked are written off and the rest is still owed', (
    tester,
  ) async {
    _useATallScreen(tester);
    final app = await Harness.startWithShop(tester);
    final aslam = await _owes(app, 'Aslam Karyana', [3000, 2000]);
    final oldest = (await app.services.queries.openBillsFor(
      app.services.identity!.firmId,
      aslam,
    )).first;

    await _openKhata(tester, 'Aslam Karyana');
    await tester.tap(find.byTooltip('Doobi hui raqam likhein'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Sirf kuch bill');
    await tapText(tester, '${oldest.docNo} · ${oldest.dateLocal}');
    await tapText(tester, 'Dene se inkaar');
    await tapButton(tester, 'Doobi hui raqam mein likh dein');
    await settleReal(
      tester,
      until: find.textContaining('doobi hui raqam mein likh diye'),
    );
    expect(await _balance(app, aslam), const Money.rupees(2000));
    await _expectBooksBalance(app);
  });

  testWidgets('what was let go is listed with who, why and how much', (
    tester,
  ) async {
    _useATallScreen(tester);
    final app = await Harness.startWithShop(tester);
    final aslam = await _owes(app, 'Aslam Karyana', [3000]);
    final bilal = await _owes(app, 'Bilal Store', [10000]);
    await app.services.udhaar.writeOff(
      aslam,
      reason: 'Gahak chala gaya',
      amount: const Money.rupees(3000),
    );
    await app.services.udhaar.settleWithDiscount(
      ReceiptDraft(
        partyId: bilal,
        amount: const Money.rupees(9800),
        mode: 'cash',
        paymentAccountId: await _cash(app),
      ),
      discount: const Money.rupees(200),
      reason: 'Khulay paisay nahi thay',
    );

    await _openChase(tester);
    await tester.tap(find.byTooltip('Chhori hui raqam'));
    await tester.pumpAndSettle();
    expect(find.text('Aslam Karyana'), findsOneWidget);
    expect(find.text('Gahak chala gaya'), findsOneWidget);
    expect(find.text('Malik Sahib ne chhora'), findsOneWidget);
    expect(find.text('Rs 3,000.00'), findsOneWidget);

    await tapText(tester, 'Riayat');
    expect(find.text('Bilal Store'), findsOneWidget);
    expect(find.text('Khulay paisay nahi thay'), findsOneWidget);
    expect(find.text('Rs 200.00'), findsOneWidget);
  });

  group('at 200% on a small phone', () {
    setUpAll(_loadRealFont);

    testWidgets('the write-off sheet and the list of what was let go fit', (
      tester,
    ) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      final name = await _owes(app, 'Chaudhry Muhammad Aslam Karyana Store', [
        123456,
        4500,
      ]);
      await _openKhata(tester, 'Chaudhry Muhammad Aslam Karyana Store');
      await tester.tap(find.byTooltip('Doobi hui raqam likhein'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
      await tapText(tester, 'Sirf kuch bill');
      _expectNothingPaintsOffScreen(tester);

      await app.services.udhaar.writeOff(
        name,
        reason: 'Gahak shehar chhor kar chala gaya, number band hai',
        amount: const Money.rupees(127956),
      );
      await _openChase(tester);
      await tester.tap(find.byTooltip('Chhori hui raqam'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
    });

    testWidgets('the receipt sheet with the rest let go fits', (tester) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      await _owes(app, 'Chaudhry Muhammad Aslam Karyana Store', [123456]);
      await _openKhata(tester, 'Chaudhry Muhammad Aslam Karyana Store');
      await tapText(tester, 'Paisay wasool karein');
      await typeInto(tester, 'Kitne paisay milay', '120000');
      await tapText(tester, 'Baqi chhor dein (riayat se hisaab saaf)');
      _expectNothingPaintsOffScreen(tester);
    });
  });
}

/// A customer with one udhaar bill per amount in [rupees], oldest first.
Future<String> _owes(Harness app, String name, List<int> rupees) async {
  final id = await app.services.catalogue.addParty(
    app.services.actorNow(),
    PartyDraft(name: name),
  );
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');
  for (var i = 0; i < rupees.length; i++) {
    final itemId = await app.services.catalogue.addItem(
      app.services.actorNow(),
      ItemDraft(
        name: 'Item $name $i',
        baseUnitId: pcs.id,
        saleRate: Rate.rupees(rupees[i]),
        openingStock: Qty.units(10),
      ),
    );
    await app.services.postSale(
      app.services.actorNow(),
      SaleDraft(
        partyId: id,
        lines: [
          SaleLineDraft(
            itemId: itemId,
            itemName: 'Item',
            qty: Qty.units(1),
            baseQty: Qty.units(1),
            unitId: pcs.id,
            unitCode: 'pcs',
            rate: Rate.rupees(rupees[i]),
          ),
        ],
        tenders: const [],
      ),
    );
  }
  return id;
}

Future<Money> _balance(Harness app, String partyId) async =>
    (await app.services.queries.partyById(
      app.services.identity!.firmId,
      partyId,
    ))!.balance;

Future<Money> _net(Harness app, String key) async {
  final rows = await app.rowsOf(
    'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS n '
    'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
    "WHERE a.system_key = '$key' AND jl.deleted_at_utc IS NULL",
  );
  return Money.paisa(rows.single['n']! as int);
}

Future<void> _expectBooksBalance(Harness app) async {
  final totals = await app.rowsOf(
    'SELECT SUM(debit_paisa) AS dr, SUM(credit_paisa) AS cr FROM journal_lines',
  );
  expect(totals.single['dr'], totals.single['cr']);
  final health = await app.services.checkHealth();
  expect(health.findings, isEmpty);
}

Future<String> _cash(Harness app) async =>
    (await app.services.queries.paymentAccounts(
      app.services.identity!.firmId,
    )).firstWhere((a) => a.isDefault).id;

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

/// The owner's PIN, Bilal at the counter with his own, and Bilal signed in.
Future<void> _signInAsCashier(WidgetTester tester, Harness app) async {
  final services = app.services;
  await services.setPin(services.currentUser!.id, '1947');
  await services.addStaff(name: 'Bilal', role: Role.cashier, pin: '2468');
  ProviderScope.containerOf(
    tester.element(find.byType(HomeScreen)),
  ).bumpRefresh();
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Taala lagayein'));
  await tester.pumpAndSettle();
  await tapText(tester, 'Bilal · Cashier');
  await typeInto(tester, 'PIN', '2468');
  await tapButton(tester, 'Kholein');
}

void _useATallScreen(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(800, 2000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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

/// A real font, because the test font's square glyphs make every width
/// assertion pass.
Future<void> _loadRealFont() async {
  final candidates = [
    'C:/Windows/Fonts/segoeui.ttf',
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/System/Library/Fonts/Helvetica.ttc',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final loader = FontLoader('Roboto')
      ..addFont(file.readAsBytes().then((b) => ByteData.view(b.buffer)));
    await loader.load();
    return;
  }
  fail('no real font found to measure text with');
}
