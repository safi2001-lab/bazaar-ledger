import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Where one item's stock went.
///
/// The question a shopkeeper actually asks is never "what is the balance" —
/// they can see the shelf. It is "there should be forty and there are
/// thirty-one, where did nine go", and the only honest answer is the list of
/// movements with the bill or the reason beside each one.
///
/// `stock_ledger` is append-only and `TxRunner` refuses to rewrite or tombstone
/// a row in it, so this is a read of history rather than a reconstruction of
/// one. That is the whole reason the answer can be trusted.
void main() {
  late AppDatabase db;
  late FixedClock clock;
  late UlidGenerator ids;
  late TxRunner runner;
  late FirstRunResult firm;
  late ActorContext actor;
  late DriftCatalogueWriter catalogue;
  late DriftAppQueries queries;
  late String itemId;

  setUp(() async {
    db = await openTestDatabase();
    clock = FixedClock(DateTime.utc(2026, 8, 20, 9));
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

    final pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');

    // Forty tins on the shelf to begin with.
    itemId = await catalogue.addItem(
      actor,
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: pcs,
        saleRate: Rate.rupees(1450),
        openingStock: Qty.units(40),
        openingRate: Rate.rupees(1200),
      ),
    );
  });

  tearDown(() async => db.close());

  /// A correction, a day later each time so the ordering has something to sort.
  Future<void> adjust(int day, Qty counted, String reason) async {
    clock.set(DateTime.utc(2026, 8, day, 11));
    await catalogue.adjustStock(
      firm.actorAt(clock.nowUtc()),
      StockAdjustmentDraft.counted(
        itemId: itemId,
        counted: counted,
        reason: reason,
      ),
    );
  }

  test('an opening balance is the first thing the history shows', () async {
    final movements = await queries.stockMovements(firm.firmId, itemId);

    expect(movements, hasLength(1));
    expect(movements.single.txnType, 'opening');
    expect(movements.single.qtyDelta, Qty.units(40));
    expect(movements.single.isOut, isFalse);
  });

  test('a correction names the reason, because no bill explains it', () async {
    // The difference that matters between a sale and a correction: a sale has
    // a document number a shopkeeper can look up, and a correction has only
    // whatever the person typed. A history that showed neither would be a list
    // of numbers.
    await adjust(21, Qty.units(31), 'Nau tin toot gaye');

    final movements = await queries.stockMovements(firm.firmId, itemId);
    expect(movements.first.txnType, 'adjustment');
    expect(movements.first.reason, 'Nau tin toot gaye');
    expect(movements.first.qtyDelta, const Qty.units(-9));
    expect(movements.first.isOut, isTrue);
  });

  test(
    'newest first, because that is the end a shopkeeper starts from',
    () async {
      await adjust(21, Qty.units(38), 'Do gum');
      await adjust(22, Qty.units(35), 'Teen toot gaye');

      final movements = await queries.stockMovements(firm.firmId, itemId);
      expect(movements.map((m) => m.occurredOnLocal), [
        '2026-08-22',
        '2026-08-21',
        '2026-08-20',
      ]);
    },
  );

  test('the running balance is carried on each row', () async {
    await adjust(21, Qty.units(38), 'Do gum');

    final movements = await queries.stockMovements(firm.firmId, itemId);
    expect(movements.first.balanceAfter, Qty.units(38));
    expect(movements.last.balanceAfter, Qty.units(40));
  });

  test('another item history is not mixed in', () async {
    final pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');
    await catalogue.addItem(
      actor,
      ItemDraft(
        name: 'Chawal 5kg',
        baseUnitId: pcs,
        saleRate: Rate.rupees(2450),
        openingStock: Qty.units(12),
      ),
    );

    final movements = await queries.stockMovements(firm.firmId, itemId);
    expect(movements, hasLength(1));
    expect(movements.single.qtyDelta, Qty.units(40));
  });

  group('paging', () {
    setUp(() async {
      // Twenty-five corrections, one a day.
      var onHand = 40;
      for (var day = 1; day <= 25; day++) {
        onHand -= 1;
        clock.set(DateTime.utc(2026, 9, day, 11));
        await catalogue.adjustStock(
          firm.actorAt(clock.nowUtc()),
          StockAdjustmentDraft.counted(
            itemId: itemId,
            counted: Qty.units(onHand),
            reason: 'Din $day',
          ),
        );
      }
    });

    test('every movement appears exactly once across pages', () async {
      // The failure this guards is specific and nasty: if the ORDER BY and the
      // cursor predicate disagree, a page boundary drops or repeats rows. The
      // evidence a shopkeeper sees is one movement that vanished, which reads
      // as data loss rather than as a paging bug.
      final seen = <String>[];
      String? cursor;

      while (true) {
        final page = await queries.stockMovements(
          firm.firmId,
          itemId,
          afterId: cursor,
          limit: 7,
        );
        if (page.isEmpty) break;
        seen.addAll(page.map((m) => m.id));
        cursor = page.last.id;
      }

      // 25 corrections plus the opening balance.
      expect(seen, hasLength(26));
      expect(
        seen.toSet(),
        hasLength(26),
        reason:
            'a movement was shown on two pages, so the shopkeeper is '
            'looking at a history that does not add up',
      );
    });

    test('paged order matches unpaged order exactly', () async {
      final whole = await queries.stockMovements(
        firm.firmId,
        itemId,
        limit: 100,
      );

      final paged = <String>[];
      String? cursor;
      while (true) {
        final page = await queries.stockMovements(
          firm.firmId,
          itemId,
          afterId: cursor,
          limit: 4,
        );
        if (page.isEmpty) break;
        paged.addAll(page.map((m) => m.id));
        cursor = page.last.id;
      }

      expect(paged, whole.map((m) => m.id).toList());
    });

    test('the last page ends, rather than repeating forever', () async {
      final all = await queries.stockMovements(firm.firmId, itemId, limit: 100);
      final past = await queries.stockMovements(
        firm.firmId,
        itemId,
        afterId: all.last.id,
      );
      expect(past, isEmpty);
    });
  });
}
