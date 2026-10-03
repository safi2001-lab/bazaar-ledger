@Timeout(Duration(minutes: 15))
library;

import 'package:drift/native.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

import 'support/big_shop.dart';

/// M67's reports on the wholesaler with three years in the book (M62's
/// fixture: fifty thousand bills, a quarter of a million lines, two
/// thousand parties, five thousand items).
///
/// The budgets are M62's host budgets, each the phone's divided by five,
/// in M62's classes. ABC over a year reads what a year of Item-wise profit
/// reads: M33's 2.5 seconds for a year of every bill. The ratio analysis
/// reads two years of every account and two balance sheets of the whole
/// book (this year's and last year's, for "vs the period before"), and the
/// attention list and the shelf valued at its price read the whole stock
/// ledger to the day, as M34's stock detail does: theirs is M34's class, 4
/// and 2 seconds here (20 and 10 on the phone, behind a spinner). The
/// ageing reports in the shop's own buckets are held to half a second, the
/// chase list's class. Each figure is the best of three, printed beside its
/// budget; one that fails under a loaded machine is run again alone before
/// anything is concluded from it, as M62 runs its own.
void main() {
  late AppDatabase db;
  late BigShop shop;
  late ReportEngine reports;
  const today = BigShop.today;
  final year = ReportPeriod(
    const BusinessDate('2025-07-01'),
    const BusinessDate('2026-06-30'),
  );

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    shop = await seedBigShop(db);
    reports = ReportEngine(DriftReportSource(db));
  });

  tearDownAll(() async => db.close());

  Future<void> timed(
    String label,
    ReportKind kind, {
    required int hostBudgetMs,
    ReportPeriod? period,
    ReportFilters filters = ReportFilters.none,
    ReportOptions options = ReportOptions.standard,
  }) async {
    Future<ReportTable> run() => reports.run(
      kind,
      firmId: shop.firm.firmId,
      period: period ?? year,
      today: today,
      filters: filters,
      options: options,
    );
    final rows = (await run()).rows.length;
    expect(rows, greaterThan(1), reason: '$label is empty');
    final ms = await bestOfThreeMillis(run);
    // ignore: avoid_print
    print(
      '$label ($rows rows): ${ms}ms (host budget ${hostBudgetMs}ms, about '
      '${hostBudgetMs * 5}ms on the phone)',
    );
    expect(
      ms,
      lessThan(hostBudgetMs),
      reason: '$label took ${ms}ms here, about ${ms * 5}ms on a phone',
    );
  }

  test('ratio analysis and ABC classes over a year of a wholesaler', () async {
    await timed(
      'ratio analysis, a year and the year before',
      ReportKind.ratioAnalysis,
      hostBudgetMs: 4000,
    );
    await timed(
      'ABC classification, a year',
      ReportKind.abcClassification,
      hostBudgetMs: 2500,
    );
  });

  test('the attention list, the whole shelf and every open bill', () async {
    await timed(
      'needs attention',
      ReportKind.needsAttention,
      period: ReportPeriod.day(today),
      options: ReportOptions(nowUtc: DateTime.utc(2026, 6, 30, 9)),
      hostBudgetMs: 2000,
    );
  });

  test(
    'ageing in the shop\'s buckets, and the shelf at its sale price',
    () async {
      const mine = ReportOptions(ageing: AgeingBuckets([15, 30, 60, 120]));
      await timed(
        'udhaar by age in five buckets',
        ReportKind.receivables,
        options: mine,
        hostBudgetMs: 500,
      );
      await timed(
        'udhaar by due date in five buckets',
        ReportKind.receivablesByDueDate,
        options: mine,
        hostBudgetMs: 500,
      );
      await timed(
        'stock summary at the sale price with tax',
        ReportKind.stockSummary,
        filters: const ReportFilters(
          valuation: StockValuation.salePriceWithTax,
        ),
        hostBudgetMs: 2000,
      );
    },
  );
}
