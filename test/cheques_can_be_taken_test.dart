import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// A cheque taken at the counter and against a khata, with its due date.
///
/// The counter offered Cheque and asked for nothing, and the schema refuses a
/// cheque with no number — so every cheque sale failed with "nothing was
/// written". The khata asked for a number and a bank but never the date, and
/// a post-dated cheque without its date is one nobody can bank on time.
void main() {
  testWidgets('a cheque sale at the counter is saved, dated for banking', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await app.seedParty(name: 'Rashid Traders');

    await _ringUp(tester);
    await _pickCustomer(tester);
    await tapText(tester, 'Cheque');
    await typeInto(tester, 'Cheque number', '004512');
    await tapText(tester, '30 din baad');
    await tapButton(tester, 'Save karein');

    final cheque = await app.rowsOf(
      "SELECT cheque_no, status, cheque_date_utc FROM payments WHERE mode = 'cheque'",
    );
    expect(cheque.single['cheque_no'], '004512');
    expect(cheque.single['status'], 'pending');
    final today = BusinessDate.now(app.services.clock);
    expect(
      chequeDueDate(cheque.single['cheque_date_utc']! as int),
      today.addDays(30),
    );

    final inHand = await app.rowsOf(
      'SELECT SUM(jl.debit_paisa - jl.credit_paisa) AS held '
      'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      "WHERE a.system_key = 'cheques_in_hand'",
    );
    expect(
      inHand.single['held'],
      250000,
      reason: 'a cheque is not money in the bank until it clears',
    );
  });

  testWidgets('a cheque from a walk-in is refused in words', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);

    await _ringUp(tester);
    await tapText(tester, 'Cheque');
    await typeInto(tester, 'Cheque number', '004512');
    await tapButton(tester, 'Save karein');

    expect(find.textContaining('naam wale gahak'), findsOneWidget);
    expect(await app.countIn('documents'), 0);
  });

  testWidgets('a cheque with no number is refused in words', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await app.seedParty(name: 'Rashid Traders');

    await _ringUp(tester);
    await _pickCustomer(tester);
    await tapText(tester, 'Cheque');
    await tapButton(tester, 'Save karein');

    expect(find.text('Cheque number likhein'), findsOneWidget);
    expect(await app.countIn('documents'), 0);
  });

  testWidgets('a cheque taken against udhaar carries its due date', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedParty(name: 'Rashid Traders', owedRupees: 45000);

    await tapText(tester, 'Gahak');
    await tapText(tester, 'Rashid Traders');
    await tapText(tester, 'Paisay wasool karein');
    await tapText(tester, 'Cheque');
    await typeInto(tester, 'Cheque number', '778812');
    await tapText(tester, '45 din baad');
    await tapText(tester, 'Wasooli save karein');

    final cheque = await app.rowsOf(
      "SELECT cheque_date_utc FROM payments WHERE mode = 'cheque'",
    );
    expect(
      chequeDueDate(cheque.single['cheque_date_utc']! as int),
      BusinessDate.now(app.services.clock).addDays(45),
    );
  });
}

Future<void> _ringUp(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Naya Bill');
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    'Cooking',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
  await tapButton(tester, 'Paisay lein');
}

Future<void> _pickCustomer(WidgetTester tester) async {
  await tapText(tester, 'Aam gahak');
  await tapText(tester, 'Rashid Traders');
}
