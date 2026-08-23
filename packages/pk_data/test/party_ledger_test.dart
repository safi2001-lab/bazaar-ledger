import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// A customer's khata, as an argument-settler.
///
/// The open-bills view answers "what is still owed". This answers the
/// question a customer actually asks, which is "I paid you last week" — and
/// the answer has to be a date, an amount and a receipt number they can match
/// against the paper in their hand.
void main() {
  late AppDatabase db;
  late UlidGenerator ids;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late PostSaleUseCase postSale;
  late RecordReceiptUseCase receive;
  late String pcsUnitId;
  late String itemId;
  late String partyId;
  late String cashAccountId;

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
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    postSale = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    receive = RecordReceiptUseCase(writer: DriftPaymentWriter(runner: runner));

    pcsUnitId =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');
    cashAccountId = (await queries.paymentAccounts(
      firm.firmId,
    )).firstWhere((a) => a.isDefault).id;

    await runner.run(firm.actorAt(clock.nowUtc()), (tx) async {
      itemId = await tx.insert('items', {
        'name': 'Cooking Oil 5L',
        'name_search': 'cooking oil 5l',
        'base_unit_id': pcsUnitId,
        'sale_rate_milli_paisa': Rate.rupees(1000).inMilliPaisa,
      });
      partyId = await tx.insert('parties', {
        'name': 'Rashid Traders',
        'name_search': 'rashid traders',
        'party_type': 'customer',
      });
    });
  });

  tearDown(() async => db.close());

  ActorContext on(String date) {
    final parts = date.split('-').map(int.parse).toList();
    return ActorContext(
      firmId: firm.firmId,
      userId: firm.ownerUserId,
      deviceId: firm.deviceId,
      startedAtUtc: DateTime.utc(parts[0], parts[1], parts[2], 9),
    );
  }

  Future<String> bill(int rupees, String onDate) async => (await postSale(
    on(onDate),
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: 'Cooking Oil 5L',
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitId: pcsUnitId,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
        ),
      ],
      tenders: const [],
    ),
  )).docNo;

  Future<String> paid(int rupees, String onDate) async => (await receive(
    on(onDate),
    ReceiptDraft(
      partyId: partyId,
      amount: Money.rupees(rupees),
      mode: 'cash',
      paymentAccountId: cashAccountId,
    ),
  )).paymentNo;

  test('a customer with no history has an empty khata', () async {
    expect(await queries.partyLedger(firm.firmId, partyId), isEmpty);
  });

  test('bills and payments are interleaved by date', () async {
    await bill(3000, '2026-06-01');
    await paid(1000, '2026-06-15');
    await bill(2000, '2026-07-01');
    await paid(500, '2026-07-20');

    final ledger = await queries.partyLedger(firm.firmId, partyId);

    expect(ledger.map((e) => e.kind), ['sale', 'payment', 'sale', 'payment']);
    expect(ledger.map((e) => e.dateLocal), [
      '2026-06-01',
      '2026-06-15',
      '2026-07-01',
      '2026-07-20',
    ]);
  });

  test('a payment reduces what is owed and a bill increases it', () async {
    // Signed, rather than paired with a direction flag. A running balance
    // that adds some rows and subtracts others by reading a second column is
    // a running balance somebody eventually gets backwards.
    await bill(3000, '2026-06-01');
    await paid(1000, '2026-06-15');

    final ledger = await queries.partyLedger(firm.firmId, partyId);

    expect(ledger.first.amount, const Money.rupees(3000));
    expect(ledger.last.amount, const Money.rupees(-1000));
    expect(ledger.last.isPayment, isTrue);
  });

  test('the running balance is right after every line', () async {
    await bill(3000, '2026-06-01');
    await paid(1000, '2026-06-15');
    await bill(2000, '2026-07-01');
    await paid(500, '2026-07-20');

    final ledger = await queries.partyLedger(firm.firmId, partyId);

    expect(ledger.map((e) => e.balanceAfter), [
      const Money.rupees(3000),
      const Money.rupees(2000),
      const Money.rupees(4000),
      const Money.rupees(3500),
    ]);
  });

  test('a backdated bill lands where its date puts it', () async {
    // Entered on Sunday, dated Friday. Every shop does this, and it is the
    // reason the running balance is computed on read rather than stored: a
    // cached one would be wrong for every row after the insertion point.
    await bill(3000, '2026-07-01');
    await paid(1000, '2026-07-10');
    await bill(500, '2026-06-01');

    final ledger = await queries.partyLedger(firm.firmId, partyId);

    expect(ledger.first.dateLocal, '2026-06-01');
    expect(ledger.map((e) => e.balanceAfter), [
      const Money.rupees(500),
      const Money.rupees(3500),
      const Money.rupees(2500),
    ]);
  });

  test('every line carries the number on the customer paper', () async {
    // A customer holding a receipt can match it. Without the number the
    // shopkeeper is asking them to take a date on trust.
    final invoiceNo = await bill(3000, '2026-06-01');
    final receiptNo = await paid(1000, '2026-06-15');

    final ledger = await queries.partyLedger(firm.firmId, partyId);

    expect(ledger.first.reference, invoiceNo);
    expect(ledger.last.reference, receiptNo);
    expect(receiptNo, startsWith('RCV-'));
  });

  test('a void bill never appears', () async {
    await bill(3000, '2026-06-01');
    final rows = await db
        .customSelect("SELECT id FROM documents WHERE status = 'posted'")
        .get();
    await runner.run(
      on('2026-08-23'),
      (tx) => tx.update('documents', rows.first.read<String>('id'), {
        'status': 'void',
      }),
    );

    expect(await queries.partyLedger(firm.firmId, partyId), isEmpty);
  });

  test('another customer khata is not in this one', () async {
    final other = await runner.run(
      on('2026-06-01'),
      (tx) => tx.insert('parties', {
        'name': 'Someone Else',
        'name_search': 'someone else',
        'party_type': 'customer',
      }),
    );
    await bill(3000, '2026-06-01');

    expect(await queries.partyLedger(firm.firmId, other), isEmpty);
  });
}
