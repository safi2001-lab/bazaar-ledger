import 'dart:convert';
import 'dart:io';

import 'package:bazaar_ledger/features/printing/bill_design_preview.dart';
import 'package:bazaar_ledger/features/sales/sales_screen.dart';
import 'package:bazaar_ledger/features/settings/bill_design_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// A bill that looks like the shop's own (M51), driven through the app.
///
/// The owner designs the PDF once in Settings; every bill after it goes out
/// in that design, with the khata block for a credit customer and the
/// shop's own footer. At the counter, or from a bill's row, the sheet is
/// chosen: the original, a duplicate, a triplicate, or the transporter's
/// copy with no prices and the bilty on it. Everything is asserted on what
/// the app handed over — the file on the share sheet, the bytes the
/// printer received — against a real database.
final _sheet = _FakeShareSheet();

void main() {
  setUpAll(() => SharePlatform.instance = _sheet);
  setUp(_sheet.reset);

  testWidgets('the owner designs the bill in Settings and the next PDF is '
      'drawn in it, the khata block and footer included', (tester) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await _customer(app, owed: 1000);

    await tester.pumpAndSettle();
    await openSettings(tester);
    await tapText(tester, 'Bill ka design');

    for (final choice in ['Rangeen patti', 'Hara']) {
      await _scrollTo(tester, find.text(choice));
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();
    }
    final preset = find.widgetWithText(
      ActionChip,
      'Bika hua maal wapas ya tabdeel nahi hoga',
    );
    await _scrollTo(tester, preset);
    await tester.tap(preset);
    await tester.pumpAndSettle();

    // A sketch of the page in the colour and layout chosen, under the
    // switch between it and the till slip.
    final slip = find.text('Thermal slip');
    await _scrollTo(tester, slip);
    expect(find.byType(BillDesignPreview), findsOneWidget);

    // The till slip, as the printer will be handed it.
    await tester.tap(slip);
    await tester.pumpAndSettle();
    expect(find.textContaining('KUL BAQAYA'), findsOneWidget);
    expect(find.textContaining('Bika hua maal'), findsWidgets);

    await tapButton(tester, 'Save karein');
    final design = await app.services.billDesign();
    expect(design.theme, BillTheme.modern);
    expect(design.accent, BillAccent.green);
    expect(design.footerLines, [
      BillDesign.defaultThanks,
      'Bika hua maal wapas ya tabdeel nahi hoga',
    ]);

    final bill = await _sell(app, 5525, rashid, paid: 1000);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _openSales(tester);
    await _sendFromRow(tester, 'PDF bhejein', of: bill.docNo);

    final words = _pdfWords(File(_sheet.paths.single).readAsBytesSync());
    for (final word in [
      'Pichhla',
      '1,000.00',
      '4,525.00',
      '5,525.00',
      'Bika',
      'tabdeel',
    ]) {
      expect(words, contains(word), reason: word);
    }
  });

  testWidgets('a transporter\'s copy goes out with the bilty on it and no '
      'price anywhere', (tester) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await _customer(app);
    final bill = await _sell(app, 5525, rashid, paid: 1000);

    await _openSales(tester);
    await tester.tap(_sendButtonOf(bill.docNo));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Transporter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transport ki tafseel likhein (bilty, gaari)'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Transporter / adda', 'Daewoo Cargo');
    await typeInto(tester, 'Bilty no', 'BT-88123');
    await tapButton(tester, 'Save karein');
    await settleReal(tester, until: find.textContaining('BT-88123'));
    expect(find.textContaining('BT-88123'), findsOneWidget);

    await tester.tap(find.text('PDF bhejein'));
    await _settleWhileBusy(tester);

    final bytes = File(_sheet.paths.single).readAsBytesSync();
    expect(
      String.fromCharCodes(bytes),
      contains('${bill.docNo} - TRANSPORTER COPY'),
    );
    final words = _pdfWords(bytes);
    for (final word in ['BT-88123', 'Daewoo', 'Rashid', 'Cooking']) {
      expect(words, contains(word), reason: word);
    }
    for (final amount in ['5,525.00', '1,000.00', '4,525.00']) {
      expect(words, isNot(contains(amount)), reason: amount);
    }
    expect(
      _sheet.texts.single,
      allOf(contains('Bilty no: BT-88123'), isNot(contains('Rs'))),
      reason: 'the copy with no prices arrived with them typed beside it',
    );
    expect(
      await app.scalar<String>(
        "SELECT bilty_no FROM documents WHERE id = '${bill.documentId}'",
      ),
      'BT-88123',
    );
  });

  testWidgets('a triplicate prints as a sheet of its own, and the original '
      'is not offered twice', (tester) async {
    final printer = _RecordingPrinter();
    final app = await Harness.startWithShop(tester, transports: [printer]);
    await app.services.printing.saveSettings(
      app.services.actorNow(),
      const PrinterSettings(
        transportKind: 'tcp',
        address: '192.168.1.50:9100',
        name: 'Counter printer',
      ),
    );
    final bill = await _sell(app, 5525, null);

    Future<void> print({String? copy}) async {
      await tester.tap(_sendButtonOf(bill.docNo));
      await tester.pumpAndSettle();
      if (copy != null) {
        await tester.tap(find.widgetWithText(ChoiceChip, copy));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Printer par bhejein'));
      await tester.pumpAndSettle();
    }

    await _openSales(tester);
    await print();
    expect(printer.jobs, hasLength(1));
    expect(_text(printer.jobs.single), isNot(contains('ORIGINAL')));

    // The original has gone to paper; it is not offered again.
    await tester.tap(_sendButtonOf(bill.docNo));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Asal'))
          .onSelected,
      isNull,
    );
    expect(find.text('Asal copy pehle chhap chuki hai'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await print(copy: 'Triplicate');
    expect(printer.jobs, hasLength(2));
    expect(_text(printer.jobs.last), contains('TRIPLICATE / TEESRI COPY'));
    await print(copy: 'Duplicate');
    expect(printer.jobs, hasLength(3));
    expect(_text(printer.jobs.last), contains('DUPLICATE / DOBARA COPY'));

    // Asking for the plain bill again still prints nothing more.
    await print();
    expect(printer.jobs, hasLength(3));
    final copies = await app.rowsOf(
      'SELECT copy_index FROM print_jobs ORDER BY copy_index',
    );
    expect([for (final r in copies) r['copy_index']], [1, 2, 3]);
  });

  testWidgets('the bill on screen is the sheet chosen, as it will print', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await _customer(app, owed: 1000);
    final bill = await _sell(app, 5525, rashid, paid: 1000);

    await _openSales(tester);
    await tapText(tester, bill.docNo);
    expect(find.textContaining('Pichhla baqaya'), findsOneWidget);
    expect(find.textContaining('KUL BAQAYA'), findsOneWidget);
    expect(find.textContaining('5,525.00'), findsWidgets);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Transporter'));
    await settleReal(tester, until: find.textContaining('DELIVERY COPY'));
    expect(find.textContaining('TRANSPORTER / DELIVERY COPY'), findsOneWidget);
    expect(find.textContaining('5,525.00'), findsNothing);
    expect(find.textContaining('KUL BAQAYA'), findsNothing);
  });

  testWidgets('the shop\'s own payment QR is shown where it was promised and '
      'goes on the PDF; none is made when there is none', (tester) async {
    final app = await Harness.startWithShop(tester);
    final bill = await _sell(app, 900, null);

    await _openSales(tester);
    await _sendFromRow(tester, 'PDF bhejein', of: bill.docNo);
    expect(
      String.fromCharCodes(File(_sheet.paths.last).readAsBytesSync()),
      isNot(contains(_image)),
      reason: 'no QR was given, so none may appear',
    );

    await app.services.setPaymentQr(_png, fileName: 'raast-qr.png');
    await _sendFromRow(tester, 'PDF bhejein', of: bill.docNo);
    expect(
      String.fromCharCodes(File(_sheet.paths.last).readAsBytesSync()),
      contains(_image),
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await openSettings(tester);
    await tapText(tester, 'Paisay lene ki tafseel');
    // Under the note that says to add it, the picture added, to change.
    expect(find.text('Payment QR'), findsOneWidget);
    expect(find.text('Tasveer badlein'), findsOneWidget);
  });

  testWidgets('the bill design screen fits a small phone at 200%', (
    tester,
  ) async {
    // A real disk read, so on the real clock: under the test's fake one the
    // font never arrives.
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
    await app.services.setPaymentQr(_png, fileName: 'qr.png');
    await tester.pumpAndSettle();
    await openSettings(tester);
    await tapText(tester, 'Bill ka design');
    expect(tester.takeException(), isNull);
    for (final theme in ['Sales tax invoice', 'Chhota', 'Rangeen patti']) {
      await _scrollTo(tester, find.text(theme));
      await tester.tap(find.text(theme));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: theme);
    }
    // Down the whole screen, the sketch, the QR and the footer presets
    // included.
    for (var i = 0; i < 12; i++) {
      await tester.drag(_designList, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Save karein'), findsOneWidget);
  });
}

/// A 64-pixel grey PNG: a black square on white, standing in for the QR a
/// bank issued, and deliberately not one.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAAAAACPAi4CAAAAL0lEQVR42u3XMREAAAjEsPdvGjRwbJAKyN7UsgBOARkGAAAAAAAAAAAA/gCe6TXQgjb5W+rfoMsAAAAASUVORK5CYII=',
);

/// A picture placed on a PDF page.
final _image = RegExp(r'/Subtype\s*/Image');

Future<String> _customer(Harness app, {int owed = 0}) =>
    app.services.catalogue.addParty(
      app.services.actorNow(),
      PartyDraft(
        name: 'Rashid Traders',
        phone: '0300-4471203',
        addressLine1: 'Shop 5, Shah Alam Market',
        city: 'Lahore',
        openingBalance: Money.rupees(owed),
      ),
    );

/// One line of Cooking Oil at [rupees], [paid] of it in cash — all of it
/// unless said — to [partyId], or to a walk-in when null.
Future<PostedSale> _sell(
  Harness app,
  int rupees,
  String? partyId, {
  int? paid,
}) async {
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');
  final cash = (await app.services.queries.paymentAccounts(
    firm,
  )).firstWhere((a) => a.modeLabel == 'cash');
  final itemId = await app.seedItem(name: 'Cooking Oil 5L', rupees: rupees);
  final party = partyId == null
      ? null
      : await app.services.queries.partyById(firm, partyId);
  final taken = paid ?? rupees;
  return app.services.postSale(
    app.services.actorNow(),
    SaleDraft(
      partyId: partyId,
      partyName: party?.name,
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: 'Cooking Oil 5L',
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
        ),
      ],
      tenders: [
        if (taken > 0)
          TenderDraft(
            paymentAccountId: cash.id,
            mode: 'cash',
            amount: Money.rupees(taken),
          ),
      ],
    ),
  );
}

/// The bill design screen's own list. Not the first Scrollable in the tree:
/// that is the home screen's, still underneath, and dragging it moves
/// nothing on the screen on top.
Finder get _designList => find
    .descendant(
      of: find.byType(BillDesignScreen),
      matching: find.byType(Scrollable),
    )
    .first;

/// Scrolls the design screen until [target] is built and on screen: its
/// list builds only what is near the screen. Down first, then back up for
/// something already scrolled past.
Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  for (final step in const [300.0, -300.0]) {
    if (target.evaluate().isNotEmpty) break;
    try {
      await tester.scrollUntilVisible(
        target,
        step,
        scrollable: _designList,
        maxScrolls: 30,
      );
    } on StateError {
      // Not that way; the other.
    }
  }
  await tester.ensureVisible(target.first);
  await tester.pumpAndSettle();
}

Future<void> _openSales(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Farokht');
  await tester.pumpAndSettle();
}

Future<void> _sendFromRow(
  WidgetTester tester,
  String way, {
  required String of,
}) async {
  await tester.tap(_sendButtonOf(of));
  await tester.pumpAndSettle();
  await tester.tap(find.text(way));
  await _settleWhileBusy(tester);
}

Finder _sendButtonOf(String docNo) => find.descendant(
  of: find.ancestor(of: find.text(docNo), matching: find.byType(SaleRowTile)),
  matching: find.byTooltip('Bhejein'),
);

/// Lets a share finish, which takes both a clock and a disk; see
/// a_bill_is_sent_again_test.
Future<void> _settleWhileBusy(WidgetTester tester) async {
  for (var round = 0; round < 40; round++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump();
}

/// The words on a PDF's pages: every content stream inflated, every string
/// it shows.
Set<String> _pdfWords(List<int> bytes) {
  final words = <String>{};
  final text = String.fromCharCodes(bytes);
  for (final match in RegExp(r'stream\r?\n').allMatches(text)) {
    final end = text.indexOf('endstream', match.end);
    if (end < 0) continue;
    String body;
    try {
      body = String.fromCharCodes(zlib.decode(bytes.sublist(match.end, end)));
    } on Object {
      continue;
    }
    for (final run in RegExp(r'\((.*?)\)\]?\s*TJ').allMatches(body)) {
      words.add(run.group(1)!.replaceAll(r'\(', '(').replaceAll(r'\)', ')'));
    }
  }
  return words;
}

String _text(List<int> bytes) =>
    String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));

/// Stands in for the system share sheet and records what it was handed.
final class _FakeShareSheet extends SharePlatform {
  final paths = <String>[];
  final texts = <String>[];

  void reset() {
    paths.clear();
    texts.clear();
  }

  @override
  Future<ShareResult> share(ShareParams params) async {
    paths.addAll((params.files ?? const []).map((f) => f.path));
    if (params.text case final text?) texts.add(text);
    return const ShareResult('ok', ShareResultStatus.success);
  }
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

