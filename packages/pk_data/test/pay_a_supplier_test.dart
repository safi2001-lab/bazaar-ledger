import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Paying a supplier, against a real database.
///
/// Until this, a delivery left part-paid sat on Accounts Payable for ever:
/// there was a way to owe a supplier and no way to stop owing them. And the
/// party it was owed to is, often enough, also a customer — the rice mill
/// buys the shop's bran — which is where two defects were hiding that only
/// show up once both sides of one name have bills on them.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late RecordPurchaseUseCase buy;
  late PostSaleUseCase sell;
  late RecordReceiptUseCase receive;
  late RecordExpenseUseCase spend;
  late PaySupplierUseCase pay;
  late ActorContext actor;
  late String pcsUnitId;
  late String riceId;
  late String millId;
  late String cashAccountId;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 8, 23, 9, 15));
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
    queries = DriftAppQueries(db);
    buy = RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: runner));
    sell = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    receive = RecordReceiptUseCase(writer: DriftPaymentWriter(runner: runner));
    spend = RecordExpenseUseCase(writer: DriftExpenseWriter(runner: runner));
    pay = PaySupplierUseCase(writer: DriftPaymentWriter(runner: runner));

    pcsUnitId =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');
    cashAccountId = (await queries.paymentAccounts(
      firm.firmId,
    )).firstWhere((a) => a.isDefault).id;

    await runner.run(actor, (tx) async {
      // Both: the mill sells the shop rice and buys its bran.
      millId = await tx.insert('parties', {
        'name': 'Punjab Rice Mills',
        'name_search': 'punjab rice mills',
        'party_type': 'both',
      });
      riceId = await tx.insert('items', {
        'name': 'Chawal Basmati',
        'name_search': 'chawal basmati',
        'base_unit_id': pcsUnitId,
        'sale_rate_milli_paisa': Rate.rupees(150).inMilliPaisa,
      });
    });
  });

  tearDown(() async => db.close());

  ActorContext on(String date) => ActorContext(
    firmId: firm.firmId,
    userId: firm.ownerUserId,
    deviceId: firm.deviceId,
    startedAtUtc: DateTime.parse('${date}T09:00:00Z'),
  );

  Future<String> deliver({
    required int rupees,
    int paidRupees = 0,
    String date = '2026-08-23',
  }) async {
    final posted = await buy(
      on(date),
      PurchaseDraft(
        partyId: millId,
        paid: Money.rupees(paidRupees),
        paymentAccountId: paidRupees > 0 ? cashAccountId : null,
        lines: [
          PurchaseLineDraft(
            itemId: riceId,
            itemName: 'Chawal Basmati',
            qty: Qty.units(10),
            baseQty: Qty.units(10),
            unitId: pcsUnitId,
            unitCode: 'pcs',
            rate: Rate.rupees(rupees ~/ 10),
          ),
        ],
      ),
    );
    return posted.documentId;
  }

  Future<String> udhaarSale(int rupees) async {
    final posted = await sell(
      actor,
      SaleDraft(
        partyId: millId,
        lines: [
          SaleLineDraft(
            itemId: riceId,
            itemName: 'Chawal Basmati',
            qty: Qty.units(1),
            baseQty: Qty.units(1),
            unitId: pcsUnitId,
            unitCode: 'pcs',
            rate: Rate.rupees(rupees),
          ),
        ],
        tenders: const [],
      ),
    );
    return posted.documentId;
  }

  Future<RecordedReceipt> payMill(int rupees, {String mode = 'cash'}) => pay(
    actor,
    SupplierPaymentDraft(
      partyId: millId,
      amount: Money.rupees(rupees),
      mode: mode,
      paymentAccountId: cashAccountId,
    ),
  );

  Future<int> balanceOf(String documentId) async =>
      (await db
              .customSelect(
                'SELECT balance_paisa FROM documents WHERE id = ?',
                variables: [Variable<String>(documentId)],
              )
              .getSingle())
          .read<int>('balance_paisa');

  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).data.values.first! as int;

  test('a payment clears the oldest delivery first', () async {
    final june = await deliver(rupees: 3000, date: '2026-06-10');
    final july = await deliver(rupees: 2500, date: '2026-07-10');

    final paid = await payMill(4000);

    expect(paid.settledDocumentIds, [june, july]);
    expect(await balanceOf(june), 0);
    expect(await balanceOf(july), 150000);
  });

  test('what the shop owes the supplier comes down, by name', () async {
    await deliver(rupees: 5000);
    expect(
      (await queries.partyById(firm.firmId, millId))!.payable.inPaisa,
      500000,
    );

    await payMill(2000);

    final mill = (await queries.partyById(firm.firmId, millId))!;
    expect(mill.payable, const Money.rupees(3000));

    final owedOnBooks = await count(
      'SELECT SUM(jl.credit_paisa - jl.debit_paisa) FROM journal_lines jl '
      'JOIN accounts a ON a.id = jl.account_id '
      "WHERE a.system_key = 'accounts_payable' AND jl.party_id = '$millId'",
    );
    expect(owedOnBooks, 300000, reason: 'the payable and the bills disagree');
  });

  test('paying a supplier leaves the books balanced', () async {
    await deliver(rupees: 5000, paidRupees: 1000);
    await payMill(4000);

    final totals = await db
        .customSelect(
          'SELECT SUM(debit_paisa) AS dr, SUM(credit_paisa) AS cr '
          'FROM journal_lines',
        )
        .getSingle();
    expect(totals.read<int>('dr'), totals.read<int>('cr'));
  });

  test('the payment is money going out, under its own number', () async {
    await deliver(rupees: 5000);
    final paid = await payMill(5000);

    final row = await db
        .customSelect(
          'SELECT direction, payment_no, status FROM payments WHERE id = ?',
          variables: [Variable<String>(paid.paymentId)],
        )
        .getSingle();
    expect(row.read<String>('direction'), 'out');
    expect(row.read<String>('payment_no'), startsWith('PAY'));
    expect(row.read<String>('status'), 'cleared');
    expect(
      await count(
        "SELECT COUNT(*) FROM audit_log WHERE action_code = 'PAYMENT_MADE'",
      ),
      1,
    );
  });

  test('an expense left on account is paid off the same way', () async {
    await spend(
      actor,
      ExpenseDraft(
        accountSystemKey: 'freight',
        amount: const Money.rupees(800),
        note: 'Rickshaw from the mill',
        partyId: millId,
      ),
    );

    await payMill(800);

    expect((await queries.partyById(firm.firmId, millId))!.payable, Money.zero);
  });

  test('paying more than is owed writes nothing and burns no number', () async {
    await deliver(rupees: 3000);

    await expectLater(payMill(3001), throwsA(isA<SupplierPaymentRefused>()));
    expect(await count('SELECT COUNT(*) FROM payments'), 0);

    final next = await payMill(3000);
    expect(next.paymentNo, endsWith('0001'));
  });

  test('a customer payment never settles a bill the shop owes', () async {
    // The defect: open bills were read with no document type, so the mill's
    // Rs 3,000 against its bran bill paid down the shop's own rice delivery
    // instead — the payable vanished and the udhaar stayed.
    final delivery = await deliver(rupees: 5000, date: '2026-06-01');
    final bran = await udhaarSale(3000);

    await receive(
      actor,
      ReceiptDraft(
        partyId: millId,
        amount: const Money.rupees(3000),
        mode: 'cash',
        paymentAccountId: cashAccountId,
      ),
    );

    expect(await balanceOf(bran), 0);
    expect(await balanceOf(delivery), 500000);
  });

  test('what the shop owes a supplier is not udhaar', () async {
    // The same missing filter, in the ageing summary and the chase list: a
    // delivery not yet paid for aged there as though a customer owed it.
    await deliver(rupees: 5000, date: '2026-05-01');

    final aging = await queries.aging(firm.firmId, asOfDateLocal: '2026-08-23');
    expect(aging.total, Money.zero);
    expect(
      await queries.partiesToChase(firm.firmId, asOfDateLocal: '2026-08-23'),
      isEmpty,
    );
  });

  test('the supplier khata runs from deliveries to payments', () async {
    await deliver(rupees: 5000, paidRupees: 1000, date: '2026-06-01');
    await payMill(1500);

    final entries = await queries.payablesLedger(firm.firmId, millId);
    expect(entries.map((e) => e.kind), ['purchase', 'payment']);
    // Only what went on account: Rs 1,000 was handed over at the door.
    expect(entries.first.amount, const Money.rupees(4000));
    expect(entries.last.amount, const Money.rupees(-1500));
    expect(entries.last.balanceAfter, const Money.rupees(2500));
  });
}
