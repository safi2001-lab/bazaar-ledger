import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

/// The item and stock reports (M34), each total proved here without a
/// database: the stock summary and detail, profit and discount by item and
/// category, what to order, fast and slow stock, stock ageing, serial
/// numbers, and the engine's handling of the day a report is read for.
final _september = ReportPeriod(
  const BusinessDate('2026-09-01'),
  const BusinessDate('2026-09-30'),
);
const _today = BusinessDate('2026-09-26');

StockLine _line(
  String name, {
  int qty = 0,
  int value = 0,
  int sale = 100,
  int avg = 50,
  String? category,
}) => StockLine(
  itemId: 'id-$name',
  itemName: name,
  unitCode: 'pcs',
  category: category,
  saleRate: Rate.rupees(sale),
  averageCost: Rate.rupees(avg),
  qty: Qty.units(qty),
  value: Money.rupees(value),
);

ItemTrade _trade(
  String? name, {
  String? category,
  int sold = 0,
  int returned = 0,
  int gross = 0,
  int discount = 0,
  int sales = 0,
  int returns = 0,
  int cost = 0,
  int returnedCost = 0,
  int bought = 0,
  int purchases = 0,
}) => ItemTrade(
  itemId: name == null ? null : 'id-$name',
  itemName: name ?? ItemTrade.looseLines,
  unitCode: name == null ? '' : 'pcs',
  category: category,
  qtySold: Qty.units(sold),
  qtyReturned: Qty.units(returned),
  salesGross: Money.rupees(gross),
  discount: Money.rupees(discount),
  sales: Money.rupees(sales),
  returns: Money.rupees(returns),
  cost: Money.rupees(cost),
  returnedCost: Money.rupees(returnedCost),
  qtyBought: Qty.units(bought),
  purchases: Money.rupees(purchases),
);

Object? _cell(ReportTable t, String first, String column) => t.rows
    .firstWhere((r) => r.cells.first == first)
    .cells[t.columns.indexWhere((c) => c.title == column)];

Object? _total(ReportTable t, String column) =>
    t.totals.single.cells[t.columns.indexWhere((c) => c.title == column)];

void main() {
  group('stock summary', () {
    test('every item at the value the books carry, beside Inventory', () {
      final t = stockSummary(_today, [
        _line('Sugar', qty: -2, value: -280, category: 'Kiryana'),
        _line('Oil', qty: 6, value: 12000, sale: 2500, avg: 1990),
        _line('Tea', avg: 300),
      ], inBooks: const Money.rupees(11720));
      expect(
        [for (final r in t.rows) r.cells.first],
        ['Oil', 'Sugar', 'Tea', 'Total'],
      );
      expect(_cell(t, 'Oil', 'Cost'), const Money.rupees(2000));
      expect(
        _cell(t, 'Tea', 'Cost'),
        const Money.rupees(300),
        reason: 'nothing on the shelf: its own average',
      );
      expect(_cell(t, 'Oil', 'Category'), 'No category');
      expect(_total(t, 'Value'), const Money.rupees(11720));
      expect(t.summary.last.amount, const Money.rupees(11720));
      expect(t.summary.where((f) => f.isCost), hasLength(2));
      expect(t.notes, contains(startsWith('1 item shows less than nothing')));
      expect(
        t.notes,
        contains('The stock value agrees with Inventory in the books.'),
      );
      final off = stockSummary(_today, [
        _line('Oil', qty: 1, value: 100),
      ], inBooks: const Money.rupees(99));
      expect(off.notes, contains(startsWith('The stock value and Inventory')));
      expect(
        stockSummary(_today, const []).summary.map((f) => f.label),
        ['Items', 'Stock value'],
        reason: 'a narrowed list is not set beside the books',
      );
    });

    test('by category, each the sum of its items', () {
      final t = stockSummaryByCategory(_today, [
        _line('Oil', qty: 6, value: 12000, category: 'Ghee'),
        _line('Banaspati', qty: 2, value: 900, category: 'Ghee'),
        _line('Sugar', qty: 3, value: 420),
      ]);
      expect(_cell(t, 'Ghee', 'Items'), 2);
      expect(_cell(t, 'Ghee', 'Value'), const Money.rupees(12900));
      expect(_cell(t, 'No category', 'Stock'), Qty.units(3));
      expect(_total(t, 'Value'), const Money.rupees(13320));
    });
  });

  group('stock detail', () {
    test('opening, plus in, less out, plus adjusted, is the closing', () {
      final t = stockDetail(
        _september,
        [
          StockFlow(
            itemId: 'oil',
            itemName: 'Oil',
            unitCode: 'pcs',
            openingQty: Qty.units(10),
            openingValue: const Money.rupees(20000),
            moves: StockMoves(
              purchased: Qty.units(4),
              returnsIn: Qty.units(1),
              transfersIn: Qty.units(2),
              sold: Qty.units(5),
              transfersOut: Qty.units(2),
              wasted: Qty.units(1),
              adjusted: Qty.units(-1),
            ),
            movedValue: const Money.rupees(-4000),
          ),
          StockFlow(
            itemId: 'masala',
            itemName: 'Masala',
            unitCode: 'pcs',
            openingQty: Qty.zero,
            openingValue: Money.zero,
            moves: StockMoves(produced: Qty.units(4)),
            movedValue: const Money.rupees(1100),
          ),
        ],
        openingInBooks: const Money.rupees(20000),
        closingInBooks: const Money.rupees(17100),
      );
      expect(_cell(t, 'Oil', 'Closing'), Qty.units(8));
      expect(_cell(t, 'Oil', 'Closing value'), const Money.rupees(16000));
      expect(_cell(t, 'Masala', 'Closing'), Qty.units(4));
      expect(_total(t, 'Closing value'), const Money.rupees(17100));
      expect(_total(t, 'Sold'), Qty.units(5));
      expect(
        t.notes,
        contains(startsWith('The opening and closing values agree')),
      );
    });

    test('one item day by day, each day opening where the last closed', () {
      final t = itemDetail(
        _september,
        ItemHistory(
          itemId: 'oil',
          itemName: 'Oil',
          unitCode: 'pcs',
          openingQty: Qty.units(10),
          days: [
            ItemDay(
              date: const BusinessDate('2026-09-26'),
              moves: StockMoves(sold: Qty.units(5), returnsIn: Qty.units(1)),
            ),
            ItemDay(
              date: const BusinessDate('2026-09-02'),
              moves: StockMoves(purchased: Qty.units(12)),
            ),
          ],
        ),
      );
      expect(
        [for (final r in t.rows) (r.cells[0], r.cells[1], r.cells.last)],
        [
          ('2026-09-02', Qty.units(10), Qty.units(22)),
          ('2026-09-26', Qty.units(22), Qty.units(18)),
          ('Total', Qty.units(10), Qty.units(18)),
        ],
      );
      expect(itemDetail(_september, null).notes.single, startsWith('Choose'));
    });
  });

  group('profit and discount by item', () {
    final trades = [
      _trade(
        'Oil',
        category: 'Ghee',
        sold: 5,
        returned: 1,
        sales: 12500,
        returns: 2500,
        cost: 10000,
        returnedCost: 2000,
        gross: 12500,
        discount: 435,
      ),
      _trade('Phone', category: 'Mobiles', sold: 1, sales: 30000, cost: 25000),
      _trade('Sugar', sold: 2, sales: 300, cost: 320, gross: 320, discount: 20),
      _trade(null, sold: 3, sales: 450, gross: 500, discount: 50),
      _trade('Rice', bought: 30, purchases: 3600),
    ];

    test('item-wise, most profitable first, khula maal at no cost of its own, '
        'the total the bills\' profit', () {
      final t = itemProfitAndLoss(_september, trades);
      expect(
        [for (final r in t.rows) r.cells.first],
        ['Phone', 'Oil', ItemTrade.looseLines, 'Sugar', 'Total'],
      );
      expect(_cell(t, 'Oil', 'Qty sold'), Qty.units(4));
      expect(_cell(t, 'Oil', 'Profit'), const Money.rupees(2000));
      expect(_cell(t, 'Oil', 'Margin'), 2000);
      final loose = t.rows.firstWhere(
        (r) => r.cells.first == ItemTrade.looseLines,
      );
      expect(loose.cells.sublist(2, 8), [
        null,
        '',
        const Money.rupees(450),
        null,
        const Money.rupees(450),
        null,
      ]);
      expect(loose.link, isNull);
      expect(_total(t, 'Sales'), const Money.rupees(40750));
      expect(_total(t, 'Profit'), const Money.rupees(7430));
      expect(t.notes, contains('1 item sold below cost.'));
      expect(t.notes, contains(startsWith(ItemTrade.looseLines)));
      expect(t.rows.first.link?.kind, ReportLinkKind.item);
    });

    test('category-wise, each the sum of its items, khula maal under no '
        'category', () {
      final items = itemProfitAndLoss(_september, trades);
      final t = categoryProfitAndLoss(_september, trades);
      expect(_total(t, 'Profit'), _total(items, 'Profit'));
      expect(_total(t, 'Sales'), _total(items, 'Sales'));
      expect(_cell(t, 'No category', 'Items'), 1, reason: 'sugar alone');
      expect(_cell(t, 'No category', 'Sales'), const Money.rupees(750));
      expect(_cell(t, 'Mobiles', 'Profit'), const Money.rupees(5000));
    });

    test('sale and purchase by category, khula maal counted in money only', () {
      final t = salePurchaseByCategory(_september, trades);
      expect(_cell(t, 'No category', 'Sold qty'), Qty.units(2));
      expect(_cell(t, 'No category', 'Sale amount'), const Money.rupees(750));
      expect(
        _cell(t, 'No category', 'Purchase amount'),
        const Money.rupees(3600),
      );
      expect(_total(t, 'Sale amount'), const Money.rupees(40750));
    });

    test(
      'item-wise discount, the biggest first, each a share of the price',
      () {
        final t = itemDiscount(_september, trades);
        expect(
          [for (final r in t.rows) r.cells.first],
          ['Oil', ItemTrade.looseLines, 'Sugar', 'Total'],
        );
        expect(_cell(t, 'Oil', 'Discount %'), 348);
        expect(_cell(t, 'Oil', 'After discount'), const Money.rupees(12065));
        expect(_total(t, 'Discount'), const Money.rupees(505));
        expect(t.summary.first.amount, const Money.rupees(505));
      },
    );
  });

  group('what to order', () {
    LowStockLine low(int stock, int min, int sold) => LowStockLine(
      itemId: 'sugar',
      itemName: 'Sugar',
      unitCode: 'kg',
      minStock: Qty.units(min),
      stock: Qty.units(stock),
      sold: Qty.units(sold),
    );

    test('a fortnight of selling less the shelf, never less than the floor, '
        'in whole units rounded up', () {
      Qty order(LowStockLine l) => reorderQty(l, salesDays: 30, coverDays: 15);
      expect(order(low(3, 10, 2)), Qty.units(7), reason: 'up to the floor');
      expect(order(low(3, 10, 61)), Qty.units(28), reason: '30.5 for cover');
      expect(order(low(0, 5, 0)), Qty.units(5));
      expect(order(low(-2, 5, 0)), Qty.units(7), reason: 'below nothing');
      expect(
        reorderQty(
          LowStockLine(
            itemId: 'atta',
            itemName: 'Atta',
            unitCode: 'kg',
            minStock: Qty.units(10),
            stock: const Qty.parts(9, 500),
            sold: Qty.zero,
          ),
          salesDays: 30,
          coverDays: 15,
        ),
        Qty.units(1),
        reason: 'half a kilo short is a kilo to order',
      );
    });

    test('the low stock list, worst first, with its arithmetic below it', () {
      final t = lowStockSummary(
        _today,
        [
          low(8, 10, 2),
          LowStockLine(
            itemId: 'oil',
            itemName: 'Oil',
            unitCode: 'pcs',
            minStock: Qty.units(10),
            stock: Qty.units(1),
            sold: Qty.units(30),
            lastSupplier: 'Akbari Mandi',
          ),
        ],
        salesDays: 30,
        coverDays: 15,
      );
      expect(t.rows.first.cells.first, 'Oil');
      expect(_cell(t, 'Oil', 'Order'), Qty.units(14));
      expect(_cell(t, 'Oil', 'Short by'), Qty.units(9));
      expect(t.summary.first.count, 2);
      expect(t.notes.first, contains('last 30 days, times 15 days'));
    });
  });

  group('fast, slow and dead stock', () {
    test('banded by bills, with the money tied up in each band', () {
      expect(bandFor(0, fastAt: 10, slowBelow: 3), MovementBand.dead);
      expect(bandFor(2, fastAt: 10, slowBelow: 3), MovementBand.slow);
      expect(bandFor(3, fastAt: 10, slowBelow: 3), MovementBand.medium);
      expect(bandFor(10, fastAt: 10, slowBelow: 3), MovementBand.fast);

      ItemSelling selling(String name, int bills, int value) => ItemSelling(
        itemId: name,
        itemName: name,
        unitCode: 'pcs',
        bills: bills,
        qtySold: Qty.units(bills),
        stock: Qty.units(1),
        value: Money.rupees(value),
        lastSold: bills == 0 ? null : _today,
      );
      final t = fastSlowStock(_today, [
        selling('Chilli', 0, 1200),
        selling('Oil', 12, 12000),
        selling('Salt', 1, 400),
        selling('Rice', 4, 2880),
      ]);
      expect(
        [for (final r in t.rows) r.cells[2]],
        ['Fast', 'Medium', 'Slow', 'Not sold', null],
      );
      expect(_cell(t, 'Chilli', 'Last sold'), 'Never');
      expect(t.period.from.value, '2026-06-29', reason: 'ninety days');
      expect(t.summary.first.count, 1);
      expect(
        t.summary.firstWhere((f) => f.label == 'Not sold: value').amount,
        const Money.rupees(1200),
      );
      expect(t.withoutCostColumns().summary.map((f) => f.label), ['Not sold']);
    });
  });

  group('stock ageing', () {
    test('first in, first out, each band its share of the value, the rest '
        'the oldest', () {
      final t = stockAgeing(_today, [
        ItemAgeing(
          itemId: 'oil',
          itemName: 'Oil',
          unitCode: 'pcs',
          onHand: Qty.units(6),
          value: const Money.rupees(12000),
          buckets: [Qty.units(1), Qty.zero, Qty.zero, Qty.units(5)],
        ),
        ItemAgeing(
          itemId: 'tea',
          itemName: 'Tea',
          unitCode: 'pcs',
          onHand: Qty.units(4),
          value: const Money.rupees(1000),
          buckets: [Qty.units(1), Qty.units(1), Qty.zero, Qty.zero],
        ),
      ]);
      expect(_cell(t, 'Oil', '0-45 days'), const Money.rupees(2000));
      expect(_cell(t, 'Oil', 'Over 180 days'), const Money.rupees(10000));
      expect(
        _cell(t, 'Tea', 'Over 180 days'),
        const Money.rupees(500),
        reason: 'two the receipts on record do not reach',
      );
      expect(_total(t, 'Value'), const Money.rupees(13000));
      expect(
        Money.sum([for (final band in ageBands) _total(t, band)! as Money]),
        const Money.rupees(13000),
      );
    });
  });

  group('serial numbers', () {
    SerialLine piece({
      int onHand = 0,
      String? lastOut,
      String? sold,
      String? returned,
    }) => SerialLine(
      serial: 'IMEI-1',
      itemId: 'phone',
      itemName: 'Phone',
      onHand: Qty.units(onHand),
      lastOut: lastOut,
      soldOn: sold == null ? null : BusinessDate(sold),
      returnedOn: returned == null ? null : BusinessDate(returned),
    );

    test('here, back from a customer, sold, sent back or written off', () {
      expect(serialStatus(piece(onHand: 1)), SerialStatus.inStock);
      expect(
        serialStatus(
          piece(onHand: 1, sold: '2026-09-01', returned: '2026-09-03'),
        ),
        SerialStatus.backFromCustomer,
      );
      expect(serialStatus(piece(lastOut: 'sale')), SerialStatus.sold);
      expect(
        serialStatus(piece(lastOut: 'purchase_return')),
        SerialStatus.sentBack,
      );
      expect(serialStatus(piece(lastOut: 'wastage')), SerialStatus.writtenOff);
    });
  });

  group('item and stock reports in the engine', () {
    test('a day gone by is what a stock report is read as at, and an item '
        'report with no item reads nothing', () async {
      final source = _Recording();
      final engine = ReportEngine(source);
      final t = await engine.run(
        ReportKind.stockSummary,
        firmId: 'f',
        period: _september,
        today: _today,
        filters: const ReportFilters(asOf: BusinessDate('2026-08-31')),
      );
      expect(source.asOf, ['2026-08-31', '2026-08-31']);
      expect(t.period.to.value, '2026-08-31');
      expect(t.filters, ['As at the close of 2026-08-31']);
      for (final kind in [ReportKind.itemDetail, ReportKind.itemByParty]) {
        final none = await ReportEngine(
          _Recording(),
        ).run(kind, firmId: 'f', period: _september, today: _today);
        expect(none.rows, isEmpty);
      }
      expect(ReportEngine.isAsOfToday(ReportKind.stockSummary), isTrue);
      expect(ReportEngine.isAsOfToday(ReportKind.stockDetail), isFalse);
      for (final kind in [
        ReportKind.itemProfitAndLoss,
        ReportKind.categoryProfitAndLoss,
        ReportKind.stockAgeing,
      ]) {
        expect(ReportEngine.showsCost(kind), isTrue, reason: '$kind');
      }
      expect(ReportEngine.showsCost(ReportKind.stockSummary), isFalse);
    });

    test('the stock filters are kept only by a report that takes them', () {
      const all = ReportFilters(
        location: 'GODOWN',
        inStockOnly: true,
        asOf: BusinessDate('2026-08-31'),
        salesDays: 60,
        coverDays: 30,
        fastAt: 20,
        slowBelow: 5,
        serial: '4471',
      );
      expect(all.only(const {}).isEmpty, isTrue);
      final kept = all.only(const {ReportFilter.location, ReportFilter.serial});
      expect(kept.location, 'GODOWN');
      expect(kept.serial, '4471');
      expect(kept.salesDays, isNull);
      expect(all.without(ReportFilter.asOf).asOf, isNull);
      expect(all.describe(), containsAll(['Place: GODOWN', 'Serial: 4471']));
      expect(const ReportFilters(location: 'MAIN').describe(), [
        'Place: Shop floor',
      ]);
    });
  });
}

/// Answers the stock summary's reads, and says which day it was asked for.
final class _Recording implements ReportSource {
  final asOf = <String>[];

  @override
  Future<List<StockLine>> stockLines(
    String firmId,
    BusinessDate asOf, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    this.asOf.add(asOf.value);
    return const [];
  }

  @override
  Future<Money> inventoryAsOf(String firmId, BusinessDate asOf) async {
    this.asOf.add(asOf.value);
    return Money.zero;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('read ${invocation.memberName}');
}
