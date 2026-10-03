import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// The shop's money and the home's kept apart, other income in the books,
/// and the monthly bills remembered (M47), driven from the screens and read
/// back out of the database.
void main() {
  testWidgets('ghar ka kharcha is entered on the expense screen, kept apart '
      'from the shop\'s, and never reaches the profit and loss', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _openNewExpense(tester);

    await tapText(tester, 'Ghar ka kharcha');
    expect(
      find.textContaining('Ghar ka kharcha malik ka apna paisa'),
      findsOneWidget,
    );
    // Paid now, always: the home's spending is never owed to a supplier.
    expect(find.text('Baad mein dena hai'), findsNothing);
    await typeInto(tester, 'Raqam', '15000');
    await typeInto(tester, 'Kis cheez ke liye', 'Bachon ki school fees');
    await tapButton(tester, 'Kharcha save karein');

    final lines = await app.rowsOf(
      'SELECT a.system_key AS head, jl.debit_paisa AS dr '
      'FROM journal_entries je '
      'JOIN journal_lines jl ON jl.journal_entry_id = je.id '
      'JOIN accounts a ON a.id = jl.account_id '
      "WHERE je.source_type = 'expense' AND jl.debit_paisa > 0",
    );
    expect(lines.single['head'], 'owner_drawings');
    expect(lines.single['dr'], 1500000);

    // On the list as the home's, with the month's split above it.
    expect(find.text('Ghar ka kharcha'), findsOneWidget);
    expect(find.text('Is mahine ghar'), findsOneWidget);

    final today = BusinessDate.now(app.services.clock);
    final pnl = await app.services.reports.run(
      ReportKind.profitAndLoss,
      firmId: app.services.identity!.firmId,
      period: ReportPeriod.day(today),
      today: today,
    );
    expect(pnl.rows.any((r) => r.cells.first == "Owner's Drawings"), isFalse);
    await _expectBooksBalance(app);
  });

  testWidgets('a monthly bill shows when its day has come, and Pay now opens '
      'the expense filled in', (tester) async {
    final app = await Harness.startWithShop(tester);
    final money = app.services.shopMoney;
    final id = money.newMonthlyBillId();
    await money.saveMonthlyBill(
      MonthlyBill(
        id: id,
        headKey: 'rent',
        amount: const Money.rupees(40000),
        note: 'Haji Sahib ka kiraya',
        day: 1,
      ),
    );

    await tapText(tester, 'Kharcha');
    expect(
      find.text('Is mahine dena hai: Haji Sahib ka kiraya'),
      findsOneWidget,
    );
    await tapButton(tester, 'Abhi dein');
    // Filled in from the bill; nothing was written yet.
    expect(find.text('Haji Sahib ka kiraya'), findsOneWidget);
    expect(await app.countIn('documents'), 0);
    await tapButton(tester, 'Kharcha save karein');

    final tagged = await app.rowsOf(
      'SELECT DISTINCT jl.cost_centre AS tag, d.total_paisa AS total '
      'FROM documents d '
      'JOIN journal_entries je ON je.document_id = d.id '
      'JOIN journal_lines jl ON jl.journal_entry_id = je.id',
    );
    expect(tagged.single['tag'], 'expense:recurring:$id');
    expect(tagged.single['total'], 4000000);
    expect(find.textContaining('Is mahine dena hai'), findsNothing);
    await _expectBooksBalance(app);
  });

  testWidgets('an expense saved with a reminder becomes a monthly bill', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _openNewExpense(tester);
    await tapText(tester, 'Bijli, gas, pani');
    await typeInto(tester, 'Raqam', '9000');
    await typeInto(tester, 'Kis cheez ke liye', 'LESCO bill');
    await tester.tap(find.text('Har mahine yaad dilayen'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Mahine ki tareekh', '10');
    await tapButton(tester, 'Kharcha save karein');

    final bills = await app.services.shopMoney.monthlyBills();
    expect(bills.single.note, 'LESCO bill');
    expect(bills.single.day, 10);
    expect(bills.single.headKey, 'utilities');

    await tester.tap(find.byTooltip('Mahana bill'));
    await tester.pumpAndSettle();
    expect(find.text('LESCO bill'), findsOneWidget);
    expect(find.textContaining('Har mahine 10 tareekh ko'), findsOneWidget);
  });

  testWidgets('other income is entered under its head and cancelled from '
      'its page', (tester) async {
    final app = await Harness.startWithShop(tester);
    await tapText(tester, 'Kharcha');
    await tester.tap(find.byTooltip('Deegar aamdani'));
    await tester.pumpAndSettle();
    expect(find.text('Abhi koi deegar aamdani nahi'), findsOneWidget);

    await tester.tap(find.text('Nayi aamdani'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Raddi, khali dabbe');
    await typeInto(tester, 'Raqam', '1200');
    await typeInto(tester, 'Kis se mila (marzi se)', 'Kabari Bashir');
    await tapButton(tester, 'Aamdani save karein');

    final doc = await app.rowsOf(
      'SELECT d.id, d.party_id, d.party_name_snapshot AS from_name, '
      '       d.total_paisa AS total, d.status '
      "FROM documents d WHERE d.doc_type = 'other_income'",
    );
    expect(doc.single['party_id'], isNull, reason: 'never on a khata');
    expect(doc.single['from_name'], 'Kabari Bashir');
    expect(doc.single['total'], 120000);
    expect(find.text('Is mahine'), findsOneWidget);

    await tapText(tester, 'Kabari Bashir');
    await tapButton(tester, 'Mansookh karein');
    await tapText(tester, 'Do baar likh di');
    await tapButton(tester, 'Haan, mansookh karein');
    await settleReal(tester, until: find.textContaining('mansookh ho gaya'));

    final after = await app.rowsOf(
      "SELECT status FROM documents WHERE doc_type = 'other_income'",
    );
    expect(after.single['status'], 'void');
    expect(find.text('Abhi koi deegar aamdani nahi'), findsOneWidget);
    await _expectBooksBalance(app);
  });

  testWidgets('a head of the shop\'s own is added under Heads and used for '
      'an expense', (tester) async {
    final app = await Harness.startWithShop(tester);
    await tapText(tester, 'Kharcha');
    await tester.tap(find.byTooltip('Mad'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kharche ki nayi mad'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Naam', 'Generator diesel');
    await tapButton(tester, 'Save karein');
    expect(find.text('Generator diesel'), findsOneWidget);
    // The "saved" note sits over the bottom of the next screen until it
    // times out, as it would on a phone.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapText(tester, 'Naya kharcha');
    await tapText(tester, 'Generator diesel');
    await typeInto(tester, 'Raqam', '5000');
    await typeInto(tester, 'Kis cheez ke liye', 'Hafte ka diesel');
    await tapButton(tester, 'Kharcha save karein');

    final head = await app.rowsOf(
      'SELECT a.name AS name, a.system_key AS k FROM journal_lines jl '
      'JOIN accounts a ON a.id = jl.account_id '
      'WHERE jl.debit_paisa > 0',
    );
    expect(head.single['name'], 'Generator diesel');
    expect(head.single['k'], isNull);
    expect(find.text('Generator diesel'), findsOneWidget);
    await _expectBooksBalance(app);
  });

  testWidgets('goods taken home come off the shelf from the home\'s side of '
      'the expense screen', (tester) async {
    final app = await Harness.startWithShop(tester);
    final ghee = await app.seedItem(
      name: 'Dalda Ghee',
      rupees: 600,
      openingStock: 10,
    );
    await _openNewExpense(tester);
    await tapText(tester, 'Ghar ka kharcha');
    await tapText(tester, 'Dukaan ka maal ghar le gaye?');
    await typeInto(tester, 'Kaunsa maal', 'Dalda');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tapText(tester, 'Dalda Ghee');
    await typeInto(tester, 'Kitna', '2');
    await tapButton(tester, 'Ghar le gaye, save karein');

    final item = await app.services.queries.itemById(
      app.services.identity!.firmId,
      ghee,
    );
    expect(item!.stockOnHand, Qty.units(8));
    expect(find.textContaining('Ghar le gaye: 2'), findsOneWidget);
    await _expectBooksBalance(app);
  });

  testWidgets('a manager is not offered ghar ka kharcha, and cannot change '
      'one the owner entered', (tester) async {
    final app = await Harness.startWithShop(tester);
    final cash = (await app.services.queries.paymentAccounts(
      app.services.identity!.firmId,
    )).firstWhere((a) => a.isDefault).id;
    await app.services.recordExpense(
      app.services.actorNow(),
      ExpenseDraft(
        accountSystemKey: ownerDrawingsKey,
        amount: const Money.rupees(15000),
        note: 'School fees',
        paymentAccountId: cash,
        forHome: true,
      ),
    );
    await _signIn(tester, app, role: Role.manager, name: 'Nadeem');

    await tapText(tester, 'Kharcha');
    await tapText(tester, 'School fees');
    expect(find.text('Mansookh karein'), findsNothing);
    expect(
      find.text('Ghar ka kharcha sirf malik ya accountant badal sakte hain.'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tapText(tester, 'Naya kharcha');
    expect(find.text('Ghar ka kharcha'), findsNothing);
    expect(find.text('Dukaan ka kiraya'), findsOneWidget);
    // And the service, which is what actually stands in the way.
    await expectLater(
      app.services.shopMoney.takeGoodsHome(
        GoodsTakenHomeDraft(itemId: 'any', qty: Qty.units(1)),
      ),
      throwsA(isA<PermissionDenied>()),
    );
  });

  group('at 200% on a small phone', () {
    setUpAll(loadRealFont);

    testWidgets('the expense, income, heads and monthly bill screens fit', (
      tester,
    ) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      final money = app.services.shopMoney;
      await money.saveMonthlyBill(
        MonthlyBill(
          id: money.newMonthlyBillId(),
          headKey: 'rent',
          amount: const Money.rupees(4000000),
          note: 'Dukaan aur godown ka kiraya, Haji Abdul Rasheed',
          day: 1,
        ),
      );
      final cash = (await app.services.queries.paymentAccounts(
        app.services.identity!.firmId,
      )).firstWhere((a) => a.isDefault).id;
      await money.recordExpense(
        ExpenseDraft(
          accountSystemKey: ownerDrawingsKey,
          amount: const Money.rupees(1250000),
          note: 'Bachon ki school aur tuition fees',
          paymentAccountId: cash,
          forHome: true,
        ),
      );

      await tapText(tester, 'Kharcha');
      _expectNothingPaintsOffScreen(tester);
      await tester.tap(find.text('Naya kharcha'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Ghar ka kharcha');
      _expectNothingPaintsOffScreen(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Deegar aamdani'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nayi aamdani'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Mad'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Mahana bill'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
      await tapText(tester, 'Dukaan aur godown ka kiraya, Haji Abdul Rasheed');
      _expectNothingPaintsOffScreen(tester);
    });
  });
}

Future<void> _openNewExpense(WidgetTester tester) async {
  await tapText(tester, 'Kharcha');
  await tapText(tester, 'Naya kharcha');
}

Future<void> _expectBooksBalance(Harness app) async {
  final totals = await app.rowsOf(
    'SELECT SUM(debit_paisa) AS dr, SUM(credit_paisa) AS cr FROM journal_lines',
  );
  expect(totals.single['dr'], totals.single['cr']);
  final health = await app.services.checkHealth();
  expect(health.findings, isEmpty);
}

/// Locks the app and signs back in as a new member of staff in [role].
Future<void> _signIn(
  WidgetTester tester,
  Harness app, {
  required Role role,
  required String name,
}) async {
  final services = app.services;
  await services.setPin(services.currentUser!.id, '1947');
  await services.addStaff(name: name, role: role, pin: '2468');
  ProviderScope.containerOf(
    tester.element(find.byType(HomeScreen)),
  ).bumpRefresh();
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Taala lagayein'));
  await tester.pumpAndSettle();
  await tapText(
    tester,
    '$name · ${role == Role.manager ? 'Manager' : 'Cashier'}',
  );
  await typeInto(tester, 'PIN', '2468');
  await tapButton(tester, 'Kholein');
}

/// 360x800 dp — an Infinix Smart at its 720x1600 native resolution — with
/// the font at 200%, as `large_text_test.dart` lays the app out.
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

