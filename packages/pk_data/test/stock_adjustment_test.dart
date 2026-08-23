import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Correcting what the shelf says.
///
/// Two things have to happen and the second is the one that gets forgotten.
/// The stock ledger gains a row, so the figure changes and stays attributable.
/// And the books gain an entry, because goods that walked off the shelf are an
/// expense whether or not anyone noticed — without it the Inventory account
/// still carries stock that is not there, the Trial Balance is quietly wrong,
/// and the shop's profit is overstated by exactly the value of what it lost.
void main() {
  late AppDatabase db;
  late FixedClock clock;
  late UlidGenerator ids;
  late TxRunner runner;
  late FirstRunResult firm;
  late ActorContext actor;
  late DriftCatalogueWriter catalogue;
  late String pcsUnitId;
  late String oilId;

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

    pcsUnitId = (await db
            .customSelect("SELECT id FROM units WHERE code = 'pcs'")
            .getSingle())
        .read<String>('id');

    // Twenty tins on the shelf, bought at Rs 300 each.
    oilId = await catalogue.addItem(
      actor,
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: pcsUnitId,
        saleRate: const Rate.rupees(500),
        openingStock: Qty.units(20),
        openingRate: const Rate.rupees(300),
      ),
    );
  });

  tearDown(() async => db.close());

  Future<Qty> onHand() async {
    final row = await db.customSelect(
      'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS q FROM stock_ledger '
      'WHERE deleted_at_utc IS NULL',
    ).getSingle();
    return Qty.raw(row.read<int>('q'));
  }

  Future<Map<String, (int, int)>> journalByAccountCode() async {
    final rows = await db.customSelect(
      '''
      SELECT a.code AS code,
             SUM(jl.debit_paisa) AS dr,
             SUM(jl.credit_paisa) AS cr
      FROM journal_lines jl
      JOIN accounts a ON a.id = jl.account_id
      JOIN journal_entries je ON je.id = jl.journal_entry_id
      WHERE je.source_type = 'adjustment'
      GROUP BY a.code
      ''',
    ).get();
    return {
      for (final r in rows)
        r.read<String>('code'): (r.read<int>('dr'), r.read<int>('cr')),
    };
  }

  test('a stock take that comes up short writes the loss off', () async {
    // Counted seventeen. Three tins are gone.
    await catalogue.adjustStock(
      actor,
      StockAdjustmentDraft.counted(
        itemId: oilId,
        counted: Qty.units(17),
        reason: 'Mahana ginti',
      ),
    );

    expect(await onHand(), Qty.units(17));

    // Three tins at Rs 300 apiece: Rs 900 off the shelf and Rs 900 of expense.
    final journal = await journalByAccountCode();
    expect(journal['5500'], (90000, 0), reason: 'Stock Wastage is debited');
    expect(journal['1200'], (0, 90000), reason: 'Inventory is credited');
  });

  test('and the correction says who, when and why', () async {
    await catalogue.adjustStock(
      actor,
      StockAdjustmentDraft.counted(
        itemId: oilId,
        counted: Qty.units(17),
        reason: 'Mahana ginti',
      ),
    );

    final row = await db.customSelect(
      "SELECT txn_type, reason, qty_delta_thousandths q, created_by, "
      "balance_after_thousandths b FROM stock_ledger "
      "WHERE txn_type IN ('adjustment', 'wastage')",
    ).getSingle();

    expect(row.read<String>('txn_type'), 'adjustment');
    expect(row.read<String>('reason'), 'Mahana ginti');
    expect(row.read<int>('q'), -3000);
    expect(row.read<int>('b'), 17000);
    expect(row.read<String>('created_by'), firm.ownerUserId);

    final audit = await db.customSelect(
      "SELECT action_code, summary FROM audit_log "
      "WHERE action_code = 'STOCK_ADJUSTED'",
    ).getSingle();
    expect(audit.read<String>('summary'), contains('Mahana ginti'));
  });

  test('a breakage is a write-off, and says so', () async {
    // Not a recount. Three tins broke, and the ledger records which it was:
    // the arithmetic is the same and the fact is not.
    await catalogue.adjustStock(
      actor,
      StockAdjustmentDraft.byDelta(
        itemId: oilId,
        change: Qty.units(-3),
        reason: 'Toot gaye',
      ),
    );

    expect(await onHand(), Qty.units(17));
    final row = await db.customSelect(
      "SELECT txn_type FROM stock_ledger WHERE reason = 'Toot gaye'",
    ).getSingle();
    expect(row.read<String>('txn_type'), 'wastage');
  });

  test('stock that turns up is put back, the other way round', () async {
    // A recount that comes out long. The shop had already expensed goods it
    // still has, so the entry reverses.
    await catalogue.adjustStock(
      actor,
      StockAdjustmentDraft.counted(
        itemId: oilId,
        counted: Qty.units(22),
        reason: 'Peeche mil gaye',
      ),
    );

    expect(await onHand(), Qty.units(22));
    final journal = await journalByAccountCode();
    expect(journal['1200'], (60000, 0), reason: 'Inventory is debited back');
    expect(journal['5500'], (0, 60000));
  });

  test('a correction without a reason is refused', () async {
    // The whole point. A stock figure that can be changed without saying why
    // is a stock figure nobody can defend to an auditor, to a supplier, or to
    // whoever was on the counter that afternoon.
    // Thrown synchronously, before the transaction is even opened: there is
    // nothing to weigh up, and a write path that has already started is a
    // worse place to find out.
    expect(
      () => catalogue.adjustStock(
        actor,
        StockAdjustmentDraft.counted(
          itemId: oilId,
          counted: Qty.units(17),
          reason: '   ',
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(await onHand(), Qty.units(20), reason: 'nothing moved');
  });

  test('a stock take that agrees with the ledger is not a correction',
      () async {
    await expectLater(
      catalogue.adjustStock(
        actor,
        StockAdjustmentDraft.counted(
          itemId: oilId,
          counted: Qty.units(20),
          reason: 'Ginti',
        ),
      ),
      throwsA(isA<StateError>()),
    );
    final count = await db.customSelect(
      "SELECT COUNT(*) c FROM stock_ledger WHERE txn_type = 'adjustment'",
    ).getSingle();
    expect(count.read<int>('c'), 0, reason: 'no empty row was written');
  });

  test('the books still balance afterwards', () async {
    await catalogue.adjustStock(
      actor,
      StockAdjustmentDraft.byDelta(
        itemId: oilId,
        change: Qty.units(-3),
        reason: 'Toot gaye',
      ),
    );
    expect((await db.checkHealth()).isHealthy, isTrue);
  });

  test('an item that carries no stock has nothing to correct', () async {
    final serviceId = await catalogue.addItem(
      actor,
      ItemDraft(
        name: 'Home delivery',
        baseUnitId: pcsUnitId,
        saleRate: const Rate.rupees(100),
        tracksStock: false,
      ),
    );
    await expectLater(
      catalogue.adjustStock(
        actor,
        StockAdjustmentDraft.byDelta(
          itemId: serviceId,
          change: Qty.units(-1),
          reason: 'x',
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
