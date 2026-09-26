import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Goods going back to the supplier, against a real database.
///
/// Two deliveries of rice: ten sacks at Rs 100, then ten at Rs 120 with
/// Rs 200 of freight. The shelf holds twenty at an average of Rs 120.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late DriftAppQueries queries;
  late RecordPurchaseUseCase buy;
  late PostSaleUseCase sell;
  late RecordPurchaseReturnUseCase sendBack;
  late ActorContext actor;
  late String pcsUnitId;
  late String riceId;
  late String millId;
  late String cashAccountId;

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
    final runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    buy = RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: runner));
    sell = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    sendBack = RecordPurchaseReturnUseCase(
      writer: DriftPurchaseReturnWriter(runner: runner),
    );

    pcsUnitId =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');
    cashAccountId = (await queries.paymentAccounts(
      firm.firmId,
    )).firstWhere((a) => a.isDefault).id;

    await runner.run(actor, (tx) async {
      millId = await tx.insert('parties', {
        'name': 'Punjab Rice Mills',
        'name_search': 'punjab rice mills',
        'party_type': 'supplier',
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

  Future<String> deliver({
    required int rate,
    int freight = 0,
    int paid = 0,
  }) async => (await buy(
    actor,
    PurchaseDraft(
      partyId: millId,
      freight: Money.rupees(freight),
      paid: Money.rupees(paid),
      paymentAccountId: paid > 0 ? cashAccountId : null,
      lines: [
        PurchaseLineDraft(
          itemId: riceId,
          itemName: 'Chawal Basmati',
          qty: Qty.units(10),
          baseQty: Qty.units(10),
          unitId: pcsUnitId,
          unitCode: 'pcs',
          rate: Rate.rupees(rate),
        ),
      ],
    ),
  )).documentId;

  Future<String> lineOf(String deliveryId) async =>
      (await queries.returnableDelivery(
        firm.firmId,
        deliveryId,
      ))!.lines.single.documentLineId;

  Future<RecordedPurchaseReturn> returnSome(
    String deliveryId,
    int qty, {
    int refund = 0,
  }) async => sendBack(
    actor,
    PurchaseReturnDraft(
      originalDocumentId: deliveryId,
      lines: [
        ReturnLineDraft(
          documentLineId: await lineOf(deliveryId),
          qty: Qty.units(qty),
        ),
      ],
      reason: 'Boriyan phati hui thin',
      refundNow: Money.rupees(refund),
      paymentAccountId: refund > 0 ? cashAccountId : null,
    ),
  );

  Future<int> scalar(String sql, [List<Object> args = const []]) async =>
      (await db
                  .customSelect(
                    sql,
                    variables: [for (final a in args) Variable<Object>(a)],
                  )
                  .getSingle())
              .data
              .values
              .first
          as int;

  Future<int> averageOfRice() =>
      scalar('SELECT avg_cost_milli_paisa FROM items WHERE id = ?', [riceId]);

  test(
    'torn sacks go back and what is owed on the delivery comes down',
    () async {
      await deliver(rate: 100);
      final second = await deliver(rate: 120, freight: 200);

      await returnSome(second, 4);

      expect(
        await scalar('SELECT balance_paisa FROM documents WHERE id = ?', [
          second,
        ]),
        92000,
        reason: 'Rs 1,400 owed, less the Rs 480 of goods that went back',
      );
      final mill = await queries.partyById(firm.firmId, millId);
      expect(mill!.payable, const Money.rupees(1920));
    },
  );

  test('a whole delivery sent back puts the shelf and its cost back', () async {
    await deliver(rate: 100);
    final second = await deliver(rate: 120, freight: 200);
    expect(await averageOfRice(), const Rate.rupees(120).inMilliPaisa);

    await returnSome(second, 10);

    expect(await averageOfRice(), const Rate.rupees(100).inMilliPaisa);
    expect(
      await scalar(
        'SELECT SUM(qty_delta_thousandths) FROM stock_ledger WHERE item_id = ?',
        [riceId],
      ),
      10000,
    );
  });

  test('the inventory account matches the shelf afterwards', () async {
    await deliver(rate: 100);
    final second = await deliver(rate: 120, freight: 200);
    await returnSome(second, 10);

    final inventory = await scalar(
      'SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) '
      'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
      "WHERE a.system_key = 'inventory'",
    );
    expect(inventory, 100000, reason: 'ten sacks at Rs 100 are on the shelf');

    final totals = await db
        .customSelect(
          'SELECT SUM(debit_paisa) AS dr, SUM(credit_paisa) AS cr '
          'FROM journal_lines',
        )
        .getSingle();
    expect(totals.read<int>('dr'), totals.read<int>('cr'));
  });

  test('a second return cannot send back more than came in', () async {
    final delivery = await deliver(rate: 120);
    await returnSome(delivery, 6);

    await expectLater(returnSome(delivery, 5), throwsA(isA<ReturnRefused>()));
    expect(
      (await queries.returnableDelivery(
        firm.firmId,
        delivery,
      ))!.lines.single.returnable,
      Qty.units(4),
    );
  });

  test('goods already sold cannot go back to the supplier', () async {
    final delivery = await deliver(rate: 120);
    await sell(
      actor,
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: riceId,
            itemName: 'Chawal Basmati',
            qty: Qty.units(8),
            baseQty: Qty.units(8),
            unitId: pcsUnitId,
            unitCode: 'pcs',
            rate: Rate.rupees(150),
          ),
        ],
        tenders: [
          TenderDraft(
            mode: 'cash',
            paymentAccountId: cashAccountId,
            amount: const Money.rupees(1200),
          ),
        ],
      ),
    );

    await expectLater(
      returnSome(delivery, 4),
      throwsA(
        isA<ReturnRefused>().having(
          (e) => e.reason,
          'reason',
          contains('already been sold'),
        ),
      ),
    );
  });

  test('a paid-for delivery sends back cash, into the drawer', () async {
    final delivery = await deliver(rate: 120, paid: 1200);

    await expectLater(returnSome(delivery, 4), throwsA(isA<ReturnRefused>()));
    final back = await returnSome(delivery, 4, refund: 480);

    expect(back.refunded, const Money.rupees(480));
    expect(back.againstBill, Money.zero);
  });

  test('the supplier khata shows the return against the delivery', () async {
    final delivery = await deliver(rate: 120);
    await returnSome(delivery, 4);

    final entries = await queries.payablesLedger(firm.firmId, millId);
    expect(entries.map((e) => e.kind), ['purchase', 'return']);
    expect(entries.last.amount, const Money.rupees(-480));
    expect(entries.last.balanceAfter, const Money.rupees(720));
  });

  test('a refused return writes nothing and burns no number', () async {
    final delivery = await deliver(rate: 120);
    final before = await scalar('SELECT COUNT(*) FROM documents');

    await expectLater(returnSome(delivery, 11), throwsA(isA<ReturnRefused>()));
    expect(await scalar('SELECT COUNT(*) FROM documents'), before);

    final back = await returnSome(delivery, 1);
    expect(back.docNo, endsWith('0001'));
  });

  test('a return to a supplier is recorded in the audit trail', () async {
    final delivery = await deliver(rate: 120);
    final back = await returnSome(delivery, 2);

    expect(
      await scalar(
        'SELECT COUNT(*) FROM audit_log '
        "WHERE action_code = 'PURCHASE_RETURNED' AND entity_id = ?",
        [back.documentId],
      ),
      1,
    );
  });
}
