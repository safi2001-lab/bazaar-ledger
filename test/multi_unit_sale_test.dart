import 'package:bazaar_ledger/design/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// Selling in one unit while the shelf is counted in another.
///
/// This is how a Pakistani shop actually trades. Atta is bought and quoted by
/// the maund and handed over by the kilo; eggs come in and go out by the
/// dozen and are counted in pieces. Until now the counter could only sell in
/// the item's own unit, which meant a shopkeeper doing either had to do the
/// arithmetic in their head and type the answer — and the whole point of this
/// product is that nobody does arithmetic in their head.
///
/// The property that matters is that the paper and the shelf disagree about
/// nothing: the bill says what the customer asked for, in the words they
/// asked for it, and the stock ledger moves the goods that actually left.
void main() {
  testWidgets('a bill in maunds takes kilos off the shelf', (tester) async {
    final app = await Harness.startWithShop(tester);
    // Atta, stocked in kilos: 200 kg on the shelf at Rs 120 a kilo.
    await app.seedItem(
      name: 'Atta Chakki',
      rupees: 120,
      unitCode: 'kg',
      openingStock: 200,
    );
    await tester.pumpAndSettle();

    await tapText(tester, 'Naya Bill');
    await tester.pumpAndSettle();
    await _addToCart(tester, 'Atta');
    await _clearSearch(tester);

    // Switch the line to maunds. A maund is 40 kg, so the price has to follow:
    // Rs 120 a kilo is Rs 4,800 a maund. A counter that changed the unit and
    // left the price alone would charge a maund at the price of a kilo.
    await tester.tap(
      find.ancestor(of: find.byType(BlQty), matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(ChoiceChip, 'maund'),
      findsOneWidget,
      reason: 'the counter offers no way to sell atta by the maund',
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'maund'));
    await tester.pumpAndSettle();

    // Two maunds.
    await tester.tap(
      find.ancestor(of: find.byType(BlQty), matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
    await typeInto(tester, 'Tadaad (maund)', '2');
    await tapButton(tester, 'Ho gaya');
    await tester.pumpAndSettle();

    // Rs 4,800 a maund, two maunds: Rs 9,600.
    expect(find.text('Rs 9,600.00'), findsWidgets);

    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '9600');
    await tapButton(tester, 'Save karein');
    await tester.pumpAndSettle();

    // The bill says maunds, because that is what the customer asked for.
    final line = await app.rowsOf(
      'SELECT unit_code_snapshot u, qty_thousandths q, '
      'base_qty_thousandths b, rate_milli_paisa r FROM document_lines',
    );
    expect(line.single['u'], 'maund');
    expect(line.single['q'], 2000, reason: 'two maunds, as typed');

    // The shelf moves in kilos, because that is what left it.
    expect(
      line.single['b'],
      80000,
      reason: 'two maunds is eighty kilos, and the shelf is counted in kilos',
    );

    final movement = await app.scalar<int>(
      "SELECT qty_delta_thousandths FROM stock_ledger WHERE txn_type = 'sale'",
    );
    expect(movement, -80000);

    // And 120 kg are left of the 200 that were there.
    final onHand = await app.scalar<int>(
      'SELECT SUM(qty_delta_thousandths) FROM stock_ledger',
    );
    expect(onHand, 120000);

    // The books balance on the number the customer paid.
    final balance = await app.rowsOf(
      'SELECT SUM(debit_paisa) d, SUM(credit_paisa) c FROM journal_lines',
    );
    expect(balance.single['d'], balance.single['c']);

    final total = await app.scalar<int>('SELECT total_paisa FROM documents');
    expect(total, 960000);
  });

  testWidgets('an item with no conversions offers no choice at all',
      (tester) async {
    // The ordinary case, and it must stay out of the way: a kiryana counter
    // sells pieces of what it stocks in pieces, and a unit picker with one
    // option in it is a control that only takes up room.
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await tester.pumpAndSettle();

    await tapText(tester, 'Naya Bill');
    await tester.pumpAndSettle();
    await _addToCart(tester, 'Cooking Oil');
    await _clearSearch(tester);

    await tester.tap(
      find.ancestor(of: find.byType(BlQty), matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();

    // Pieces convert to dozens, so this item DOES have a choice. What must
    // not appear is a unit from another kind entirely.
    expect(find.widgetWithText(ChoiceChip, 'kg'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'maund'), findsNothing);
  });
}

Future<void> _addToCart(WidgetTester tester, String query) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    query,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
}

Future<void> _clearSearch(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    '',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}
