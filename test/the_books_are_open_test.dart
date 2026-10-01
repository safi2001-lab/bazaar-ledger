import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// The books themselves, from the screen: every account, a voucher written
/// by hand, and the balance sheet.
void main() {
  testWidgets('a voucher moves cash from the drawer to the bank', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);

    await tapText(tester, 'Hisaab kitaab');
    await tester.tap(find.text('Voucher likhein'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Kis liye (zaroori)', 'Cash deposited in Meezan');

    await tester.tap(find.byKey(const ValueKey('account-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Bank Accounts').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Debit').at(0),
      '200000',
    );

    await tester.tap(find.byKey(const ValueKey('account-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Cash in Hand').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Credit').at(1),
      '200000',
    );
    await tester.pumpAndSettle();
    expect(find.text('Dono taraf barabar'), findsOneWidget);
    await tapButton(tester, 'Voucher save karein');

    final firm = await app.services.queries.currentFirm();
    final chart = await app.services.queries.chartOfAccounts(firm!.id);
    expect(
      chart.firstWhere((a) => a.systemKey == 'bank').onItsSide,
      const Money.rupees(200000),
    );
    expect(
      chart.firstWhere((a) => a.systemKey == 'cash_in_hand').onItsSide,
      const Money.rupees(-200000),
    );
    expect(find.text('Hisaab kitaab'), findsOneWidget);
  });

  testWidgets('a voucher that does not agree is refused in words', (
    tester,
  ) async {
    await Harness.startWithShop(tester);

    await tapText(tester, 'Hisaab kitaab');
    await tester.tap(find.text('Voucher likhein'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Kis liye (zaroori)', 'Wrong');
    await tester.tap(find.byKey(const ValueKey('account-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Bank Accounts').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Debit').at(0),
      '100',
    );
    await tester.pumpAndSettle();

    expect(find.text('Farq: 100.00'), findsOneWidget);
    await tapButton(tester, 'Voucher save karein');
    expect(find.textContaining('at least two lines'), findsOneWidget);
  });

  testWidgets('an account shows every entry that moved it', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedParty(name: 'Rashid Traders', owedRupees: 4500);

    await tapText(tester, 'Hisaab kitaab');
    await tapText(tester, 'Receivables (Udhaar)');

    expect(find.text('Opening balance of Rashid Traders'), findsOneWidget);
  });

  testWidgets('the balance sheet balances on the phone', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await app.seedParty(name: 'Rashid Traders', owedRupees: 4500);

    await tapText(tester, 'Report');
    await tester.scrollUntilVisible(find.text('Balance sheet'), 200);
    await tapText(tester, 'Balance sheet');

    expect(find.text('Total liabilities and equity'), findsOneWidget);
    expect(find.textContaining('What the shop has equals'), findsOneWidget);
  });

  testWidgets('the shop adds an account of its own, and a year with nothing '
      'in it is not closed', (tester) async {
    final app = await Harness.startWithShop(tester);

    await tapText(tester, 'Hisaab kitaab');
    await tester.tap(find.byTooltip('Naya account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Account ka naam'),
      'Generator diesel',
    );
    await tester.tap(find.text('Naya account').last);
    await settleReal(tester, until: find.text('Generator diesel'));
    final added = await app.scalar<int>(
      "SELECT COUNT(*) FROM accounts WHERE name = 'Generator diesel' "
      "AND account_type = 'expense'",
    );
    expect(added, 1);

    await tester.tap(find.byTooltip('Saal band karein'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saal band karein').last);
    await settleReal(tester, until: find.textContaining('left to close'));
    expect(find.textContaining('left to close'), findsOneWidget);
    expect(
      await app.scalar<int>(
        "SELECT COUNT(*) FROM journal_entries WHERE source_type = 'year_close'",
      ),
      0,
    );
  });
}
