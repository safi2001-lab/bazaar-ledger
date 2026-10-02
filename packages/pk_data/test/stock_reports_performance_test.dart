import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

import 'support/large_catalogue.dart';
import 'support/test_db.dart';

/// The stock reports (M34) against the catalogue the counter is measured
/// on: twenty thousand items, and a year of a busy shop's stock ledger,
/// a hundred and twenty thousand movements, deliveries and sales.
///
/// The stock detail reads every row of the ledger up to the end of its
/// period and sums it by item; the rest read the same rows another way.
/// The bar is the one the reports hub set (M33): a host budget where a
/// regression shows, and the numbers printed so the room left can be seen.
const _movements = 120000;

void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late ReportEngine reports;
  final year = ReportPeriod(
    const BusinessDate('2025-07-01'),
    const BusinessDate('2026-06-30'),
  );

  setUpAll(() async {
    db = await openTestDatabase();
    final clock = FixedClock(DateTime.utc(2026, 9, 30, 9));
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Wholesale',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    final pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');
    await seedLargeCatalogue(
      db,
      firmId: firm.firmId,
      userId: firm.ownerUserId,
      deviceId: firm.deviceId,
      baseUnitId: pcs,
    );
    await _seedAYearOfStock(db, firm);
    reports = ReportEngine(DriftReportSource(db));
  });

  tearDownAll(() async => db.close());

  Future<int> time(
    String label,
    ReportKind kind, {
    ReportPeriod? period,
    ReportFilters filters = ReportFilters.none,
  }) async {
    late ReportTable table;
    final ms = await millisFor(() async {
      table = await reports.run(
        kind,
        firmId: firm.firmId,
        period: period ?? year,
        today: const BusinessDate('2026-09-30'),
        filters: filters,
      );
    });
    // ignore: avoid_print
    print('$label: ${ms}ms, ${table.rows.length} rows');
    return ms;
  }

  test('the fixture really is twenty thousand items and a year of '
      'movements', () async {
    final row = await db
        .customSelect(
          'SELECT (SELECT COUNT(*) FROM items) AS items, '
          '(SELECT COUNT(*) FROM stock_ledger) AS moves',
        )
        .getSingle();
    expect(row.read<int>('items'), 20000);
    expect(row.read<int>('moves'), greaterThan(_movements));
  });

  test(
    'the stock detail of a large catalogue reads inside its budget',
    () async {
      final yearMs = await time('stock detail, a year', ReportKind.stockDetail);
      final monthMs = await time(
        'stock detail, a month',
        ReportKind.stockDetail,
        period: ReportPeriod.monthOf(const BusinessDate('2026-03-15')),
      );
      final oneItem = await time(
        'item detail, one item a year',
        ReportKind.itemDetail,
        filters: const ReportFilters(itemId: 'itm00000007', itemName: 'Item 7'),
      );
      expect(yearMs, lessThan(4000));
      expect(monthMs, lessThan(4000));
      expect(oneItem, lessThan(200));
    },
  );

  test(
    'the shelf, its age and how it sells stay inside their budget',
    () async {
      final summary = await time(
        'stock summary, today',
        ReportKind.stockSummary,
      );
      final past = await time(
        'stock summary, a day gone by',
        ReportKind.stockSummary,
        filters: const ReportFilters(asOf: BusinessDate('2026-01-31')),
      );
      final ageing = await time('stock ageing', ReportKind.stockAgeing);
      final moving = await time(
        'fast and slow stock',
        ReportKind.fastSlowStock,
      );
      final low = await time('low stock', ReportKind.lowStock);
      for (final ms in [summary, past, ageing, moving, low]) {
        expect(ms, lessThan(4000));
      }
    },
  );
}

/// A year of deliveries and sales over the catalogue: every item's
/// deliveries spread through the year at cost, and its sales taking stock
/// out at cost, so the ledger has the size and the shape of a busy shop's.
Future<void> _seedAYearOfStock(AppDatabase db, FirstRunResult firm) async {
  final audit = [
    firm.firmId,
    firm.ownerUserId,
    firm.ownerUserId,
    firm.deviceId,
  ];
  const columns =
      'id, firm_id, created_at_utc, updated_at_utc, created_by, updated_by, '
      'origin_device_id, hlc';
  await db.transaction(() async {
    await db.customStatement('''
      WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n
                              WHERE i < $_movements - 1)
      INSERT INTO stock_ledger ($columns, item_id, location_code, txn_type,
                                qty_delta_thousandths, rate_milli_paisa,
                                value_delta_paisa, occurred_at_utc,
                                occurred_on_local)
      SELECT printf('perf-stk-%07d', i), ?, i, i, ?, ?, ?, 'h',
             printf('itm%08d', i % 20000), 'MAIN',
             CASE WHEN i % 6 = 0 THEN 'purchase' ELSE 'sale' END,
             CASE WHEN i % 6 = 0 THEN 12000 ELSE -1000 END,
             500000,
             CASE WHEN i % 6 = 0 THEN 60000 ELSE -5000 END,
             i,
             date('2025-07-01', '+' || (i * 365 / $_movements) || ' days')
      FROM n
      ''', audit);
  });
  await db.customStatement('ANALYZE');
}
