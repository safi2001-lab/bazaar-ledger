import 'package:bazaar_ledger/app/preferences.dart';
import 'package:bazaar_ledger/design/components.dart';
import 'package:bazaar_ledger/design/text_size.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// Found however it is spelt, weighed the way the bazaar weighs, and
/// readable at any size (M56) — driven at the counter and in Settings.
void main() {
  testWidgets('aata, or atta typed in Urdu, finds Atta at the counter, and '
      'chini finds Cheeni but not Chana', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Atta Chakki', rupees: 120);
    await app.seedItem(name: 'Cheeni Desi', rupees: 160);
    await app.seedItem(name: 'Chana Dal', rupees: 300);
    await tester.pumpAndSettle();

    await tapText(tester, 'Naya Bill');
    await tester.pumpAndSettle();

    await _search(tester, 'aata');
    expect(find.text('Atta Chakki'), findsOneWidget);
    expect(find.text('Chana Dal'), findsNothing);

    await _search(tester, 'آٹا');
    expect(find.text('Atta Chakki'), findsOneWidget);
    expect(find.text('Cheeni Desi'), findsNothing);

    await _search(tester, 'chini');
    expect(find.text('Cheeni Desi'), findsOneWidget);
    expect(find.text('Chana Dal'), findsNothing);

    // And what the cashier finds is what they sell.
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pumpAndSettle();
    await _search(tester, '');
    expect(find.text('Cheeni Desi'), findsOneWidget);
  });

  testWidgets('a kilo and a half on the bill reads 1 kg 500 g, and 1.5 kg '
      'leaves the shelf', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(
      name: 'Atta Chakki',
      rupees: 120,
      unitCode: 'kg',
      openingStock: 50,
    );
    await tester.pumpAndSettle();

    await tapText(tester, 'Naya Bill');
    await tester.pumpAndSettle();
    await _search(tester, 'Atta');
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pumpAndSettle();
    await _search(tester, '');

    await tester.tap(
      find
          .ancestor(of: find.byType(BlQty), matching: find.byType(InkWell))
          .first,
    );
    await tester.pumpAndSettle();
    await typeInto(tester, 'Tadaad (kg)', '1.5');
    await tapButton(tester, 'Ho gaya');
    await tester.pumpAndSettle();

    expect(find.text('1 kg 500 g'), findsOneWidget);
    // Rs 120 a kilo, a kilo and a half: Rs 180.
    expect(find.text('Rs 180.00'), findsWidgets);

    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '180');
    await tapButton(tester, 'Save karein');
    await tester.pumpAndSettle();

    final sold = await app.scalar<int>(
      "SELECT qty_delta_thousandths FROM stock_ledger WHERE txn_type = 'sale'",
    );
    expect(sold, -1500, reason: 'a kilo and a half, to the gram');
  });

  testWidgets('Larger text is applied the moment it is chosen, and the phone '
      'remembers it', (tester) async {
    await Harness.startWithShop(tester);
    await openSettings(tester);

    double scaleOf(String text) => MediaQuery.textScalerOf(
      tester.element(find.text(text).first),
    ).scale(10);
    const hint =
        'Sirf is phone ki screen par. Bill, raseed aur PDF har size par aik '
        'jaise chhapte hain.';
    expect(find.text('LIKHAI KA SIZE'), findsOneWidget);
    expect(scaleOf(hint), closeTo(10, 0.001));

    await tester.tap(find.text('Aur bara'));
    await tester.pumpAndSettle();
    expect(
      scaleOf(hint),
      closeTo(13, 0.001),
      reason: 'the phone is at 100% and the shop asked for Larger',
    );

    // Kept on the phone with the language and the theme, so it is there
    // after a restart.
    // The save writes a real file, which a widget test's fake clock alone
    // never lets finish.
    await settleReal(tester, rounds: 20);
    final saved = await tester.runAsync(AppPreferences.load);
    expect(saved!.textSize, BlTextSize.larger);

    await tester.tap(find.text('Aam'));
    await tester.pumpAndSettle();
    expect(scaleOf(hint), closeTo(10, 0.001));
  });
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    query,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}
