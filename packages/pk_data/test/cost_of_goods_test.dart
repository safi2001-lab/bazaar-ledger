import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// What the shop actually made on a bill.
///
/// A shopkeeper's first question about a sale is not what it rang up for, it
/// is what was left over. `documents.cost_paisa` is the number every
/// bill-wise profit report reads, and it comes from `items.avg_cost_milli_paisa`
/// by way of `averageCostFor`.
///
/// That column sat at its schema default of zero for every item the app could
/// create. Opening stock captured the cost in two other places — on the item
/// row as `opening_rate_milli_paisa`, and on the stock ledger row as
/// `value_delta_paisa` — and neither is the one the sale reads. So the sale
/// posted no COGS line at all, the Inventory account was credited nothing
/// while six thousand rupees of goods left the shelf, and the bill reported
/// its entire selling price as profit.
///
/// Every shop hits this. Entering what is already on the shelf is the last
/// field of the item quick-add form.
void main() {
  late AppDatabase db;
  late FixedClock clock;
  late UlidGenerator ids;
  late TxRunner runner;
  late FirstRunResult firm;
  late ActorContext actor;
  late DriftCatalogueWriter catalogue;
  late PostSaleUseCase postSale;
  late String pcsUnitId;

  setUp(() async {
    db = await openTestDatabase();
    clock = FixedClock(DateTime.utc(2026, 8, 23, 9, 15));
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
    catalogue = DriftCatalogueWriter(runner);
    postSale = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));

    final unit = await db
        .customSelect("SELECT id FROM units WHERE code = 'pcs'")
        .getSingle();
    pcsUnitId = unit.read<String>('id');
  });

  tearDown(() async => db.close());

  /// A tin bought for Rs 300 and sold for Rs 500: Rs 200 of margin.
  Future<String> addOilWithOpeningStock() => catalogue.addItem(
    actor,
    ItemDraft(
      name: 'Cooking Oil 5L',
      baseUnitId: pcsUnitId,
      saleRate: const Rate.rupees(500),
      openingStock: Qty.units(20),
      openingRate: const Rate.rupees(300),
    ),
  );

  Future<int?> costOf(String documentId) async {
    final row = await db
        .customSelect(
          'SELECT cost_paisa FROM documents WHERE id = ?',
          variables: [Variable<String>(documentId)],
        )
        .getSingle();
    return row.readNullable<int>('cost_paisa');
  }

  test('opening stock sets the average cost it was bought at', () async {
    final itemId = await addOilWithOpeningStock();

    final row = await db
        .customSelect(
          'SELECT avg_cost_milli_paisa FROM items WHERE id = ?',
          variables: [Variable<String>(itemId)],
        )
        .getSingle();

    expect(
      row.read<int>('avg_cost_milli_paisa'),
      const Rate.rupees(300).inMilliPaisa,
      reason: 'the weighted average of one consignment is that consignment',
    );
  });

  test('an item with nothing on the shelf has no cost yet', () async {
    final itemId = await catalogue.addItem(
      actor,
      ItemDraft(
        name: 'Special Order Cloth',
        baseUnitId: pcsUnitId,
        saleRate: const Rate.rupees(500),
      ),
    );

    final row = await db
        .customSelect(
          'SELECT avg_cost_milli_paisa FROM items WHERE id = ?',
          variables: [Variable<String>(itemId)],
        )
        .getSingle();

    expect(
      row.read<int>('avg_cost_milli_paisa'),
      0,
      reason: 'nothing has been bought, so nothing has been paid',
    );
  });

  test('a sale of opening stock costs what the goods cost', () async {
    final itemId = await addOilWithOpeningStock();

    final posted = await postSale(
      actor,
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: itemId,
            itemName: 'Cooking Oil 5L',
            qty: Qty.units(2),
            baseQty: Qty.units(2),
            unitId: pcsUnitId,
            unitCode: 'pcs',
            rate: const Rate.rupees(500),
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: firm.cashPaymentAccountId,
            mode: 'cash',
            amount: Money.rupees(1000),
            tendered: Money.rupees(1000),
          ),
        ],
      ),
    );

    // Two tins at Rs 300 apiece.
    expect(
      await costOf(posted.documentId),
      const Money.rupees(600).inPaisa,
      reason: 'bill-wise profit reads this column and nothing else',
    );

    // And the books say the same thing: Inventory is credited what left the
    // shelf, and Cost of Goods Sold is debited the same. Without this the
    // sale posted no cost line at all, so the Inventory account still carried
    // stock that had already been sold.
    final cogs = await db.customSelect('''
      SELECT a.code AS code, jl.debit_paisa AS dr, jl.credit_paisa AS cr
      FROM journal_lines jl
      JOIN accounts a ON a.id = jl.account_id
      WHERE jl.debit_paisa > 0 OR jl.credit_paisa > 0
      ''').get();

    final byCode = {
      for (final r in cogs)
        r.read<String>('code'): (r.read<int>('dr'), r.read<int>('cr')),
    };

    expect(
      byCode.keys.where((c) => byCode[c]!.$1 == 60000),
      isNotEmpty,
      reason: 'something must be debited the Rs 600 the goods cost',
    );
    expect(
      byCode.keys.where((c) => byCode[c]!.$2 == 60000),
      isNotEmpty,
      reason: 'and inventory must be credited the same Rs 600',
    );

    // The whole entry still balances at exact integer equality.
    final totals = await db
        .customSelect(
          'SELECT SUM(debit_paisa) d, SUM(credit_paisa) c FROM journal_lines',
        )
        .getSingle();
    expect(totals.read<int>('d'), totals.read<int>('c'));
  });

  test('the item editor cannot retype what the goods cost', () async {
    final itemId = await addOilWithOpeningStock();

    await catalogue.updateItem(
      actor,
      itemId,
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: pcsUnitId,
        saleRate: const Rate.rupees(900),
        // An ItemDraft built by the edit form carries no opening stock, so
        // this would drive the average cost to zero if the update path did
        // not strip it — and every bill after the edit would report the full
        // selling price as margin.
        openingRate: Rate.zero,
      ),
    );

    final row = await db
        .customSelect(
          'SELECT avg_cost_milli_paisa, sale_rate_milli_paisa FROM items '
          'WHERE id = ?',
          variables: [Variable<String>(itemId)],
        )
        .getSingle();

    expect(
      row.read<int>('avg_cost_milli_paisa'),
      const Rate.rupees(300).inMilliPaisa,
      reason: 'cost is what was paid, not what an editor types',
    );
    expect(
      row.read<int>('sale_rate_milli_paisa'),
      const Rate.rupees(900).inMilliPaisa,
      reason: 'the reprice itself still went through',
    );
  });
}
