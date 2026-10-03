import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/features/home/home_screen.dart';
import 'package:bazaar_ledger/features/khata/goods_given.dart';
import 'package:bazaar_ledger/features/khata/statement.dart';
import 'package:bazaar_ledger/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// Goods on the khata now, priced later (M55), driven through the screens
/// against a real database.
///
/// "Das kilo ghee de diya, rate baad mein": the goods leave the shelf on a
/// challan with no rate and nothing is owed; the khata shows them apart from
/// the money; on settlement day the rates are put on from the khata, the
/// bill is made at the counter, and the khata owes exactly the bill.
void main() {
  testWidgets('goods given on the khata with no rate leave the shelf and '
      'owe nothing', (tester) async {
    final app = await Harness.startWithShop(tester);
    final ghee = await app.seedItem(name: 'Desi Ghee', rupees: 600);
    final aslam = await app.seedParty(name: 'Aslam Karyana');

    await _openKhata(tester, 'Aslam Karyana');
    await tapButton(tester, 'Maal diya, rate baad mein');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Cheez talash karein'),
      'Ghee',
    );
    await settleReal(tester, until: find.text('Desi Ghee'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Desi Ghee');
    await typeInto(tester, 'Kitna', '10');
    await tapButton(tester, 'Maal de diya');
    await settleReal(tester, until: find.text('rate baqi'));

    final challan = await app.rowsOf(
      'SELECT doc_type, doc_no, total_paisa, balance_paisa FROM documents',
    );
    expect(challan.single['doc_type'], 'delivery_challan');
    expect(challan.single['total_paisa'], 0);
    expect(challan.single['balance_paisa'], 0);
    final out = await app.scalar<int>(
      "SELECT qty_delta_thousandths FROM stock_ledger WHERE txn_type = 'sale'",
    );
    expect(out, -10000);
    // At what the ghee cost (Rs 360 a piece, 60% of the price, as seeded).
    expect(await _held(app, 'goods_on_challan'), 360000);
    expect(await _owed(app, aslam), Money.zero);

    // On the khata, apart from the money.
    expect(find.text('Maal diya, bill baqi'), findsOneWidget);
    expect(find.text('1 cheez bina rate ke'), findsOneWidget);
    expect(find.text('Desi Ghee · 10 pcs'), findsOneWidget);
    expect(find.text('Koi udhaar baqi nahi'), findsOneWidget);
    expect(await app.countIn('stock_ledger'), 2, reason: 'opening, then out');
    expect(ghee, isNotEmpty);
  });

  testWidgets('rates set on the khata bill the goods at the counter, and the '
      'khata owes exactly the bill', (tester) async {
    final app = await Harness.startWithShop(tester);
    final ghee = await app.seedItem(name: 'Desi Ghee', rupees: 600);
    final aslam = await app.seedParty(name: 'Aslam Karyana');
    await _giveRateLater(app, aslam, ghee, 'Desi Ghee', qty: 10);
    await _giveRateLater(app, aslam, ghee, 'Desi Ghee', qty: 2);

    await _openKhata(tester, 'Aslam Karyana');
    expect(find.text('2 cheezein bina rate ke'), findsOneWidget);
    await tapButton(tester, 'Rate lagayein');
    await settleReal(tester, until: find.text('Counter par bill banayein'));
    // What the counter would charge today, never a blank.
    final rates = find.widgetWithText(TextFormField, 'Rate fi pcs');
    expect(rates, findsNWidgets(2));
    expect(
      tester.widget<TextFormField>(rates.first).controller!.text,
      '600.00',
    );
    // Agreed at Rs 580 on settlement day.
    await tester.enterText(rates.first, '580');
    await tester.enterText(rates.last, '580');
    await tester.pumpAndSettle();
    await tapButton(tester, 'Counter par bill banayein');
    await tester.pumpAndSettle();

    await tapButton(tester, 'Paisay lein');
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Save karein');
    await settleReal(tester, until: find.textContaining('INV-'));

    final bill = await app.rowsOf(
      'SELECT id, total_paisa, balance_paisa FROM documents '
      "WHERE doc_type = 'sale_invoice'",
    );
    expect(bill.single['total_paisa'], 696000);
    expect(bill.single['balance_paisa'], 696000);
    expect(await _owed(app, aslam), const Money.rupees(6960));
    expect(
      await app.scalar<int>(
        'SELECT COUNT(*) FROM doc_links WHERE to_document_id = '
        "'${bill.single['id']}'",
      ),
      2,
      reason: 'both challans on the one bill',
    );
    expect(await _held(app, 'goods_on_challan'), 0);
    expect(await app.countIn('stock_ledger'), 3, reason: 'no second exit');
    expect(
      await app.services.collections.unpricedParties(),
      isEmpty,
      reason: 'nothing waits for a rate any more',
    );
    final health = await app.services.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  });

  testWidgets('a rate left blank is asked for before anything goes to the '
      'counter', (tester) async {
    final app = await Harness.startWithShop(tester);
    final ghee = await app.seedItem(name: 'Desi Ghee', rupees: 600);
    final aslam = await app.seedParty(name: 'Aslam Karyana');
    await _giveRateLater(app, aslam, ghee, 'Desi Ghee', qty: 10);

    await _openKhata(tester, 'Aslam Karyana');
    await tapButton(tester, 'Rate lagayein');
    await settleReal(tester, until: find.text('Counter par bill banayein'));
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Rate fi pcs'),
      '',
    );
    await tester.pumpAndSettle();
    await tapButton(tester, 'Counter par bill banayein');

    expect(find.text('Desi Ghee ka rate likhein.'), findsOneWidget);
    expect(await app.countIn('documents'), 1, reason: 'the challan alone');
  });

  testWidgets('the counter hands goods over rate later', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Desi Ghee', rupees: 600);
    final aslam = await app.seedParty(name: 'Aslam Karyana');

    await tester.pumpAndSettle();
    await tapText(tester, 'Naya Bill');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Talash karein').first,
      'Ghee',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Paisay lein');
    await tapText(tester, 'Aam gahak');
    await tapText(tester, 'Aslam Karyana');
    await tapButton(tester, 'Rate baad mein (maal de diya)');

    final challan = await app.rowsOf(
      'SELECT doc_type, doc_no, total_paisa, balance_paisa FROM documents',
    );
    expect(challan.single['doc_type'], 'delivery_challan');
    expect(challan.single['total_paisa'], 0);
    expect(
      find.text('Maal likh liya: ${challan.single['doc_no']}, rate baad mein'),
      findsOneWidget,
    );
    expect(await _owed(app, aslam), Money.zero);
    final lines = await app.rowsOf(
      'SELECT rate_milli_paisa FROM document_lines',
    );
    expect(lines.single['rate_milli_paisa'], 0);
  });

  testWidgets('the chase list and the statement say what has no rate yet', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final ghee = await app.seedItem(name: 'Desi Ghee', rupees: 600);
    final aslam = await app.seedParty(name: 'Aslam Karyana');
    // A bill on udhaar, so he is on the chase list.
    await app.services.postSale(
      app.services.actorNow(),
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: ghee,
            itemName: 'Desi Ghee',
            qty: Qty.units(5),
            baseQty: Qty.units(5),
            unitCode: 'pcs',
            rate: Rate.rupees(600),
          ),
        ],
        partyId: aslam,
        partyName: 'Aslam Karyana',
      ),
    );
    await _giveRateLater(app, aslam, ghee, 'Desi Ghee', qty: 10);
    // A household that owes nothing in money and still holds goods.
    final bilal = await app.seedParty(name: 'Bilal Ghar');
    await _giveRateLater(app, bilal, ghee, 'Desi Ghee', qty: 3);

    await _home(tester);
    await tapText(tester, 'Gahak');
    await tester.tap(find.byTooltip('Udhaar wasooli'));
    await tester.pumpAndSettle();

    expect(find.text('Rate baqi: 2 gahak, 2 cheezein'), findsOneWidget);
    // On Aslam's row, below the summary.
    await tester.scrollUntilVisible(
      find.text('1 cheez bina rate ke'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('1 cheez bina rate ke'), findsOneWidget, reason: 'Aslam');
    await tester.scrollUntilVisible(
      find.text('Rate baqi: 2 gahak, 2 cheezein'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tapText(tester, 'Rate baqi: 2 gahak, 2 cheezein');
    await tapText(tester, 'Bilal Ghar');
    expect(find.text('Maal diya, bill baqi'), findsOneWidget);

    final party = (await app.services.queries.partyById(
      app.services.identity!.firmId,
      aslam,
    ))!;
    final s = AppStrings.of(tester.element(find.byType(Scaffold).last));
    final table = await statementFor(
      app.services,
      party,
      span: StatementSpan.all,
      owedToUs: true,
      unpriced: unpricedNotes(
        s,
        await app.services.collections.goodsGivenTo(aslam),
      ),
    );
    expect(
      table.notes.last,
      startsWith(
        'Maal diya, rate baqi (1), is hisaab mein shamil nahi: '
        'Desi Ghee 10 pcs (CHL-',
      ),
    );
  });

  _smallPhone();
}

/// The khata's card and the rates sheet on the smallest phone, the font all
/// the way up (as large_text_test lays the app out).
void _smallPhone() {
  testWidgets('at 200% on a small phone goods given, and their rates, fit', (
    tester,
  ) async {
    await tester.runAsync(loadRealFont);
    tester.view
      ..physicalSize = const Size(720, 1600)
      ..devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final app = await Harness.startWithShop(tester);
    final ghee = await app.seedItem(name: 'Desi Ghee Pure 16 kg', rupees: 600);
    final aslam = await app.seedParty(name: 'Aslam Karyana General Store');
    await _giveRateLater(app, aslam, ghee, 'Desi Ghee Pure 16 kg', qty: 10);

    await _openKhata(tester, 'Aslam Karyana General Store');
    await tester.ensureVisible(find.text('Maal diya, bill baqi'));
    await tester.pumpAndSettle();
    _expectNothingOffScreen(tester);
    await tapButton(tester, 'Rate lagayein');
    await settleReal(tester, until: find.text('Counter par bill banayein'));
    await tester.pumpAndSettle();
    _expectNothingOffScreen(tester);
  });
}

void _expectNothingOffScreen(WidgetTester tester) {
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
      reason: '"${(element.widget as Text).data}" runs off the screen',
    );
    expect(left, greaterThanOrEqualTo(-0.5));
  }
}


Future<void> _giveRateLater(
  Harness app,
  String partyId,
  String itemId,
  String name, {
  required int qty,
}) async {
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');
  final party = await app.services.queries.partyById(firm, partyId);
  await app.services.collections.giveRateLater(
    SaleDraft(
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: name,
          qty: Qty.units(qty),
          baseQty: Qty.units(qty),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.zero,
        ),
      ],
      partyId: partyId,
      partyName: party!.name,
    ),
  );
}

Future<Money> _owed(Harness app, String partyId) async =>
    (await app.services.queries.partyById(
      app.services.identity!.firmId,
      partyId,
    ))!.balance;

Future<int> _held(Harness app, String systemKey) async =>
    await app.scalar<int>(
      'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) '
      'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      "WHERE a.system_key = '$systemKey'",
    ) ??
    0;

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
