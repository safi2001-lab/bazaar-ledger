import 'dart:io';

import 'package:bazaar_ledger/features/reports/report_screen.dart';
import 'package:bazaar_ledger/features/reports/report_shelf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// The business status, staff, tax and order reports (M35), from the
/// screen: the new groups in the hub, the night's Z report opened from the
/// hub and from the day close and printed on a 58mm roll, a split bill in
/// the payment-mode summary, and a bank statement narrowed to an account.
void main() {
  testWidgets('the hub lists business status, taxes and orders, and the '
      'search finds the annexures', (tester) async {
    await Harness.startWithShop(tester, overrides: _shelfAt(_shelfDirectory()));
    await tapText(tester, 'Report');

    await tester.scrollUntilVisible(find.text('KAROBAR KI HALAT'), 200);
    expect(find.text('KAROBAR KI HALAT'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('BIKRI AUR KHAREED KE ORDER'),
      200,
    );
    expect(find.text('BIKRI AUR KHAREED KE ORDER'), findsOneWidget);

    await tester.tap(find.byTooltip('Talash karein'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'annex');
    await tester.pumpAndSettle();
    expect(find.text('Annex-C (bikri)'), findsOneWidget);
    expect(find.text('Annex-A (khareed)'), findsOneWidget);
    expect(find.text('Din ka khulasa (Z report)'), findsNothing);
  });

  testWidgets('the night\'s Z report opens from the hub and prints on a '
      '58mm roll, every line inside it', (tester) async {
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
        columns: 32,
      ),
    );
    await _sellSplit(app);

    await tapText(tester, 'Report');
    await tapText(tester, 'Din ka khulasa (Z report)');
    expect(find.text('Total collected'), findsOneWidget);
    expect(find.text('JazzCash'), findsOneWidget);
    expect(find.text('Net sales'), findsWidgets);

    await tester.tap(find.byTooltip('Printer par chhapein'));
    await settleReal(tester, done: () => printer.jobs.isNotEmpty);
    final lines = [
      for (final l in String.fromCharCodes(
        printer.jobs.single.where((b) => b >= 32 && b < 127 || b == 10),
      ).split('\n'))
        l.replaceFirst(RegExp('^@?aE'), ''),
    ];
    expect(lines, contains('Day summary (Z report)'));
    expect(lines, contains('Cash${' ' * 20}1,000.00'), reason: '$lines');
    expect(lines, contains('JazzCash${' ' * 16}1,500.00'), reason: '$lines');
    expect(lines.every((l) => l.length <= 32), isTrue, reason: '$lines');
  });

  testWidgets('the day close opens the Z report in one tap', (tester) async {
    await Harness.startWithShop(tester, overrides: _shelfAt(_shelfDirectory()));
    await tapText(tester, 'Din band');
    await tapText(tester, 'Din ka khulasa dekhein (Z report)');
    expect(find.byType(ReportScreen), findsOneWidget);
    expect(find.text('Din ka khulasa (Z report)'), findsOneWidget);
  });

  testWidgets('a split bill is a line for each tender in the payment-mode '
      'summary, and the bank statement narrows to an account', (tester) async {
    final app = await Harness.startWithShop(
      tester,
      overrides: _shelfAt(_shelfDirectory()),
    );
    await _sellSplit(app);

    await tapText(tester, 'Report');
    await tapText(tester, 'Adaigi ke tareeqay');
    expect(find.text('Cash'), findsOneWidget);
    expect(find.text('JazzCash'), findsOneWidget);
    expect(find.text('Udhaar'), findsNothing, reason: 'paid in full');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tapText(tester, 'Bank statement');
    await tester.tap(find.widgetWithText(ActionChip, 'Bank ya wallet'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Mobile Wallet').first);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Bank ya wallet: Mobile Wallet'),
      findsOneWidget,
    );
    expect(find.textContaining('Rs 1,500.00'), findsWidgets);
  });
}

/// A Rs 2,500 bill paid Rs 1,000 in cash and Rs 1,500 by JazzCash.
Future<void> _sellSplit(Harness app) async {
  final services = app.services;
  final firm = (await services.queries.currentFirm())!;
  final itemId = await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
  final item = (await services.queries.itemById(firm.id, itemId))!;
  final accounts = await services.queries.paymentAccounts(firm.id);
  final cash = accounts.firstWhere((a) => a.modeLabel == 'cash');
  final jazz = accounts.firstWhere((a) => a.modeLabel == 'jazzcash');
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
          rate: Rate.rupees(2500),
        ),
      ],
      tenders: [
        TenderDraft(
          paymentAccountId: cash.id,
          mode: 'cash',
          amount: const Money.rupees(1000),
        ),
        TenderDraft(
          paymentAccountId: jazz.id,
          mode: 'jazzcash',
          amount: const Money.rupees(1500),
        ),
      ],
    ),
  );
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

Directory _shelfDirectory() =>
    Directory.systemTemp.createTempSync('report_shelf');

List<Override> _shelfAt(Directory dir) => [
  reportShelfDirectoryProvider.overrideWith((ref) async => dir),
];
