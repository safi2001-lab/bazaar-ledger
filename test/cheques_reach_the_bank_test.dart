import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/features/home/home_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// The cheque drawer, from the screen.
///
/// Taking a cheque was already recorded; what happened to it next was not.
/// There was nowhere to say a cheque had cleared or bounced, so every cheque
/// ever taken sat in Cheques in Hand for good, and a bounced one read as
/// paid on the customer's khata.
void main() {
  testWidgets('the drawer lists what is due today before what is not', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await app.seedParty(
      name: 'Rashid Traders',
      owedRupees: 45000,
    );
    final today = BusinessDate.now(app.services.clock);
    await _takeCheque(app, rashid, no: 'LATER', due: today.addDays(10));
    await _takeCheque(app, rashid, no: 'TODAY', due: today);

    await tapText(tester, 'Cheque');

    expect(find.text('Aaj jama karein'), findsOneWidget);
    expect(find.text('10 din baqi'), findsOneWidget);
    expect(
      tester.getTopLeft(find.textContaining('TODAY')).dy,
      lessThan(tester.getTopLeft(find.textContaining('LATER')).dy),
    );
  });

  testWidgets('a cheque cleared from the drawer puts the money in the bank', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await app.seedParty(
      name: 'Rashid Traders',
      owedRupees: 45000,
    );
    await _takeCheque(
      app,
      rashid,
      no: '004512',
      due: BusinessDate.now(app.services.clock),
    );

    await tapText(tester, 'Cheque');
    await tapText(tester, 'Rashid Traders');
    await tapButton(tester, 'Clear ho gaya');
    await tapButton(tester, 'Clear ho gaya');

    expect(await _net(app, 'cheques_in_hand'), 0);
    expect(await _net(app, 'bank'), 4500000);
    expect(find.text('Koi cheque haath mein nahi'), findsOneWidget);
  });

  testWidgets('a bounced cheque reopens the khata and names the notice date', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await app.seedParty(
      name: 'Rashid Traders',
      owedRupees: 45000,
    );
    final today = BusinessDate.now(app.services.clock);
    await _takeCheque(app, rashid, no: '004512', due: today);

    await tapText(tester, 'Cheque');
    await tapText(tester, 'Rashid Traders');
    await tapButton(tester, 'Bounce ho gaya');
    await typeInto(
      tester,
      'Bank ne kya likha (marzi se)',
      'Funds insufficient',
    );
    await tapButton(tester, 'Bounce ho gaya');

    final firm = await app.services.queries.currentFirm();
    final party = await app.services.queries.partyById(firm!.id, rashid);
    expect(party!.balance, const Money.rupees(45000));
    expect(
      find.text('489-F notice ${today.addDays(30).value} tak bhejein'),
      findsOneWidget,
    );
    final reason = await app.scalar<String>(
      "SELECT narration FROM journal_entries WHERE source_type = 'reversal'",
    );
    expect(reason, contains('Funds insufficient'));
  });

  testWidgets('the bank fee on a bounce is booked against the bank', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await app.seedParty(
      name: 'Rashid Traders',
      owedRupees: 45000,
    );
    await _takeCheque(
      app,
      rashid,
      no: '004512',
      due: BusinessDate.now(app.services.clock),
    );

    await tapText(tester, 'Cheque');
    await tapText(tester, 'Rashid Traders');
    await tapButton(tester, 'Bounce ho gaya');
    await typeInto(tester, 'Bank ki fee, agar kaati (marzi se)', '500');
    await tapButton(tester, 'Bounce ho gaya');

    final fee = await app.rowsOf(
      "SELECT d.total_paisa, d.notes FROM documents d WHERE d.doc_type = 'expense'",
    );
    expect(fee.single['total_paisa'], 50000);
    expect(fee.single['notes'], contains('004512'));
    expect(await _net(app, 'bank'), -50000);
    expect(await _net(app, 'misc'), 50000);
    expect(await _net(app, 'cheques_in_hand'), 0);
  });

  testWidgets('a post-dated cheque cannot be banked before its date', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await app.seedParty(
      name: 'Rashid Traders',
      owedRupees: 45000,
    );
    final due = BusinessDate.now(app.services.clock).addDays(10);
    await _takeCheque(app, rashid, no: '004512', due: due);

    await tapText(tester, 'Cheque');
    await tapText(tester, 'Rashid Traders');

    expect(find.text('Bank ise ${due.value} se pehle nahi lega'), findsOne);
    await tapButton(tester, 'Clear ho gaya');
    expect(await _net(app, 'cheques_in_hand'), 4500000);
    expect(await _net(app, 'bank'), 0);
  });

  testWidgets('the first screen says when a cheque is due at the bank', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await app.seedParty(
      name: 'Rashid Traders',
      owedRupees: 45000,
    );
    final today = BusinessDate.now(app.services.clock);
    await _takeCheque(app, rashid, no: 'LATER', due: today.addDays(10));
    await _reopenHome(tester);
    expect(find.textContaining('bank le jane ka din'), findsNothing);

    await _takeCheque(app, rashid, no: 'TODAY', due: today);
    await _reopenHome(tester);
    await tapText(tester, '1 cheque bank le jane ka din aa gaya');

    expect(find.text('Aaj jama karein'), findsOneWidget);
  });
}

/// The home screen as it is when the shop opens the app in the morning, with
/// whatever was recorded since it last looked.
Future<void> _reopenHome(WidgetTester tester) async {
  ProviderScope.containerOf(
    tester.element(find.byType(HomeScreen)),
  ).bumpRefresh();
  await tester.pumpAndSettle();
}

Future<void> _takeCheque(
  Harness app,
  String partyId, {
  required String no,
  required BusinessDate due,
}) async {
  final firm = await app.services.queries.currentFirm();
  final accounts = await app.services.queries.paymentAccounts(firm!.id);
  await app.services.recordReceipt(
    app.services.actorNow(),
    ReceiptDraft(
      partyId: partyId,
      amount: const Money.rupees(45000),
      mode: 'cheque',
      paymentAccountId: accounts.firstWhere((a) => a.modeLabel == 'cheque').id,
      chequeNo: no,
      chequeBank: 'Meezan',
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
