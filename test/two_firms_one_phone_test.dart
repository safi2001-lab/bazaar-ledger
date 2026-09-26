import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// Two firms on one phone, from the screen.
void main() {
  testWidgets('a second firm is added and opened, with its own khatas', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedParty(name: 'Store Customer');

    await openSettings(tester);
    await tapText(tester, 'Dukaanein aur firms');
    await tapButton(tester, 'Nayi firm');
    await typeInto(tester, 'Firm ka naam', 'Chishti Traders');
    await tester.tap(find.text('Nayi firm').last);
    await tester.pumpAndSettle();
    expect(find.text('Chishti Traders'), findsOneWidget);

    await tapText(tester, 'Chishti Traders');
    // Back on the first screen, which now carries the other firm's name.
    expect(find.text('Naya Bill'), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Chishti Traders'),
      ),
      findsOneWidget,
    );
    expect(find.text('Chishti Kiryana Store'), findsNothing);

    await tapText(tester, 'Gahak');
    expect(find.text('Store Customer'), findsNothing);
  });
}
