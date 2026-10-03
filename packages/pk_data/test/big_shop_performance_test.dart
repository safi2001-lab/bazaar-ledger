@Timeout(Duration(minutes: 15))
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

import 'support/big_shop.dart';

/// A shop with years of bills stays fast (M62).
///
/// Rupin and Udhaar are "unusable at about 180 customers"; Vyapar's 1-star
/// reviews say "Loading… Loading…". The shop this product is for is the
/// wholesaler with three years in the book: fifty thousand bills and a
/// quarter of a million lines, two thousand parties, five thousand items,
/// twenty thousand receipts and three thousand deliveries (support/
/// big_shop.dart, built once for the file). Every list a shopkeeper opens
/// and the heaviest reports are timed against it, and the hot lists' query
/// plans are read: a list may read its own page, its own party or its own
/// day, never the whole book.
///
/// ## The budgets, and why they hold on a phone
///
/// These are host budgets, as M1's, M33's and M34's are, and each is the
/// phone's budget divided by five. A mid-range phone of the kind this ships
/// to (an Infinix or a Tecno at Rs 35,000-45,000, a Helio G-series chip and
/// eMMC storage) runs SQLite about five times slower than the development
/// machine — the "several times faster" M1's catalogue test leaves
/// unnumbered, made a number here so a budget can be read as the wait a
/// shopkeeper will see:
///
/// * the first page of a list opened with a tap: half a second on the
///   phone, 100 ms here;
/// * a search, a khata, a party list, the chase list: within a second on
///   the phone after the search box's quarter-second pause — 150-200 ms
///   here;
/// * a report over a month or one party's year: a second on the phone,
///   200 ms to 1 s here; the heaviest, a year of every bill or a month of
///   five thousand items' stock, M33's and M34's own 2.5 s and 4 s here
///   (12 and 20 seconds on the phone, behind a spinner, for a report a
///   shop runs once a month).
///
/// Each figure is the best of three, because the suite runs its files side
/// by side and other agents' builds share the machine; and each is printed,
/// because the number is what shows a regression coming before it crosses
/// the line. A budget that fails is re-run with the file alone before
/// anything is concluded from it.
///
/// ## What this found
///
/// * The sales list (M30) sorted the whole book to show its first forty
///   bills: idx_documents_list found every sale bill, and a temporary
///   B-tree put all fifty thousand in order, a correlated count of each
///   one's lines included, before the first forty were kept — 190 ms here,
///   about a second on the phone, and growing with every bill. It now
///   walks the bills newest first by their id and stops at the page.
/// * Udhaar by age read every document in the shop (SCAN d): its
///   `balance_paisa > 0` could not prove the partial index's
///   `balance_paisa <> 0`, so idx_documents_open_balance, built for exactly
///   this, was never used. The chase list and a khata's open bills had the
///   same blind spot. Each now says both, and rides the index.
/// * A regular's khata showed his OLDEST two hundred entries: the history
///   is read oldest first, to run the balance forwards, and was cut at two
///   hundred in SQL — so a customer with three years of bills saw nothing
///   newer than early 2024 under "history", and the newest bill the
///   shopkeeper had just made was not on it. The same for a supplier's
///   account. The whole account is read and the newest kept.
///
/// No index was needed: every hot read rides an index the schema already
/// has.
void main() {
  final recorder = _Recorder();
  late AppDatabase db;
  late BigShop shop;
  late DriftAppQueries queries;
  late ReportEngine reports;
  late String firmId;
  const today = BigShop.today;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory().interceptWith(recorder));
    await db.customSelect('SELECT 1').get();
    final started = DateTime.now();
    shop = await seedBigShop(db);
    // ignore: avoid_print
    print(
      'three years of a wholesaler seeded in '
      '${DateTime.now().difference(started).inSeconds}s',
    );
    queries = DriftAppQueries(db);
    reports = ReportEngine(DriftReportSource(db));
    firmId = shop.firm.firmId;
  });

  tearDownAll(() async => db.close());

  /// Times [work] (best of three), prints it beside its budget, and holds
  /// it to [hostBudgetMs].
  Future<int> timed(
    String label,
    Future<void> Function() work, {
    required int hostBudgetMs,
  }) async {
    final ms = await bestOfThreeMillis(work);
    // ignore: avoid_print
    print(
      '$label: ${ms}ms (host budget ${hostBudgetMs}ms, '
      'about ${hostBudgetMs * 5}ms on the phone)',
    );
    expect(
      ms,
      lessThan(hostBudgetMs),
      reason:
          '$label took ${ms}ms here, about ${ms * 5}ms on a mid-range '
          'phone',
    );
    return ms;
  }

  /// Every SELECT [work] runs, with its query plan.
  Future<List<_Planned>> plansOf(Future<void> Function() work) async {
    recorder.start();
    await work();
    final statements = recorder.stop();
    final seen = <String>{};
    return [
      for (final (sql, args) in statements)
        if (seen.add(sql))
          _Planned(sql, [
            for (final step in await db.executor.runSelect(
              'EXPLAIN QUERY PLAN $sql',
              args,
            ))
              '${step['detail']}',
          ]),
    ];
  }

  /// No step of [plans] reads one of the book's tables whole, except an
  /// index walk named in [walks] — a list paging newest first, which stops
  /// at its page.
  void readsNoTableWhole(
    List<_Planned> plans,
    String what, {
    Set<String> walks = const {},
  }) {
    for (final plan in plans) {
      for (final step in plan.steps) {
        final scan = RegExp(r'^SCAN (\w+)(.*)$').firstMatch(step);
        if (scan == null) continue;
        final table = plan.tableOf(scan.group(1)!);
        if (!_book.contains(table)) continue;
        final walk = RegExp(
          r'USING (?:COVERING )?INDEX (\w+)',
        ).firstMatch(scan.group(2)!)?.group(1);
        expect(
          walk != null && walks.contains(walk),
          isTrue,
          reason:
              '$what reads all of $table ($step):\n${plan.steps.join('\n')}'
              '\n${plan.sql}',
        );
      }
    }
  }

  test('the fixture really is three years of a wholesaler', () async {
    final row = await db.customSelect('''
      SELECT
        (SELECT COUNT(*) FROM documents
          WHERE doc_type = 'sale_invoice') AS bills,
        (SELECT COUNT(*) FROM document_lines dl JOIN documents d
           ON d.id = dl.document_id AND d.doc_type = 'sale_invoice') AS lines,
        (SELECT COUNT(*) FROM parties) AS parties,
        (SELECT COUNT(*) FROM items) AS items,
        (SELECT COUNT(*) FROM payments WHERE payment_no LIKE 'RCV-%')
          AS receipts,
        (SELECT COUNT(*) FROM documents WHERE doc_type = 'purchase_bill')
          AS purchases,
        (SELECT MIN(doc_date_local) || ' ' || MAX(doc_date_local)
           FROM documents) AS span,
        (SELECT COUNT(*) FROM documents WHERE party_id = '${shop.bigCustomer}'
           AND doc_type = 'sale_invoice') AS regular
      ''').getSingle();
    expect(row.read<int>('bills'), 50000);
    expect(row.read<int>('lines'), 250000);
    expect(row.read<int>('parties'), 2000);
    expect(row.read<int>('items'), 5000);
    expect(row.read<int>('receipts'), 20000);
    expect(row.read<int>('purchases'), 3000);
    expect(row.read<String>('span'), '2023-07-01 2026-06-30');
    expect(row.read<int>('regular'), greaterThan(500));
  });

  group('the lists a shopkeeper opens', () {
    test('the sales list opens on its newest page without reading the '
        'whole book', () async {
      final page = await queries.recentSales(firmId);
      expect(page, hasLength(40));
      expect(page.first.docNo, 'INV-0049999', reason: 'newest first');
      final next = await queries.recentSales(firmId, afterId: page.last.id);
      expect(next.first.docNo, 'INV-0049959');

      await timed(
        'sales list, first page',
        () => queries.recentSales(firmId),
        hostBudgetMs: 100,
      );
      await timed(
        'sales list, a page deep in the book',
        () => queries.recentSales(firmId, afterId: 'bd-0020000'),
        hostBudgetMs: 100,
      );
      final plans = await plansOf(() => queries.recentSales(firmId));
      readsNoTableWhole(
        plans,
        'the first page',
        walks: {'sqlite_autoindex_documents_1'},
      );
      expect(
        plans.single.steps,
        isNot(contains('USE TEMP B-TREE FOR ORDER BY')),
        reason: 'the first page sorted the whole book to keep forty bills',
      );
    });

    test('the sales list finds a bill by name, number, phone or amount, and '
        'the search that finds nothing is measured too', () async {
      final byName = await queries.recentSales(
        firmId,
        filter: const SaleFilter(query: 'rashid'),
      );
      expect(byName, hasLength(40));
      for (final query in [
        'rashid',
        'INV-0031337',
        // The regular's number, as it is read off his phone.
        '01000259',
        '1,23,400',
        // Matches nothing, so it cannot stop at a page: the worst case.
        'zzzzqq',
      ]) {
        await timed(
          'sales search "$query"',
          () => queries.recentSales(firmId, filter: SaleFilter(query: query)),
          hostBudgetMs: 150,
        );
      }
      readsNoTableWhole(
        await plansOf(
          () => queries.recentSales(
            firmId,
            filter: const SaleFilter(query: 'zzzzqq'),
          ),
        ),
        'a sales search',
        walks: {'sqlite_autoindex_documents_1'},
      );
    });

    test('a regular\'s khata opens on his newest entries, and its balance '
        'is the khata\'s', () async {
      final party = shop.bigCustomer;
      final history = await queries.partyLedger(firmId, party);
      final newest =
          (await db
                  .customSelect(
                    '''
          SELECT MAX(day) AS day FROM (
            SELECT doc_date_local AS day FROM documents WHERE party_id = ?1
            UNION ALL
            SELECT payment_date_local FROM payments WHERE party_id = ?1)
          ''',
                    variables: [Variable<String>(party)],
                  )
                  .getSingle())
              .read<String>('day');
      expect(
        history.last.dateLocal,
        newest,
        reason:
            'the khata showed his oldest entries and stopped, so the bill '
            'just made was not on it',
      );
      final summary = (await queries.partyById(firmId, party))!;
      expect(history.last.balanceAfter, summary.balance);

      Future<void> openKhata() async {
        await queries.partyById(firmId, party);
        await queries.openBillsFor(firmId, party);
        await queries.partyLedger(firmId, party);
      }

      await timed(
        'a regular\'s khata: balance, open bills, history',
        openKhata,
        hostBudgetMs: 150,
      );
      readsNoTableWhole(await plansOf(openKhata), 'a khata');
    });

    test('a supplier\'s account opens on its newest deliveries', () async {
      const mill = 'bp-1950';
      final account = await queries.payablesLedger(firmId, mill);
      final newest =
          (await db
                  .customSelect(
                    'SELECT MAX(doc_date_local) AS day FROM documents '
                    "WHERE party_id = '$mill'",
                  )
                  .getSingle())
              .read<String>('day');
      expect(account.last.dateLocal, newest);
      await timed(
        'a supplier\'s account',
        () => queries.payablesLedger(firmId, mill),
        hostBudgetMs: 150,
      );
    });

    test('the parties list, by name, balance and oldest due, by route, and '
        'its groups', () async {
      await timed(
        'party groups',
        () => queries.partyGroups(firmId),
        hostBudgetMs: 200,
      );
      for (final filter in [
        for (final sort in PartySort.values) PartyListFilter(sort: sort),
        const PartyListFilter(group: 'Route 3', sort: PartySort.balance),
        const PartyListFilter(ungrouped: true),
        const PartyListFilter(query: 'rashid'),
      ]) {
        await timed(
          'parties list, ${filter.sort.name}'
          '${filter.group == null ? '' : ', ${filter.group}'}'
          '${filter.ungrouped ? ', ungrouped' : ''}'
          '${filter.query.isEmpty ? '' : ', "${filter.query}"'}',
          () => queries.partyList(firmId, filter: filter, limit: 300),
          hostBudgetMs: 200,
        );
        readsNoTableWhole(
          await plansOf(
            () => queries.partyList(firmId, filter: filter, limit: 300),
          ),
          'the parties list',
        );
      }
      readsNoTableWhole(
        await plansOf(() => queries.partyGroups(firmId)),
        'party groups',
      );
    });

    test('items are found however they are spelt', () async {
      for (final query in ['dalda', 'daalda oyl', 'chawal basmti', 'zzzzqq']) {
        await timed(
          'item search "$query"',
          () => queries.searchItems(firmId, query: query),
          hostBudgetMs: 150,
        );
      }
      expect(
        await queries.searchItems(firmId, query: 'daalda oyl'),
        isNotEmpty,
      );
    });

    test('who to chase, and udhaar by age, read only what is owed', () async {
      final chase = await queries.partiesToChase(
        firmId,
        asOfDateLocal: today.value,
      );
      expect(chase, isNotEmpty);
      await timed(
        'the chase list',
        () => queries.partiesToChase(firmId, asOfDateLocal: today.value),
        hostBudgetMs: 200,
      );
      await timed(
        'udhaar by age',
        () => queries.aging(firmId, asOfDateLocal: today.value),
        hostBudgetMs: 100,
      );
      readsNoTableWhole(
        await plansOf(
          () => queries.partiesToChase(firmId, asOfDateLocal: today.value),
        ),
        'the chase list',
      );
      readsNoTableWhole(
        await plansOf(() => queries.aging(firmId, asOfDateLocal: today.value)),
        'udhaar by age',
      );
    });
  });

  group('the heaviest reports', () {
    final year = ReportPeriod(
      const BusinessDate('2025-07-01'),
      const BusinessDate('2026-06-30'),
    );
    final month = ReportPeriod.monthOf(const BusinessDate('2026-03-15'));

    Future<void> report(
      String label,
      ReportKind kind,
      ReportPeriod period, {
      required int hostBudgetMs,
      ReportFilters filters = ReportFilters.none,
    }) async {
      Future<ReportTable> run() => reports.run(
        kind,
        firmId: firmId,
        period: period,
        today: today,
        filters: filters,
      );
      final rows = (await run()).rows.length;
      expect(rows, greaterThan(1), reason: '$label is empty');
      await timed('$label ($rows rows)', run, hostBudgetMs: hostBudgetMs);
    }

    test(
      'a year of every bill, a month of everything, a month of stock',
      () async {
        await report(
          'sale report, a year',
          ReportKind.saleReport,
          year,
          hostBudgetMs: 2500,
        );
        await report(
          'all transactions, a month',
          ReportKind.allTransactions,
          month,
          hostBudgetMs: 1000,
        );
        await report(
          'stock detail, a month',
          ReportKind.stockDetail,
          month,
          hostBudgetMs: 4000,
        );
      },
    );

    test('a regular\'s year, and the day\'s summary', () async {
      await report(
        'party statement, a regular\'s year',
        ReportKind.partyStatement,
        year,
        filters: ReportFilters(
          partyId: shop.bigCustomer,
          partyName: shop.bigCustomerName,
        ),
        hostBudgetMs: 200,
      );
      await report(
        'day summary (Z report)',
        ReportKind.dailySummary,
        ReportPeriod.day(const BusinessDate('2026-03-16')),
        hostBudgetMs: 150,
      );
    });
  });
}

/// The book's own tables: a read of any of these whole grows with every
/// bill, and on a three-year book is the wait the reviews complain of.
/// Parties and items are not here: the parties list and the counter's
/// spelling search (M56) read their whole list by design, and both are
/// timed above.
const _book = {
  'documents',
  'document_lines',
  'document_line_taxes',
  'payments',
  'payment_allocations',
  'journal_entries',
  'journal_lines',
  'stock_ledger',
};

/// One statement and its plan.
final class _Planned {
  _Planned(this.sql, this.steps);

  final String sql;
  final List<String> steps;

  /// The table [name] reads in [sql]: an alias resolved, or itself. An
  /// alias used twice in one statement for different tables resolves to
  /// either, and a book table wins, so a doubt is a failure, not a pass.
  String tableOf(String name) {
    const words = {
      'where',
      'on',
      'left',
      'join',
      'inner',
      'cross',
      'using',
      'group',
      'order',
      'limit',
      'union',
      'and',
      'or',
      'select',
      'set',
      'values',
      'as',
    };
    String? found;
    for (final m in RegExp(
      r'\b(?:FROM|JOIN)\s+([a-z_][a-z_0-9]*)'
      r'(?:\s+(?:AS\s+)?([a-z_][a-z_0-9]*))?',
      caseSensitive: false,
    ).allMatches(sql)) {
      final table = m.group(1)!.toLowerCase();
      final alias = m.group(2)?.toLowerCase();
      final named = alias == null || words.contains(alias) ? table : alias;
      if (named != name.toLowerCase()) continue;
      if (_book.contains(table)) return table;
      found ??= table;
    }
    return found ?? name;
  }
}

/// Records every SELECT while it is switched on.
final class _Recorder extends QueryInterceptor {
  List<(String, List<Object?>)>? _seen;

  void start() => _seen = [];

  List<(String, List<Object?>)> stop() {
    final seen = _seen ?? const [];
    _seen = null;
    return seen;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _seen?.add((statement, args));
    return executor.runSelect(statement, args);
  }
}
