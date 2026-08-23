import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// A real sale, on real paper.
///
/// The setup screen's test print proves a printer is reachable. This proves
/// the thing a shop is actually for: that the bill a customer was just charged
/// for comes out of the machine, with that customer's items and that
/// customer's total on it.
///
/// Deliberately separate, because a test print and a receipt take different
/// paths — the receipt goes through the renderer, the layout, the document
/// query and the print log, and the test print goes through none of them.
void main() {
  testWidgets('the bill a customer just paid comes out of the printer', (
    tester,
  ) async {
    final printer = _RecordingPrinter();
    final app = await Harness.startWithShop(tester, transports: [printer]);

    await _configurePrinter(app);
    await _stockAndSell(tester, app);

    // The sale is posted and the app is on the receipt.
    final documents = await app.rowsOf('SELECT id, doc_no FROM documents');
    expect(documents, hasLength(1));
    final docNo = documents.single['doc_no']! as String;

    await tapButton(tester, 'Printer par bhejein');
    await tester.pumpAndSettle();

    expect(
      printer.jobs,
      hasLength(1),
      reason:
          'the Print button did nothing. Every printer artefact in this '
          'repository was in exactly that state for two commits.',
    );

    final paper = _text(printer.jobs.single);
    expect(
      paper,
      contains(docNo),
      reason:
          'the printed bill does not carry its own invoice number, so a '
          'customer holding it cannot be matched to the shop record of it',
    );
    expect(paper, contains('Cooking Oil'));
    expect(
      paper,
      contains('5,525.00'),
      reason: 'the total on the paper is not the total the customer paid',
    );
    expect(
      paper,
      // Uppercased on the paper, which is what a receipt header does.
      contains('CHISHTI KIRYANA STORE'),
      reason: 'a receipt with no shop name on it is not a receipt',
    );

    // Recorded, so a reprint after the app is killed knows this already
    // happened.
    final jobs = await app.rowsOf(
      'SELECT status, bytes_written, copy_index FROM print_jobs',
    );
    expect(jobs, hasLength(1));
    expect(jobs.single['status'], 'printed');
    expect(jobs.single['copy_index'], 1);
  });

  testWidgets('asking twice hands the customer one receipt', (tester) async {
    // The rule the whole print path exists for. A thermal printer has no
    // memory: asked twice it prints twice, and the customer walks away with
    // two receipts while the shop has one record of the sale.
    final printer = _RecordingPrinter();
    final app = await Harness.startWithShop(tester, transports: [printer]);

    await _configurePrinter(app);
    await _stockAndSell(tester, app);

    await tapButton(tester, 'Printer par bhejein');
    await tester.pumpAndSettle();
    // A rebuilt widget, or a shopkeeper who did not see the first one work.
    await tapButton(tester, 'Dobara print');
    await tester.pumpAndSettle();

    expect(
      printer.jobs,
      hasLength(1),
      reason:
          'the customer was handed ${printer.jobs.length} receipts for '
          'one sale, and the shop has one record of it',
    );
  });

  testWidgets('a cash sale kicks the drawer, and only when asked to', (
    tester,
  ) async {
    // Off by default: most shops in this bracket have no drawer, and a printer
    // that clicks on every sale for no reason is a printer somebody unplugs.
    final printer = _RecordingPrinter();
    final app = await Harness.startWithShop(tester, transports: [printer]);

    await _configurePrinter(app, openDrawer: false);
    await _stockAndSell(tester, app);
    await tapButton(tester, 'Printer par bhejein');
    await tester.pumpAndSettle();

    expect(
      _containsDrawerKick(printer.jobs.single),
      isFalse,
      reason: 'the drawer opened on a shop that never asked for one',
    );
  });

  testWidgets('with the drawer switched on, a cash sale opens it', (
    tester,
  ) async {
    final printer = _RecordingPrinter();
    final app = await Harness.startWithShop(tester, transports: [printer]);

    await _configurePrinter(app, openDrawer: true);
    await _stockAndSell(tester, app);
    await tapButton(tester, 'Printer par bhejein');
    await tester.pumpAndSettle();

    expect(
      _containsDrawerKick(printer.jobs.single),
      isTrue,
      reason:
          'the cashier has to open the drawer by hand on every cash sale, '
          'with a queue behind them',
    );
  });
}

Future<void> _configurePrinter(Harness app, {bool openDrawer = false}) =>
    app.services.printing.saveSettings(
      app.services.actorNow(),
      PrinterSettings(
        transportKind: 'tcp',
        address: '192.168.1.50:9100',
        name: 'Counter printer',
        openDrawerOnCash: openDrawer,
      ),
    );

/// Two tins of oil and a bag of rice, paid in cash: 2 x 2500 + 525 = 5525.
Future<void> _stockAndSell(WidgetTester tester, Harness app) async {
  final firm = app.services.identity!.firmId;
  final actor = app.services.actorNow();
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');

  for (final (name, rupees) in const [
    ('Cooking Oil 5L', 2500),
    ('Chawal Basmati', 525),
  ]) {
    await app.services.catalogue.addItem(
      actor,
      ItemDraft(
        name: name,
        baseUnitId: pcs.id,
        saleRate: Rate.rupees(rupees),
        openingStock: Qty.units(50),
      ),
    );
  }

  await tester.pumpAndSettle();
  await tester.tap(find.text('Naya Bill').first);
  await tester.pumpAndSettle();

  await _addToCart(tester, 'Cooking Oil');
  await _addToCart(tester, 'Cooking Oil');
  await _addToCart(tester, 'Chawal');

  await tapButton(tester, 'Paisay lein');
  await typeInto(tester, 'Diye gaye', '6000');
  await tester.pumpAndSettle();
  await tapButton(tester, 'Save karein');
  await tester.pumpAndSettle();
}

Future<void> _addToCart(WidgetTester tester, String query) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    query,
  );
  // The search field is debounced at 250ms.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
}

/// The printable characters, as a shopkeeper would read them.
String _text(List<int> bytes) =>
    String.fromCharCodes(bytes.where((b) => (b >= 32 && b < 127) || b == 10));

/// `ESC p 0 25 250` — the generic drawer kick.
bool _containsDrawerKick(List<int> bytes) {
  for (var i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == 0x1B && bytes[i + 1] == 0x70) return true;
  }
  return false;
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
