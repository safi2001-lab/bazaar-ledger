import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Rent, bijli, and the boy who carries sacks, against a real database.
///
/// The chart has carried these heads since M0 with nothing ever posting to
/// them. Until something does, the shop's P&L is fiction and its cash book
/// will not reconcile.
void main() {
  late AppDatabase db;
  late UlidGenerator ids;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late RecordExpenseUseCase spend;
  late ActorContext actor;
  late String cashAccountId;
  late String landlordId;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 8, 23, 9, 15));
    db = await openTestDatabase();
    ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    actor = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    spend = RecordExpenseUseCase(writer: DriftExpenseWriter(runner: runner));

    cashAccountId = (await queries.paymentAccounts(
      firm.firmId,
    )).firstWhere((a) => a.isDefault).id;

    await runner.run(actor, (tx) async {
      landlordId = await tx.insert('parties', {
        'name': 'Malik Property',
        'name_search': 'malik property',
        'party_type': 'supplier',
      });
    });
  });

  tearDown(() async => db.close());

  Future<RecordedExpense> pay({
    String head = 'utilities',
    int rupees = 4000,
    String note = 'Bijli ka bill, August',
    bool onCredit = false,
  }) => spend(
    actor,
    ExpenseDraft(
      accountSystemKey: head,
      amount: Money.rupees(rupees),
      note: note,
      paymentAccountId: onCredit ? null : cashAccountId,
      partyId: onCredit ? landlordId : null,
    ),
  );

  Future<int> netOf(String systemKey) async =>
      (await db
              .customSelect(
                'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS n '
                'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
                'WHERE a.system_key = ?',
                variables: [Variable<String>(systemKey)],
              )
              .getSingle())
          .read<int>('n');

  test('a bijli bill lands on the utilities head', () async {
    final expense = await pay();

    expect(expense.docNo, startsWith('EXP-'));
    expect(expense.head, 'utilities');
    expect(await netOf('utilities'), 400000);
  });

  test('and comes out of the drawer', () async {
    await pay();

    expect(await netOf('cash_in_hand'), -400000);
  });

  test('the books balance', () async {
    await pay();
    await pay(head: 'rent', rupees: 25000, note: 'Dukan ka kiraya');

    final totals = await db
        .customSelect(
          'SELECT SUM(debit_paisa) AS d, SUM(credit_paisa) AS c '
          'FROM journal_lines',
        )
        .getSingle();
    expect(totals.read<int>('d'), totals.read<int>('c'));
  });

  test('an unpaid expense sits on the payable, by name', () async {
    await pay(head: 'rent', rupees: 25000, note: 'Kiraya', onCredit: true);

    expect(await netOf('accounts_payable'), -2500000);

    final line = await db
        .customSelect(
          'SELECT jl.party_id FROM journal_lines jl '
          'JOIN accounts a ON a.id = jl.account_id '
          "WHERE a.system_key = 'accounts_payable'",
        )
        .getSingle();
    expect(line.read<String>('party_id'), landlordId);
  });

  test('the head is read back off the journal, not off a column', () async {
    // A denormalised column would be a second answer to a question the ledger
    // already holds. This is the join that column would have replaced.
    final expense = await pay(head: 'salaries', note: 'Mazdoor ki tankhwah');

    final head = await db
        .customSelect(
          '''
          SELECT a.system_key
          FROM journal_entries je
          JOIN journal_lines jl ON jl.journal_entry_id = je.id
          JOIN accounts a ON a.id = jl.account_id
          WHERE je.document_id = ? AND a.account_type = 'expense'
          ''',
          variables: [Variable<String>(expense.documentId)],
        )
        .getSingle();
    expect(head.read<String>('system_key'), 'salaries');
  });

  test('the note is kept, because the amount alone defends nothing', () async {
    final expense = await pay(note: 'Bijli ka bill, August');

    final doc = await db
        .customSelect(
          'SELECT notes FROM documents WHERE id = ?',
          variables: [Variable<String>(expense.documentId)],
        )
        .getSingle();
    expect(doc.read<String>('notes'), 'Bijli ka bill, August');
  });

  test('a head this shop does not keep is refused', () async {
    await expectLater(
      spend(
        actor,
        ExpenseDraft(
          accountSystemKey: 'chai_pani',
          amount: const Money.rupees(100),
          note: 'Chai',
          paymentAccountId: cashAccountId,
        ),
      ),
      throwsA(isA<ExpenseRefused>()),
    );
    expect(
      await db
          .customSelect('SELECT COUNT(*) AS n FROM documents')
          .getSingle()
          .then((r) => r.read<int>('n')),
      0,
    );
  });

  test('a failed expense burns no number', () async {
    await expectLater(
      spend(
        actor,
        ExpenseDraft(
          accountSystemKey: 'misc',
          amount: const Money.rupees(100),
          note: '   ',
          paymentAccountId: cashAccountId,
        ),
      ),
      throwsA(isA<ExpenseRefused>()),
    );

    final expense = await pay();
    expect(expense.docNo, endsWith('0001'));
  });

  test('the expense is recorded in the audit trail', () async {
    final expense = await pay();

    final audit = await db
        .customSelect(
          'SELECT entity_id, summary, amount_paisa FROM audit_log '
          "WHERE action_code = 'EXPENSE_RECORDED'",
        )
        .getSingle();

    expect(audit.read<String>('entity_id'), expense.documentId);
    expect(audit.read<int>('amount_paisa'), 400000);
    expect(audit.read<String>('summary'), contains('utilities'));
    expect(audit.read<String>('summary'), contains('Bijli ka bill, August'));
  });
}
