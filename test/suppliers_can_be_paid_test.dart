import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Paying a supplier, from the app.
///
/// Until this there was a way to owe a supplier — any delivery not fully paid
/// at the door — and no way to stop owing them. These drive the real khata
/// screen and read what the payment wrote back out of the database.
void main() {
  testWidgets('a supplier the shop owes does not read as settled', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _owe(app, rupees: 5000);

    await tapText(tester, 'Gahak');

    expect(find.text('5,000.00 dena hai'), findsOneWidget);
    expect(find.text('Hisaab saaf'), findsNothing);
  });

  testWidgets('a supplier is paid from their khata and the debt comes down', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final millId = await _owe(app, rupees: 5000);

    await _openKhata(tester);
    expect(find.text('Kitna dena hai'), findsOneWidget);

    await tapText(tester, 'Paisay dein');
    await typeInto(tester, 'Kitne diye', '3000');
    await tapButton(tester, 'Payment save karein');

    final payment = await app.rowsOf(
      'SELECT direction, amount_paisa, party_id FROM payments',
    );
    expect(payment.single['direction'], 'out');
    expect(payment.single['amount_paisa'], 300000);
    expect(payment.single['party_id'], millId);

    final mill = await app.services.queries.partyById(
      app.services.identity!.firmId,
      millId,
    );
    expect(mill!.payable, const Money.rupees(2000));
  });

  testWidgets('the preview names the delivery before the money leaves', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _owe(app, rupees: 5000);

    await _openKhata(tester);
    await tapText(tester, 'Paisay dein');

    // Prefilled with everything owed, so the whole delivery clears.
    expect(find.text('Yeh bill chuk jayenge'), findsOneWidget);
    expect(find.text('Ho gaya'), findsOneWidget);
  });

  testWidgets('paying more than is owed is refused in words', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _owe(app, rupees: 5000);

    await _openKhata(tester);
    await tapText(tester, 'Paisay dein');
    await typeInto(tester, 'Kitne diye', '6000');
    await tapButton(tester, 'Payment save karein');

    expect(find.text('Sirf 5,000.00 dena hai'), findsOneWidget);
    expect(await app.countIn('payments'), 0);
  });

  testWidgets('a paid-off supplier shows nothing left to pay', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _owe(app, rupees: 5000);

    await _openKhata(tester);
    await tapText(tester, 'Paisay dein');
    await tapButton(tester, 'Payment save karein');

    expect(find.text('Is supplier ka sab chuka diya'), findsOneWidget);
    final books = await app.rowsOf(
      'SELECT SUM(debit_paisa) AS dr, SUM(credit_paisa) AS cr '
      'FROM journal_lines',
    );
    expect(books.single['dr'], books.single['cr']);
  });
}

/// A supplier with one delivery of [rupees] not yet paid for.
Future<String> _owe(Harness app, {required int rupees}) async {
  final actor = app.services.actorNow();
  final millId = await app.services.catalogue.addParty(
    actor,
    const PartyDraft(name: 'Punjab Rice Mills', partyType: 'supplier'),
  );
  final riceId = await app.seedItem(name: 'Chawal Basmati', rupees: 150);
  final pcs = (await app.services.queries.units(
    actor.firmId,
  )).firstWhere((u) => u.code == 'pcs');

  await app.services.recordPurchase(
    app.services.actorNow(),
    PurchaseDraft(
      partyId: millId,
      lines: [
        PurchaseLineDraft(
          itemId: riceId,
          itemName: 'Chawal Basmati',
          qty: Qty.units(10),
          baseQty: Qty.units(10),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees ~/ 10),
        ),
      ],
    ),
  );
  return millId;
}

Future<void> _openKhata(WidgetTester tester) async {
  await tapText(tester, 'Gahak');
  await tapText(tester, 'Punjab Rice Mills');
}
