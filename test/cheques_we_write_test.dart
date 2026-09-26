import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/features/home/home_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Cheques the shop writes, from the app.
///
/// The supplier sheet refused a cheque outright, and in the wholesale trade
/// the shop pays the mill the way its own customers pay it: with a cheque
/// dated a month ahead. The delivery is settled the day the cheque is handed
/// over; the money leaves the bank when the mill presents it, and the shop
/// needs to know that day is coming.
void main() {
  testWidgets('a supplier can be paid by a cheque dated ahead', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _owe(app, rupees: 80000);

    await tapText(tester, 'Gahak');
    await tapText(tester, 'Faisal Flour Mills');
    await tapText(tester, 'Paisay dein');
    await tapText(tester, 'Cheque se diya');
    await typeInto(tester, 'Cheque number', '118830');
    await tapText(tester, '30 din baad');
    await tapButton(tester, 'Payment save karein');

    final cheque = await app.rowsOf(
      'SELECT direction, mode, status, cheque_no, cheque_date_utc '
      'FROM payments',
    );
    expect(cheque.single['direction'], 'out');
    expect(cheque.single['mode'], 'cheque');
    expect(cheque.single['status'], 'pending');
    expect(cheque.single['cheque_no'], '118830');
    expect(
      chequeDueDate(cheque.single['cheque_date_utc']! as int),
      BusinessDate.now(app.services.clock).addDays(30),
    );
    expect(await _net(app, 'bank'), 0, reason: 'nothing has left the bank');
    expect(await _net(app, 'cheques_issued'), -8000000);
  });

  testWidgets('a cheque to a supplier with no number is refused in words', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _owe(app, rupees: 80000);

    await tapText(tester, 'Gahak');
    await tapText(tester, 'Faisal Flour Mills');
    await tapText(tester, 'Paisay dein');
    await tapText(tester, 'Cheque se diya');
    await tapButton(tester, 'Payment save karein');

    expect(find.text('Cheque number likhein'), findsOneWidget);
    expect(await app.countIn('payments'), 0);
  });

  testWidgets('a cheque we wrote is marked paid from the drawer', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final mill = await _owe(app, rupees: 80000);
    await _writeCheque(app, mill, due: BusinessDate.now(app.services.clock));

    await tapText(tester, 'Cheque');
    expect(find.text('HUMARE DIYE HUE CHEQUE'), findsOneWidget);
    await tapText(tester, 'Faisal Flour Mills');
    await tapButton(tester, 'Bank ne ada kar diya');

    expect(await _net(app, 'bank'), -8000000);
    expect(await _net(app, 'cheques_issued'), 0);
    expect(find.text('HUMARE DIYE HUE CHEQUE'), findsNothing);
  });

  testWidgets('a cheque we wrote that bounces is owed to the supplier again', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final mill = await _owe(app, rupees: 80000);
    await _writeCheque(app, mill, due: BusinessDate.now(app.services.clock));

    await tapText(tester, 'Cheque');
    await tapText(tester, 'Faisal Flour Mills');
    await tapButton(tester, 'Bounce ho gaya');
    await tapButton(tester, 'Bounce ho gaya');

    final party = await app.services.queries.partyById(
      app.services.identity!.firmId,
      mill,
    );
    expect(party!.payable, const Money.rupees(80000));
    expect(party.bouncedCheques, 0, reason: 'our bounce is not theirs');
    expect(find.text('BOUNCE HUE'), findsNothing);
  });

  testWidgets('the first screen warns when our cheques can be presented', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final mill = await _owe(app, rupees: 80000);
    await _writeCheque(
      app,
      mill,
      due: BusinessDate.now(app.services.clock).addDays(2),
    );
    ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    ).bumpRefresh();
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Rs 80,000.00 ke apne cheque 3 din mein pesh ho sakte hain — '
        'bank mein paisay rakhein',
      ),
      findsOneWidget,
    );
  });
}

/// Faisal Flour Mills delivered [rupees] of atta, unpaid.
Future<String> _owe(Harness app, {required int rupees}) async {
  final actor = app.services.actorNow();
  final millId = await app.services.catalogue.addParty(
    actor,
    const PartyDraft(name: 'Faisal Flour Mills', partyType: 'supplier'),
  );
  final attaId = await app.seedItem(name: 'Atta 20kg', rupees: 2400);
  final pcs = (await app.services.queries.units(
    actor.firmId,
  )).firstWhere((u) => u.code == 'pcs');
  await app.services.recordPurchase(
    app.services.actorNow(),
    PurchaseDraft(
      partyId: millId,
      lines: [
        PurchaseLineDraft(
          itemId: attaId,
          itemName: 'Atta 20kg',
          qty: Qty.units(40),
          baseQty: Qty.units(40),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees ~/ 40),
        ),
      ],
    ),
  );
  return millId;
}

Future<void> _writeCheque(
  Harness app,
  String millId, {
  required BusinessDate due,
}) async {
  final accounts = await app.services.queries.paymentAccounts(
    app.services.identity!.firmId,
  );
  await app.services.paySupplier(
    app.services.actorNow(),
    SupplierPaymentDraft(
      partyId: millId,
      amount: const Money.rupees(80000),
      mode: 'cheque',
      paymentAccountId: accounts
          .firstWhere((a) => a.modeLabel == 'bank_transfer')
          .id,
      chequeNo: '118830',
      chequeDateUtcMillis: chequeDueUtcMillis(due),
    ),
  );
}

Future<int> _net(Harness app, String systemKey) async =>
    await app.scalar<int>(
      'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) '
      'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      "WHERE a.system_key = '$systemKey'",
    ) ??
    0;
