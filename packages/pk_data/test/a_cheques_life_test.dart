import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// A cheque from taking to clearing or bouncing, against a real database.
///
/// Rashid Traders owes Rs 45,000 on one bill and hands over a cheque for
/// Rs 50,000 dated fifteen days ahead. Rs 45,000 settles the bill and Rs 5,000
/// is left as an advance — every bit of it only as real as the cheque.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late DriftAppQueries queries;
  late PostSaleUseCase sell;
  late RecordReceiptUseCase receive;
  late MoveChequeUseCase cheques;
  late String pcsUnitId;
  late String oilId;
  late String rashidId;
  late String chequeAccountId;
  late String bankAccountId;
  late String cashAccountId;

  const today = '2026-09-26';
  const due = '2026-10-11';

  ActorContext on(String date) => ActorContext(
    firmId: firm.firmId,
    userId: firm.ownerUserId,
    deviceId: firm.deviceId,
    startedAtUtc: DateTime.parse('${date}T09:15:00Z'),
  );

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
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    final runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    sell = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    receive = RecordReceiptUseCase(writer: DriftPaymentWriter(runner: runner));
    cheques = MoveChequeUseCase(writer: DriftChequeWriter(runner: runner));

    pcsUnitId =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');
    final accounts = await queries.paymentAccounts(firm.firmId);
    chequeAccountId = accounts.firstWhere((a) => a.modeLabel == 'cheque').id;
    bankAccountId = accounts
        .firstWhere((a) => a.modeLabel == 'bank_transfer')
        .id;
    cashAccountId = accounts.firstWhere((a) => a.isDefault).id;

    await runner.run(on(today), (tx) async {
      rashidId = await tx.insert('parties', {
        'name': 'Rashid Traders',
        'name_search': 'rashid traders',
        'party_type': 'customer',
      });
      oilId = await tx.insert('items', {
        'name': 'Cooking Oil 5L',
        'name_search': 'cooking oil 5l',
        'base_unit_id': pcsUnitId,
        'sale_rate_milli_paisa': Rate.rupees(4500).inMilliPaisa,
      });
    });
  });

  tearDown(() async => db.close());

  SaleDraft oilSale({List<TenderDraft> tenders = const []}) => SaleDraft(
    partyId: rashidId,
    lines: [
      SaleLineDraft(
        itemId: oilId,
        itemName: 'Cooking Oil 5L',
        qty: Qty.units(10),
        baseQty: Qty.units(10),
        unitId: pcsUnitId,
        unitCode: 'pcs',
        rate: Rate.rupees(4500),
      ),
    ],
    tenders: tenders,
  );

  Future<String> udhaarBill() async =>
      (await sell(on(today), oilSale())).documentId;

  Future<String> takeCheque({
    int rupees = 50000,
    String dated = due,
    String no = '004512',
  }) async => (await receive(
    on(today),
    ReceiptDraft(
      partyId: rashidId,
      amount: Money.rupees(rupees),
      mode: 'cheque',
      paymentAccountId: chequeAccountId,
      chequeNo: no,
      chequeBank: 'Meezan',
      chequeDateUtcMillis: chequeDueUtcMillis(BusinessDate(dated)),
    ),
  )).paymentId;

  Future<int> net(String systemKey) async =>
      (await db
              .customSelect(
                'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS n '
                'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
                'WHERE a.system_key = ?',
                variables: [Variable<String>(systemKey)],
              )
              .getSingle())
          .read<int>('n');

  Future<void> booksBalance() async {
    final t = await db
        .customSelect(
          'SELECT SUM(debit_paisa) AS dr, SUM(credit_paisa) AS cr '
          'FROM journal_lines',
        )
        .getSingle();
    expect(t.read<int>('dr'), t.read<int>('cr'));
  }

  test('cheques in hand are listed soonest due first', () async {
    await udhaarBill();
    await takeCheque(rupees: 10000, dated: '2026-11-10', no: 'LATE');
    await takeCheque(rupees: 10000, dated: '2026-10-01', no: 'SOON');

    final inHand = await queries.chequesInHand(firm.firmId);
    expect(inHand.map((c) => c.chequeNo), ['SOON', 'LATE']);
    expect(inHand.first.due, const BusinessDate('2026-10-01'));
  });

  test('a cheque cannot go to the bank before its date', () async {
    await udhaarBill();
    final cheque = await takeCheque();

    await expectLater(
      cheques.deposit(on(today), cheque),
      throwsA(isA<ChequeRefused>()),
    );
    await cheques.deposit(on(due), cheque);

    expect((await queries.chequesInHand(firm.firmId)).single.deposited, isTrue);
  });

  test('a cleared cheque puts the money in the bank', () async {
    await udhaarBill();
    final cheque = await takeCheque();
    expect(await net('cheques_in_hand'), 5000000);

    await cheques.clear(on(due), cheque, bankAccountId: bankAccountId);

    expect(await net('cheques_in_hand'), 0);
    expect(await net('bank'), 5000000);
    expect(await queries.chequesInHand(firm.firmId), isEmpty);
    await booksBalance();
  });

  test('a bounced cheque puts the udhaar back on the khata', () async {
    final bill = await udhaarBill();
    final cheque = await takeCheque();
    expect(
      (await queries.partyById(firm.firmId, rashidId))!.balance,
      const Money.rupees(-5000),
      reason: 'paid in full with Rs 5,000 on account',
    );

    await cheques.bounce(
      on('2026-10-12'),
      cheque,
      reason: 'Funds insufficient',
    );

    expect(
      (await queries.partyById(firm.firmId, rashidId))!.balance,
      const Money.rupees(45000),
      reason: 'the bill is owed again and the advance never existed',
    );
    final reopened = await db
        .customSelect(
          'SELECT paid_paisa, balance_paisa FROM documents WHERE id = ?',
          variables: [Variable<String>(bill)],
        )
        .getSingle();
    expect(reopened.read<int>('balance_paisa'), 4500000);
    expect(reopened.read<int>('paid_paisa'), 0);
    expect(await net('cheques_in_hand'), 0);
    await booksBalance();
  });

  test('the khata shows the cheque and then its bounce', () async {
    await udhaarBill();
    final cheque = await takeCheque();
    await cheques.bounce(on('2026-10-12'), cheque);

    final entries = await queries.partyLedger(firm.firmId, rashidId);
    expect(entries.map((e) => e.kind), ['sale', 'payment', 'bounce']);
    expect(entries.last.amount, const Money.rupees(50000));
    expect(entries.last.dateLocal, '2026-10-12');
    expect(entries.last.balanceAfter, const Money.rupees(45000));
  });

  test('a bounced cheque is listed with its 489-F notice date', () async {
    await udhaarBill();
    final cheque = await takeCheque();
    await cheques.bounce(on('2026-10-12'), cheque);

    final bounced = (await queries.bouncedCheques(firm.firmId)).single;
    expect(bounced.chequeNo, '004512');
    expect(bounced.bouncedOn, const BusinessDate('2026-10-12'));
    expect(bounced.noticeBy, const BusinessDate('2026-11-11'));
  });

  test('a cheque cannot clear twice, or clear after it bounced', () async {
    await udhaarBill();
    final first = await takeCheque(rupees: 20000, no: 'A');
    final second = await takeCheque(rupees: 20000, no: 'B');
    await cheques.clear(on(due), first, bankAccountId: bankAccountId);
    await cheques.bounce(on(due), second);

    await expectLater(
      cheques.clear(on(due), first, bankAccountId: bankAccountId),
      throwsA(isA<ChequeRefused>()),
    );
    await expectLater(
      cheques.clear(on(due), second, bankAccountId: bankAccountId),
      throwsA(isA<ChequeRefused>()),
    );
  });

  test('a cheque taken at the counter that bounces reopens the sale', () async {
    final sale = await sell(
      on(today),
      oilSale(
        tenders: [
          TenderDraft(
            paymentAccountId: chequeAccountId,
            mode: 'cheque',
            amount: const Money.rupees(45000),
            chequeNo: '991100',
            chequeDateUtc: DateTime.fromMillisecondsSinceEpoch(
              chequeDueUtcMillis(const BusinessDate(due)),
              isUtc: true,
            ),
          ),
        ],
      ),
    );
    final chequeId = (await queries.chequesInHand(
      firm.firmId,
    )).single.paymentId;

    await cheques.bounce(on(due), chequeId);

    final reopened = await db
        .customSelect(
          'SELECT balance_paisa FROM documents WHERE id = ?',
          variables: [Variable<String>(sale.documentId)],
        )
        .getSingle();
    expect(reopened.read<int>('balance_paisa'), 4500000);
    await booksBalance();
  });

  test('every step is in the audit trail', () async {
    await udhaarBill();
    final a = await takeCheque(rupees: 20000, no: 'A');
    final b = await takeCheque(rupees: 20000, no: 'B');
    await cheques.deposit(on(due), a);
    await cheques.clear(on(due), a, bankAccountId: bankAccountId);
    await cheques.bounce(on(due), b);

    final actions = await db
        .customSelect(
          "SELECT action_code FROM audit_log WHERE action_code LIKE 'CHEQUE_%' "
          'ORDER BY at_utc, id',
        )
        .get();
    expect(actions.map((r) => r.read<String>('action_code')).toSet(), {
      'CHEQUE_DEPOSITED',
      'CHEQUE_CLEARED',
      'CHEQUE_BOUNCED',
    });
    // Not in the drawer: the cash account never saw any of it.
    final cash = (await queries.paymentAccounts(
      firm.firmId,
    )).firstWhere((x) => x.id == cashAccountId);
    expect(cash.modeLabel, 'cash');
  });
}
