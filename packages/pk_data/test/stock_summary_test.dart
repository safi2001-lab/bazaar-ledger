import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// What the shelves are worth, in one glance.
///
/// The number that matters is the valuation, and the way to get it wrong is to
/// value stock at what it would SELL for. That counts profit the shop has not
/// made and is the most common way a small business talks itself into believing
/// it is richer than it is. Cost, always.
///
/// The second way to get it wrong is arithmetic. Quantity is thousandths and
/// cost is milli-paisa, so the product needs scaling twice, and doing it in the
/// wrong order either truncates a paisa per item — two hundred rupees across a
/// 20,000-SKU catalogue — or overflows int64 on a large shop.
void main() {
  late AppDatabase db;
  late FixedClock clock;
  late UlidGenerator ids;
  late TxRunner runner;
  late FirstRunResult firm;
  late ActorContext actor;
  late DriftCatalogueWriter catalogue;
  late DriftAppQueries queries;
  late String pcs;

  setUp(() async {
    db = await openTestDatabase();
    clock = FixedClock(DateTime.utc(2026, 8, 23, 9));
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
    queries = DriftAppQueries(db);
    pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');
  });

  tearDown(() async => db.close());

  Future<String> stock({
    required String name,
    required int units,
    required int costRupees,
    int floorUnits = 0,
    bool tracksStock = true,
  }) => catalogue.addItem(
    actor,
    ItemDraft(
      name: name,
      baseUnitId: pcs,
      saleRate: Rate.rupees(costRupees * 2),
      openingStock: Qty.units(units),
      openingRate: Rate.rupees(costRupees),
      minStock: Qty.units(floorUnits),
      tracksStock: tracksStock,
    ),
  );

  test('an empty shop is empty, not an error', () async {
    final summary = await queries.stockSummary(firm.firmId);
    expect(summary.isEmpty, isTrue);
    expect(summary.stockValue, Money.zero);
  });

  test('stock is valued at cost, never at what it would sell for', () async {
    // Twenty tins bought at Rs 300, priced at Rs 600. The shelf is worth
    // Rs 6,000, not Rs 12,000 — the other Rs 6,000 is profit the shop has not
    // made and may never make.
    await stock(name: 'Cooking Oil 5L', units: 20, costRupees: 300);

    final summary = await queries.stockSummary(firm.firmId);
    expect(summary.trackedItems, 1);
    expect(
      summary.stockValue,
      Money.rupees(6000),
      reason: 'the valuation counts margin the shop has not earned',
    );
  });

  test('several items add up', () async {
    await stock(name: 'Cooking Oil 5L', units: 20, costRupees: 300);
    await stock(name: 'Chawal 5kg', units: 12, costRupees: 1200);
    await stock(name: 'Cheeni 1kg', units: 40, costRupees: 145);

    final summary = await queries.stockSummary(firm.firmId);
    expect(summary.trackedItems, 3);
    // 6,000 + 14,400 + 5,800
    expect(summary.stockValue, Money.rupees(26200));
  });

  test('a service is not stock and does not count as out of stock', () async {
    // Counting services would put every tailoring charge in the shop on the
    // out-of-stock list, and a list that is always full is a list nobody reads.
    await stock(name: 'Cooking Oil 5L', units: 20, costRupees: 300);
    await stock(name: 'Silai', units: 0, costRupees: 0, tracksStock: false);

    final summary = await queries.stockSummary(firm.firmId);
    expect(summary.trackedItems, 1);
    expect(summary.outCount, 0);
  });

  test('low, out and negative are counted apart', () async {
    // Three different problems with three different answers. "Order more",
    // "you have none", and "your books say less than nothing, which cannot be
    // true and needs a person".
    await stock(name: 'Low', units: 3, costRupees: 100, floorUnits: 5);
    await stock(name: 'Fine', units: 50, costRupees: 100, floorUnits: 5);
    final outId = await stock(name: 'Out', units: 10, costRupees: 100);
    final shortId = await stock(name: 'Short', units: 10, costRupees: 100);

    await catalogue.adjustStock(
      actor,
      StockAdjustmentDraft.counted(
        itemId: outId,
        counted: Qty.zero,
        reason: 'Sab bik gaya',
      ),
    );
    await catalogue.adjustStock(
      actor,
      StockAdjustmentDraft.byDelta(
        itemId: shortId,
        change: const Qty.units(-14),
        reason: 'Bina record ke bika',
      ),
    );

    final summary = await queries.stockSummary(firm.firmId);
    expect(summary.trackedItems, 4);
    expect(summary.lowCount, 1, reason: 'Low');
    expect(summary.outCount, 1, reason: 'Out');
    expect(summary.negativeCount, 1, reason: 'Short');
  });

  test('an item at exactly its floor is low, not fine', () async {
    // The boundary a shopkeeper set is the point at which they want telling,
    // not one below it.
    await stock(name: 'Exactly', units: 5, costRupees: 100, floorUnits: 5);
    final summary = await queries.stockSummary(firm.firmId);
    expect(summary.lowCount, 1);
  });

  test('an item with no floor is never low, however little is left', () async {
    // A default floor of zero would make every item the shop has ever run
    // down into an alert.
    await stock(name: 'No floor', units: 1, costRupees: 100);
    final summary = await queries.stockSummary(firm.firmId);
    expect(summary.lowCount, 0);
  });

  test('a fractional quantity is valued exactly', () async {
    // 3.5 kg at Rs 150/kg is Rs 525.00 — the reference line this whole money
    // stack was built around.
    final kg =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'kg'")
                .getSingle())
            .read<String>('id');
    await catalogue.addItem(
      actor,
      ItemDraft(
        name: 'Mutton',
        baseUnitId: kg,
        saleRate: Rate.rupees(1800),
        openingStock: const Qty.parts(3, 500),
        openingRate: Rate.rupees(150),
      ),
    );

    final summary = await queries.stockSummary(firm.firmId);
    expect(summary.stockValue, Money.rupees(525));
  });

  test('two thousand items are valued to the paisa', () async {
    // The arithmetic claim in the query's own comment: scaling per row rather
    // than after the SUM keeps the running total well below the int64 ceiling,
    // and rounding once in Dart keeps the total exact rather than losing up to
    // a paisa per item.
    for (var i = 0; i < 2000; i++) {
      await stock(name: 'Item $i', units: 7, costRupees: 137);
    }

    final summary = await queries.stockSummary(firm.firmId);
    expect(summary.trackedItems, 2000);
    // 7 x 137 x 2000 = 1,918,000 rupees, exactly.
    expect(
      summary.stockValue,
      Money.rupees(1918000),
      reason:
          'the valuation drifted, which means it is truncating per item '
          'rather than rounding once',
    );
  });

  test('a very large shop does not overflow', () async {
    // A wholesaler: ten thousand units of something worth Rs 50,000 each.
    // Multiplying thousandths by milli-paisa without scaling down first
    // reaches 1e18 here, which is close enough to the int64 ceiling to be a
    // real risk rather than a theoretical one.
    for (var i = 0; i < 50; i++) {
      await stock(name: 'Bulk $i', units: 10000, costRupees: 50000);
    }

    final summary = await queries.stockSummary(firm.firmId);
    expect(summary.stockValue, Money.rupees(50 * 10000 * 50000));
    expect(summary.stockValue.inPaisa, greaterThan(0));
  });

  test('another firm is not counted', () async {
    await stock(name: 'Cooking Oil 5L', units: 20, costRupees: 300);
    final summary = await queries.stockSummary('SOME-OTHER-FIRM');
    expect(summary.isEmpty, isTrue);
  });
}
