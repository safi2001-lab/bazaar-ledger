import 'dart:io';

import 'package:bazaar_ledger/features/parties/party_picker.dart';
import 'package:bazaar_ledger/features/reports/report_registry.dart';
import 'package:bazaar_ledger/features/reports/report_shelf.dart';
import 'package:bazaar_ledger/features/sales/receipt_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/harness.dart';

/// The reports hub (M33), from the screen: the groups, the search, the
/// stars, a report narrowed by a party and opened to its bill, the party
/// statement, the period remembered, a column sorted, and the workbook the
/// accountant asked for.
final _sheet = _FakeShareSheet();

void main() {
  setUpAll(() => SharePlatform.instance = _sheet);
  setUp(_sheet.paths.clear);
  _printTests();

  test('every report is in the registry exactly once, in a group', () {
    for (final kind in ReportKind.values) {
      expect(
        reportRegistry.where((e) => e.kind == kind),
        hasLength(1),
        reason: '$kind',
      );
    }
    expect(
      reportRegistry.where((e) => e.plan != null).map((e) => e.kind),
      containsAll([
        ReportKind.billWiseProfit,
        ReportKind.balanceSheet,
        ReportKind.partyProfitAndLoss,
      ]),
      reason: 'the premium ones ride the plan that sells the books',
    );
  });

  test('the report shelf survives a restart, and a file it cannot read is '
      'an empty shelf', () {
    final dir = _shelfDirectory();
    const ReportShelf()
        .toggleFavourite(ReportKind.saleReport)
        .opened(ReportKind.dayBook)
        .rememberPeriod(
          ReportKind.cashflow,
          DatePreset.custom,
          custom: ReportPeriod(
            const BusinessDate('2026-09-01'),
            const BusinessDate('2026-09-15'),
          ),
        )
        .saveTo(dir);
    final back = ReportShelf.loadFrom(dir);
    expect(back.favourites, [ReportKind.saleReport]);
    expect(back.recent, [ReportKind.dayBook]);
    expect(back.periodFor(ReportKind.cashflow)?.custom?.to.value, '2026-09-15');
    expect(back.periodFor(ReportKind.dayBook), isNull);

    expect(
      ReportShelf.decode(
        '{"favourites": ["noSuchReport", "cashflow"], "periods": 7}',
      ).favourites,
      [ReportKind.cashflow],
    );
    expect(ReportShelf.decode('not json').favourites, isEmpty);
  });

  testWidgets('the reports sit in their groups, and the search finds them '
      'by name', (tester) async {
    final dir = _shelfDirectory();
    await Harness.startWithShop(tester, overrides: _shelfAt(dir));
    await tapText(tester, 'Report');

    expect(find.text('LEN DEN'), findsOneWidget);
    expect(find.text('Bikri report'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('PARTY KI REPORT'), 200);
    expect(find.text('PARTY KI REPORT'), findsOneWidget);

    await tester.tap(find.byTooltip('Talash karein'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nafa');
    await tester.pumpAndSettle();
    expect(find.text('Nafa nuqsan'), findsOneWidget);
    expect(find.text('Bill-war nafa'), findsOneWidget);
    expect(find.text('Party-war nafa nuqsan'), findsOneWidget);
    expect(find.text('Bikri report'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.text('Is naam ki koi report nahi'), findsOneWidget);
  });

  testWidgets('a starred report sits under favourites, and the phone keeps '
      'the star', (tester) async {
    final dir = _shelfDirectory();
    await Harness.startWithShop(tester, overrides: _shelfAt(dir));
    await tapText(tester, 'Report');

    final tile = find.ancestor(
      of: find.text('Cash flow'),
      matching: find.byType(InkWell),
    );
    // Today's figures sit above the groups since M46, so the tile may be
    // below the fold of the test's small screen.
    await tester.ensureVisible(tile.first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: tile.first,
        matching: find.byTooltip('Pasandeeda mein daalein'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('PASANDEEDA'), -200);

    expect(find.text('PASANDEEDA'), findsOneWidget);
    expect(find.text('Cash flow'), findsNWidgets(2));
    expect(
      ReportShelf.loadFrom(dir).favourites,
      [ReportKind.cashflow],
      reason: 'kept on the phone, not only on the screen',
    );
  });

  testWidgets('the sale report narrows to a party, its tiles say what was '
      'sold, received and owed, and a bill opens its receipt', (tester) async {
    final app = await Harness.startWithShop(
      tester,
      overrides: _shelfAt(_shelfDirectory()),
    );
    final rashid = await app.seedParty(name: 'Rashid Traders');
    await _sell(app, rupees: 2500, paid: 2500);
    final udhaar = await _sell(app, rupees: 4000, partyId: rashid);

    await tapText(tester, 'Report');
    await tapText(tester, 'Bikri report');
    expect(find.text('Total sale'), findsOneWidget);
    expect(find.text('Rs 6,500.00'), findsOneWidget);
    expect(find.text('Rs 4,000.00'), findsOneWidget, reason: 'the balance');

    await tester.tap(find.widgetWithText(ActionChip, 'Party'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(PartyPicker),
        matching: find.text('Rashid Traders'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Party: Rashid Traders'), findsOneWidget);
    expect(find.text('1 bill'), findsOneWidget);
    expect(find.text('Rs 4,000.00'), findsNWidgets(2));

    await tester.tap(find.text(udhaar.docNo));
    await tester.pumpAndSettle();
    expect(find.byType(ReceiptScreen), findsOneWidget);
  });

  testWidgets('a party\'s statement closes on what their khata says', (
    tester,
  ) async {
    final app = await Harness.startWithShop(
      tester,
      overrides: _shelfAt(_shelfDirectory()),
    );
    final rashid = await app.seedParty(
      name: 'Rashid Traders',
      owedRupees: 4500,
    );
    await _sell(app, rupees: 2500, partyId: rashid);

    await tapText(tester, 'Report');
    await tapText(tester, 'Party ka statement');
    expect(find.text('Statement dekhne ke liye party chunein'), findsOneWidget);

    await tapButton(tester, 'Party');
    await tester.tap(
      find.descendant(
        of: find.byType(PartyPicker),
        matching: find.text('Rashid Traders'),
      ),
    );
    await tester.pumpAndSettle();

    final khata = await app.services.queries.partyById(
      (await app.services.queries.currentFirm())!.id,
      rashid,
    );
    expect(khata!.balance, const Money.rupees(7000));
    expect(find.text('Balance owed to us'), findsOneWidget);
    expect(find.text('Rs 7,000.00'), findsOneWidget, reason: 'owed to us');
  });

  testWidgets('a report opens on the period it was last read for', (
    tester,
  ) async {
    await Harness.startWithShop(tester, overrides: _shelfAt(_shelfDirectory()));
    await tapText(tester, 'Report');
    await tapText(tester, 'Roznamcha');
    expect(_chip(tester, 'Aaj').selected, isTrue, reason: 'it opens on today');

    await tapText(tester, 'Is mahina');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapText(tester, 'Roznamcha');

    expect(_chip(tester, 'Is mahina').selected, isTrue);
    expect(_chip(tester, 'Aaj').selected, isFalse);
  });

  testWidgets('a column sorts either way, and the total stays at the foot', (
    tester,
  ) async {
    final app = await Harness.startWithShop(
      tester,
      overrides: _shelfAt(_shelfDirectory()),
    );
    final small = await _sell(app, rupees: 1500, paid: 1500);
    final big = await _sell(app, rupees: 9000, paid: 9000);
    final semantics = tester.ensureSemantics();

    await tapText(tester, 'Report');
    await tapText(tester, 'Bikri report');
    double y(String text) => tester.getTopLeft(find.text(text).first).dy;
    expect(y(small.docNo), lessThan(y(big.docNo)), reason: 'oldest first');

    await tester.tap(find.bySemanticsLabel('Total se tarteeb'));
    await tester.pumpAndSettle();
    expect(y(big.docNo), lessThan(y(small.docNo)), reason: 'largest first');
    expect(y('2 bills'), greaterThan(y(small.docNo)));

    await tester.tap(find.bySemanticsLabel('Total se tarteeb'));
    await tester.pumpAndSettle();
    expect(y(small.docNo), lessThan(y(big.docNo)));
    expect(y('2 bills'), greaterThan(y(big.docNo)));
    semantics.dispose();
  });

  testWidgets('a report goes out as an Excel workbook the app\'s own import '
      'can read', (tester) async {
    final app = await Harness.startWithShop(
      tester,
      overrides: _shelfAt(_shelfDirectory()),
    );
    await _sell(app, rupees: 2500, paid: 2500);

    await tapText(tester, 'Report');
    await tapText(tester, 'Bikri report');
    await tester.tap(find.byTooltip('Excel bhejein'));
    await settleReal(tester, done: () => _sheet.paths.isNotEmpty);

    expect(_sheet.paths.single, endsWith('.xlsx'));
    final bytes = (await tester.runAsync(
      () => File(_sheet.paths.single).readAsBytes(),
    ))!;
    final rows = readSpreadsheet(bytes, fileName: 'report.xlsx').rows;
    expect(rows[1], ['Sale report']);
    expect(rows.any((r) => r.contains('2500.00')), isTrue);
  });
}

void _printTests() {
  testWidgets('the day book prints on the counter\'s receipt printer', (
    tester,
  ) async {
    final printer = _RecordingPrinter();
    final app = await Harness.startWithShop(
      tester,
      transports: [printer],
      overrides: _shelfAt(_shelfDirectory()),
    );
    await app.services.printing.saveSettings(
      app.services.actorNow(),
      const PrinterSettings(
        transportKind: 'tcp',
        address: '192.168.1.50:9100',
        name: 'Counter printer',
      ),
    );
    await _sell(app, rupees: 2500, paid: 2500);

    await tapText(tester, 'Report');
    await tapText(tester, 'Roznamcha');
    await tester.tap(find.byTooltip('Printer par chhapein'));
    await settleReal(tester, done: () => printer.jobs.isNotEmpty);

    expect(printer.jobs, hasLength(1));
    // The printed words, with each line's alignment and bold commands (ESC
    // a n, ESC E n) taken off the front.
    final lines = [
      for (final l in String.fromCharCodes(
        printer.jobs.single.where((b) => b >= 32 && b < 127 || b == 10),
      ).split('\n'))
        l.replaceFirst(RegExp('^@?aE'), ''),
    ];
    expect(lines, contains('Day Book'));
    expect(lines, contains('Money in${' ' * 32}2,500.00'), reason: 'a tile');
    expect(lines.every((l) => l.length <= 48), isTrue, reason: '$lines');
  });
}

final class _RecordingPrinter implements PrinterTransport {
  final jobs = <List<int>>[];

  @override
  String get kind => 'tcp';

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<List<PrinterTarget>> discover({Duration? timeout}) async => const [];

  @override
  Future<void> send(PrinterTarget target, List<int> bytes) async {
    jobs.add(bytes);
  }
}

ChoiceChip _chip(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

Directory _shelfDirectory() =>
    Directory.systemTemp.createTempSync('report_shelf');

List<Override> _shelfAt(Directory dir) => [
  reportShelfDirectoryProvider.overrideWith((ref) async => dir),
];

/// A bill of one item at [rupees], paid [paid] in cash at the counter.
Future<PostedSale> _sell(
  Harness app, {
  required int rupees,
  int paid = 0,
  String? partyId,
}) async {
  final services = app.services;
  final firm = (await services.queries.currentFirm())!;
  final itemId = await app.seedItem(name: 'Item $rupees', rupees: rupees);
  final item = (await services.queries.itemById(firm.id, itemId))!;
  final cash = (await services.queries.paymentAccounts(
    firm.id,
  )).firstWhere((a) => a.modeLabel == 'cash');
  return services.postSale(
    services.actorNow(),
    SaleDraft(
      partyId: partyId,
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
        if (paid > 0)
          TenderDraft(
            paymentAccountId: cash.id,
            mode: 'cash',
            amount: Money.rupees(paid),
          ),
      ],
    ),
  );
}

final class _FakeShareSheet extends SharePlatform {
  final paths = <String>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    paths.addAll((params.files ?? const []).map((f) => f.path));
    return const ShareResult('ok', ShareResultStatus.success);
  }
}
