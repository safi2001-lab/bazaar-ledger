import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

import 'support/large_catalogue.dart' show millisFor;
import 'support/test_db.dart';

/// The reports hub (M33) against a year of a busy wholesaler: twenty
/// thousand bills to two hundred customers, half paid at the counter, each
/// with its line and its journal entry.
///
/// The same bar `catalogue_performance_test` sets for the counter, for the
/// same reason: a report that takes seconds here takes a minute on the
/// handset this ships to, and the shop owner closes the app before it
/// answers. The budgets are host budgets, set where a regression shows, and
/// the numbers are printed so the room left can be seen.
///
/// Seeded the fast way, one `INSERT ... SELECT` over a counter per table,
/// because what is measured is the read; every other suite goes through the
/// write path.
const _bills = 20000;

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
    final clock = FixedClock(DateTime.utc(2026, 6, 30, 9));
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Wholesale',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    reports = ReportEngine(DriftReportSource(db));
    await _seedAYear(db, firm);
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
        today: year.to,
        filters: filters,
      );
    });
    // ignore: avoid_print
    print('$label: ${ms}ms, ${table.rows.length} rows');
    return ms;
  }

  test('the fixture really is a year of twenty thousand bills', () async {
    final row = await db
        .customSelect(
          "SELECT COUNT(*) c FROM documents WHERE doc_type = 'sale_invoice'",
        )
        .getSingle();
    expect(row.read<int>('c'), _bills);
  });

  test('a year of every bill reads inside its budget', () async {
    final sale = await time('sale report, a year', ReportKind.saleReport);
    final profit = await time(
      'bill-wise profit, a year',
      ReportKind.billWiseProfit,
    );
    final all = await time(
      'all transactions, a year',
      ReportKind.allTransactions,
    );
    expect(sale, lessThan(2500));
    expect(profit, lessThan(2500));
    expect(all, lessThan(2500));
  });

  test('one customer\'s year is an index away, not a scan', () async {
    final party =
        (await db
                .customSelect(
                  "SELECT id FROM parties WHERE name = 'Customer 7'",
                )
                .getSingle())
            .read<String>('id');
    final filters = ReportFilters(partyId: party);
    final sale = await time(
      'sale report, one customer',
      ReportKind.saleReport,
      filters: filters,
    );
    final items = await time(
      'party items, one customer',
      ReportKind.partyItems,
      filters: filters,
    );
    final statement = await time(
      'party statement, one customer',
      ReportKind.partyStatement,
      filters: filters,
    );
    expect(sale, lessThan(200));
    expect(items, lessThan(200));
    expect(statement, lessThan(200));
  });

  test('summaries over a year stay inside their budget', () async {
    final byParty = await time(
      'party-wise P&L, a year',
      ReportKind.partyProfitAndLoss,
    );
    final groups = await time(
      'sale and purchase by group, a year',
      ReportKind.salePurchaseByPartyGroup,
    );
    final flow = await time('cash flow, a year', ReportKind.cashflow);
    final pl = await time('profit and loss, a year', ReportKind.profitAndLoss);
    final parties = await time('all parties', ReportKind.allParties);
    final day = await time(
      'day book, one day',
      ReportKind.dayBook,
      period: ReportPeriod.day(const BusinessDate('2026-03-15')),
    );
    for (final ms in [byParty, groups, flow, pl, parties]) {
      expect(ms, lessThan(1000));
    }
    expect(day, lessThan(150));
  });
}

/// Two hundred customers and [_bills] sale bills spread over the fiscal year
/// 2025-26, each with a line, a journal entry of two lines, and for every
/// other bill a cash tender allocated to it at the counter.
Future<void> _seedAYear(AppDatabase db, FirstRunResult firm) async {
  Future<String> idOf(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<String>('id');
  final pcs = await idOf("SELECT id FROM units WHERE code = 'pcs'");
  final cash = await idOf(
    "SELECT id FROM accounts WHERE system_key = 'cash_in_hand'",
  );
  final receivable = await idOf(
    "SELECT id FROM accounts WHERE system_key = 'accounts_receivable'",
  );
  final sales = await idOf(
    "SELECT id FROM accounts WHERE system_key = 'sales'",
  );
  final drawer = await idOf(
    "SELECT id FROM payment_accounts WHERE mode_label = 'cash'",
  );
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
    await db.customStatement(
      '''
      INSERT INTO items ($columns, name, name_search, base_unit_id, category,
                         sale_rate_milli_paisa, avg_cost_milli_paisa)
      VALUES ('perf-item', ?, 0, 0, ?, ?, ?, 'h', 'Atta 10kg', 'atta 10kg',
              ?, 'Atta', 1000000, 800000)
      ''',
      [...audit, pcs],
    );
    await db.customStatement('''
      WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n
                              WHERE i < 199)
      INSERT INTO parties ($columns, name, name_search, party_type,
                           party_group)
      SELECT printf('perf-party-%03d', i), ?, 0, 0, ?, ?, ?, 'h',
             'Customer ' || i, 'customer ' || i, 'customer',
             CASE WHEN i % 4 = 0 THEN NULL ELSE 'Route ' || (i % 4) END
      FROM n
      ''', audit);
    // A bill a day's worth of minutes apart, Rs 1,000 to Rs 5,990 each.
    const bill =
        '''
      WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i + 1 FROM n
                              WHERE i < $_bills - 1)
    ''';
    await db.customStatement('''
      $bill
      INSERT INTO documents ($columns, doc_type, doc_no, doc_series, doc_seq,
                             fiscal_year, doc_date_utc, doc_date_local,
                             party_id, status, posted_at_utc, subtotal_paisa,
                             taxable_paisa, total_paisa, paid_paisa,
                             balance_paisa, cost_paisa)
      SELECT printf('perf-doc-%06d', i), ?, i, i, ?, ?, ?, 'h',
             'sale_invoice', printf('PERF-%06d', i), 'PERF', i + 1, 2526, i,
             date('2025-07-01', '+' || (i * 365 / $_bills) || ' days'),
             printf('perf-party-%03d', i % 200), 'posted', i,
             (100000 + (i % 500) * 1000), (100000 + (i % 500) * 1000),
             (100000 + (i % 500) * 1000),
             CASE WHEN i % 2 = 0 THEN 100000 + (i % 500) * 1000 ELSE 0 END,
             CASE WHEN i % 2 = 0 THEN 0 ELSE 100000 + (i % 500) * 1000 END,
             (80000 + (i % 500) * 800)
      FROM n
      ''', audit);
    await db.customStatement('''
      $bill
      INSERT INTO document_lines ($columns, document_id, line_no, item_id,
                                  item_name_snapshot, qty_thousandths,
                                  unit_code_snapshot, base_qty_thousandths,
                                  rate_milli_paisa, gross_paisa, taxable_paisa,
                                  line_total_paisa, cost_paisa)
      SELECT printf('perf-line-%06d', i), ?, i, i, ?, ?, ?, 'h',
             printf('perf-doc-%06d', i), 1, 'perf-item', 'Atta 10kg', 1000,
             'pcs', 1000, (100000 + (i % 500) * 1000) * 1000,
             (100000 + (i % 500) * 1000), (100000 + (i % 500) * 1000),
             (100000 + (i % 500) * 1000), (80000 + (i % 500) * 800)
      FROM n
      ''', audit);
    await db.customStatement(
      '''
      $bill
      INSERT INTO payments ($columns, payment_no, direction, party_id,
                            payment_account_id, mode, amount_paisa,
                            payment_date_utc, payment_date_local, status)
      SELECT printf('perf-pay-%06d', i), ?, i, i, ?, ?, ?, 'h',
             printf('PAY-%06d', i), 'in', printf('perf-party-%03d', i % 200),
             ?, 'cash', (100000 + (i % 500) * 1000), i,
             date('2025-07-01', '+' || (i * 365 / $_bills) || ' days'),
             'cleared'
      FROM n WHERE i % 2 = 0
      ''',
      [...audit, drawer],
    );
    await db.customStatement('''
      $bill
      INSERT INTO payment_allocations ($columns, payment_id, document_id,
                                       amount_paisa, allocation_mode,
                                       allocated_at_utc)
      SELECT printf('perf-alloc-%06d', i), ?, i, i, ?, ?, ?, 'h',
             printf('perf-pay-%06d', i), printf('perf-doc-%06d', i),
             (100000 + (i % 500) * 1000), 'exact', i
      FROM n WHERE i % 2 = 0
      ''', audit);
    await db.customStatement('''
      $bill
      INSERT INTO journal_entries ($columns, entry_no, entry_date_utc,
                                   entry_date_local, fiscal_year, source_type,
                                   document_id, narration, total_debit_paisa,
                                   total_credit_paisa)
      SELECT printf('perf-je-%06d', i), ?, i, i, ?, ?, ?, 'h',
             printf('JV-PERF-%06d', i), i,
             date('2025-07-01', '+' || (i * 365 / $_bills) || ' days'), 2526,
             'sale', printf('perf-doc-%06d', i), 'Sale',
             (100000 + (i % 500) * 1000), (100000 + (i % 500) * 1000)
      FROM n
      ''', audit);
    await db.customStatement(
      '''
      $bill
      INSERT INTO journal_lines ($columns, journal_entry_id, line_no,
                                 account_id, debit_paisa, party_id)
      SELECT printf('perf-jld-%06d', i), ?, i, i, ?, ?, ?, 'h',
             printf('perf-je-%06d', i), 1,
             CASE WHEN i % 2 = 0 THEN ? ELSE ? END,
             (100000 + (i % 500) * 1000),
             CASE WHEN i % 2 = 0 THEN NULL
                  ELSE printf('perf-party-%03d', i % 200) END
      FROM n
      ''',
      [...audit, cash, receivable],
    );
    await db.customStatement(
      '''
      $bill
      INSERT INTO journal_lines ($columns, journal_entry_id, line_no,
                                 account_id, credit_paisa)
      SELECT printf('perf-jlc-%06d', i), ?, i, i, ?, ?, ?, 'h',
             printf('perf-je-%06d', i), 2, ?, (100000 + (i % 500) * 1000)
      FROM n
      ''',
      [...audit, sales],
    );
  });
  await db.customStatement('ANALYZE');
}
