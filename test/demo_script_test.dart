import 'package:bazaar_ledger/design/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// The M0 demo script, driven by taps and typing only.
///
/// This is the acceptance gate for the milestone, and it is deliberately
/// written as the thing a person would do rather than as a set of unit tests
/// that happen to touch the same code. Nothing here calls a use case directly:
/// every row asserted at the end got there because a widget was tapped.
///
/// The previous build passed twenty-five tests while `grep
/// InvoicesCompanion.insert lib/` returned no hits anywhere in the repository.
/// The difference is that these assertions read the app's own database after
/// the app's own buttons were pressed, so a checkout that shows a message and
/// writes nothing fails here on the first assertion.
void main() {
  testWidgets('a shopkeeper sets up, stocks two items and rings a cash sale', (
    tester,
  ) async {
    // ---- 1. First run -----------------------------------------------------
    final app = await Harness.start(tester);

    expect(find.text('Apni dukan set karein'), findsOneWidget);
    expect(await app.countIn('firms'), 0, reason: 'nothing written yet');

    await typeInto(tester, 'Dukan ka naam', 'Chishti Kiryana Store');
    await typeInto(tester, 'Aap ka naam', 'Malik Sahib');
    await typeInto(tester, 'Shehar', 'Lahore');
    await tapButton(tester, 'Dukan shuru karein');

    expect(await app.countIn('firms'), 1);
    expect(await app.countIn('users'), 1);
    expect(await app.countIn('devices'), 1);
    expect(
      await app.countIn('accounts'),
      greaterThan(20),
      reason: 'the chart of accounts is seeded on first run',
    );
    expect(find.text('Chishti Kiryana Store'), findsOneWidget);

    // ---- 2. Two items, through the editor ---------------------------------
    await tester.tap(find.text('Maal').first);
    await tester.pumpAndSettle();
    expect(find.text('Abhi koi maal nahi'), findsOneWidget);

    await _addItem(tester, name: 'Cooking Oil 5L', price: '2500', stock: '20');
    await _addItem(tester, name: 'Chawal Basmati', price: '525', stock: '50');

    expect(await app.countIn('items'), 2);
    expect(
      await app.countIn('stock_ledger'),
      2,
      reason: 'opening stock is a ledger movement, not a column',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    // ---- 3. A cash sale ---------------------------------------------------
    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();

    // Two tins of oil and one bag of rice: 2 x 2500 + 525 = 5525. The oil goes
    // on twice, which is what a cashier scanning the same barcode twice means
    // and what every till in the world does with it.
    await _addToCart(tester, 'Cooking Oil');
    await _addToCart(tester, 'Cooking Oil');
    await _addToCart(tester, 'Chawal');

    expect(
      find.text('2 pcs'),
      findsOneWidget,
      reason:
          'a rescan is a second, and a new item defaults to pieces rather '
          'than to whatever unit happens to sort first',
    );

    expect(
      find.text('Rs 5,525.00'),
      findsWidgets,
      reason: 'the running total, before the tender sheet is opened',
    );

    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '6000');
    await tester.pumpAndSettle();
    expect(find.text('475.00'), findsOneWidget, reason: 'change due');

    await tapButton(tester, 'Save karein');

    // ---- 4. What is actually in the database ------------------------------
    final documents = await app.rowsOf(
      'SELECT doc_no, total_paisa, status FROM documents',
    );
    expect(documents, hasLength(1));
    expect(documents.single['doc_no'], 'INV-2627-0001');
    expect(documents.single['total_paisa'], 552500);
    expect(documents.single['status'], 'posted');

    expect(await app.countIn('document_lines'), 2);
    expect(await app.countIn('payments'), 1);
    expect(await app.countIn('payment_allocations'), 1);

    final movements = await app.rowsOf('''
      SELECT qty_delta_thousandths q FROM stock_ledger
      WHERE txn_type = 'sale'
      ORDER BY q
      ''');
    expect(movements, hasLength(2), reason: 'one movement per stocked line');
    expect(
      movements.map((m) => m['q']),
      // Two tins and one bag, in base units times a thousand.
      [-2000, -1000],
      reason: 'stock left the shop, in the item base unit',
    );

    final balance = await app.rowsOf('''
      SELECT SUM(debit_paisa) d, SUM(credit_paisa) c
      FROM journal_lines
      ''');
    expect(balance.single['d'], 552500);
    expect(
      balance.single['c'],
      552500,
      reason: 'the books balance at exact integer equality, no tolerance',
    );

    // Both tables already hold rows from first run and from adding the two
    // items, so `greaterThan(0)` was true before the sale was rung. What has
    // to be true is that the SALE wrote its own.
    final saleAudits = await app.rowsOf('''
      SELECT action_code FROM audit_log
      WHERE entity_table = 'documents'
      ''');
    expect(saleAudits, hasLength(1));
    expect(saleAudits.single['action_code'], 'SALE_POSTED');

    final saleOutbox = await app.rowsOf('''
      SELECT entity_table FROM change_log
      WHERE entity_table IN ('documents', 'document_lines', 'payments',
                             'payment_allocations', 'journal_entries',
                             'journal_lines', 'stock_ledger')
      ''');
    expect(
      saleOutbox.length,
      greaterThanOrEqualTo(10),
      reason:
          'every row the sale wrote is offered to the next counter: '
          'one document, two lines, one payment, one allocation, one entry, '
          'its lines, and two stock movements',
    );

    // ---- 5. And the shopkeeper can see it ---------------------------------
    expect(find.textContaining('INV-2627-0001'), findsWidgets);
  });

  testWidgets('a failed save writes nothing and says so', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);

    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    await _addToCart(tester, 'Cooking Oil');

    // Pull the floor out from under the write path, deep enough that no
    // pre-flight check can catch it: the cash account is still there and
    // still offered at the counter, but the chart entry it posts into has
    // been archived, so the failure happens partway through the transaction —
    // after the document row, after the lines, after the invoice number has
    // been drawn.
    await app.services.database.customStatement('''
      UPDATE accounts SET deleted_at_utc = 1
      WHERE id IN (SELECT ledger_account_id FROM payment_accounts)
      ''');

    await tapButton(tester, 'Paisay lein');
    await tapButton(tester, 'Save karein');

    for (final table in const [
      'documents',
      'document_lines',
      'document_line_taxes',
      'payments',
      'payment_allocations',
    ]) {
      expect(
        await app.countIn(table),
        0,
        reason: '$table must be empty after a failed post',
      );
    }
    // Since M10 the harness's opening stock has an entry of its own; the
    // failed sale must have added nothing beside it.
    expect(
      await app.scalar<int>(
        "SELECT COUNT(*) FROM journal_entries WHERE source_type <> 'opening'",
      ),
      0,
      reason: 'journal_entries must hold no sale after a failed post',
    );
    expect(
      await app.scalar<int>(
        'SELECT COUNT(*) FROM journal_lines jl '
        'JOIN journal_entries je ON je.id = jl.journal_entry_id '
        "WHERE je.source_type <> 'opening'",
      ),
      0,
      reason: 'journal_lines must hold no sale after a failed post',
    );

    expect(
      await app.scalar<int>('''
        SELECT next_value FROM numbering_sequences
        WHERE doc_type = 'sale_invoice'
        '''),
      1,
      reason: 'a rolled-back sale must not burn an invoice number',
    );

    expect(
      find.textContaining('Bill save nahi hua'),
      findsOneWidget,
      reason: 'the shopkeeper is told, in words, that nothing was saved',
    );
  });
}

Future<void> _addItem(
  WidgetTester tester, {
  required String name,
  required String price,
  required String stock,
}) async {
  final fab = find.byType(FloatingActionButton);
  if (fab.evaluate().isNotEmpty) {
    await tester.tap(fab.first);
  } else {
    await tester.tap(find.widgetWithText(BlButton, 'Naya maal').first);
  }
  await tester.pumpAndSettle();

  await typeInto(tester, 'Naam', name);
  await typeInto(tester, 'Farokht ki qeemat', price);
  await typeInto(tester, 'Mojooda stock', stock);
  await tapButton(tester, 'Save karein');
}

Future<void> _addToCart(WidgetTester tester, String query) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    query,
  );
  // The search field is debounced at 250ms so a fast typist does not fire a
  // query per keystroke.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
}
