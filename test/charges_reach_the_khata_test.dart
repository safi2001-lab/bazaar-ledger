import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Debit notes, from the screen: a charge on a customer's khata with no sale
/// behind it.
///
/// Until these, the only way to put the bank's bounce fee back on the
/// customer who caused it was to ring up a fake sale, which put a bank fee
/// in the day's takings.
void main() {
  testWidgets('a charge is put on the khata from the customer screen', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await app.seedParty(name: 'Rashid Traders');

    await tester.pumpAndSettle();
    await tapText(tester, 'Gahak');
    await tapText(tester, 'Rashid Traders');
    await tester.tap(find.byTooltip('Khate mein charge dalein'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Kitne ka charge', '800');
    await typeInto(tester, 'Kis cheez ka (zaroori)', 'Bilty ka kiraya');
    await tapButton(tester, 'Khate mein dalein');

    final firm = await app.services.queries.currentFirm();
    final party = await app.services.queries.partyById(firm!.id, rashid);
    expect(party!.balance, const Money.rupees(800));
    expect(find.textContaining('Bilty ka kiraya'), findsOneWidget);
    final sales = await app.scalar<int>(
      "SELECT COUNT(*) FROM documents WHERE doc_type = 'sale_invoice'",
    );
    expect(sales, 0);
  });

  testWidgets('a charge put on by mistake is taken back from the khata', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await app.seedParty(name: 'Rashid Traders');

    await tester.pumpAndSettle();
    await tapText(tester, 'Gahak');
    await tapText(tester, 'Rashid Traders');
    await tester.tap(find.byTooltip('Khate mein charge dalein'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Kitne ka charge', '800');
    await typeInto(tester, 'Kis cheez ka (zaroori)', 'Bilty ka kiraya');
    await tapButton(tester, 'Khate mein dalein');

    await tester.tap(find.textContaining('Bilty ka kiraya'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yeh charge wapas lein').last);
    await settleReal(tester, until: find.text('Charge wapas ho gaya'));

    final firm = await app.services.queries.currentFirm();
    final party = await app.services.queries.partyById(firm!.id, rashid);
    expect(party!.balance, Money.zero);
    expect(
      await app.scalar<String>(
        "SELECT status FROM documents WHERE doc_type = 'other_income'",
      ),
      'void',
    );
  });

  testWidgets('a charge with no reason is not saved', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedParty(name: 'Rashid Traders');

    await tester.pumpAndSettle();
    await tapText(tester, 'Gahak');
    await tapText(tester, 'Rashid Traders');
    await tester.tap(find.byTooltip('Khate mein charge dalein'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Kitne ka charge', '800');
    await tapButton(tester, 'Khate mein dalein');

    expect(
      find.text('Likhein kis cheez ka charge hai, warna gahak nahi dega'),
      findsOneWidget,
    );
    expect(await app.countIn('documents'), 0);
  });

  testWidgets('a bounce fee is put back on the customer who caused it', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final rashid = await app.seedParty(
      name: 'Rashid Traders',
      owedRupees: 45000,
    );
    final firm = await app.services.queries.currentFirm();
    final accounts = await app.services.queries.paymentAccounts(firm!.id);
    await app.services.recordReceipt(
      app.services.actorNow(),
      ReceiptDraft(
        partyId: rashid,
        amount: const Money.rupees(45000),
        mode: 'cheque',
        paymentAccountId: accounts
            .firstWhere((a) => a.modeLabel == 'cheque')
            .id,
        chequeNo: '004512',
        chequeBank: 'Meezan',
        chequeDateUtcMillis: chequeDueUtcMillis(
          BusinessDate.now(app.services.clock),
        ),
      ),
    );

    await tapText(tester, 'Cheque');
    await tapText(tester, 'Rashid Traders');
    await tapButton(tester, 'Bounce ho gaya');
    await typeInto(tester, 'Bank ki fee, agar kaati (marzi se)', '500');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tapButton(tester, 'Bounce ho gaya');

    final party = await app.services.queries.partyById(firm.id, rashid);
    expect(party!.balance, const Money.rupees(45500));
    final note = await app.rowsOf(
      "SELECT total_paisa, notes FROM documents WHERE doc_type = 'other_income'",
    );
    expect(note.single['total_paisa'], 50000);
    expect(note.single['notes'], contains('004512'));
  });
}
