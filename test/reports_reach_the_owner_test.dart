import 'dart:io';

import 'package:bazaar_ledger/features/reports/report_shelf.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/harness.dart';

/// The report pack, from the screen.
///
/// Until M8 the only figures the app could show were a day's takings and one
/// customer's balance. The owner's question at the end of the month, did I
/// make money and where did it go, had no answer on the phone at all.
final _sheet = _FakeShareSheet();

void main() {
  setUpAll(() => SharePlatform.instance = _sheet);
  setUp(_sheet.paths.clear);

  testWidgets("this month's profit is on the phone", (tester) async {
    final app = await Harness.startWithShop(tester, overrides: _ownShelf());
    await _aDayOfTrade(app);

    await tapText(tester, 'Report');
    await tapText(tester, 'Nafa nuqsan');

    // Rs 2,500 sold of goods that cost Rs 1,500, less Rs 500 of rent.
    expect(find.text('Gross profit'), findsOneWidget);
    expect(find.text('1,000.00'), findsOneWidget);
    expect(find.text('Net profit'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
  });

  testWidgets('last month shows nothing earned this month', (tester) async {
    final app = await Harness.startWithShop(tester, overrides: _ownShelf());
    await _aDayOfTrade(app);

    await tapText(tester, 'Report');
    await tapText(tester, 'Nafa nuqsan');
    await tapText(tester, 'Pichla mahina');

    expect(find.text('Rent'), findsNothing);
    expect(find.text('1,000.00'), findsNothing);
  });

  testWidgets('a report goes out as a CSV the accountant can open', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester, overrides: _ownShelf());
    await _aDayOfTrade(app);

    await tapText(tester, 'Report');
    await tapText(tester, 'Nafa nuqsan');
    await tester.tap(find.byTooltip('CSV bhejein'));
    await settleReal(tester, done: () => _sheet.paths.isNotEmpty);

    final csv = File(_sheet.paths.single).readAsStringSync();
    expect(_sheet.paths.single, endsWith('.csv'));
    expect(csv, contains('Profit and Loss'));
    expect(csv, contains('Net profit,500.00'));
  });

  testWidgets('a report goes out as a PDF headed with the shop', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester, overrides: _ownShelf());
    await _aDayOfTrade(app);

    await tapText(tester, 'Report');
    await tapText(tester, 'Nafa nuqsan');
    await tester.tap(find.byTooltip('PDF bhejein'));
    await settleReal(tester, done: () => _sheet.paths.isNotEmpty);

    expect(_sheet.paths.single, endsWith('.pdf'));
    final bytes = File(_sheet.paths.single).readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  testWidgets('stock value is as of now and lists the shelf', (tester) async {
    final app = await Harness.startWithShop(tester, overrides: _ownShelf());
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500, openingStock: 12);

    await tapText(tester, 'Report');
    await tapText(tester, 'Stock ki qeemat');

    expect(find.text('Abhi tak'), findsOneWidget);
    expect(find.text('Cooking Oil 5L'), findsOneWidget);
    expect(find.text('Pichla mahina'), findsNothing);
  });

  testWidgets('udhaar by age is as of now and lists who owes', (tester) async {
    final app = await Harness.startWithShop(tester, overrides: _ownShelf());
    await app.seedParty(name: 'Rashid Traders', owedRupees: 4500);

    await tapText(tester, 'Report');
    // The last report on the list, below the fold on a phone.
    await tester.scrollUntilVisible(find.text('Udhaar kitna purana'), 200);
    await tapText(tester, 'Udhaar kitna purana');

    expect(find.text('Abhi tak'), findsOneWidget);
    expect(find.text('Rashid Traders'), findsOneWidget);
    expect(find.text('4,500.00'), findsWidgets);
  });

  testWidgets('what is owed to suppliers is on its own page', (tester) async {
    final app = await Harness.startWithShop(tester, overrides: _ownShelf());
    final supplier = await app.services.catalogue.addParty(
      app.services.actorNow(),
      const PartyDraft(name: 'Malik Property', partyType: 'supplier'),
    );
    await app.services.recordExpense(
      app.services.actorNow(),
      ExpenseDraft(
        accountSystemKey: 'utilities',
        amount: const Money.rupees(700),
        note: 'Bijli ka bill',
        partyId: supplier,
      ),
    );

    await tapText(tester, 'Report');
    await tester.scrollUntilVisible(find.text('Suppliers ka baqi'), 200);
    await tapText(tester, 'Suppliers ka baqi');

    expect(find.text('Malik Property'), findsOneWidget);
    expect(find.text('700.00'), findsWidgets);
  });

  testWidgets('sales by day shows the day the bill was rung', (tester) async {
    final app = await Harness.startWithShop(tester, overrides: _ownShelf());
    await _aDayOfTrade(app);

    await tapText(tester, 'Report');
    await tapText(tester, 'Roz ki bikri');

    final today = BusinessDate.now(app.services.clock).value;
    expect(find.text(today), findsOneWidget);
    expect(find.text('2,500.00'), findsWidgets);
  });
}

/// A cash sale of Rs 2,500, of goods the harness stocks at Rs 1,500, and
/// Rs 500 of rent paid from the drawer.
Future<void> _aDayOfTrade(Harness app) async {
  final oil = await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
  final services = app.services;
  final firm = (await services.queries.currentFirm())!;
  final item = (await services.queries.itemById(firm.id, oil))!;
  final cash = (await services.queries.paymentAccounts(
    firm.id,
  )).firstWhere((a) => a.modeLabel == 'cash');
  await services.postSale(
    services.actorNow(),
    SaleDraft(
      lines: [
        SaleLineDraft(
          itemId: oil,
          itemName: item.name,
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitId: item.unitId,
          unitCode: 'pcs',
          rate: Rate.rupees(2500),
        ),
      ],
      tenders: [
        TenderDraft(
          paymentAccountId: cash.id,
          mode: 'cash',
          amount: const Money.rupees(2500),
        ),
      ],
    ),
  );
  await services.recordExpense(
    services.actorNow(),
    ExpenseDraft(
      accountSystemKey: 'rent',
      amount: const Money.rupees(500),
      note: 'Shutter rent',
      paymentAccountId: cash.id,
    ),
  );
}

/// A shelf of its own for each test (M33). The phone remembers the period
/// each report was last read for, and one test choosing last month must not
/// open the next test's report on last month.
List<Override> _ownShelf() => [
  reportShelfDirectoryProvider.overrideWith(
    (ref) async => Directory.systemTemp.createTempSync('report_shelf'),
  ),
];

final class _FakeShareSheet extends SharePlatform {
  final paths = <String>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    paths.addAll((params.files ?? const []).map((f) => f.path));
    return const ShareResult('ok', ShareResultStatus.success);
  }
}
