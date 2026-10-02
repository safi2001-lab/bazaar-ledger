import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/features/home/home_screen.dart';
import 'package:bazaar_ledger/features/sales/receipt_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Every entry in a khata can be opened and put right; a bill stays as it
/// was printed (M31).
///
/// Shopkeepers testing the app reported that a customer account entry could
/// not be changed once it was added. These drive the real screens — tap the
/// entry, cancel it or correct it — and then read the books back out of the
/// database, because a button that says "cancelled" and writes nothing is
/// the failure this project exists to make impossible.
void main() {
  testWidgets('a receipt is cancelled from the khata and is owed again', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await _sellOnUdhaar(app, rupees: 3000);
    final receipt = await _receive(app, rashid, rupees: 1000);

    await _openKhata(tester, 'Rashid Traders');
    await tapText(tester, receipt.paymentNo);
    // The whole receipt, and who took it and when.
    expect(find.textContaining('Malik Sahib ·'), findsOneWidget);

    await tapButton(tester, 'Mansookh karein');
    // A reason picked, not typed: one of the presets the books can count.
    await tapText(tester, 'Do baar likh di');
    await tapButton(tester, 'Haan, mansookh karein');
    await settleReal(
      tester,
      until: find.text('${receipt.paymentNo} mansookh ho gaya'),
    );

    final payment = await app.rowsOf('SELECT status FROM payments');
    expect(payment.single['status'], 'void');
    final reason = await app.rowsOf(
      "SELECT after_json FROM audit_log WHERE action_code = 'PAYMENT_VOIDED'",
    );
    expect(reason.single['after_json'], contains('Do baar likh di'));
    final party = await app.services.queries.partyById(
      app.services.identity!.firmId,
      rashid,
    );
    expect(party!.balance, const Money.rupees(3000));
    await _expectBooksBalance(app);
  });

  testWidgets('an edited receipt leaves one payment, at the new amount', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await _sellOnUdhaar(app, rupees: 3000);
    final wrong = await _receive(app, rashid, rupees: 5000);

    await _openKhata(tester, 'Rashid Traders');
    await tapText(tester, wrong.paymentNo);
    await tapButton(tester, 'Tabdeeli karein');
    // The same sheet the receipt was taken with, filled in with it.
    expect(find.text('${wrong.paymentNo} theek karein'), findsOneWidget);
    await typeInto(tester, 'Kitne paisay milay', '500');
    await tapButton(tester, 'Tabdeeli save karein');
    await settleReal(tester, until: find.textContaining('theek ho gaya, ab'));

    final live = await app.rowsOf(
      "SELECT amount_paisa FROM payments WHERE status <> 'void'",
    );
    expect(live.single['amount_paisa'], 50000);
    expect(await app.rowsOf('SELECT id FROM payments'), hasLength(2));
    final party = await app.services.queries.partyById(
      app.services.identity!.firmId,
      rashid,
    );
    expect(party!.balance, const Money.rupees(2500));
    await _expectBooksBalance(app);

    // The corrected receipt remembers what it replaced, a tap away.
    final fresh =
        (await app.rowsOf(
              "SELECT payment_no FROM payments WHERE status <> 'void'",
            )).single['payment_no']!
            as String;
    await tapText(tester, fresh);
    await tapText(tester, '${wrong.paymentNo} ki jagah likhi gayi');
    expect(find.text('Mansookh'), findsOneWidget);
  });

  testWidgets('a cashier is not offered a cancel, and cannot make one', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await _sellOnUdhaar(app, rupees: 3000);
    final receipt = await _receive(app, rashid, rupees: 1000);
    await _signInAsCashier(tester, app);

    await _openKhata(tester, 'Rashid Traders');
    await tapText(tester, receipt.paymentNo);

    expect(find.text('Mansookh karein'), findsNothing);
    expect(find.text('Tabdeeli karein'), findsNothing);
    expect(
      find.text(
        'Isay sirf malik, manager ya accountant badal ya mansookh kar sakte '
        'hain.',
      ),
      findsOneWidget,
    );
    // And the service, which is what actually stands in the way.
    expect(() => app.services.corrections, throwsA(isA<PermissionDenied>()));
    final payment = await app.rowsOf('SELECT status FROM payments');
    expect(payment.single['status'], 'cleared');
  });

  testWidgets('a sale bill opens as it was printed, with nothing to edit', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _sellOnUdhaar(app, rupees: 3000);
    final bill = (await app.rowsOf(
      "SELECT id, doc_no FROM documents WHERE doc_type = 'sale_invoice'",
    )).single;

    await _openKhata(tester, 'Rashid Traders');
    // The open bill by the number on the paper, never by its database id.
    expect(find.text(bill['doc_no']! as String), findsWidgets);
    expect(find.text(bill['id']! as String), findsNothing);

    await tapText(tester, bill['doc_no']! as String);
    expect(find.byType(ReceiptScreen), findsOneWidget);
    expect(find.byTooltip('Tabdeeli karein'), findsNothing);
    expect(find.text('Tabdeeli karein'), findsNothing);
  });

  testWidgets('an expense is opened from the list and cancelled', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final rent = await _spend(app, rupees: 4000);

    await tapText(tester, 'Kharcha');
    await tapText(tester, 'August ka kiraya');
    await tapButton(tester, 'Mansookh karein');
    await typeInto(tester, 'Wajah', 'Do baar likha gaya');
    await tapButton(tester, 'Haan, mansookh karein');
    await settleReal(
      tester,
      until: find.text('${rent.docNo} mansookh ho gaya'),
    );

    final doc = await app.rowsOf(
      "SELECT status FROM documents WHERE doc_type = 'expense'",
    );
    expect(doc.single['status'], 'void');
    expect(find.text('Abhi koi kharcha nahi'), findsOneWidget);
    await _expectBooksBalance(app);
  });

  testWidgets('an expense is corrected to the right amount', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _spend(app, rupees: 40000);

    await tapText(tester, 'Kharcha');
    await tapText(tester, 'August ka kiraya');
    await tapButton(tester, 'Tabdeeli karein');
    await typeInto(tester, 'Raqam', '4000');
    await tapButton(tester, 'Tabdeeli save karein');
    await settleReal(tester, until: find.textContaining('theek ho gaya, ab'));

    final posted = await app.rowsOf(
      'SELECT total_paisa FROM documents '
      "WHERE doc_type = 'expense' AND status = 'posted'",
    );
    expect(posted.single['total_paisa'], 400000);
    await _expectBooksBalance(app);
  });

  testWidgets('an opening balance is corrected from the khata', (tester) async {
    final app = await Harness.startWithShop(tester);
    final aslam = await app.seedParty(name: 'Aslam Karyana', owedRupees: 4500);

    await _openKhata(tester, 'Aslam Karyana');
    await tapText(tester, 'Purana baqaya');
    await typeInto(tester, 'Sahi purana baqaya', '45000');
    await typeInto(tester, 'Wajah', 'Ek sifar reh gaya tha');
    await tapButton(tester, 'Theek karein');
    await settleReal(tester, until: find.text('Purana baqaya theek ho gaya'));

    final party = await app.services.queries.partyById(
      app.services.identity!.firmId,
      aslam,
    );
    expect(party!.balance, const Money.rupees(45000));
    await _expectBooksBalance(app);
  });

  testWidgets('a payment to a supplier is cancelled from their khata', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final mill = await _owe(app, rupees: 5000);
    final paid = await app.services.paySupplier(
      app.services.actorNow(),
      SupplierPaymentDraft(
        partyId: mill,
        amount: const Money.rupees(3000),
        mode: 'cash',
        paymentAccountId: await _cash(app),
      ),
    );

    await _openKhata(tester, 'Punjab Rice Mills');
    await tapText(tester, paid.paymentNo);
    await tapButton(tester, 'Mansookh karein');
    await typeInto(tester, 'Wajah', 'Galat account se diya');
    await tapButton(tester, 'Haan, mansookh karein');
    await settleReal(
      tester,
      until: find.text('${paid.paymentNo} mansookh ho gaya'),
    );

    final party = await app.services.queries.partyById(
      app.services.identity!.firmId,
      mill,
    );
    expect(party!.payable, const Money.rupees(5000));
    await _expectBooksBalance(app);
  });
}

Future<void> _expectBooksBalance(Harness app) async {
  final totals = await app.rowsOf(
    'SELECT SUM(debit_paisa) AS dr, SUM(credit_paisa) AS cr FROM journal_lines',
  );
  expect(totals.single['dr'], totals.single['cr']);
  final health = await app.services.checkHealth();
  expect(health.findings, isEmpty);
}

Future<void> _openKhata(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Gahak');
  await tapText(tester, name);
}

Future<String> _cash(Harness app) async =>
    (await app.services.queries.paymentAccounts(
      app.services.identity!.firmId,
    )).firstWhere((a) => a.isDefault).id;

Future<RecordedReceipt> _receive(
  Harness app,
  String partyId, {
  required int rupees,
}) async => app.services.recordReceipt(
  app.services.actorNow(),
  ReceiptDraft(
    partyId: partyId,
    amount: Money.rupees(rupees),
    mode: 'cash',
    paymentAccountId: await _cash(app),
  ),
);

Future<RecordedExpense> _spend(Harness app, {required int rupees}) async =>
    app.services.recordExpense(
      app.services.actorNow(),
      ExpenseDraft(
        accountSystemKey: 'rent',
        amount: Money.rupees(rupees),
        note: 'August ka kiraya',
        paymentAccountId: await _cash(app),
      ),
    );

/// One bill to Rashid, entirely on udhaar. Returns Rashid's id.
Future<String> _sellOnUdhaar(Harness app, {required int rupees}) async {
  final partyId = await app.seedParty(name: 'Rashid Traders');
  final itemId = await app.seedItem(name: 'Cooking Oil', rupees: rupees);
  final pcs = (await app.services.queries.units(
    app.services.identity!.firmId,
  )).firstWhere((u) => u.code == 'pcs');
  await app.services.postSale(
    app.services.actorNow(),
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: 'Cooking Oil',
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
        ),
      ],
    ),
  );
  return partyId;
}

/// A supplier with one delivery of [rupees] not yet paid for.
Future<String> _owe(Harness app, {required int rupees}) async {
  final millId = await app.services.catalogue.addParty(
    app.services.actorNow(),
    const PartyDraft(name: 'Punjab Rice Mills', partyType: 'supplier'),
  );
  final riceId = await app.seedItem(name: 'Chawal Basmati', rupees: 150);
  final pcs = (await app.services.queries.units(
    app.services.identity!.firmId,
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

/// The owner's PIN, Bilal at the counter with his own, and Bilal signed in.
Future<void> _signInAsCashier(WidgetTester tester, Harness app) async {
  final services = app.services;
  await services.setPin(services.currentUser!.id, '1947');
  await services.addStaff(name: 'Bilal', role: Role.cashier, pin: '2468');
  ProviderScope.containerOf(
    tester.element(find.byType(HomeScreen)),
  ).bumpRefresh();
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Taala lagayein'));
  await tester.pumpAndSettle();
  await tapText(tester, 'Bilal · Cashier');
  await typeInto(tester, 'PIN', '2468');
  await tapButton(tester, 'Kholein');
}
