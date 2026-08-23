import 'package:pk_data/pk_data.dart';

/// Twenty thousand SKUs, seeded the fast way.
///
/// Deliberately NOT through `TxRunner`. Every write through the real path
/// opens a transaction and writes an audit row and an outbox row, which is
/// exactly right for a shop and hopeless for a fixture: twenty thousand of
/// them takes minutes, and a perf test nobody runs because it is slow is a
/// perf test that does not exist.
///
/// What this is measuring is the READ side — the counter's search against a
/// large catalogue — so the rows only have to be shaped correctly, not
/// created the way the app creates them. Everything else in the suite goes
/// through the write path.
///
/// Twenty thousand is not an arbitrary round number. It is the size the plan
/// names, and it comes from the failure it is defending against: the largest
/// cluster of crash reports against the competitor this product is measured
/// on is people with big catalogues, and the reports say the app loads the
/// whole list into memory. Finding that at month eleven is the risk; finding
/// it here is the point.
Future<void> seedLargeCatalogue(
  AppDatabase db, {
  required String firmId,
  required String userId,
  required String deviceId,
  required String baseUnitId,
  int items = 20000,
}) async {
  // Realistic enough to be searched like a real catalogue: shared prefixes,
  // repeated words, and a long tail. A fixture of "item 1..20000" would make
  // every LIKE match either everything or nothing.
  const brands = [
    'Dalda',
    'Sufi',
    'Kausar',
    'Habib',
    'Meezan',
    'Tullo',
    'Eva',
    'Seasons',
    'Shan',
    'National',
    'Mehran',
    'Ahmed',
    'Rafhan',
    'Olpers',
    'Nurpur',
    'Adam',
    'Nestle',
    'Tapal',
    'Lipton',
    'Supreme',
  ];
  const goods = [
    'Cooking Oil',
    'Banaspati',
    'Chawal Basmati',
    'Atta Chakki',
    'Cheeni',
    'Chai Patti',
    'Doodh',
    'Dahi',
    'Namak',
    'Lal Mirch',
    'Haldi',
    'Dhania',
    'Zeera',
    'Elaichi',
    'Besan',
    'Maida',
    'Suji',
    'Dal Chana',
    'Dal Masoor',
    'Dal Moong',
    'Sabun',
    'Surf',
    'Shampoo',
    'Toothpaste',
    'Biscuit',
  ];
  const sizes = ['250g', '500g', '1kg', '2.5kg', '5kg', '5L', '1L', '200ml'];

  await db.transaction(() async {
    // One statement per row is still twenty thousand statements, but inside a
    // single transaction that is one fsync rather than twenty thousand.
    for (var i = 0; i < items; i++) {
      final brand = brands[i % brands.length];
      final good = goods[(i ~/ brands.length) % goods.length];
      final size = sizes[(i ~/ 7) % sizes.length];
      final name = '$brand $good $size #$i';
      final id = 'itm${i.toString().padLeft(8, '0')}';

      await db.customStatement(
        '''
        INSERT INTO items (
          id, firm_id, created_at_utc, updated_at_utc, created_by, updated_by,
          origin_device_id, hlc, rev,
          name, name_search, code, barcode, base_unit_id,
          sale_rate_milli_paisa, avg_cost_milli_paisa,
          min_stock_thousandths, track_stock, is_active
        ) VALUES (?, ?, 0, 0, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1)
        ''',
        [
          id,
          firmId,
          userId,
          userId,
          deviceId,
          'FIX-${i.toString().padLeft(8, '0')}',
          name,
          name.toLowerCase(),
          'SKU$i',
          '890${i.toString().padLeft(9, '0')}',
          baseUnitId,
          (50 + i % 5000) * 100 * 1000,
          (30 + i % 3000) * 100 * 1000,
          // A tenth of the catalogue has a floor set, which is about what a
          // real shop bothers to do.
          i % 10 == 0 ? 5000 : 0,
        ],
      );

      // Opening stock for most of them, so the counter's stock subquery has
      // something real to sum. Every tenth item is out of stock, which is
      // also what a real shelf looks like.
      if (i % 10 != 3) {
        await db.customStatement(
          '''
          INSERT INTO stock_ledger (
            id, firm_id, created_at_utc, updated_at_utc, created_by,
            updated_by, origin_device_id, hlc, rev,
            item_id, location_code, txn_type, qty_delta_thousandths,
            rate_milli_paisa, value_delta_paisa, balance_after_thousandths,
            occurred_at_utc, occurred_on_local
          ) VALUES (?, ?, 0, 0, ?, ?, ?, ?, 1, ?, 'MAIN', 'opening', ?,
                    0, 0, ?, 0, '2026-08-23')
          ''',
          [
            'stk${i.toString().padLeft(8, '0')}',
            firmId,
            userId,
            userId,
            deviceId,
            'FIXS-${i.toString().padLeft(8, '0')}',
            id,
            (1 + i % 40) * 1000,
            (1 + i % 40) * 1000,
          ],
        );
      }
    }
  });

  // The optimiser needs to know how big the tables are. Without this SQLite
  // plans against guesses, and a plan chosen from guesses is not the plan
  // that will run on a shopkeeper's phone.
  await db.customStatement('ANALYZE');
}

/// How long [work] takes, as milliseconds.
///
/// Reported rather than only asserted: a budget that passes tells you nothing
/// about how much room is left, and the number is what shows a regression
/// coming before it crosses the line.
Future<int> millisFor(Future<void> Function() work) async {
  final started = DateTime.now();
  await work();
  return DateTime.now().difference(started).inMilliseconds;
}
