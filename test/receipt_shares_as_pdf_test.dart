import 'dart:io';

import 'package:bazaar_ledger/features/sales/receipt_file_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/harness.dart';

/// Sending a customer their bill.
///
/// The half of the receipt that most shops in this bracket will use more than
/// the printer, because a phone is free and a thermal printer is not. A
/// wholesaler messaging a bill to a retailer who is forty kilometres away is
/// the normal case, not the exception.
///
/// The share sheet itself is a system surface and cannot be driven from a
/// host test. What these check is everything either side of it: that the PDF
/// is rendered and written before the sheet is asked for, that the file
/// handed over is a real PDF carrying this bill's numbers, that its name is
/// safe to put on a filesystem, and that a second tap does not produce a
/// second file.
final _sheet = _FakeShareSheet();

void main() {
  setUpAll(() => SharePlatform.instance = _sheet);
  setUp(_sheet.reset);

  testWidgets('the bill reaches the share sheet as a readable PDF', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _stockAndSell(tester, app);

    final docNo =
        (await app.rowsOf('SELECT doc_no FROM documents')).single['doc_no']!
            as String;

    await _tapShare(tester);

    expect(
      _sheet.paths,
      hasLength(1),
      reason:
          'the Share button did nothing. Every printer artefact in this '
          'repository was in exactly that state for two commits, and a '
          'button that silently does nothing is how that went unnoticed.',
    );

    final file = File(_sheet.paths.single);
    expect(file.existsSync(), isTrue, reason: 'the sheet was handed a path '
        'to a file that was never written');

    final bytes = file.readAsBytesSync();
    expect(
      String.fromCharCodes(bytes.take(5)),
      '%PDF-',
      reason: 'what was shared is not a PDF',
    );
    expect(
      String.fromCharCodes(bytes),
      contains('Invoice $docNo'),
      reason:
          'the shared file does not carry its own invoice number, so a '
          'customer holding it cannot be matched to the shop record of it',
    );
  });

  testWidgets('the file is named after the bill', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _stockAndSell(tester, app);

    final docNo =
        (await app.rowsOf('SELECT doc_no FROM documents')).single['doc_no']!
            as String;

    await _tapShare(tester);

    expect(
      _sheet.paths.single.split(Platform.pathSeparator).last,
      '$docNo.pdf',
      reason:
          'a customer scrolling a year of WhatsApp cannot find the bill '
          'again, because every one of them is called the same thing',
    );
  });

  group('a document number is shop-controlled, and goes into a path', () {
    // The default series is INV-2627-0001 and looks harmless, which is exactly
    // why this is a separate group asserted on the rule rather than on one
    // generated bill: the numbering format is a setting, and the shop that has
    // always written INV/26-27/0001 on its pad will type that. A slash goes
    // straight into a path. On Android the write then lands in a directory
    // that does not exist and throws — on the share path, with a customer
    // waiting, and only for the shops that use one.
    //
    // A widget test cannot reach these, because the number comes from the
    // sequence allocator. Asserting the rule directly is what makes the claim
    // real; the widget test above only proves the rule is the one in use.
    test('a slash never becomes a directory separator', () {
      expect(receiptFileName('INV/26-27/0001'), 'INV_26-27_0001.pdf');
    });

    test('a backslash does not either', () {
      expect(receiptFileName(r'INV\2627\1'), 'INV_2627_1.pdf');
    });

    test('a parent-directory hop cannot escape the temp folder', () {
      expect(receiptFileName('../../etc/passwd'), 'etc_passwd.pdf');
    });

    test('Urdu in a series survives the trip as something nameable', () {
      // Most filesystems take it, and then the file travels through WhatsApp
      // to whatever the customer's phone does with it.
      expect(receiptFileName('بل-0001'), '0001.pdf');
    });

    test('a number that reduces to nothing still gets a name', () {
      // A file called `.pdf` is one a share sheet will not offer, and the bill
      // still has to reach the customer.
      expect(receiptFileName('///'), 'bill.pdf');
      expect(receiptFileName(''), 'bill.pdf');
    });

    test('an ordinary number is left exactly alone', () {
      expect(receiptFileName('INV-2627-0001'), 'INV-2627-0001.pdf');
    });
  });

  testWidgets('asking twice shares one file, not two', (tester) async {
    // The same rule as the printer, for the same reason: rendering a PDF
    // takes long enough on an entry handset that a shopkeeper who sees
    // nothing happen taps again.
    final app = await Harness.startWithShop(tester);
    await _stockAndSell(tester, app);

    final button = await _shareButton(tester);
    await tester.tap(button);
    await tester.tap(button);
    await _settleWhileBusy(tester);

    expect(
      _sheet.paths,
      hasLength(1),
      reason:
          'two share sheets opened for one bill, which on a real handset is '
          'two sheets stacked on top of each other',
    );
  });

  testWidgets('a share that fails says so instead of going quiet', (
    tester,
  ) async {
    // A phone with nothing installed that can receive a PDF, which is a real
    // handset in this market and not a hypothetical. The shopkeeper has to
    // learn that from the screen rather than from the customer.
    _sheet.failWith = StateError('no app can receive this');
    final app = await Harness.startWithShop(tester);
    await _stockAndSell(tester, app);

    await _tapShare(tester);

    // On the words, not on the widget. The first version of this asserted
    // that some SnackBar was on screen and passed while the share button was
    // unreachable underneath the "bill saved" SnackBar from the sale before
    // it — a test that proved the previous screen still worked.
    expect(find.textContaining('Kuch masla ho gaya'), findsOneWidget);
  });
}

/// Stands in for the system share sheet and records what it was handed.
///
/// Injected at the platform seam rather than at the method channel, because
/// on a host `flutter test` there is no Android to talk to: `share_plus`
/// resolves to its desktop implementation and the Android channel is never
/// called. A test that stubbed the channel would pass while asserting
/// nothing, which is the failure this whole suite exists to catch elsewhere.
///
/// One instance for the file. `SharePlus.instance` is a `static final` that
/// reads the platform once, on first use, so it cannot be swapped between
/// tests — [failWith] changes its behaviour instead.
final class _FakeShareSheet extends SharePlatform {
  final paths = <String>[];

  /// Set to make the next share throw, standing in for a phone with nothing
  /// installed that can receive a PDF.
  Object? failWith;

  void reset() {
    paths.clear();
    failWith = null;
  }

  @override
  Future<ShareResult> share(ShareParams params) async {
    if (failWith case final error?) throw error;
    paths.addAll((params.files ?? const []).map((f) => f.path));
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

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

  // "Bill saved" comes up as a SnackBar and covers the action row for four
  // seconds. A tap in that window lands on the SnackBar, not the button —
  // which is also true for a shopkeeper, and is why the buttons sit where
  // they do rather than under it.
  await tester.pump(const Duration(seconds: 5));
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

/// Taps Share and waits for the PDF, without waiting on the spinner forever.
///
/// The button shows a progress indicator while the document renders, and a
/// progress indicator is a continuous animation — `pumpAndSettle` waits on it
/// until it times out. So this pumps frames for a bounded time instead, which
/// is what any test of a screen with a spinner on it has to do.
Future<void> _tapShare(WidgetTester tester) async {
  await _shareButton(tester);
  await tester.tap(find.text('PDF bhejein').first);
  await _settleWhileBusy(tester);
}

/// Scrolls the action row into view and returns the finder for it.
Future<Finder> _shareButton(WidgetTester tester) async {
  final button = find.text('PDF bhejein').first;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  return button;
}

/// Lets the share finish, which takes both a clock and a disk.
///
/// Two different problems, and each defeats the obvious answer to the other.
/// `pumpAndSettle` never returns, because the button shows a progress
/// indicator and a progress indicator is a continuous animation. And pumping
/// frames is not enough on its own either: rendering the PDF and writing it
/// to a temporary file is real work on a real disk, and a widget test's clock
/// is fake, so no amount of pumping advances the world that work lives in.
/// `runAsync` is what hands it back.
Future<void> _settleWhileBusy(WidgetTester tester) async {
  for (var round = 0; round < 40; round++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump();
}
