import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// A cheque the shop writes to a supplier, against a real database.
///
/// Faisal Flour Mills delivered Rs 80,000 of atta. The shop pays with a
/// cheque on its Meezan account dated fifteen days ahead. The deliveries are
/// settled that day; the money leaves the bank only when the mill presents
/// the cheque, and if the bank will not pay it, the shop owes the mill again.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late RecordPurchaseUseCase buy;
  late PaySupplierUseCase pay;
  late MoveChequeUseCase cheques;
  late String pcsUnitId;
  late String attaId;
  late String millId;
  late String bankAccountId;

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
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    buy = RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: runner));
    pay = PaySupplierUseCase(writer: DriftPaymentWriter(runner: runner));
    cheques = MoveChequeUseCase(writer: DriftChequeWriter(runner: runner));

    pcsUnitId =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');
    bankAccountId = (await queries.paymentAccounts(
      firm.firmId,
    )).firstWhere((a) => a.modeLabel == 'bank_transfer').id;

    await runner.run(on(today), (tx) async {
      millId = await tx.insert('parties', {
        'name': 'Faisal Flour Mills',
        'name_search': 'faisal flour mills',
        'party_type': 'supplier',
      });
      attaId = await tx.insert('items', {
        'name': 'Atta 20kg',
        'name_search': 'atta 20kg',
        'base_unit_id': pcsUnitId,
        'sale_rate_milli_paisa': Rate.rupees(2400).inMilliPaisa,
      });
    });
  });

  tearDown(() async => db.close());

  Future<String> deliver(int rupees) async => (await buy(
    on(today),
    PurchaseDraft(
      partyId: millId,
      paid: Money.zero,
      lines: [
        PurchaseLineDraft(
          itemId: attaId,
          itemName: 'Atta 20kg',
          qty: Qty.units(40),
          baseQty: Qty.units(40),
          unitId: pcsUnitId,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees ~/ 40),
        ),
      ],
    ),
  )).documentId;

  Future<String> writeCheque(int rupees, {String no = '118830'}) async =>
      (await pay(
        on(today),
        SupplierPaymentDraft(
          partyId: millId,
          amount: Money.rupees(rupees),
          mode: 'cheque',
          paymentAccountId: bankAccountId,
          chequeNo: no,
          chequeDateUtcMillis: chequeDueUtcMillis(const BusinessDate(due)),
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

  Future<int> balanceOf(String documentId) async =>
      (await db
              .customSelect(
                'SELECT balance_paisa FROM documents WHERE id = ?',
                variables: [Variable<String>(documentId)],
              )
              .getSingle())
          .read<int>('balance_paisa');

  test(
    'a cheque to a supplier settles the delivery and leaves the bank alone',
    () async {
      final delivery = await deliver(80000);
      await writeCheque(80000);

      expect(await balanceOf(delivery), 0);
      expect(await net('accounts_payable'), 0);
      expect(await net('cheques_issued'), -8000000);
      expect(await net('bank'), 0, reason: 'nothing has left the bank yet');

      final issued = (await queries.chequesIssued(firm.firmId)).single;
      expect(issued.chequeNo, '118830');
      expect(issued.due, const BusinessDate(due));
      expect(issued.partyName, 'Faisal Flour Mills');
    },
  );

  test('when the supplier presents it, the money leaves the bank', () async {
    await deliver(80000);
    final cheque = await writeCheque(80000);

    await expectLater(
      cheques.clearIssued(on(today), cheque),
      throwsA(isA<ChequeRefused>()),
    );
    await cheques.clearIssued(on(due), cheque);

    expect(await net('cheques_issued'), 0);
    expect(await net('bank'), -8000000);
    expect(await queries.chequesIssued(firm.firmId), isEmpty);
  });

  test('when it bounces, the shop owes the supplier again', () async {
    final delivery = await deliver(80000);
    final cheque = await writeCheque(80000);

    await cheques.bounceIssued(on(due), cheque, reason: 'Funds insufficient');

    expect(await balanceOf(delivery), 8000000);
    expect(await net('accounts_payable'), -8000000);
    expect(await net('cheques_issued'), 0);
    expect(
      (await queries.partyById(firm.firmId, millId))!.payable,
      const Money.rupees(80000),
    );
  });

  test(
    'the shop bouncing its own cheque is not a 489-F case against the mill',
    () async {
      await deliver(80000);
      final cheque = await writeCheque(80000);
      await cheques.bounceIssued(on(due), cheque);

      expect(await queries.bouncedCheques(firm.firmId), isEmpty);
      expect(
        await queries.demandNotice(
          firm.firmId,
          cheque,
          issuedOn: const BusinessDate(due),
        ),
        isNull,
      );
      expect((await queries.partyById(firm.firmId, millId))!.bouncedCheques, 0);
    },
  );

  test(
    'a shop set up before Cheques Issued existed gets it when first needed',
    () async {
      // Every shop set up before M6 has a chart without this account.
      await db.customStatement(
        "DELETE FROM accounts WHERE system_key = 'cheques_issued'",
      );
      await deliver(80000);
      await writeCheque(80000);

      final added = await db
          .customSelect(
            'SELECT a.code, p.code AS parent FROM accounts a '
            'JOIN accounts p ON p.id = a.parent_id '
            "WHERE a.system_key = 'cheques_issued'",
          )
          .getSingle();
      expect(added.read<String>('code'), '2150');
      expect(added.read<String>('parent'), '2000');
      expect(await net('cheques_issued'), -8000000);
      final audit = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM audit_log WHERE action_code = 'ACCOUNT_ADDED'",
          )
          .getSingle();
      expect(audit.read<int>('n'), 1);
    },
  );

  test('a cheque to a supplier needs its number', () async {
    await deliver(80000);
    await expectLater(
      writeCheque(80000, no: ''),
      throwsA(isA<SupplierPaymentRefused>()),
    );
  });
}
