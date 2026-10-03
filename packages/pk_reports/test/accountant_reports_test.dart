import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

/// The reports an accountant and an owner reach for next (M67), proved
/// here without a database: ratios read off the statements, the attention
/// list, ABC classes, ageing in the shop's own buckets, the shelf valued
/// four ways, a table the shop arranges, and last period on a trend.
const _today = BusinessDate('2026-10-03');
final _september = ReportPeriod(
  const BusinessDate('2026-09-01'),
  const BusinessDate('2026-09-30'),
);
final _august = ReportPeriod(
  const BusinessDate('2026-08-01'),
  const BusinessDate('2026-08-31'),
);

Money _rs(int rupees) => Money.rupees(rupees);

AccountMovement _account(
  String code,
  String name,
  String type, {
  int debit = 0,
  int credit = 0,
  String? key,
  bool direct = false,
}) => AccountMovement(
  code: code,
  name: name,
  type: type,
  debit: _rs(debit),
  credit: _rs(credit),
  systemKey: key,
  isDirect: direct,
);

/// A month of a shop: Rs 100,000 sold, Rs 60,000 of it at cost, Rs 10,000
/// of rent, the shelf from Rs 50,000 to Rs 60,000 with Rs 70,000 bought.
List<AccountMovement> _month({
  int sales = 100000,
  int cogs = 60000,
  int rent = 10000,
}) => [
  _account('4100', 'Sales', 'income', credit: sales, key: 'sales'),
  _account(
    '5100',
    'Cost of Goods Sold',
    'expense',
    debit: cogs,
    key: 'cogs',
    direct: true,
  ),
  _account('6100', 'Rent', 'expense', debit: rent, key: 'rent'),
];

/// Everything posted by the month's end.
List<AccountMovement> _balances({int receivables = 25000}) => [
  _account('1010', 'Golak', 'asset', debit: 20000, key: 'cash_in_hand'),
  _account(
    '1100',
    'Udhaar Lena Hai',
    'asset',
    debit: receivables,
    key: 'accounts_receivable',
  ),
  _account('1200', 'Maal', 'asset', debit: 60000, key: 'inventory'),
  _account('1400', 'Fixed Assets', 'asset', debit: 15000, key: 'fixed_assets'),
  _account(
    '2100',
    'Udhaar Dena Hai',
    'liability',
    credit: 35000,
    key: 'accounts_payable',
  ),
  _account(
    '3100',
    "Owner's Capital",
    'equity',
    credit: 55000 + receivables - 25000,
    key: 'owner_capital',
  ),
  ..._month(),
];

/// The books a ratio reads, period by period.
final class _Books implements ReportSource {
  _Books(this.months, this.stock, this.balances, this.money);

  final Map<ReportPeriod, List<AccountMovement>> months;
  final Map<ReportPeriod, StockFigures> stock;
  final Map<String, List<AccountMovement>> balances;
  final Map<String, MoneyBalance> money;

  @override
  Future<List<AccountMovement>> accountMovements(
    String firmId,
    ReportPeriod period,
  ) async => months[period] ?? const [];

  @override
  Future<StockFigures> stockFigures(String firmId, ReportPeriod period) async =>
      stock[period]!;

  @override
  Future<List<AccountMovement>> accountBalances(
    String firmId,
    BusinessDate asOf,
  ) async => balances[asOf.value] ?? const [];

  @override
  Future<MoneyBalance> moneyBefore(String firmId, BusinessDate day) async =>
      money[day.value] ?? MoneyBalance.zero;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('${invocation.memberName} was not expected');
}

/// A source that must not be read at all.
final class _Untouched implements ReportSource {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('${invocation.memberName} was read');
}

ItemTrade _trade(
  String name,
  int sales, {
  int cost = 0,
  String? category,
  bool loose = false,
}) => ItemTrade(
  itemId: loose ? null : 'i-$name',
  itemName: loose ? ItemTrade.looseLines : name,
  unitCode: loose ? '' : 'pcs',
  category: category,
  qtySold: loose ? Qty.zero : Qty.units(1),
  sales: _rs(sales),
  cost: _rs(cost),
);

String _cell(ReportRow r, ReportTable t, String title) =>
    '${r.cells[t.columns.indexWhere((c) => c.title == title)] ?? ''}';

Object? _at(ReportRow r, ReportTable t, String title) =>
    r.cells[t.columns.indexWhere((c) => c.title == title)];

void main() {
  group('a table the shop arranges', () {
    ReportTable bills() => ReportTable(
      id: 'sale_report',
      title: 'Sale report',
      period: _september,
      columns: const [
        ReportColumn('Bill', CellKind.text),
        ReportColumn('Party', CellKind.text),
        ReportColumn('Total', CellKind.money),
        ReportColumn('Lines', CellKind.count),
        ReportColumn('Share', CellKind.percent),
      ],
      rows: [
        ReportRow([
          'INV-1',
          'Rashid Traders',
          _rs(4000),
          2,
          4000,
        ], link: const ReportLink.document('d1', label: 'INV-1')),
        ReportRow(['INV-2', 'Akbar', _rs(2500), 1, 2500]),
        ReportRow(['INV-3', 'Rashid Traders', _rs(3500), 3, 3500]),
        ReportRow(['Total', null, _rs(10000), 6, 10000], style: RowStyle.total),
      ],
    );

    test('columns are hidden and moved by title, and every row follows', () {
      final arranged = arrangeTable(
        bills(),
        const TableArrangement(
          order: ['Total', 'Bill'],
          hidden: {'Lines', 'Share'},
        ),
      );
      expect(arranged.columns.map((c) => c.title), ['Total', 'Bill', 'Party']);
      expect(arranged.rows.first.cells, [_rs(4000), 'INV-1', 'Rashid Traders']);
      expect(arranged.rows.first.link?.id, 'd1');
      expect(arranged.rows.last.cells, [_rs(10000), 'Total', null]);
      expect(arranged.rows, hasLength(4), reason: 'no row added or lost');
      expect(arranged.filters, isEmpty, reason: 'hiding narrows nothing');
      // A report that gains a column shows it, after the arranged ones.
      expect(const TableArrangement(order: ['Party']).shownKeys(bills()), [
        'Party',
        'Bill',
        'Total',
        'Lines',
        'Share',
      ]);
      // Never no columns at all.
      expect(
        const TableArrangement(
          hidden: {'Bill', 'Party', 'Total', 'Lines', 'Share'},
        ).shownKeys(bills()),
        ['Bill'],
      );
      final same = bills();
      expect(
        identical(arrangeTable(same, TableArrangement.none), same),
        isTrue,
      );
    });

    test('a column filter keeps whole rows, adds what they come to as Shown '
        "rows, and leaves the Total the builder's", () {
      final arranged = arrangeTable(
        bills(),
        const TableArrangement(
          filters: [ColumnFilter.contains('Party', 'rashid')],
        ),
      );
      expect(arranged.rows.map((r) => r.cells.first), [
        'INV-1',
        'INV-3',
        'Shown rows (2 of 3)',
        'Total',
      ]);
      final shown = arranged.rows[2];
      expect(
        shown.style,
        RowStyle.total,
        reason: 'at the foot, and the rows above it still sort',
      );
      expect(_at(shown, arranged, 'Total'), _rs(7500));
      expect(_at(shown, arranged, 'Lines'), 5);
      expect(
        _at(shown, arranged, 'Share'),
        isNull,
        reason: 'a share is never added up',
      );
      expect(
        _at(arranged.rows.last, arranged, 'Total'),
        _rs(10000),
        reason: "the Total is still the whole report's",
      );
      expect(arranged.filters, ['Party contains "rashid"']);
      expect(arranged.notes.last, contains('Shown rows adds up only'));
      // Sorting keeps the shown rows and the total at the foot.
      final sorted = sortedRows(arranged, 2, ascending: true);
      expect(sorted.map((r) => r.cells.first), [
        'INV-3',
        'INV-1',
        'Shown rows (2 of 3)',
        'Total',
      ]);
    });

    test("figures filter at least and at most in the column's own unit, a "
        'hidden label column moves the count to the head of the export', () {
      final atLeast = arrangeTable(
        bills(),
        TableArrangement(
          hidden: const {'Bill', 'Party'},
          filters: [ColumnFilter.atLeast('Total', _rs(3500).inPaisa)],
        ),
      );
      expect(atLeast.columns.map((c) => c.title), ['Total', 'Lines', 'Share']);
      expect(atLeast.rows.map((r) => r.cells.first), [
        _rs(4000),
        _rs(3500),
        _rs(7500),
        _rs(10000),
      ]);
      expect(atLeast.filters, [
        'Total at least Rs 3,500.00',
        'Shown rows (2 of 3)',
      ]);
      final atMost = arrangeTable(
        bills(),
        const TableArrangement(
          filters: [
            ColumnFilter.atMost('Share', 3000),
            ColumnFilter.atMost('Lines', 1),
          ],
        ),
      );
      expect(atMost.rows.map((r) => r.cells.first), [
        'INV-2',
        'Shown rows (1 of 3)',
        'Total',
      ]);
      expect(atMost.filters, ['Share at most 30.00%', 'Lines at most 1']);
    });

    test('a statement with headings takes no column filter, only its '
        'columns arranged', () {
      final pnl = profitAndLoss(_september, _month());
      expect(pnl.isSortable, isFalse);
      final arranged = arrangeTable(
        pnl,
        const TableArrangement(
          order: ['Amount'],
          filters: [ColumnFilter.contains('Account', 'rent')],
        ),
      );
      expect(arranged.rows, hasLength(pnl.rows.length));
      expect(arranged.columns.first.title, 'Amount');
      expect(arranged.filters, isEmpty);
    });

    test('two columns of one title are told apart, and an arrangement is '
        'written down and read back', () {
      final tax = salesTaxSummary(_september, const []);
      expect(columnKeys(tax), ['Tax', 'Rate', 'Value of supplies', 'Tax (2)']);
      expect(keyTitle('Tax (2)'), 'Tax');
      final arranged = arrangeTable(
        tax,
        const TableArrangement(hidden: {'Tax (2)'}),
      );
      expect(arranged.columns.map((c) => c.kind), [
        CellKind.text,
        CellKind.percent,
        CellKind.money,
      ]);

      const a = TableArrangement(
        order: ['Total', 'Bill'],
        hidden: {'Share'},
        filters: [
          ColumnFilter.contains('Party', 'Rashid'),
          ColumnFilter.atLeast('Total', 350000),
        ],
      );
      expect(TableArrangement.fromJson(a.toJson()), a);
      expect(TableArrangement.fromJson('nonsense'), TableArrangement.none);
      expect(
        TableArrangement.fromJson({
          'order': [1, 'Bill'],
          'filters': [
            {'column': 'Total', 'test': 'between', 'value': 1},
          ],
        }),
        const TableArrangement(order: ['Bill']),
      );
      expect(a.columnsOnly.filters, isEmpty);
      expect(a.columnsOnly.arrangesColumns, isTrue);
    });
  });

  group("ageing in the shop's buckets", () {
    final old = [
      const PartyReceivable(
        name: 'Rashid Traders',
        opening: Money.rupees(500),
        upTo30: Money.rupees(1000),
        upTo60: Money.rupees(2000),
        upTo90: Money.rupees(3000),
        over90: Money.rupees(4000),
        advance: Money.rupees(250),
      ),
      const PartyReceivable(
        name: 'Akbar',
        opening: Money.zero,
        upTo30: Money.rupees(800),
        upTo60: Money.zero,
        upTo90: Money.zero,
        over90: Money.rupees(4000),
        advance: Money.zero,
      ),
    ];
    final aged = [
      for (final p in old)
        AgedBalance(
          name: p.name,
          opening: p.opening,
          buckets: [p.upTo30, p.upTo60, p.upTo90, p.over90],
          advance: p.advance,
        ),
    ];

    test('the standard buckets give the very table Udhaar by age gave, and '
        'Owed to suppliers likewise', () {
      for (final (now, before) in [
        (
          receivablesAged(_today, aged, AgeingBuckets.standard),
          receivablesByAge(_today, old),
        ),
        (
          payablesAged(_today, aged, AgeingBuckets.standard),
          payablesByAge(_today, old),
        ),
      ]) {
        expect(now.id, before.id);
        expect(now.title, before.title);
        expect(
          now.columns.map((c) => c.title),
          before.columns.map((c) => c.title),
        );
        expect(
          [for (final r in now.rows) r.cells],
          [for (final r in before.rows) r.cells],
        );
        expect(now.notes, before.notes);
        expect(now.bucketColumns, [
          '0-30 days',
          '31-60 days',
          '61-90 days',
          'Over 90 days',
        ]);
      }
    });

    test("the due-date report in the standard buckets is M58's, and its "
        'ring names the same five', () {
      const m58 = [
        DueAgeingRow(
          partyId: 'p1',
          name: 'Rashid Traders',
          notYetDue: Money.rupees(100),
          upTo30: Money.rupees(200),
          upTo60: Money.rupees(300),
          upTo90: Money.rupees(400),
          over90: Money.rupees(500),
          opening: Money.rupees(50),
          advance: Money.rupees(25),
        ),
        DueAgeingRow(partyId: 'p2', name: 'Akbar', upTo30: Money.rupees(90)),
      ];
      final ours = [
        for (final r in m58)
          DueAgedBalance(
            partyId: r.partyId,
            name: r.name,
            notYetDue: r.notYetDue,
            late: [r.upTo30, r.upTo60, r.upTo90, r.over90],
            opening: r.opening,
            advance: r.advance,
          ),
      ];
      final now = receivablesByDueDateIn(_today, ours, AgeingBuckets.standard);
      final before = receivablesByDueDate(_today, m58);
      expect(
        now.columns.map((c) => c.title),
        before.columns.map((c) => c.title),
      );
      expect(
        [for (final r in now.rows) r.cells],
        [for (final r in before.rows) r.cells],
      );
      expect(now.notes, before.notes);
      expect(now.bucketColumns, dueBucketColumns);
      final ring = chartOf(now, const ChartSpec.ringOfBuckets())!;
      final m46 = chartOf(
        before,
        const ChartSpec.ringOfTotal(dueBucketColumns),
      )!;
      expect(ring.points.map((p) => p.label), m46.points.map((p) => p.label));
      expect(ring.total, m46.total);
    });

    test('buckets the shop sets cut the money where it says, the totals do '
        'not move, and the ring follows them', () {
      const mine = AgeingBuckets([15, 30, 60]);
      final table = receivablesAged(_today, [
        AgedBalance(
          partyId: 'p1',
          name: 'Rashid Traders',
          buckets: [_rs(100), _rs(200), _rs(300), _rs(400)],
        ),
      ], mine);
      expect(table.columns.map((c) => c.title), [
        'Customer',
        'Opening',
        '0-15 days',
        '16-30 days',
        '31-60 days',
        'Over 60 days',
        'Advance',
        'Owed',
      ]);
      expect(_at(table.rows.last, table, 'Owed'), _rs(1000));
      expect(
        table.notes,
        contains(
          "Buckets are the shop's own: 0-15 / 16-30 / 31-60 / 60+ days.",
        ),
      );
      expect(table.rows.first.link?.kind, ReportLinkKind.party);

      final due = receivablesByDueDateIn(_today, [
        DueAgedBalance(
          partyId: 'p1',
          name: 'Rashid Traders',
          notYetDue: _rs(50),
          late: [_rs(1), _rs(2), _rs(3), _rs(4)],
        ),
      ], mine);
      expect(due.bucketColumns, [
        'Not yet due',
        '1-15 days late',
        '16-30 days late',
        '31-60 days late',
        'Over 60 days late',
      ]);
      final ring = chartOf(due, const ChartSpec.ringOfBuckets())!;
      expect(ring.points.map((p) => p.label), due.bucketColumns);
      expect(ring.total, _rs(60));
      // A table with no buckets draws no ring rather than a wrong one.
      expect(
        chartOf(
          profitAndLoss(_september, _month()),
          const ChartSpec.ringOfBuckets(),
        ),
        isNull,
      );
    });

    test('buckets are read as typed, and nonsense is refused', () {
      expect(
        AgeingBuckets.tryParse('15, 30, 60'),
        const AgeingBuckets([15, 30, 60]),
      );
      expect(
        AgeingBuckets.tryParse(' 45 / 90 '),
        const AgeingBuckets([45, 90]),
      );
      expect(AgeingBuckets.tryParse('30, 15'), isNull, reason: 'not rising');
      expect(AgeingBuckets.tryParse('0, 30'), isNull);
      expect(AgeingBuckets.tryParse('1,2,3,4,5,6'), isNull, reason: 'six');
      expect(AgeingBuckets.tryParse('thirty'), isNull);
      expect(AgeingBuckets.tryParse(''), isNull);
      expect(AgeingBuckets.standard.label, '0-30 / 31-60 / 61-90 / 90+');
      expect(AgeingBuckets.standard.typed, '30, 60, 90');
      expect(AgeingBuckets.standard.isStandard, isTrue);
    });
  });

  group('ABC classification', () {
    final trades = [
      _trade('Ghee', 50000, cost: 45000, category: 'Ghee and oil'),
      _trade('Atta', 30000, cost: 20000, category: 'Atta'),
      _trade('Chawal', 10000, cost: 7000, category: 'Chawal'),
      _trade('Daal', 6000, cost: 6500, category: 'Daal'),
      _trade('Namak', 3000, cost: 1000),
      _trade('loose', 1000, loose: true),
      // Bought, never sold: not ranked.
      ItemTrade(
        itemId: 'i-Sabun',
        itemName: 'Sabun',
        unitCode: 'pcs',
        qtyBought: Qty.units(10),
        purchases: _rs(900),
      ),
    ];

    test('the few that make most of the sales are A, and the classes add up '
        'to the sales', () {
      final table = abcClassification(_september, trades);
      final lines = table.rows.where((r) => r.style == RowStyle.line).toList();
      expect(lines.map((r) => _cell(r, table, 'Item')), [
        'Ghee',
        'Atta',
        'Chawal',
        'Daal',
        'Namak',
        ItemTrade.looseLines,
      ]);
      // 50% before Atta: A. 80% before Chawal: B. 90% before Daal: B.
      // 96% before Namak: C.
      expect(lines.map((r) => _cell(r, table, 'Class')), [
        'A',
        'A',
        'B',
        'B',
        'C',
        'C',
      ]);
      expect(_at(lines[1], table, 'Running share'), 8000);
      expect(_at(lines.first, table, 'Rank'), 1);
      Money figure(String label) =>
          table.summary.firstWhere((f) => f.label == label).amount!;
      int count(String label) =>
          table.summary.firstWhere((f) => f.label == label).count!;
      final classes =
          figure('Class A sales') +
          figure('Class B sales') +
          figure('Class C sales');
      expect(classes, _rs(100000));
      expect(_at(table.rows.last, table, 'Sales'), classes);
      expect(
        _at(table.rows.last, table, 'Sales'),
        _at(
          itemProfitAndLoss(_september, trades).rows.last,
          itemProfitAndLoss(_september, trades),
          'Sales',
        ),
        reason: "the Item-wise profit's total",
      );
      expect(
        count('Class A items') +
            count('Class B items') +
            count('Class C items'),
        6,
      );
      expect(
        table.notes.first,
        'Class A: 2 of 6 items (33.33%), Rs 80,000.00 of sales (80.00%).',
      );
      expect(lines.first.link?.kind, ReportLinkKind.item);
      expect(lines.last.link, isNull, reason: 'khula maal has no item');
      // The ring is the three classes' sales.
      final ring = chartOf(
        table,
        const ChartSpec.ring(label: 'Class', value: 'Sales'),
      )!;
      expect(ring.points.map((p) => p.label), ['A', 'B', 'C']);
      expect(ring.total, _rs(100000));
    });

    test("the lines are the shop's to move", () {
      final table = abcClassification(_september, trades, aAt: 50, bAt: 90);
      final lines = table.rows.where((r) => r.style == RowStyle.line);
      expect(lines.map((r) => _cell(r, table, 'Class')), [
        'A',
        'B',
        'B',
        'C',
        'C',
        'C',
      ]);
      expect(
        abcClasses([_rs(96), _rs(4)]),
        [AbcClass.a, AbcClass.c],
        reason: 'the first item alone is past the B line',
      );
      expect(abcClasses([_rs(0), _rs(-5), _rs(10)]), [
        AbcClass.c,
        AbcClass.c,
        AbcClass.a,
      ]);
    });

    test('ranked by profit a loss is C; and a role that may not see costs '
        'is refused the ranking before anything is read', () async {
      final table = abcClassification(
        _september,
        trades,
        basis: AbcBasis.margin,
      );
      final lines = table.rows.where((r) => r.style == RowStyle.line).toList();
      expect(
        _cell(lines.first, table, 'Item'),
        'Atta',
        reason: 'Rs 10,000 made',
      );
      expect(_cell(lines.last, table, 'Item'), 'Daal');
      expect(_cell(lines.last, table, 'Class'), 'C');
      expect(
        table.columns.firstWhere((c) => c.title == 'Share').isCost,
        isTrue,
      );
      expect(
        table.notes,
        contains('An item that made nothing or a loss is in class C.'),
      );

      final engine = ReportEngine(_Untouched(), canSeeCosts: false);
      await expectLater(
        engine.run(
          ReportKind.abcClassification,
          firmId: 'f',
          period: _september,
          today: _today,
          filters: const ReportFilters(abcBasis: AbcBasis.margin),
        ),
        throwsA(isA<PermissionDenied>()),
      );
      await expectLater(
        engine.run(
          ReportKind.ratioAnalysis,
          firmId: 'f',
          period: _september,
          today: _today,
        ),
        throwsA(isA<PermissionDenied>()),
      );
    });
  });

  group('ratio analysis', () {
    final books = _Books(
      {
        _september: _month(),
        _august: _month(sales: 80000, cogs: 52000, rent: 10000),
      },
      {
        _september: StockFigures(
          opening: _rs(50000),
          purchases: _rs(70000),
          purchaseReturns: Money.zero,
          closing: _rs(60000),
        ),
        _august: StockFigures(
          opening: _rs(40000),
          purchases: _rs(62000),
          purchaseReturns: Money.zero,
          closing: _rs(50000),
        ),
      },
      {'2026-09-30': _balances(), '2026-08-31': _balances(receivables: 32000)},
      {
        '2026-10-01': MoneyBalance(cash: _rs(15000), bank: _rs(5000)),
        '2026-09-01': MoneyBalance(cash: _rs(5000), bank: _rs(5000)),
      },
    );

    test('every input is a line of the Profit and Loss or the Balance '
        'Sheet', () {
      final pnl = profitAndLoss(
        _september,
        _month(),
        stock: StockFigures(
          opening: _rs(50000),
          purchases: _rs(70000),
          purchaseReturns: _rs(2000),
          closing: _rs(60000),
        ),
      );
      final sheet = balanceSheet(const BusinessDate('2026-09-30'), _balances());
      final f = RatioFigures.fromBooks(
        period: _september,
        days: 30,
        profitAndLoss: pnl,
        balanceSheet: sheet,
        balances: _balances(),
        money: MoneyBalance(cash: _rs(15000), bank: _rs(5000)),
      );
      Money line(ReportTable t, String label) =>
          t.rows.firstWhere((r) => r.cells.first == label).cells[1]! as Money;
      expect(f.netSales, line(pnl, 'Net sales'));
      expect(f.grossProfit, line(pnl, 'Gross profit'));
      expect(f.netProfit, pnl.totals.single.cells[1]);
      expect(f.costOfGoodsSold, line(pnl, 'Cost of goods sold'));
      expect(f.expenses, line(pnl, 'Total expenses'));
      expect(f.openingStock, line(pnl, 'Opening stock'));
      expect(f.closingStock, -line(pnl, 'Closing stock'));
      expect(
        f.purchases,
        line(pnl, 'Purchases') + line(pnl, 'Purchase returns'),
      );
      expect(f.purchases, _rs(68000));
      expect(f.receivables, line(sheet, 'Udhaar Lena Hai'));
      expect(f.payables, line(sheet, 'Udhaar Dena Hai'));
      expect(
        f.currentAssets,
        line(sheet, 'Total assets') - line(sheet, 'Fixed Assets'),
      );
      expect(f.currentLiabilities, line(sheet, 'Total liabilities'));
      expect(f.cash, _rs(20000));
    });

    test('each ratio is worked out in whole numbers, beside the period '
        'before, better or worse', () async {
      final table = await buildRatioReport(
        books,
        firmId: 'f',
        period: _september,
        today: _today,
      );
      String row(RatioKind k, String column) => _cell(
        table.rows.firstWhere((r) => r.cells.first == k.title),
        table,
        column,
      );
      expect(row(RatioKind.grossMargin, 'This period'), '40.00%');
      expect(row(RatioKind.grossMargin, 'Period before'), '35.00%');
      expect(row(RatioKind.grossMargin, 'Change'), '+5.00 points');
      expect(row(RatioKind.grossMargin, 'Reading'), 'Better');
      expect(row(RatioKind.netMargin, 'This period'), '30.00%');
      // 60,000 over (50,000 + 60,000) halved.
      expect(row(RatioKind.stockTurnover, 'This period'), '1.09 times');
      // 55,000 average stock at 2,000 a day of cost of goods sold.
      expect(row(RatioKind.daysOfStock, 'This period'), '28 days');
      // 25,000 of udhaar against 100,000 in 30 days.
      expect(row(RatioKind.debtorsDays, 'This period'), '8 days');
      expect(row(RatioKind.debtorsDays, 'Period before'), '12 days');
      expect(row(RatioKind.debtorsDays, 'Reading'), 'Better');
      expect(row(RatioKind.creditorsDays, 'This period'), '15 days');
      expect(
        row(RatioKind.creditorsDays, 'Reading'),
        '',
        reason: 'neither way is plainly better',
      );
      expect(row(RatioKind.currentRatio, 'This period'), '3.00 : 1');
      expect(row(RatioKind.cashCover, 'This period'), '2.00 months');
      expect(row(RatioKind.cashCover, 'Period before'), '1.03 months');
      expect(
        row(RatioKind.grossMargin, 'Worked out from'),
        'Gross profit Rs 40,000.00 of net sales Rs 1,00,000.00',
      );
      expect(table.rows.first.link?.kind, ReportLinkKind.report);
      expect(
        table.rows
            .firstWhere((r) => r.cells.first == RatioKind.debtorsDays.title)
            .link
            ?.id,
        ReportKind.paymentPerformance.name,
      );
      expect(table.summary.map((f) => f.label), [
        'Net sales',
        'Gross profit',
        'Net profit',
      ]);
      expect(table.notes.first, contains('2026-08-01 to 2026-08-31'));
    });

    test('a ratio with nothing to divide by is a dash, and the days are '
        'those passed', () {
      final nothing = RatioFigures(
        period: _noPeriod,
        days: 0,
        netSales: Money.zero,
        grossProfit: Money.zero,
        netProfit: Money.zero,
        costOfGoodsSold: Money.zero,
        expenses: Money.zero,
        purchases: Money.zero,
        openingStock: Money.zero,
        closingStock: Money.zero,
        receivables: Money.zero,
        payables: Money.zero,
        currentAssets: Money.zero,
        currentLiabilities: Money.zero,
        cash: Money.zero,
      );
      for (final k in RatioKind.values) {
        expect(ratioText(k, ratioOf(k, nothing)), '-', reason: '$k');
      }
      expect(daysPassed(_september, _today), 30);
      expect(daysPassed(ReportPeriod.monthOf(_today), _today), 3);
      expect(
        daysPassed(
          ReportPeriod.monthOf(const BusinessDate('2026-11-05')),
          _today,
        ),
        0,
      );
    });
  });

  group('needs attention', () {
    final cheques = [
      ChequeInHand(
        paymentId: 'c1',
        paymentNo: 'RCV-1',
        partyId: 'p1',
        partyName: 'Rashid Traders',
        amount: _rs(5000),
        chequeNo: '000123',
        bank: 'HBL',
        receivedOn: const BusinessDate('2026-09-20'),
        due: const BusinessDate('2026-10-01'),
        deposited: false,
      ),
      ChequeInHand(
        paymentId: 'c2',
        paymentNo: 'RCV-2',
        partyId: 'p2',
        partyName: 'Akbar',
        amount: _rs(7000),
        chequeNo: '000456',
        receivedOn: const BusinessDate('2026-03-01'),
        due: const BusinessDate('2026-04-03'),
        deposited: false,
      ),
      // Not due yet, and one at the bank in date: neither is named.
      ChequeInHand(
        paymentId: 'c3',
        paymentNo: 'RCV-3',
        partyId: 'p3',
        partyName: 'Bilal',
        amount: _rs(1000),
        chequeNo: '000789',
        receivedOn: const BusinessDate('2026-09-20'),
        due: const BusinessDate('2026-10-20'),
        deposited: false,
      ),
      ChequeInHand(
        paymentId: 'c4',
        paymentNo: 'RCV-4',
        partyId: 'p4',
        partyName: 'Imran',
        amount: _rs(1000),
        chequeNo: '000999',
        receivedOn: const BusinessDate('2026-09-20'),
        due: const BusinessDate('2026-09-25'),
        deposited: true,
      ),
    ];
    final odd = ShopExceptions(
      shortItems: [
        ShortItem(
          itemId: 'i1',
          itemName: 'Ghee 16kg',
          unitCode: 'tin',
          qty: Qty.units(-2),
        ),
        ShortItem(
          itemId: 'i2',
          itemName: 'Surf 1kg',
          unitCode: 'pcs',
          qty: Qty.units(-1),
          blocked: true,
        ),
      ],
      overdrawn: [
        OverdrawnAccount(accountId: 'a1', name: 'Golak', balance: _rs(-300)),
      ],
      lateUdhaar: [
        LateUdhaar(
          partyId: 'p1',
          name: 'Rashid Traders',
          owed: _rs(9000),
          daysLate: 45,
          phone: '03001234567',
        ),
      ],
      cheques: cheques,
      cancelled: [
        CancelledBill(
          documentId: 'd9',
          docNo: 'INV-9',
          total: _rs(1200),
          party: 'Akbar',
          reason: 'Galti se',
          by: 'Bilal',
        ),
      ],
      belowCost: [
        BelowCostLine(
          documentId: 'd8',
          docNo: 'INV-8',
          itemName: 'Atta 10kg',
          sold: _rs(900),
          cost: _rs(1000),
        ),
      ],
      expired: [
        LotOnHand(
          lotId: 'l1',
          itemId: 'i3',
          itemName: 'Panadol',
          lotNo: 'B-17',
          qty: Qty.units(20),
          cost: Rate.rupees(5),
          expiry: const BusinessDate('2026-09-30'),
        ),
      ],
      lateFbr: [
        LateFbrBill(
          documentId: 'd7',
          docNo: 'INV-7',
          madeOn: const BusinessDate('2026-10-01'),
        ),
      ],
    );

    test('everything odd today is one list, the worst kind first, each a '
        'tap from its screen', () {
      final table = needsAttention(_today, odd, lateDays: 30);
      final lines = table.rows.where((r) => r.style == RowStyle.line).toList();
      expect(lines.map((r) => r.cells.first), [
        'Oversold while set to block',
        'Stock below zero',
        'Money below zero',
        'Not with FBR after 24 hours',
        'Udhaar overdue',
        'Cheque gone stale',
        'Cheque can be banked',
        'Bill cancelled today',
        'Sold below cost today',
        'Expired batch on the shelf',
      ]);
      expect(lines.map((r) => r.link?.kind), [
        ReportLinkKind.item,
        ReportLinkKind.item,
        ReportLinkKind.account,
        ReportLinkKind.screen,
        ReportLinkKind.party,
        ReportLinkKind.screen,
        ReportLinkKind.screen,
        ReportLinkKind.document,
        ReportLinkKind.document,
        ReportLinkKind.item,
      ]);
      expect(_cell(lines[0], table, 'Details'), contains('-1 pcs'));
      expect(_at(lines[2], table, 'Amount'), _rs(-300));
      expect(_cell(lines[4], table, 'Details'), contains('45 days'));
      expect(_at(lines[8], table, 'Amount'), _rs(-100));
      expect(_at(lines[9], table, 'Amount'), _rs(100));
      expect(_cell(lines[7], table, 'Details'), 'Akbar, by Bilal, "Galti se"');
      final total = table.summary.firstWhere(
        (f) => f.label == attentionTotalLabel,
      );
      expect(total.count, 10);
      expect(
        table.summary.firstWhere((f) => f.label == 'Udhaar overdue').count,
        1,
      );
      expect(table.isSortable, isTrue);
    });

    test('a cheque is named when it can be banked and when it has gone '
        'stale, never once at the bank and in date', () {
      expect(chequeIsStale(const BusinessDate('2026-04-03'), _today), isTrue);
      expect(chequeIsStale(const BusinessDate('2026-04-04'), _today), isFalse);
      final table = needsAttention(
        _today,
        ShopExceptions(cheques: cheques),
        lateDays: 30,
      );
      expect(
        table.rows
            .where((r) => r.style == RowStyle.line)
            .map((r) => r.cells[1]),
        ['Akbar', 'Rashid Traders'],
      );
    });

    test('nothing odd today says so', () {
      final table = needsAttention(
        _today,
        const ShopExceptions(),
        lateDays: 15,
      );
      expect(table.rows.single.style, RowStyle.total);
      expect(table.notes.first, 'Nothing odd today.');
      expect(table.notes[1], contains('from 15 days'));
      expect(table.summary.single.count, 0);
    });
  });

  group('the shelf valued four ways', () {
    StockLine line({bool includes = false}) => StockLine(
      itemId: 'i1',
      itemName: 'Ghee 1kg',
      unitCode: 'pcs',
      saleRate: Rate.rupees(590),
      averageCost: Rate.rupees(450),
      qty: Qty.units(10),
      value: _rs(4500),
      taxBp: 1800,
      priceIncludesTax: includes,
    );

    test("at cost it is the books' value; at the sale price, with the tax "
        'or without', () {
      expect(line().valueAt(StockValuation.cost), _rs(4500));
      expect(line().valueAt(StockValuation.costWithTax), _rs(5310));
      expect(line().valueAt(StockValuation.salePrice), _rs(5900));
      expect(line().valueAt(StockValuation.salePriceWithTax), _rs(6962));
      // A price with the tax in it: Rs 5,900 is Rs 5,000 and the tax.
      expect(line(includes: true).valueAt(StockValuation.salePrice), _rs(5000));
      expect(
        line(includes: true).valueAt(StockValuation.salePriceWithTax),
        _rs(5900),
      );
    });

    test('only at cost is it set beside Inventory, and a cashier sees a '
        'value at a price but never at cost', () {
      final atCost = stockSummary(_today, [line()], inBooks: _rs(4500));
      expect(
        atCost.summary.map((f) => f.label),
        contains('Inventory in the books'),
      );
      expect(
        atCost.notes,
        contains('The stock value agrees with Inventory in the books.'),
      );
      final atPrice = stockSummary(
        _today,
        [line()],
        inBooks: _rs(4500),
        valuation: StockValuation.salePriceWithTax,
      );
      expect(_at(atPrice.rows.last, atPrice, 'Value'), _rs(6962));
      expect(
        atPrice.summary.map((f) => f.label),
        isNot(contains('Inventory in the books')),
      );
      expect(atPrice.notes.first, startsWith('Valued at sale price with tax.'));
      expect(
        atPrice.notes.first,
        endsWith('Only the value at cost is Inventory in the books.'),
      );

      final cashier = atPrice.withoutCostColumns();
      expect(cashier.columns.map((c) => c.title), contains('Value'));
      expect(cashier.columns.map((c) => c.title), isNot(contains('Cost')));
      expect(
        atCost.withoutCostColumns().columns.map((c) => c.title),
        isNot(contains('Value')),
      );
      final byCategory = stockSummaryByCategory(_today, [
        line(),
      ], valuation: StockValuation.salePrice);
      expect(byCategory.summary.single.amount, _rs(5900));
      expect(byCategory.summary.single.isCost, isFalse);
      expect(
        const ReportFilters(valuation: StockValuation.salePrice).describe(),
        ['Valued at sale price before tax'],
      );
    });
  });

  group('the period before on a trend', () {
    ReportChart trend(Map<String, int> days) => ReportChart(
      form: ChartForm.trend,
      valueTitle: 'Sales',
      points: [for (final e in days.entries) ChartPoint(e.key, _rs(e.value))],
      total: _rs(days.values.fold(0, (a, b) => a + b)),
    );

    test('a day is set beside the same day of the period before, an hour '
        'beside the same hour', () {
      final now = trend({
        '2026-10-01': 100,
        '2026-10-02': 200,
        '2026-10-03': 0,
      });
      final before = trend({'2026-09-01': 50, '2026-09-02': 70});
      final both = compareWithPrevious(now, before);
      expect(both.previous, [_rs(50), _rs(70), null]);
      expect(both.previousTotal, _rs(120));
      expect(both.points, now.points);
      expect(both.peakWithPrevious, _rs(200));

      final hours = compareWithPrevious(
        trend({'09:00-10:00': 10, '18:00-19:00': 30}),
        trend({'18:00-19:00': 40, '20:00-21:00': 5}),
      );
      expect(hours.previous, [null, _rs(40)]);
      expect(hours.peakWithPrevious, _rs(40));
    });

    test('a ranking and a ring are not compared, nor is nothing', () {
      final ring = ReportChart(
        form: ChartForm.ring,
        valueTitle: 'Sales',
        points: [ChartPoint('Cash', _rs(10))],
        total: _rs(10),
      );
      expect(compareWithPrevious(ring, ring).comparesPrevious, isFalse);
      final now = trend({'2026-10-01': 1});
      expect(compareWithPrevious(now, null).comparesPrevious, isFalse);
    });
  });

  test('a saved view keeps how its table was arranged and the choices M67 '
      'adds', () {
    final view = SavedReportView(
      id: 'v1',
      name: 'Mandi ka udhaar',
      kind: ReportKind.abcClassification,
      preset: DatePreset.thisFiscalYear,
      filters: const ReportFilters(
        abcBasis: AbcBasis.margin,
        abcA: 70,
        abcB: 90,
        valuation: StockValuation.salePrice,
        lateDays: 45,
      ),
      arrangement: const TableArrangement(
        order: ['Sales', 'Item'],
        hidden: {'Rank'},
        filters: [ColumnFilter.contains('Category', 'ghee')],
      ),
    );
    final back = decodeSavedViews(encodeSavedViews([view])).single;
    expect(back, view);
    expect(back.filters.abcA, 70);
    expect(back.arrangement.hidden, {'Rank'});
    // A view saved before M67 arranges nothing.
    final older = SavedReportView.fromJson({
      'id': 'v0',
      'name': 'Old',
      'kind': 'saleReport',
      'preset': 'today',
    })!;
    expect(older.arrangement, TableArrangement.none);
  });
}

final _noPeriod = ReportPeriod.day(_today);
