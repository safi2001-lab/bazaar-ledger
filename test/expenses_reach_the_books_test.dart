import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Rent, bijli and wages, entered from the app.
///
/// `RecordExpenseUseCase` posted to the right heads from the commit that
/// introduced it, and nothing in `lib/` called it. That is the shape of the
/// failure this repository keeps finding — the printer and the costing engine
/// both shipped as a library with no button first — so these drive the real
/// screens and read the rows back out of the database.
void main() {
  testWidgets('expenses can be reached from the home screen', (tester) async {
    await Harness.startWithShop(tester);
    await tapText(tester, 'Kharcha');

    expect(find.text('Abhi koi kharcha nahi'), findsOneWidget);
  });

  testWidgets('a bijli bill paid from the drawer lands on utilities', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _openNewExpense(tester);

    await tapText(tester, 'Bijli, gas, pani');
    await typeInto(tester, 'Raqam', '4200');
    await typeInto(tester, 'Kis cheez ke liye', 'LESCO bill August');
    await tapButton(tester, 'Kharcha save karein');

    final lines = await app.rowsOf(
      'SELECT a.system_key AS head, jl.debit_paisa AS dr, '
      'jl.credit_paisa AS cr '
      'FROM journal_entries je '
      'JOIN journal_lines jl ON jl.journal_entry_id = je.id '
      'JOIN accounts a ON a.id = jl.account_id '
      "WHERE je.source_type = 'expense' ORDER BY jl.line_no",
    );
    expect(lines, hasLength(2));
    expect(lines.first['head'], 'utilities');
    expect(lines.first['dr'], 420000);
    expect(
      lines.last['head'],
      'cash_in_hand',
      reason: 'money paid now comes out of the drawer',
    );
    expect(lines.last['cr'], 420000);

    // And it is on the list the shopkeeper returns to.
    expect(find.text('Bijli, gas, pani'), findsOneWidget);
    expect(find.text('LESCO bill August'), findsOneWidget);
  });

  testWidgets('an expense with no note is refused in words', (tester) async {
    // "Misc — Rs 4,000" six months later is a number nobody can defend.
    final app = await Harness.startWithShop(tester);
    await _openNewExpense(tester);

    await typeInto(tester, 'Raqam', '4000');
    await tapButton(tester, 'Kharcha save karein');

    expect(find.text('Likhein yeh kharcha kis cheez ka tha'), findsOneWidget);
    expect(await app.countIn('documents'), 0);
  });

  testWidgets('an expense of nothing is refused in words', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _openNewExpense(tester);

    await typeInto(tester, 'Kis cheez ke liye', 'chai');
    await tapButton(tester, 'Kharcha save karein');

    expect(find.text('Raqam likhein'), findsOneWidget);
    expect(await app.countIn('documents'), 0);
  });

  testWidgets('an unpaid expense has to say who it is owed to', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _openNewExpense(tester);

    await typeInto(tester, 'Raqam', '15000');
    await typeInto(tester, 'Kis cheez ke liye', 'Dukaan ka kiraya September');
    await tapText(tester, 'Baad mein dena hai');
    await tapButton(tester, 'Kharcha save karein');

    expect(find.text('Batayein yeh kis ko dena hai'), findsOneWidget);
    expect(await app.countIn('documents'), 0);
  });

  testWidgets('an unpaid expense sits on the payable, by name', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.services.catalogue.addParty(
      app.services.actorNow(),
      const PartyDraft(name: 'Haji Sahib (malik)', partyType: 'supplier'),
    );
    await _openNewExpense(tester);

    await tapText(tester, 'Dukaan ka kiraya');
    await typeInto(tester, 'Raqam', '15000');
    await typeInto(tester, 'Kis cheez ke liye', 'Kiraya September');
    await tapText(tester, 'Baad mein dena hai');
    await tapText(tester, 'Kis ko dena hai');
    await tapText(tester, 'Haji Sahib (malik)');
    await tapButton(tester, 'Kharcha save karein');

    final owed = await app.rowsOf(
      'SELECT p.name AS name, '
      'SUM(jl.credit_paisa - jl.debit_paisa) AS owed '
      'FROM journal_lines jl '
      'JOIN accounts a ON a.id = jl.account_id '
      'JOIN parties p ON p.id = jl.party_id '
      "WHERE a.system_key = 'accounts_payable' GROUP BY p.name",
    );
    expect(owed.single['name'], 'Haji Sahib (malik)');
    expect(owed.single['owed'], 1500000);

    final doc = await app.rowsOf(
      "SELECT balance_paisa FROM documents WHERE doc_type = 'expense'",
    );
    expect(doc.single['balance_paisa'], 1500000);
    expect(find.text('Haji Sahib (malik) ko dena hai'), findsOneWidget);
  });

  testWidgets('an expense entered on screen leaves the books balanced', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _openNewExpense(tester);

    await tapText(tester, 'Tankhwah');
    await typeInto(tester, 'Raqam', '18000');
    await typeInto(tester, 'Kis cheez ke liye', 'Bilal ki tankhwah');
    await tapButton(tester, 'Kharcha save karein');

    final totals = await app.rowsOf(
      'SELECT SUM(debit_paisa) AS dr, SUM(credit_paisa) AS cr '
      'FROM journal_lines',
    );
    expect(totals.single['dr'], totals.single['cr']);
    expect(
      await app.scalar<int>(
        "SELECT COUNT(*) FROM audit_log WHERE action_code = 'EXPENSE_RECORDED'",
      ),
      1,
    );
  });
}

Future<void> _openNewExpense(WidgetTester tester) async {
  await tapText(tester, 'Kharcha');
  await tapText(tester, 'Naya kharcha');
}
