import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

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

    await tapText(tester, 'Maal');
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

  testWidgets('the full item master round-trips through the editor',
      (tester) async {
    final app = await Harness.startWithShop(tester);
    await tester.pumpAndSettle();

    await tapText(tester, 'Maal');
    await tester.pumpAndSettle();
    await tapButton(tester, 'Naya maal');
    await tester.pumpAndSettle();

    await typeInto(tester, 'Naam', 'Panadol 500mg');
    await typeInto(tester, 'Farokht ki qeemat', '45');
    await typeInto(tester, 'Khareed ki qeemat', '38');
    await typeInto(tester, 'Mojooda stock', '200');

    // The rest is folded away, because most of a kiryana catalogue needs none
    // of it. A pharmacy needs the printed price it may not legally exceed,
    // and a registered shop needs the HS code on every invoice line.
    await tester.tap(find.text('Aur tafseel'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Thok ki qeemat', '40');
    await typeInto(tester, 'MRP (chhapi qeemat)', '50');
    await typeInto(tester, 'HS code', '3004.9099');
    await typeInto(tester, 'Tafseel', 'Paracetamol tablets');

    await tapButton(tester, 'Save karein');
    await tester.pumpAndSettle();

    final row = await app.rowsOf(
      'SELECT wholesale_rate_milli_paisa w, mrp_paisa m, hs_code h, '
      'description d, track_stock t FROM items',
    );
    expect(row.single['w'], const Rate.rupees(40).inMilliPaisa);
    expect(row.single['m'], const Money.rupees(50).inPaisa);
    expect(row.single['h'], '3004.9099');
    expect(row.single['d'], 'Paracetamol tablets');
    expect(row.single['t'], 1);
  });

  testWidgets('a service carries no stock and no opening balance',
      (tester) async {
    // Home delivery, a repair, a carrier bag. These belong on a bill and do
    // not belong on a stock ledger, and an item carrying stock it can never
    // have is an item permanently at minus something.
    final app = await Harness.startWithShop(tester);
    await tester.pumpAndSettle();

    await tapText(tester, 'Maal');
    await tester.pumpAndSettle();
    await tapButton(tester, 'Naya maal');
    await tester.pumpAndSettle();

    await typeInto(tester, 'Naam', 'Home delivery');
    await typeInto(tester, 'Farokht ki qeemat', '100');
    await typeInto(tester, 'Mojooda stock', '5');

    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    await tapButton(tester, 'Save karein');
    await tester.pumpAndSettle();

    expect(await app.countIn('items'), 1);
    final tracks = await app.scalar<int>('SELECT track_stock FROM items');
    expect(tracks, 0);
    expect(
      await app.countIn('stock_ledger'),
      0,
      reason: 'a service that carries no stock must not open a stock ledger, '
          'whatever was left in the opening-stock box',
    );
  });

  testWidgets('a correction cannot be saved without a reason', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500, openingStock: 20);
    await tester.pumpAndSettle();

    await tapText(tester, 'Maal');
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

    await tapText(tester, 'Maal');
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
