import 'dart:async';
import 'dart:io';

import 'package:bazaar_ledger/features/reports/report_chart_view.dart';
import 'package:bazaar_ledger/features/reports/report_export.dart';
import 'package:bazaar_ledger/features/reports/report_screen.dart';
import 'package:bazaar_ledger/features/reports/report_shelf.dart';
import 'package:bazaar_ledger/features/reports/report_table_view.dart';
import 'package:bazaar_ledger/features/reports/saved_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// The reports an accountant and an owner reach for next (M67), from the
/// screen: a table the shop arranges (columns shown, hidden and moved,
/// remembered for the report on this phone and kept in a saved view; a
/// filter on any column) and every export carrying it; the ageing buckets
/// the shop sets, with the ring following them; last period drawn behind a
/// trend; and the new reports — ratios, Dhyan dein, ABC — on a 360dp phone
/// at 200% text.
void main() {
  testWidgets('the columns a shop hides and moves stay so for the report on '
      'this phone, and every export carries them', (tester) async {
    final dir = _shelfDirectory();
    final sent = <ReportTable>[];
    final app = await Harness.startWithShop(
      tester,
      overrides: [..._shelfAt(dir), _capture(sent)],
    );
    final rashid = await app.seedParty(name: 'Rashid Traders');
    await _sell(
      app,
      'Cooking Oil 5L',
      2500,
      partyId: rashid,
      who: 'Rashid Traders',
    );
    await _sell(app, 'Surf 1kg', 650);

    await _open(tester, ReportKind.saleReport);
    expect(_columns(tester), contains('Party'));
    await tester.tap(find.byTooltip('Columns'));
    await tester.pumpAndSettle();
    await _untick(tester, 'Party');
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('Total upar'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Ho gaya'));
    await tester.pumpAndSettle();

    expect(_columns(tester), isNot(contains('Party')));
    expect(_columns(tester).sublist(0, 3), ['Date', 'Total', 'Bill']);
    expect(
      ReportShelf.loadFrom(dir).columnsFor(ReportKind.saleReport).hidden,
      {'Party'},
      reason: 'kept for the report on the phone',
    );

    await tester.tap(find.byTooltip('CSV bhejein'));
    await tester.pumpAndSettle();
    expect(sent.single.columns.map((c) => c.title), _columns(tester));
    expect(sent.single.columns.map((c) => c.title), isNot(contains('Party')));

    // Opened again, the report is still arranged so.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _open(tester, ReportKind.saleReport);
    expect(_columns(tester), isNot(contains('Party')));

    // And put back as it was built, it is forgotten.
    await tester.tap(find.byTooltip('Columns'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sab columns, asal tarteeb mein'));
    await tester.pumpAndSettle();
    expect(_columns(tester), contains('Party'));
    expect(
      ReportShelf.loadFrom(dir).columnsFor(ReportKind.saleReport),
      TableArrangement.none,
    );
  });

  testWidgets('a column filter keeps the rows that match, adds up what they '
      'come to, leaves the total alone, and the export says so', (
    tester,
  ) async {
    final sent = <ReportTable>[];
    final app = await Harness.startWithShop(
      tester,
      overrides: [..._shelfAt(_shelfDirectory()), _capture(sent)],
    );
    final rashid = await app.seedParty(name: 'Rashid Traders');
    await _sell(
      app,
      'Cooking Oil 5L',
      2500,
      partyId: rashid,
      who: 'Rashid Traders',
    );
    await _sell(app, 'Surf 1kg', 650);

    await _open(tester, ReportKind.saleReport);
    await tester.tap(find.byTooltip('Column par filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Party').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'rashid');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lagayein'));
    await tester.pumpAndSettle();

    expect(find.text('Party: "rashid"'), findsOneWidget);
    final shown = _table(tester);
    expect(
      shown.rows.map((r) => r.cells[2]),
      ['Rashid Traders', null, null],
      reason: 'his bill, what it comes to, and the whole total',
    );
    expect(shown.rows[1].cells[0], 'Shown rows (1 of 2)');
    expect(shown.rows[1].cells[3], const Money.rupees(2500));
    expect(shown.rows[2].cells[3], const Money.rupees(3150));
    expect(find.text('Shown rows (1 of 2)'), findsOneWidget);

    await tester.tap(find.byTooltip('CSV bhejein'));
    await tester.pumpAndSettle();
    expect(sent.single.filters, contains('Party contains "rashid"'));
    expect(sent.single.rows, hasLength(3));

    // A figure: bills of Rs 1,000 or more.
    await tester.tap(find.byTooltip('Hatayein'));
    await tester.pumpAndSettle();
    expect(
      _table(tester).rows,
      hasLength(3),
      reason: 'both bills and the total',
    );
    await tester.tap(find.byTooltip('Column par filter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Total').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '1000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lagayein'));
    await tester.pumpAndSettle();
    expect(find.text('Total ≥ Rs 1,000.00'), findsOneWidget);
    expect(_table(tester).rows.first.cells[3], const Money.rupees(2500));
    expect(_table(tester).rows, hasLength(3));
  });

  testWidgets('a saved view keeps the table as the shop arranged it', (
    tester,
  ) async {
    final dir = _shelfDirectory();
    final app = await Harness.startWithShop(tester, overrides: _shelfAt(dir));
    await _sell(app, 'Cooking Oil 5L', 2500);
    await _open(tester, ReportKind.saleReport);
    await tester.tap(find.byTooltip('Columns'));
    await tester.pumpAndSettle();
    await _untick(tester, 'Date');
    await tester.tap(find.text('Ho gaya'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Yeh view save karein'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save karein'));
    await tester.pumpAndSettle();

    final views = SavedViewsFile.loadFrom(dir);
    expect(views.single.arrangement.hidden, {'Date'});

    // Opened from the view on another visit, after the phone forgot it.
    ProviderScope.containerOf(tester.element(find.byType(ReportScreen)))
        .read(reportShelfProvider.notifier)
        .rememberColumns(ReportKind.saleReport, TableArrangement.none);
    await tester.pageBack();
    await tester.pumpAndSettle();
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ReportScreen(kind: ReportKind.saleReport, view: views.single),
            ),
          ),
    );
    await tester.pumpAndSettle();
    expect(_columns(tester), isNot(contains('Date')));
  });

  testWidgets('the ageing buckets the shop sets cut Udhaar by age and by '
      'due date, and the ring follows them', (tester) async {
    final dir = _shelfDirectory();
    final app = await Harness.startWithShop(tester, overrides: _shelfAt(dir));
    final akbar = await app.seedParty(name: 'Akbar');
    await _sell(app, 'Ghee 16kg', 1200, partyId: akbar, who: 'Akbar');

    await _open(tester, ReportKind.receivables);
    expect(_columns(tester), contains('0-30 days'));
    await tester.tap(find.text('Hisse: 0-30 / 31-60 / 61-90 / 90+ din'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '15, 45');
    await tester.pumpAndSettle();
    expect(find.text('Hisse: 0-15 / 16-45 / 45+ din'), findsOneWidget);
    await tester.tap(find.text('Save karein'));
    await tester.pumpAndSettle();
    expect(
      _columns(tester),
      containsAll(['0-15 days', '16-45 days', 'Over 45 days']),
    );
    expect(ReportShelf.loadFrom(dir).ageing, const AgeingBuckets([15, 45]));

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _open(tester, ReportKind.receivablesByDueDate);
    expect(find.text('Hisse: 0-15 / 16-45 / 45+ din'), findsOneWidget);
    await tester.tap(find.text('Chart'));
    await tester.pumpAndSettle();
    for (final bucket in [
      'Not yet due',
      '1-15 days late',
      '16-45 days late',
      'Over 45 days late',
    ]) {
      expect(find.text(bucket), findsOneWidget, reason: bucket);
    }
    expect(find.text('Rs 1,200.00 · 100.00%'), findsOneWidget);
  });

  testWidgets('a trend is drawn over the period before, each with its '
      'total', (tester) async {
    final app = await Harness.startWithShop(
      tester,
      overrides: _shelfAt(_shelfDirectory()),
      clock: FixedClock(DateTime.utc(2026, 10, 3, 6)),
    );
    await _sell(app, 'Cooking Oil 5L', 2500);
    await _sell(app, 'Atta 10kg', 1100, on: DateTime.utc(2026, 9, 2, 6));

    await _open(tester, ReportKind.salesByDay);
    await tester.tap(find.text('Chart'));
    await tester.pumpAndSettle();
    final chart = tester.widget<ReportChartView>(find.byType(ReportChartView));
    expect(chart.chart.comparesPrevious, isTrue);
    expect(
      chart.chart.previous[1],
      const Money.rupees(1100),
      reason: 'the 2nd of September under the 2nd of October',
    );
    expect(find.text('Yeh arsa: Rs 2,500.00'), findsOneWidget);
    expect(find.text('Pichla arsa: Rs 1,100.00'), findsOneWidget);
  });

  testWidgets('the shelf is valued at its sale price on a tap, and says the '
      'books are at cost', (tester) async {
    final app = await Harness.startWithShop(
      tester,
      overrides: _shelfAt(_shelfDirectory()),
    );
    await app.seedItem(name: 'Cheeni 1kg', rupees: 160, openingStock: 10);
    await _open(tester, ReportKind.stockSummary);
    await tester.tap(find.widgetWithText(ActionChip, 'Qeemat kis par'));
    await tester.pumpAndSettle();
    expect(
      find.text('Laagat par (khaata)'),
      findsOneWidget,
      reason: 'the owner',
    );
    await tester.tap(find.text('Bechne ki qeemat'));
    await tester.pumpAndSettle();
    expect(find.text('Qeemat kis par: Bechne ki qeemat'), findsOneWidget);
    final table = _table(tester);
    expect(table.rows.last.cells.last, const Money.rupees(1600));
    expect(
      find.textContaining('Only the value at cost is Inventory in the books'),
      findsOneWidget,
    );
  });

  group('at 200% on a small phone', () {
    setUpAll(loadRealFont);

    testWidgets('the ratios, Dhyan dein, ABC, the chooser, a column filter '
        'and the buckets all fit', (tester) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(
        tester,
        overrides: _shelfAt(_shelfDirectory()),
      );
      final akbar = await app.seedParty(
        name: 'Chaudhry Muhammad Aslam Karyana Store',
      );
      await _sell(
        app,
        'Chaudhry Brand Basmati Chawal Super Kernel 25kg Bori',
        98765,
        partyId: akbar,
        who: 'Chaudhry Muhammad Aslam Karyana Store',
      );
      await _sell(app, 'Cooking Oil 5L', 2500);

      for (final kind in [
        ReportKind.ratioAnalysis,
        ReportKind.needsAttention,
        ReportKind.abcClassification,
      ]) {
        await _open(tester, kind);
        expect(find.byType(ReportTableView), findsOneWidget, reason: '$kind');
        _expectNothingPaintsOffScreen(tester);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      await _open(tester, ReportKind.receivables);
      _expectNothingPaintsOffScreen(tester);
      await tester.tap(find.byTooltip('Columns'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
      await tester.tap(find.text('Ho gaya'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Column par filter'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Customer').last);
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Hisse:'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
    });
  });
}

/// The column titles the table on screen shows, in order.
List<String> _columns(WidgetTester tester) => [
  for (final c in _table(tester).columns) c.title,
];

ReportTable _table(WidgetTester tester) =>
    tester.widget<ReportTableView>(find.byType(ReportTableView)).table;

/// Unticks [column] in the open column chooser.
Future<void> _untick(WidgetTester tester, String column) async {
  final row = find.ancestor(
    of: find.descendant(
      of: find.byType(BottomSheet),
      matching: find.text(column),
    ),
    matching: find.byType(Row),
  );
  await tester.tap(
    find.descendant(of: row.first, matching: find.byType(Checkbox)),
  );
  await tester.pumpAndSettle();
}

/// Opens [kind]'s screen straight from the home screen.
Future<void> _open(WidgetTester tester, ReportKind kind) async {
  unawaited(
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(builder: (_) => ReportScreen(kind: kind)),
        ),
  );
  await tester.pumpAndSettle();
}

/// Reads what would have been shared, in place of the share sheet.
Override _capture(List<ReportTable> sent) => reportSharerProvider
    .overrideWithValue((table, format, {required String shopName}) async {
      sent.add(table);
    });

Future<void> _sell(
  Harness app,
  String name,
  int rupees, {
  String? partyId,
  String? who,
  DateTime? on,
}) async {
  final services = app.services;
  final firm = (await services.queries.currentFirm())!;
  final itemId = await app.seedItem(name: name, rupees: rupees);
  final item = (await services.queries.itemById(firm.id, itemId))!;
  final accounts = await services.queries.paymentAccounts(firm.id);
  final cash = accounts.firstWhere((a) => a.modeLabel == 'cash');
  final now = services.actorNow();
  await services.postSale(
    on == null
        ? now
        : ActorContext(
            firmId: now.firmId,
            userId: now.userId,
            deviceId: now.deviceId,
            startedAtUtc: on,
          ),
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
      partyId: partyId,
      partyName: who,
      tenders: partyId != null
          ? const []
          : [
              TenderDraft(
                paymentAccountId: cash.id,
                mode: 'cash',
                amount: Money.rupees(rupees),
              ),
            ],
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

