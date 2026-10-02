import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/large_catalogue.dart';
import 'support/test_db.dart';

/// The counter, against a catalogue the size of a real wholesaler's.
///
/// This is the gate the plan puts in M1 and makes everything after it depend
/// on, and it exists because of a specific, documented failure: the largest
/// cluster of crash reports against the competitor this product is measured
/// against is people with big catalogues, and the reports describe an app
/// that loads the whole list into memory. Finding that at month eleven is the
/// risk. Finding it here is the point.
///
/// The budgets below are host-machine budgets, and a development machine is
/// several times faster than a Rs 34,000 Infinix. They are set where a
/// regression shows up as a failure rather than where the hardware gives up —
/// a query that takes 200ms here has no chance at the counter. The real
/// number needs a physical handset, which is a separate, still-open item.
///
/// What the first run of this measured, which is worth writing down because
/// it changed a plan: at twenty thousand SKUs the counter's search costs
/// 2-4ms when the term matches, and 13ms in the genuine worst case — a term
/// that matches nothing and therefore cannot stop early at `LIMIT 40`, so it
/// walks all twenty thousand rows. A barcode lookup is 1ms and page twelve of
/// a browse is no slower than page one.
///
/// So FTS5 is NOT being built. The plan assumed the `LIKE '%term%'` scan
/// would have to be replaced by a full-text index at this size, and the
/// measurement says otherwise: SQLite walks twenty thousand short rows faster
/// than the 250ms the search box is debounced by, with an order of magnitude
/// of headroom for a slower phone. Adding an FTS5 table and the triggers to
/// keep it in step would be real complexity — a second copy of every item
/// name, kept correct on every insert, update and delete — bought with
/// nothing. It goes back on the shelf until a measurement asks for it, and
/// this test is what will ask.
///
/// M56 changed the shape of the question. The search now forgives spelling
/// and ranks what it finds — what the cashier typed before what only sounds
/// like it — and a ranked search cannot stop at the fortieth match the way
/// an unranked one could: every search now reads the whole catalogue, so
/// the matching terms cost what the worst case used to. Measured on the
/// development machine with nothing else running: 20-45ms for every term
/// below, matching or not, against 2-4ms (matching) and 13ms (not) before.
/// Still under the budgets, still well under the 250ms the search box waits
/// for the cashier to stop typing, and still no case for FTS5 — whose
/// tokens could not hold a spelling key anyway without a tokenizer of our
/// own. The timings below are each the best of three, because the suite
/// runs its files side by side and a single timing measured the neighbours
/// as much as the query.
void main() {
  late AppDatabase db;
  late DriftAppQueries queries;
  late FirstRunResult firm;

  setUpAll(() async {
    db = await openTestDatabase();
    final clock = FixedClock(DateTime.utc(2026, 8, 23, 9, 15));
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Wholesale',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    queries = DriftAppQueries(db);

    final unit = await db
        .customSelect("SELECT id FROM units WHERE code = 'pcs'")
        .getSingle();

    await seedLargeCatalogue(
      db,
      firmId: firm.firmId,
      userId: firm.ownerUserId,
      deviceId: firm.deviceId,
      baseUnitId: unit.read<String>('id'),
    );
  });

  tearDownAll(() async => db.close());

  test('the fixture really is twenty thousand SKUs', () async {
    final count = await db
        .customSelect('SELECT COUNT(*) c FROM items')
        .getSingle();
    expect(count.read<int>('c'), 20000);

    final ledger = await db
        .customSelect('SELECT COUNT(*) c FROM stock_ledger')
        .getSingle();
    expect(
      ledger.read<int>('c'),
      greaterThan(17000),
      reason: 'the stock subquery needs something real to sum',
    );
  });

  test('searching the counter stays inside its budget', () async {
    // The measured path: a cashier types three or four letters and expects
    // the list under their thumb before they have finished the word.
    final warm = await millisFor(
      () => queries.searchItems(firm.firmId, query: 'dalda'),
    );

    var worst = 0;
    for (final term in const ['dal', 'oil', 'cooking', 'sufi', 'chawal']) {
      final ms = await bestOfThree(
        () => queries.searchItems(firm.firmId, query: term),
      );
      worst = ms > worst ? ms : worst;
      // Printed, not only asserted. A budget that passes says nothing about
      // how much room is left, and the number is what shows a regression
      // coming before it crosses the line.
      // ignore: avoid_print
      print('search "$term": ${ms}ms');
    }
    // ignore: avoid_print
    print('search warm-up: ${warm}ms, worst: ${worst}ms');

    expect(
      worst,
      lessThan(150),
      reason:
          'a search that takes ${worst}ms on a development machine has no '
          'chance on the handset this ships to',
    );
  });

  test(
    'a search that matches nothing is the worst case, and is measured',
    () async {
      // The terms above all match early, and `LIMIT 40` stops the scan as soon
      // as forty rows are found — so they measure the best case and flatter the
      // query. A term that matches NOTHING cannot stop early: it walks all
      // twenty thousand rows before it can say so.
      //
      // This is not a hypothetical either. It is what a cashier's fourth
      // keystroke does on the way to a word that is in the catalogue, and what
      // every mistyped search does.
      var worst = 0;
      for (final term in const [
        'zzzznothing',
        'qqqq',
        'xylophone',
        'dalda cooking oil that does not exist',
      ]) {
        final ms = await bestOfThree(
          () => queries.searchItems(firm.firmId, query: term),
        );
        worst = ms > worst ? ms : worst;
        // ignore: avoid_print
        print('search "$term" (no match): ${ms}ms');
      }

      expect(
        worst,
        lessThan(250),
        reason:
            'a search that finds nothing walks the whole catalogue and took '
            '${worst}ms; that is the keystroke before every successful search',
      );
    },
  );

  test('a term that only matches the far end of the catalogue', () async {
    // Ordered by id, so a term whose matches are all at the end has to walk
    // past everything else to reach them. Between "matches nothing" and
    // "matches immediately", this is the shape a real search takes.
    final ms = await bestOfThree(
      () => queries.searchItems(firm.firmId, query: '#1999'),
    );
    // ignore: avoid_print
    print('search matching only the tail: ${ms}ms');
    expect(ms, lessThan(250));
  });

  test('the first page of a browse stays inside its budget', () async {
    final ms = await millisFor(() => queries.searchItems(firm.firmId));
    // ignore: avoid_print
    print('browse first page: ${ms}ms');
    expect(ms, lessThan(100));
  });

  test('paging does not get slower the deeper it goes', () async {
    // Keyset pagination, not OFFSET. An OFFSET of 19,960 makes SQLite walk
    // and discard nineteen thousand rows to hand back forty, so the last page
    // of a big catalogue costs five hundred times the first — which is
    // exactly where a shopkeeper scrolling their stock list gives up.
    var afterId = '';
    var firstPage = 0;
    var lastPage = 0;

    for (var page = 0; page < 12; page++) {
      final ms = await millisFor(() async {
        final rows = await queries.searchItems(
          firm.firmId,
          afterId: afterId.isEmpty ? null : afterId,
        );
        if (rows.isNotEmpty) afterId = rows.last.id;
      });
      if (page == 0) firstPage = ms;
      lastPage = ms;
    }
    // ignore: avoid_print
    print('page 1: ${firstPage}ms, page 12: ${lastPage}ms');

    expect(
      lastPage,
      lessThan(100),
      reason:
          'page twelve took ${lastPage}ms against page one at '
          '${firstPage}ms; the cursor is not doing its job',
    );
  });

  test('a barcode scan is effectively instant', () async {
    // The scanner path. A cashier scans and the line appears; anything a
    // person can perceive here is felt on every single item of every bill.
    final ms = await millisFor(
      () => queries.itemByBarcode(firm.firmId, '890000012345'),
    );
    // ignore: avoid_print
    print('barcode lookup: ${ms}ms');
    expect(ms, lessThan(50));
  });

  test('the low-stock list stays inside its budget', () async {
    final ms = await millisFor(() => queries.lowStockItems(firm.firmId));
    // ignore: avoid_print
    print('low stock: ${ms}ms');
    expect(ms, lessThan(200));
  });

  test('nothing loads the whole catalogue to answer a question', () async {
    // The property behind every budget above, stated directly. A page is
    // forty rows whatever the catalogue holds — the competitor's crash
    // cluster is an app that answered this question with all of them.
    final page = await queries.searchItems(firm.firmId);
    expect(page, hasLength(40));

    final filtered = await queries.searchItems(firm.firmId, query: 'dal');
    expect(filtered.length, lessThanOrEqualTo(40));
  });
}

/// The fastest of three runs of [work], in milliseconds.
///
/// Not the slowest: what is being measured is the query, and the slower
/// runs are the other test files sharing the machine. A query that really
/// regressed is slow all three times.
Future<int> bestOfThree(Future<void> Function() work) async {
  var best = await millisFor(work);
  for (var i = 0; i < 2; i++) {
    final ms = await millisFor(work);
    if (ms < best) best = ms;
  }
  return best;
}
