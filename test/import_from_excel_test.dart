import 'dart:convert';
import 'dart:typed_data';

import 'package:bazaar_ledger/features/import/import_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// A shop's old lists, brought in from the file they already keep them in.
void main() {
  Uint8List csv(String text) => Uint8List.fromList(utf8.encode(text));

  testWidgets('an item list from Excel becomes items with stock on hand', (
    tester,
  ) async {
    final file = csv(
      'Item name,Sale price,Purchase price,Opening quantity\n'
      'Sugar 1kg,160,140,25\n'
      'Ghee 1kg,650,600,4\n'
      ',100,,\n',
    );
    final app = await Harness.startWithShop(
      tester,
      overrides: [
        pickImportFileProvider.overrideWithValue(
          () async => ('stock.csv', file),
        ),
      ],
    );

    await openSettings(tester);
    await tapText(tester, 'Excel se laayein');
    await tapButton(tester, 'File chunein');
    expect(find.text('2 line tayyar'), findsOneWidget);
    expect(find.text('1 line nahin aa sakti'), findsOneWidget);

    await tapButton(tester, '2 laayein');
    expect(find.text('2 aa gaye, 0 chhor diye'), findsOneWidget);

    final items = await app.rowsOf(
      'SELECT name, sale_rate_milli_paisa FROM items ORDER BY name',
    );
    expect(items.map((r) => r['name']), ['Ghee 1kg', 'Sugar 1kg']);
    final stock = await app.scalar<int>(
      'SELECT SUM(qty_delta_thousandths) FROM stock_ledger',
    );
    expect(stock, 29000);
    final health = await app.services.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  });

  testWidgets('a khata list comes in with what each customer owes', (
    tester,
  ) async {
    final file = csv(
      'Party Name,Phone,Opening Balance,Type\n'
      'Rashid Traders,0300-1234567,4500,Customer\n'
      'Bilal Store,,1200,\n',
    );
    final app = await Harness.startWithShop(
      tester,
      overrides: [
        pickImportFileProvider.overrideWithValue(
          () async => ('khata.csv', file),
        ),
      ],
    );
    await app.seedParty(name: 'Bilal Store');

    await openSettings(tester);
    await tapText(tester, 'Excel se laayein');
    await tapText(tester, 'Khata');
    await tapButton(tester, 'File chunein');
    // Bilal Store is already in the khata. Since M52 that is said before
    // anything is written, and the button offers only what will come in.
    expect(find.text('1 pehle se dukaan mein hain'), findsOneWidget);
    await tapButton(tester, '1 laayein');

    expect(find.text('1 aa gaye, 1 chhor diye'), findsOneWidget);
    expect(
      find.text('Line 3: Bilal Store pehle se khate mein hai'),
      findsOneWidget,
    );
    final owed = await app.scalar<int>(
      "SELECT opening_balance_paisa FROM parties WHERE name = 'Rashid Traders'",
    );
    expect(owed, 450000);
  });
}
