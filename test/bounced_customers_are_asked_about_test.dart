import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// A customer whose cheque bounced, at the counter.
///
/// The bounce put the udhaar back on the khata and nothing else changed: the
/// same customer could walk up the next morning, take another Rs 50,000 of
/// goods on udhaar, and pay with another cheque on the same account. The
/// counter now says so first, and the shopkeeper decides.
void main() {
  testWidgets('udhaar for a customer whose cheque bounced is asked about', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _bouncedCustomer(app);

    await _ringUp(tester);
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Save karein');

    expect(find.text('Is gahak ka cheque bounce ho chuka hai'), findsOneWidget);
    expect(find.textContaining('45,000.00'), findsWidgets);
    expect(await _sales(app), 0);
  });

  testWidgets('credit can still be given to them, knowingly', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _bouncedCustomer(app);

    await _ringUp(tester);
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Save karein');
    await tapButton(tester, 'Phir bhi dein');
    await tapButton(tester, 'Save karein');

    expect(await _sales(app), 1);
  });

  testWidgets('another cheque from them is asked about too', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _bouncedCustomer(app);

    await _ringUp(tester);
    await tapText(tester, 'Cheque');
    await typeInto(tester, 'Cheque number', '004513');
    await tapButton(tester, 'Save karein');

    expect(find.text('Is gahak ka cheque bounce ho chuka hai'), findsOneWidget);
    expect(await _sales(app), 0);
  });

  testWidgets('cash from them is never interrupted', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _bouncedCustomer(app);

    await _ringUp(tester);
    await typeInto(tester, 'Diye gaye', '1000');
    await tapButton(tester, 'Save karein');

    expect(find.text('Is gahak ka cheque bounce ho chuka hai'), findsNothing);
    expect(await _sales(app), 1);
  });

  testWidgets('once they have paid up they are not asked', (tester) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await _bouncedCustomer(app);
    await app.services.recordReceipt(
      app.services.actorNow(),
      ReceiptDraft(
        partyId: rashid,
        amount: const Money.rupees(45000),
        mode: 'cash',
        paymentAccountId: (await _accounts(
          app,
        )).firstWhere((a) => a.isDefault).id,
      ),
    );

    await _ringUp(tester);
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Save karein');

    expect(find.text('Is gahak ka cheque bounce ho chuka hai'), findsNothing);
    expect(await _sales(app), 1);
  });

  testWidgets('the khata carries the bounce', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _bouncedCustomer(app);

    await tapText(tester, 'Gahak');
    await tapText(tester, 'Rashid Traders');

    expect(find.text('1 cheque bounce hua'), findsOneWidget);
  });
}

/// Rashid Traders owes Rs 45,000, pays it with a cheque due today, and the
/// bank sends it back.
Future<String> _bouncedCustomer(Harness app) async {
  await app.seedItem(name: 'Cooking Oil 5L', rupees: 1000);
  final rashid = await app.seedParty(name: 'Rashid Traders', owedRupees: 45000);
  final cheque = await app.services.recordReceipt(
    app.services.actorNow(),
    ReceiptDraft(
      partyId: rashid,
      amount: const Money.rupees(45000),
      mode: 'cheque',
      paymentAccountId: (await _accounts(
        app,
      )).firstWhere((a) => a.modeLabel == 'cheque').id,
      chequeNo: '004512',
      chequeBank: 'Meezan',
      chequeDateUtcMillis: chequeDueUtcMillis(
        BusinessDate.now(app.services.clock),
      ),
    ),
  );
  await app.services.cheques.bounce(
    app.services.actorNow(),
    cheque.paymentId,
    reason: 'Funds insufficient',
  );
  return rashid;
}

Future<List<PaymentAccountSummary>> _accounts(Harness app) async => app
    .services
    .queries
    .paymentAccounts((await app.services.queries.currentFirm())!.id);

Future<int> _sales(Harness app) async =>
    await app.scalar<int>(
      "SELECT COUNT(*) FROM documents WHERE doc_type = 'sale_invoice'",
    ) ??
    0;

/// One tin of oil in the cart for Rashid Traders, at the payment sheet.
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
  await tapText(tester, 'Aam gahak');
  await tapText(tester, 'Rashid Traders');
}
