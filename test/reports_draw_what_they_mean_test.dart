import 'dart:async';
import 'dart:io';

import 'package:bazaar_ledger/app/preferences.dart';
import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/design/tokens.dart';
import 'package:bazaar_ledger/features/reports/report_chart_view.dart';
import 'package:bazaar_ledger/features/reports/report_registry.dart';
import 'package:bazaar_ledger/features/reports/report_screen.dart';
import 'package:bazaar_ledger/features/reports/report_shelf.dart';
import 'package:bazaar_ledger/features/reports/report_table_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// The reports drawn (M46) and the money owed both ways (M58), from the
/// screen: today's figures on the hub, a report turned from a table into a
/// chart and back, the ring of udhaar by how late it is, every loan and one
/// loan's statement, and all of it on a 360dp phone at 200% text, in Roman
/// Urdu and in English, in the light and in the dark.
void main() {
  testWidgets('the hub shows today\'s figures, and they open the Z report', (
    tester,
  ) async {
    final app = await Harness.startWithShop(
      tester,
      overrides: _shelfAt(_shelfDirectory()),
    );
    await _sellForCash(app, 'Cooking Oil 5L', 2500);
    await tapText(tester, 'Report');

    expect(find.text('Aaj'), findsOneWidget);
    expect(find.text('Bikri'), findsOneWidget);
    expect(find.text('Wasool'), findsOneWidget);
    expect(find.text('Udhaar diya'), findsOneWidget);
    expect(find.text('Maal ka nafa'), findsOneWidget, reason: 'the owner');
    expect(find.textContaining('2,500.00'), findsWidgets);

    await tester.tap(find.text('Aaj'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportScreen), findsOneWidget);
    expect(find.text('Din ka khulasa (Z report)'), findsOneWidget);
  });

  testWidgets('a report that declares a chart turns from its table into a '
      'chart and back', (tester) async {
    final app = await Harness.startWithShop(
      tester,
      overrides: _shelfAt(_shelfDirectory()),
    );
    await _sellForCash(app, 'Cooking Oil 5L', 2500);
    await _sellForCash(app, 'Surf Excel 1kg', 650);
    await tapText(tester, 'Report');
    await tapText(tester, 'Cheez-war bikri');

    expect(find.byType(ReportTableView), findsOneWidget);
    await tester.tap(find.text('Chart'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportChartView), findsOneWidget);
    expect(find.byType(ReportTableView), findsNothing);
    expect(find.text('Cooking Oil 5L'), findsOneWidget);
    expect(find.text('Surf Excel 1kg'), findsOneWidget);
    expect(find.textContaining('Rs 2,500.00'), findsWidgets);

    await tester.tap(find.text('Table'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportTableView), findsOneWidget);

    // A report that reads only as a table offers no chart.
    await tester.pageBack();
    await tester.pumpAndSettle();
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const ReportScreen(kind: ReportKind.dayBook),
            ),
          ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Roznamcha'), findsOneWidget);
    expect(find.byType(ReportTableView), findsOneWidget);
    expect(find.text('Chart'), findsNothing);
  });

  testWidgets('every report that declares a chart draws one off its own '
      'table', (tester) async {
    final app = await Harness.startWithShop(
      tester,
      overrides: _shelfAt(_shelfDirectory()),
    );
    await _sellForCash(app, 'Cooking Oil 5L', 2500);
    await _sellOnUdhaar(app, 'Akbar', 1200);
    final firm = (await app.services.queries.currentFirm())!;
    final today = BusinessDate.now(app.services.clock);
    final charted = [
      for (final e in reportRegistry)
        if (e.chart != null) e,
    ];
    expect(charted.length, greaterThanOrEqualTo(9));
    for (final e in charted) {
      final table = await tester.runAsync(
        () => app.services.reports.run(
          e.kind,
          firmId: firm.id,
          period: ReportPeriod.day(today),
          today: today,
        ),
      );
      final chart = chartOf(table!, e.chart!);
      expect(chart, isNotNull, reason: '${e.kind} names a column it lacks');
    }
  });

  testWidgets('udhaar by due date draws a ring with every bucket named', (
    tester,
  ) async {
    final app = await Harness.startWithShop(
      tester,
      overrides: _shelfAt(_shelfDirectory()),
    );
    await _sellOnUdhaar(app, 'Akbar', 1200);
    await tapText(tester, 'Report');
    await tapText(tester, 'Udhaar, adaigi ki tareekh se');
    expect(find.text('Akbar'), findsOneWidget);

    await tester.tap(find.text('Chart'));
    await tester.pumpAndSettle();
    for (final bucket in dueBucketColumns) {
      expect(find.text(bucket), findsOneWidget);
    }
    expect(find.text('Rs 1,200.00 · 100.00%'), findsOneWidget);
    expect(find.text('Kul'), findsOneWidget);
  });

  testWidgets('the loan statement lists every loan, and a loan opens its '
      'own statement', (tester) async {
    final app = await Harness.startWithShop(
      tester,
      overrides: _shelfAt(_shelfDirectory()),
    );
    await _borrow(app);
    await tapText(tester, 'Report');
    await tester.scrollUntilVisible(find.text('QARZ KE KHATE'), 300);
    await tapText(tester, 'Qarz ka hisaab');
    expect(find.text('Loan from Meezan Bank'), findsOneWidget);
    expect(find.text('Meezan Bank'), findsOneWidget);

    await tester.tap(find.text('Loan from Meezan Bank'));
    await tester.pumpAndSettle();
    expect(find.text('Qarz: Loan from Meezan Bank'), findsOneWidget);
    expect(find.text('Loan received'), findsOneWidget);
  });

  testWidgets('changed and cancelled bills narrow to an amount or more, and '
      'say what each change was before', (tester) async {
    final app = await Harness.startWithShop(
      tester,
      overrides: _shelfAt(_shelfDirectory()),
    );
    final services = app.services;
    for (final rupees in [300, 4000]) {
      await _sellForCash(app, 'Bill of Rs $rupees', rupees);
    }
    final bills = await services.database
        .customSelect(
          "SELECT id FROM documents WHERE doc_type = 'sale_invoice' "
          'ORDER BY total_paisa',
        )
        .get();
    for (final b in bills) {
      await services.voidDocument(
        services.actorNow(),
        documentId: b.read<String>('id'),
        reason: 'Galti se',
      );
    }
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => const ReportScreen(kind: ReportKind.changedBills),
            ),
          ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Was'), findsOneWidget);
    expect(find.text('Allowed by'), findsOneWidget);
    expect(find.text('Voided'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(ActionChip, 'Raqam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rs 1,000.00 ya ziyada'));
    await tester.pumpAndSettle();
    expect(find.text('Raqam: Rs 1,000.00 ya ziyada'), findsOneWidget);
    expect(find.text('Voided'), findsOneWidget);
    expect(find.text('4,000.00'), findsWidgets);
  });

  group('at 200% on a small phone', () {
    setUpAll(loadRealFont);

    testWidgets('the hub with today\'s figures, and every kind of chart, fit', (
      tester,
    ) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(
        tester,
        overrides: _shelfAt(_shelfDirectory()),
      );
      await _shopWithAWeek(app);
      await tapText(tester, 'Report');
      _expectNothingPaintsOffScreen(tester);

      for (final kind in [
        ReportKind.salesByDay,
        ReportKind.salesByItem,
        ReportKind.paymentModes,
        ReportKind.receivablesByDueDate,
        ReportKind.hourlySales,
      ]) {
        await _openChart(tester, kind);
        _expectNothingPaintsOffScreen(tester);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('and in English, in the dark', (tester) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(
        tester,
        overrides: [
          ..._shelfAt(_shelfDirectory()),
          initialPreferencesProvider.overrideWithValue(
            AppPreferences(
              locale: const Locale('en'),
              themeMode: ThemeMode.dark,
            ),
          ),
        ],
      );
      await _shopWithAWeek(app);
      await tapText(tester, 'Reports');
      expect(find.text('Today'), findsOneWidget);
      _expectNothingPaintsOffScreen(tester);

      for (final kind in [
        ReportKind.salesByItem,
        ReportKind.paymentModes,
        ReportKind.receivablesByDueDate,
      ]) {
        await _openChart(tester, kind, chart: 'Chart');
        final tokens = Theme.of(
          tester.element(find.byType(ReportChartView)),
        ).extension<BlTokens>()!;
        expect(tokens.isDark, isTrue);
        expect(tokens.chartSeries, BlTokens.dark.chartSeries);
        _expectNothingPaintsOffScreen(tester);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    });
  });
}

/// Opens [kind]'s screen straight from the home screen, and its chart.
Future<void> _openChart(
  WidgetTester tester,
  ReportKind kind, {
  String chart = 'Chart',
}) async {
  unawaited(
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(builder: (_) => ReportScreen(kind: kind)),
        ),
  );
  await tester.pumpAndSettle();
  final toggle = find.text(chart);
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
  expect(find.byType(ReportChartView), findsOneWidget, reason: '$kind');
}

/// Twelve items with the long names a wholesaler gives them, sold for cash
/// and by JazzCash, and two customers on udhaar: enough for every chart to
/// have a top ten, a rest, several slices and several buckets.
Future<void> _shopWithAWeek(Harness app) async {
  for (var i = 1; i <= 12; i++) {
    await _sellForCash(
      app,
      'Chaudhry Brand Basmati Chawal Super Kernel 25kg Bori No. $i',
      1000 * i + 123456,
    );
  }
  await _sellOnUdhaar(app, 'Chaudhry Muhammad Aslam Karyana Store', 98765);
  await _sellOnUdhaar(app, 'Akbar', 1200);
}

Future<void> _sellForCash(Harness app, String name, int rupees) async {
  final services = app.services;
  final firm = (await services.queries.currentFirm())!;
  final itemId = await app.seedItem(name: name, rupees: rupees);
  final item = (await services.queries.itemById(firm.id, itemId))!;
  final accounts = await services.queries.paymentAccounts(firm.id);
  final cash = accounts.firstWhere((a) => a.modeLabel == 'cash');
  await services.postSale(
    services.actorNow(),
    SaleDraft(
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: item.name,
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitId: item.unitId,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
        ),
      ],
      tenders: [
        TenderDraft(
          paymentAccountId: cash.id,
          mode: 'cash',
          amount: Money.rupees(rupees),
        ),
      ],
    ),
  );
}

Future<void> _sellOnUdhaar(Harness app, String who, int rupees) async {
  final services = app.services;
  final firm = (await services.queries.currentFirm())!;
  final party = await app.seedParty(name: who);
  final itemId = await app.seedItem(
    name: 'Ghee 16kg tin for $who',
    rupees: rupees,
  );
  final item = (await services.queries.itemById(firm.id, itemId))!;
  await services.postSale(
    services.actorNow(),
    SaleDraft(
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: item.name,
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitId: item.unitId,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
        ),
      ],
      partyId: party,
      partyName: who,
    ),
  );
}

Future<void> _borrow(Harness app) async {
  final services = app.services;
  final firm = (await services.queries.currentFirm())!;
  final accounts = await services.queries.paymentAccounts(firm.id);
  final bank = accounts.firstWhere((a) => a.modeLabel == 'bank_transfer');
  await services.loans.take(
    LoanDraft(
      lender: 'Meezan Bank',
      amount: const Money.rupees(500000),
      intoPaymentAccountId: bank.id,
      takenOn: BusinessDate.now(services.clock),
    ),
  );
}

Directory _shelfDirectory() =>
    Directory.systemTemp.createTempSync('report_shelf');

List<Override> _shelfAt(Directory dir) => [
  reportShelfDirectoryProvider.overrideWith((ref) async => dir),
];

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

/// Every rendered piece of text still inside the screen it was drawn on,
/// and nothing overflowed.
void _expectNothingPaintsOffScreen(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  for (final element in find.byType(Text).evaluate()) {
    final box = element.renderObject! as RenderBox;
    if (!box.hasSize || box.size.isEmpty) continue;
    final left = box.localToGlobal(Offset.zero).dx;
    final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
    // Text inside a sideways-scrolling table is meant to run past the edge.
    final scrolls = find
        .ancestor(
          of: find.byWidget(element.widget),
          matching: find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          ),
        )
        .evaluate()
        .isNotEmpty;
    if (scrolls) continue;
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

