import 'package:bazaar_ledger/design/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// A van's whole day from the screens: added, loaded, this phone set to
/// sell from it, a sale rung up, and the rider's cash settled short.
void main() {
  testWidgets('a van is loaded, sells from the counter, and settles short', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500, openingStock: 50);

    await tapText(tester, 'Gaariyan (van)');
    await tapText(tester, 'Nayi gaari');
    await typeInto(tester, 'Gaari ka naam', 'Suzuki 1');
    await tapText(tester, 'Jorein');

    // This phone sells from the van.
    await tester.tap(find.byKey(const ValueKey('this-phone')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suzuki 1').last);
    await tester.pumpAndSettle();
    expect(await app.services.counterLocation(), 'VAN-SUZUKI1');

    // Loaded with ten.
    await tester.tap(find.text('Suzuki 1').last);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Maal laadein');
    await tester.tap(find.byKey(const ValueKey('load-item')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cooking Oil 5L').last);
    await tester.pumpAndSettle();
    await typeInto(tester, 'Kitna', '10');
    await tester.tap(
      find
          .ancestor(
            of: find.text('Maal laadein').last,
            matching: find.byType(BlButton),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('10 pcs'), findsOneWidget);

    // One sold at the counter, cash.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapText(tester, 'Naya Bill');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Talash karein').first,
      'Cooking',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cooking Oil 5L').first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '2500');
    await tapButton(tester, 'Save karein');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Settled: Rs 2,300 handed in against Rs 2,500.
    await tapText(tester, 'Gaariyan (van)');
    await tester.tap(find.text('Suzuki 1').last);
    await tester.pumpAndSettle();
    expect(find.text('9 pcs'), findsOneWidget);
    await tapButton(tester, 'Hisaab karein');
    await typeInto(tester, 'Rider ne diya (Rs)', '2300');
    await tester.tap(
      find
          .ancestor(
            of: find.text('Hisaab karein').last,
            matching: find.byType(BlButton),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Hisaab ho gaya, Rs 200.00 kam'), findsOneWidget);

    final back = await app.scalar<int>(
      'SELECT SUM(qty_delta_thousandths) FROM stock_ledger '
      "WHERE location_code = 'MAIN'",
    );
    expect(back, 49000, reason: '50 - 10 loaded + 9 brought back');
    final health = await app.services.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  });
}
