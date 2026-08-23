import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// Correcting the shelf, from the shelf.
///
/// The write path has its own tests in `pk_data`. What these prove is that a
/// shopkeeper can actually reach it: the action is on the item they are
/// looking at, the sheet takes what they counted rather than a difference
/// they have to work out in their head, and the reason cannot be skipped.
void main() {
  testWidgets('a stock take that comes up short is written down',
      (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500, openingStock: 20);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Maal').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Cooking Oil').first);
    await tester.pumpAndSettle();

    // An icon button in the app bar: its label is a semantics label, which
    // is what a screen reader speaks, not visible text.
    await tester.tap(find.byIcon(Icons.fact_check_outlined));
    await tester.pumpAndSettle();

    // The field opens holding what the ledger says, so a shelf that agrees
    // needs no typing at all.
    expect(find.text('20'), findsWidgets);

    await typeInto(tester, 'Ginti ke baad kitna hai', '17');
    await typeInto(tester, 'Wajah', 'Mahana ginti');
    await tapButton(tester, 'Theek karein');
    await tester.pumpAndSettle();

    // A ledger row, not a column write: the opening stock plus the
    // correction, and both still there.
    final movements = await app.rowsOf(
      'SELECT txn_type, qty_delta_thousandths q, reason FROM stock_ledger '
      'ORDER BY occurred_at_utc, id',
    );
    expect(movements, hasLength(2));
    expect(movements.last['txn_type'], 'adjustment');
    expect(movements.last['q'], -3000);
    expect(movements.last['reason'], 'Mahana ginti');

    // And the books know about it: three tins at what they cost.
    final wastage = await app.scalar<int>(
      '''
      SELECT SUM(jl.debit_paisa) FROM journal_lines jl
      JOIN accounts a ON a.id = jl.account_id
      WHERE a.code = '5500'
      ''',
    );
    expect(
      wastage,
      isNotNull,
      reason: 'goods off the shelf are an expense whether or not anyone '
          'noticed; without the entry the Trial Balance is quietly wrong',
    );
  });

  testWidgets('a correction cannot be saved without a reason', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500, openingStock: 20);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Maal').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Cooking Oil').first);
    await tester.pumpAndSettle();
    // An icon button in the app bar: its label is a semantics label, which
    // is what a screen reader speaks, not visible text.
    await tester.tap(find.byIcon(Icons.fact_check_outlined));
    await tester.pumpAndSettle();

    await typeInto(tester, 'Ginti ke baad kitna hai', '17');
    await tapButton(tester, 'Theek karein');
    await tester.pumpAndSettle();

    expect(find.text('Wajah likhna zaroori hai'), findsOneWidget);
    expect(
      await app.countIn('stock_ledger'),
      1,
      reason: 'only the opening row; nothing was corrected',
    );
  });

  testWidgets('a breakage is typed as what broke, not as a negative',
      (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500, openingStock: 20);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Maal').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Cooking Oil').first);
    await tester.pumpAndSettle();
    // An icon button in the app bar: its label is a semantics label, which
    // is what a screen reader speaks, not visible text.
    await tester.tap(find.byIcon(Icons.fact_check_outlined));
    await tester.pumpAndSettle();

    // Switch to the write-off shape and say three broke. Asking a shopkeeper
    // to type a minus sign would be asking them to get it wrong.
    await tapButton(tester, 'Zaya hua maal');
    await tester.pumpAndSettle();
    await typeInto(tester, 'Zaya hua maal', '3');
    await typeInto(tester, 'Wajah', 'Toot gaye');
    await tapButton(tester, 'Theek karein');
    await tester.pumpAndSettle();

    final row = await app.rowsOf(
      'SELECT txn_type, qty_delta_thousandths q FROM stock_ledger '
      "WHERE reason = 'Toot gaye'",
    );
    expect(row.single['txn_type'], 'wastage');
    expect(row.single['q'], -3000, reason: 'three tins left the shelf');
  });
}
