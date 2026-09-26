import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// The average cost, moving for the first time.
///
/// `items.avg_cost_milli_paisa` has been written once at item creation and
/// `DriftCatalogueWriter` explicitly strips it from every update. A shop that
/// opened rice at Rs 90 and has been buying at Rs 120 for six months still
/// reads a Rs 30 profit on every sale. These prove that stops.
void main() {
  late AppDatabase db;
  late UlidGenerator ids;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late PostSaleUseCase postSale;
  late RecordPurchaseUseCase buy;
  late ActorContext actor;
  late String pcsUnitId;
  late String riceId;
  late String supplierId;
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
    actor = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    postSale = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    buy = RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: runner));

    pcsUnitId =
        (await db.customSelect("SELECT id FROM units WHERE code = 'pcs'").get())
            .first
            .read<String>('id');
    cashAccountId = (await queries.paymentAccounts(
      firm.firmId,
    )).firstWhere((a) => a.isDefault).id;

    await runner.run(actor, (tx) async {
      supplierId = await tx.insert('parties', {
        'name': 'Punjab Rice Mills',
        'name_search': 'punjab rice mills',
        'party_type': 'supplier',
      });
      riceId = await tx.insert('items', {
        'name': 'Chawal Basmati',
        'name_search': 'chawal basmati',
        'base_unit_id': pcsUnitId,
        'sale_rate_milli_paisa': Rate.rupees(150).inMilliPaisa,
        'avg_cost_milli_paisa': Rate.rupees(90).inMilliPaisa,
      });
    });
  });

  tearDown(() async => db.close());

  Future<PostedPurchase> deliver({
    int qty = 10,
    int rateRupees = 120,
    Money freight = Money.zero,
    Money paid = Money.zero,
  }) => buy(
    actor,
    PurchaseDraft(
      partyId: supplierId,
      supplierBillNo: 'SUP/9912',
      freight: freight,
      paid: paid,
      paymentAccountId: paid.isPositive ? cashAccountId : null,
      lines: [
        PurchaseLineDraft(
          itemId: riceId,
          itemName: 'Chawal Basmati',
          qty: Qty.units(qty),
          baseQty: Qty.units(qty),
          unitId: pcsUnitId,
          unitCode: 'pcs',
          rate: Rate.rupees(rateRupees),
        ),
      ],
    ),
  );

  Future<Rate> averageOf(String itemId) async => Rate.raw(
    (await db
            .customSelect(
              'SELECT avg_cost_milli_paisa FROM items WHERE id = ?',
              variables: [Variable<String>(itemId)],
            )
            .getSingle())
        .read<int>('avg_cost_milli_paisa'),
  );

  Future<Qty> balanceOf(String itemId) async => Qty.raw(
    (await db
            .customSelect(
              'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS b '
              'FROM stock_ledger WHERE item_id = ?',
              variables: [Variable<String>(itemId)],
            )
            .getSingle())
        .read<int>('b'),
  );

  test('a delivery moves the average, which nothing did before', () async {
    expect(await averageOf(riceId), const Rate.rupees(90));

    await deliver();

    expect(
      await averageOf(riceId),
      const Rate.rupees(120),
      reason:
          'the average is still what the item was opened at, so every margin '
          'this shop reads is a guess',
    );
    expect(await balanceOf(riceId), Qty.units(10));
  });

  test("the supplier's own bill number is kept on the bill", () async {
    // It used to reach only the audit sentence, so the number a supplier
    // quotes about an unpaid delivery could not be found anywhere.
    final posted = await deliver();

    final row = await db
        .customSelect(
          'SELECT supplier_bill_no FROM documents WHERE id = ?',
          variables: [Variable<String>(posted.documentId)],
        )
        .getSingle();
    expect(row.read<String?>('supplier_bill_no'), 'SUP/9912');

    final listed = await queries.recentPurchases(firm.firmId);
    expect(listed.single.supplierBillNo, 'SUP/9912');
  });

  test('a second delivery weights against what is on the shelf', () async {
    await deliver(qty: 10, rateRupees: 90);
    await deliver(qty: 10, rateRupees: 120);

    expect(await averageOf(riceId), const Rate.rupees(105));
    expect(await balanceOf(riceId), Qty.units(20));
  });

  test('freight lands in the cost, because the shop paid it', () async {
    await deliver(qty: 10, rateRupees: 100, freight: const Money.rupees(200));

    expect(await averageOf(riceId), const Rate.rupees(120));
  });

  test('the books balance after a delivery', () async {
    await deliver(
      freight: const Money.rupees(150),
      paid: const Money.rupees(400),
    );

    final totals = await db
        .customSelect(
          'SELECT SUM(debit_paisa) AS d, SUM(credit_paisa) AS c '
          'FROM journal_lines',
        )
        .getSingle();
    expect(totals.read<int>('d'), totals.read<int>('c'));
  });

  test('what is still owed reaches the supplier khata', () async {
    final posted = await deliver(paid: const Money.rupees(400));

    expect(posted.total, const Money.rupees(1200));
    expect(posted.balance, const Money.rupees(800));

    final payable = await db
        .customSelect(
          '''
          SELECT COALESCE(SUM(jl.credit_paisa - jl.debit_paisa), 0) AS owed
          FROM journal_lines jl
          JOIN accounts a ON a.id = jl.account_id
          WHERE a.system_key = 'accounts_payable' AND jl.party_id = ?
          ''',
          variables: [Variable<String>(supplierId)],
        )
        .getSingle();
    expect(payable.read<int>('owed'), const Money.rupees(800).inPaisa);
  });

  test('a sale after a delivery costs what the delivery cost', () async {
    // The whole reason any of this exists. Before, this sale would have
    // posted COGS at Rs 90 and reported a Rs 60 profit on a Rs 30 one.
    await deliver(qty: 10, rateRupees: 120);

    await postSale(
      actor,
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: riceId,
            itemName: 'Chawal Basmati',
            qty: Qty.units(1),
            baseQty: Qty.units(1),
            unitId: pcsUnitId,
            unitCode: 'pcs',
            rate: Rate.rupees(150),
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: cashAccountId,
            mode: 'cash',
            amount: const Money.rupees(150),
          ),
        ],
      ),
    );

    final cogs = await db.customSelect('''
          SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS cost
          FROM journal_lines jl
          JOIN accounts a ON a.id = jl.account_id
          WHERE a.system_key = 'cogs'
          ''').getSingle();

    expect(
      cogs.read<int>('cost'),
      const Money.rupees(120).inPaisa,
      reason:
          'the sale posted the price the item was opened at, not what the '
          'shop actually paid for the sack it came out of',
    );
  });

  test('a delivery covering a shortfall writes the difference off', () async {
    // Sell more than is on the shelf, then take the delivery.
    //
    // The three missing units were carried out of the books at the opening
    // average of Rs 90 — Rs 270 of COGS against stock that was never there.
    // The delivery reveals they cost Rs 130 each, so Rs 120 more went out of
    // the shop than the books ever recognised, and it was never profit.
    await postSale(
      actor,
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: riceId,
            itemName: 'Chawal Basmati',
            qty: Qty.units(3),
            baseQty: Qty.units(3),
            unitId: pcsUnitId,
            unitCode: 'pcs',
            rate: Rate.rupees(150),
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: cashAccountId,
            mode: 'cash',
            amount: const Money.rupees(450),
          ),
        ],
      ),
    );
    expect(await balanceOf(riceId), Qty.raw(-3000));

    await deliver(qty: 10, rateRupees: 130);

    expect(await averageOf(riceId), const Rate.rupees(130));
    expect(await balanceOf(riceId), Qty.units(7));

    final wastage = await db.customSelect('''
          SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS lost
          FROM journal_lines jl
          JOIN accounts a ON a.id = jl.account_id
          WHERE a.system_key = 'stock_wastage'
          ''').getSingle();
    expect(wastage.read<int>('lost'), const Money.rupees(120).inPaisa);
  });

  test('a failure part-way through leaves nothing behind', () async {
    Future<Map<String, int>> counts() async {
      final result = <String, int>{};
      for (final table in const [
        'documents',
        'document_lines',
        'stock_ledger',
        'journal_entries',
        'journal_lines',
      ]) {
        result[table] =
            (await db
                    .customSelect('SELECT COUNT(*) AS n FROM $table')
                    .getSingle())
                .read<int>('n');
      }
      return result;
    }

    await deliver();
    final before = await counts();
    final averageBefore = await averageOf(riceId);

    // Inventory removed behind the writer's back, so it fails after the
    // document, its lines, the stock rows and the new average are already
    // written. Anything less would not reach the thing it claims to test.
    await db.customStatement(
      "UPDATE accounts SET deleted_at_utc = 1 WHERE system_key = 'inventory'",
    );

    await expectLater(deliver(), throwsA(isA<StateError>()));

    expect(await counts(), before, reason: 'a failed delivery left rows');
    expect(
      await averageOf(riceId),
      averageBefore,
      reason: 'a failed delivery moved the average anyway',
    );
  });

  test('the delivery is recorded in the audit trail', () async {
    final posted = await deliver();

    final audit = await db
        .customSelect(
          'SELECT entity_id, summary, amount_paisa FROM audit_log '
          "WHERE action_code = 'PURCHASE_POSTED'",
        )
        .getSingle();

    expect(audit.read<String>('entity_id'), posted.documentId);
    expect(audit.read<int>('amount_paisa'), const Money.rupees(1200).inPaisa);
    expect(audit.read<String>('summary'), contains('SUP/9912'));
  });

  test('the new average is reported back, not left to be read', () async {
    final posted = await deliver(qty: 10, rateRupees: 120);

    expect(posted.newAverages[riceId], const Rate.rupees(120));
  });
}
