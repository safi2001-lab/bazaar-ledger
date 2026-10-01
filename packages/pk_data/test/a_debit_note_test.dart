import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// A charge put on a customer's khata with no sale behind it, against a real
/// database.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late TxRunner runner;
  late RecordDebitNoteUseCase charge;
  late RecordReceiptUseCase receive;
  late DriftAppQueries queries;
  late ActorContext actor;
  late String rashidId;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 9, 26, 9, 15));
    db = await openTestDatabase();
    final ids = UlidGenerator(now: clock.nowUtc);
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
    charge = RecordDebitNoteUseCase(
      writer: DriftDebitNoteWriter(runner: runner),
    );
    receive = RecordReceiptUseCase(writer: DriftPaymentWriter(runner: runner));
    queries = DriftAppQueries(db);
    await runner.run(actor, (tx) async {
      rashidId = await tx.insert('parties', {
        'name': 'Rashid Traders',
        'name_search': 'rashid traders',
        'party_type': 'customer',
      });
    });
  });

  tearDown(() async => db.close());

  DebitNoteDraft fee({
    int rupees = 500,
    String note = 'Cheque 004512 bounce',
  }) => DebitNoteDraft(
    partyId: rashidId,
    partyName: 'Rashid Traders',
    amount: Money.rupees(rupees),
    note: note,
  );

  Future<int> net(String systemKey) async =>
      (await db
                  .customSelect(
                    'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) '
                    'AS n FROM journal_lines jl '
                    'JOIN accounts a ON a.id = jl.account_id '
                    'WHERE a.system_key = ?',
                    variables: [Variable<String>(systemKey)],
                  )
                  .getSingle())
              .data['n']!
          as int;

  test('a charge is owed on the khata and is income, not a sale', () async {
    await charge(actor, fee());

    final party = await queries.partyById(firm.firmId, rashidId);
    expect(party!.balance, const Money.rupees(500));
    expect(await net('accounts_receivable'), 50000);
    expect(await net('other_income'), -50000);
    expect(await net('sales'), 0);
    final day = await queries.dayTotals(firm.firmId, '2026-09-26');
    expect(day.sales, Money.zero, reason: 'not in the day of sales');
  });

  test('a charge shows on the khata with its reason', () async {
    final note = await charge(actor, fee());

    final ledger = await queries.partyLedger(firm.firmId, rashidId);
    expect(ledger.single.kind, 'charge');
    expect(ledger.single.reference, '${note.docNo} · Cheque 004512 bounce');
    expect(ledger.single.amount, const Money.rupees(500));
  });

  test('a receipt settles a charge like a bill', () async {
    await charge(actor, fee());
    final cash = (await queries.paymentAccounts(
      firm.firmId,
    )).firstWhere((a) => a.modeLabel == 'cash');

    await receive(
      actor,
      ReceiptDraft(
        partyId: rashidId,
        amount: const Money.rupees(500),
        mode: 'cash',
        paymentAccountId: cash.id,
      ),
    );

    final party = await queries.partyById(firm.firmId, rashidId);
    expect(party!.balance, Money.zero);
    expect(await queries.openBillsFor(firm.firmId, rashidId), isEmpty);
    expect(await net('customer_advances'), 0, reason: 'not held as advance');
  });

  test('a charge with no reason is refused', () async {
    await expectLater(
      charge(actor, fee(note: '  ')),
      throwsA(isA<DebitNoteRefused>()),
    );
    await expectLater(
      charge(actor, fee(rupees: 0)),
      throwsA(isA<DebitNoteRefused>()),
    );
    expect(
      (await db.customSelect('SELECT COUNT(*) AS n FROM documents').getSingle())
          .data['n'],
      0,
    );
  });

  test('a charge put on by mistake is cancelled and leaves the khata as it '
      'was', () async {
    final note = await charge(actor, fee(rupees: 1500, note: 'Bank fee'));
    final cancel = VoidDocumentUseCase(writer: DriftVoidWriter(runner: runner));
    await cancel(actor, documentId: note.id, reason: 'Put on by mistake');

    final party = await queries.partyById(firm.firmId, rashidId);
    expect(party!.balance, Money.zero);
    final ledger = await queries.partyLedger(firm.firmId, rashidId);
    expect(ledger, isEmpty);
    final books = await db
        .customSelect(
          'SELECT COALESCE(SUM(debit_paisa), 0) AS d, '
          'COALESCE(SUM(credit_paisa), 0) AS c FROM journal_lines',
        )
        .getSingle();
    expect(books.read<int>('d'), books.read<int>('c'));
    await expectLater(
      cancel(actor, documentId: note.id, reason: 'Again'),
      throwsA(isA<VoidRefused>()),
    );
  });
}
