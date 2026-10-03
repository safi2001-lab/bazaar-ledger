import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// Two taps in one frame must never write two rows.
///
/// `onPressed: _busy ? null : _save` does not disable anything until the next
/// build, so both taps of a double tap reach the handler. A cashier at a
/// counter taps twice as a matter of course — the screen is cracked, the
/// hands are dirty, and the first tap did not visibly do anything yet.
///
/// The tender sheet has documented and guarded this since M0 and
/// `counter_safety_test` proves one cart is one invoice. The editors were
/// never given the same guard, and each one of them writes a row:
///
///   * A duplicated customer is not merely untidy. If they carry an opening
///     balance, the khata shows a receivable that does not exist, and the
///     duplicate is PERMANENT — `archiveParty` refuses anyone with a balance,
///     and the opening-balance field is hidden on edit, so there is no path
///     in the app to zero it.
///   * A duplicated item means the cashier rings against one at random while
///     the other's stock never moves, and any opening stock is doubled on the
///     shelf figure.
void main() {
  testWidgets('two taps on Save make one customer', (tester) async {
    final app = await Harness.startWithShop(tester);

    await tapText(tester, 'Gahak');
    await tester.pumpAndSettle();
    await _openEditor(tester, 'Naya gahak');

    await typeInto(tester, 'Naam', 'Bilal General Store');
    await typeInto(tester, 'Purana baqaya', '5000');

    await _tapTwiceInOneFrame(tester, 'Save karein');

    expect(
      await app.countIn('parties'),
      1,
      reason: 'the second tap wrote a debtor who does not exist, and one the '
          'app has no way to remove',
    );
  });

  testWidgets('two taps on Save make one item', (tester) async {
    final app = await Harness.startWithShop(tester);

    await tapText(tester, 'Maal');
    await tester.pumpAndSettle();
    await _openEditor(tester, 'Naya maal');

    await typeInto(tester, 'Naam', 'Cooking Oil 5L');
    await typeInto(tester, 'Farokht ki qeemat', '2500');
    await typeInto(tester, 'Mojooda stock', '20');

    await _tapTwiceInOneFrame(tester, 'Save karein');

    expect(await app.countIn('items'), 1);
    expect(
      await app.countIn('stock_ledger'),
      1,
      reason: 'the shelf figure was doubled by a second opening-stock row',
    );
  });

  testWidgets('two taps on the setup wizard make one shop', (tester) async {
    final app = await Harness.start(tester);

    await typeInto(tester, 'Dukan ka naam', 'Chishti Kiryana Store');
    await typeInto(tester, 'Aap ka naam', 'Malik Sahib');
    await typeInto(tester, 'Shehar', 'Lahore');

    await _tapTwiceInOneFrame(tester, 'Dukan shuru karein');

    expect(await app.countIn('firms'), 1);
    expect(await app.countIn('users'), 1);
    expect(await app.countIn('devices'), 1);
  });
}

Future<void> _openEditor(WidgetTester tester, String label) async {
  final fab = find.byType(FloatingActionButton);
  if (fab.evaluate().isNotEmpty) {
    await tester.tap(fab.first);
  } else {
    await tester.tap(find.textContaining(label).first);
  }
  await tester.pumpAndSettle();
}

/// Both taps land before a single frame is built.
///
/// `pump()` between them would rebuild the button as disabled and prove
/// nothing — the whole hazard is that the disable has not happened yet.
Future<void> _tapTwiceInOneFrame(WidgetTester tester, String label) async {
  final button = find.textContaining(label).first;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  final centre = tester.getCenter(button);
  await tester.tapAt(centre);
  await tester.tapAt(centre);
  await tester.pumpAndSettle();
}
