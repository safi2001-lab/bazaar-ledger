import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// The scanner most Pakistani counters already own.
///
/// A USB or Bluetooth wedge scanner is not a camera and not a device driver:
/// it is a keyboard that types very fast and then presses Enter. So the app
/// does not fight for focus with a global key handler — the search field stays
/// focused, the wedge types into it, and Enter arrives as a submit.
///
/// This was built in M1 and never had a test. The failure it guards is quiet:
/// a scan that finds nothing must leave the bill alone rather than adding
/// whatever happened to be top of the search results, because a cashier
/// scanning a packet is not looking at the screen.
void main() {
  testWidgets('a scanned barcode puts that exact item on the bill', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _stock(app, [
      ('Cooking Oil 5L', '8964000123456', 2500),
      ('Chawal Basmati', '8964000999999', 525),
    ]);

    await tester.pumpAndSettle();
    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();

    // What the wedge does: type the code, press Enter.
    await _scan(tester, '8964000999999');

    expect(
      find.text('Chawal Basmati'),
      findsOneWidget,
      reason:
          'the scanned barcode did not reach the bill, so a counter with '
          'a scanner is a counter typing item names by hand',
    );
    expect(
      find.text('Cooking Oil 5L'),
      findsNothing,
      reason:
          'a different item went on the bill than the one scanned, which '
          'a cashier looking at the packet rather than the screen will not '
          'notice until the customer does',
    );
  });

  testWidgets('scanning the same packet twice makes it two', (tester) async {
    // What every till in the world does, and what a cashier means by it.
    final app = await Harness.startWithShop(tester);
    await _stock(app, [('Cooking Oil 5L', '8964000123456', 2500)]);

    await tester.pumpAndSettle();
    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();

    await _scan(tester, '8964000123456');
    await _scan(tester, '8964000123456');

    expect(find.text('2 pcs'), findsOneWidget);
  });

  testWidgets('an unknown code leaves the bill exactly as it was', (
    tester,
  ) async {
    // The quiet failure. Adding "the closest match" here would put a random
    // item on a bill while the cashier is looking at the packet, and it would
    // be discovered by the customer.
    final app = await Harness.startWithShop(tester);
    await _stock(app, [
      ('Cooking Oil 5L', '8964000123456', 2500),
      ('Chawal Basmati', '8964000999999', 525),
    ]);

    await tester.pumpAndSettle();
    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();

    await _scan(tester, '0000000000000');

    expect(find.text('Cooking Oil 5L'), findsNothing);
    expect(find.text('Chawal Basmati'), findsNothing);
  });

  testWidgets('an unambiguous name typed and entered also works', (
    tester,
  ) async {
    // The same path serves a shopkeeper with no scanner who types a few
    // letters and hits Enter.
    final app = await Harness.startWithShop(tester);
    await _stock(app, [
      ('Cooking Oil 5L', '8964000123456', 2500),
      ('Chawal Basmati', '8964000999999', 525),
    ]);

    await tester.pumpAndSettle();
    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();

    await _scan(tester, 'Chawal');
    expect(find.text('Chawal Basmati'), findsOneWidget);
  });

  testWidgets('an AMBIGUOUS term adds nothing, rather than guessing', (
    tester,
  ) async {
    // The case that matters, and the one the first draft of this file missed.
    //
    // It tested an unknown code, which matches nothing by barcode AND nothing
    // by name — so a version of the scanner that fell back to "the first
    // search result" passed it. Two items sharing a word is the situation
    // where a helpful fallback actually fires, and where it silently puts the
    // wrong item on a bill while the cashier is looking at the packet.
    final app = await Harness.startWithShop(tester);
    await _stock(app, [
      ('Chawal Basmati', '8964000999999', 525),
      ('Chawal Sella', '8964000888888', 410),
    ]);

    await tester.pumpAndSettle();
    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();

    await _scan(tester, 'Chawal');

    // Both appear in the search results below; neither is on the bill. The
    // cart summary is what says so.
    expect(
      find.text('1 pcs'),
      findsNothing,
      reason: 'the counter picked one of two matching items by itself. The '
          'cashier is looking at the packet, not the screen, and the customer '
          'finds out first.',
    );
  });
}

Future<void> _stock(Harness app, List<(String, String, int)> items) async {
  final firm = app.services.identity!.firmId;
  final actor = app.services.actorNow();
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');

  for (final (name, barcode, rupees) in items) {
    await app.services.catalogue.addItem(
      actor,
      ItemDraft(
        name: name,
        barcode: barcode,
        baseUnitId: pcs.id,
        saleRate: Rate.rupees(rupees),
        openingStock: Qty.units(50),
      ),
    );
  }
}

/// A wedge scanner: fast typing, then Enter.
Future<void> _scan(WidgetTester tester, String code) async {
  final field = find.widgetWithText(TextFormField, 'Talash karein').first;
  await tester.enterText(field, code);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}
