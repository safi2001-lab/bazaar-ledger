import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

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
  systemKey: key,
  isDirect: direct,
  debit: Money.rupees(debit),
  credit: Money.rupees(credit),
);

final _september = ReportPeriod(
  const BusinessDate('2026-09-01'),
  const BusinessDate('2026-09-30'),
);

Object? _cell(ReportTable t, String first, [int column = 1]) =>
    t.rows.firstWhere((r) => r.cells.first == first).cells[column];

void main() {
  group('profit and loss', () {
    final movements = [
      _account('4100', 'Sales', 'income', credit: 100000, key: 'sales'),
      _account('4300', 'Discount Given', 'income', debit: 2000),
      _account(
        '4900',
        'Other Income',
        'income',
        credit: 500,
        key: 'other_income',
      ),
      _account(
        '5100',
        'Cost of Goods Sold',
        'expense',
        debit: 70000,
        key: 'cogs',
        direct: true,
      ),
      _account('6100', 'Rent', 'expense', debit: 15000, key: 'rent'),
      _account('6300', 'Utilities', 'expense', debit: 4000, key: 'utilities'),
    ];

    test('gross and net profit come from the ledger', () {
      final t = profitAndLoss(_september, movements);
      expect(_cell(t, 'Net sales'), const Money.rupees(98000));
      expect(_cell(t, 'Gross profit'), const Money.rupees(28000));
      expect(_cell(t, 'Total other income'), const Money.rupees(500));
      expect(_cell(t, 'Total expenses'), const Money.rupees(19000));
      expect(t.totals.single.cells, ['Net profit', const Money.rupees(9500)]);
      expect(t.notes.first, 'Gross margin 28.57% of net sales.');
    });

    test('a discount given reads as a reduction of sales', () {
      final t = profitAndLoss(_september, movements);
      expect(_cell(t, 'Discount Given'), const Money.rupees(-2000));
    });

    test('a month that lost money says so', () {
      final t = profitAndLoss(_september, [
        _account('4100', 'Sales', 'income', credit: 1000, key: 'sales'),
        _account('6100', 'Rent', 'expense', debit: 15000, key: 'rent'),
      ]);
      expect(t.totals.single.cells, ['Net loss', const Money.rupees(-14000)]);
    });
  });

  group('expenses by head', () {
    test('largest first, with each head as a share, and no cost of goods', () {
      final t = expensesByHead(_september, [
        _account(
          '5100',
          'Cost of Goods Sold',
          'expense',
          debit: 70000,
          key: 'cogs',
          direct: true,
        ),
        _account(
          '5400',
          'Freight and Cartage',
          'expense',
          debit: 1000,
          key: 'freight',
          direct: true,
        ),
        _account('6100', 'Rent', 'expense', debit: 15000, key: 'rent'),
        _account('6300', 'Utilities', 'expense', debit: 4000, key: 'utilities'),
      ]);
      expect(
        [for (final r in t.rows) r.cells.first],
        ['Rent', 'Utilities', 'Freight and Cartage', 'Total'],
      );
      expect(_cell(t, 'Rent', 2), 7500);
      expect(_cell(t, 'Total'), const Money.rupees(20000));
    });
  });

  group('cash book', () {
    test('runs from the opening balance to the closing one', () {
      final t = cashBook(_september, const Money.rupees(5000), [
        const CashMovement(
          date: BusinessDate('2026-09-02'),
          entryNo: 'JV-2627-00001',
          narration: 'Sale INV-2627-0001',
          moneyIn: Money.rupees(2500),
          moneyOut: Money.zero,
        ),
        const CashMovement(
          date: BusinessDate('2026-09-03'),
          entryNo: 'JV-2627-00002',
          narration: 'Expense EXP-2627-0001: rent',
          moneyIn: Money.zero,
          moneyOut: Money.rupees(4000),
        ),
      ]);
      expect(t.rows.first.cells.last, const Money.rupees(5000));
      expect(t.rows[1].cells.last, const Money.rupees(7500));
      expect(t.totals.single.cells, [
        '2026-09-30',
        null,
        'Closing balance',
        const Money.rupees(2500),
        const Money.rupees(4000),
        const Money.rupees(3500),
      ]);
    });
  });

  group('day book', () {
    test('lists every entry and counts them', () {
      final t = dayBook(ReportPeriod.day(const BusinessDate('2026-09-26')), [
        const DayBookEntry(
          date: BusinessDate('2026-09-26'),
          entryNo: 'JV-2627-00001',
          sourceType: 'sale',
          narration: 'Sale INV-2627-0001',
          amount: Money.rupees(2500),
        ),
        const DayBookEntry(
          date: BusinessDate('2026-09-26'),
          entryNo: 'JV-2627-00002',
          sourceType: 'reversal',
          narration: 'Void of INV-2627-0001',
          amount: Money.rupees(2500),
        ),
      ]);
      expect(t.rows[1].cells[2], 'Reversal');
      expect(t.totals.single.cells.skip(3), [
        '2 entries',
        const Money.rupees(5000),
      ]);
    });
  });

  group('sales by item', () {
    test('returns come off, and the best seller is first', () {
      final t = salesByItem(_september, [
        ItemSales(
          itemName: 'Sugar 1kg',
          unitCode: 'pcs',
          qtySold: Qty.units(10),
          qtyReturned: Qty.zero,
          salesValue: const Money.rupees(1600),
          returnsValue: Money.zero,
          cost: const Money.rupees(1400),
          returnedCost: Money.zero,
        ),
        ItemSales(
          itemName: 'Cooking Oil 5L',
          unitCode: 'pcs',
          qtySold: Qty.units(4),
          qtyReturned: Qty.units(1),
          salesValue: const Money.rupees(10000),
          returnsValue: const Money.rupees(2500),
          cost: const Money.rupees(8000),
          returnedCost: const Money.rupees(2000),
        ),
      ]);
      expect(t.rows.first.cells, [
        'Cooking Oil 5L',
        Qty.units(3),
        'pcs',
        const Money.rupees(7500),
        const Money.rupees(6000),
        const Money.rupees(1500),
        2000,
      ]);
      expect(t.totals.single.cells[5], const Money.rupees(1700));
    });
  });

  group('stock value', () {
    test('values the shelf at average cost beside the books', () {
      final t = stockValue(const BusinessDate('2026-09-26'), [
        StockPosition(
          itemName: 'Cooking Oil 5L',
          unitCode: 'pcs',
          qty: Qty.units(10),
          averageCost: Rate.rupees(2000),
        ),
        StockPosition(
          itemName: 'Sugar 1kg',
          unitCode: 'pcs',
          qty: Qty.units(-2),
          averageCost: Rate.rupees(140),
        ),
        StockPosition(
          itemName: 'Tea 200g',
          unitCode: 'pcs',
          qty: Qty.zero,
          averageCost: Rate.rupees(300),
        ),
      ], const Money.rupees(19720));
      expect(t.rows, hasLength(3), reason: 'nothing on the shelf is left out');
      expect(t.totals.single.cells.last, const Money.rupees(19720));
      expect(t.notes, hasLength(2));
      expect(t.notes.last, startsWith('1 item shows less than nothing'));
    });
  });

  group('sales by day', () {
    test('each day in date order, and the period summed', () {
      final t = salesByDay(_september, [
        const DaySales(
          date: BusinessDate('2026-09-03'),
          bills: 2,
          sales: Money.rupees(3000),
          returns: Money.zero,
          received: Money.rupees(1000),
          onUdhaar: Money.rupees(2000),
        ),
        const DaySales(
          date: BusinessDate('2026-09-01'),
          bills: 5,
          sales: Money.rupees(7000),
          returns: Money.rupees(500),
          received: Money.rupees(7000),
          onUdhaar: Money.zero,
        ),
      ]);
      expect(t.rows.first.cells.first, '2026-09-01');
      expect(t.totals.single.cells, [
        'Total',
        7,
        const Money.rupees(10000),
        const Money.rupees(500),
        const Money.rupees(8000),
        const Money.rupees(2000),
      ]);
    });
  });

  group('udhaar by age', () {
    test('the oldest money first, and each owed matches the khata', () {
      final t = receivablesByAge(const BusinessDate('2026-09-26'), [
        const PartyReceivable(
          name: 'Bilal Store',
          opening: Money.zero,
          upTo30: Money.rupees(4000),
          upTo60: Money.zero,
          upTo90: Money.zero,
          over90: Money.zero,
          advance: Money.zero,
        ),
        const PartyReceivable(
          name: 'Rashid Traders',
          opening: Money.rupees(1000),
          upTo30: Money.zero,
          upTo60: Money.zero,
          upTo90: Money.zero,
          over90: Money.rupees(2500),
          advance: Money.rupees(500),
        ),
        const PartyReceivable(
          name: 'Settled Sahib',
          opening: Money.zero,
          upTo30: Money.zero,
          upTo60: Money.zero,
          upTo90: Money.zero,
          over90: Money.zero,
          advance: Money.zero,
        ),
      ]);
      expect(
        [for (final r in t.rows) r.cells.first],
        ['Rashid Traders', 'Bilal Store', 'Total'],
      );
      expect(t.rows.first.cells.sublist(6), [
        const Money.rupees(-500),
        const Money.rupees(3000),
      ]);
      expect(t.totals.single.cells.last, const Money.rupees(7000));
      expect(t.notes, hasLength(3));
    });
  });

  group('periods', () {
    test('a month ends on its last day, February included', () {
      final feb = ReportPeriod.monthOf(const BusinessDate('2028-02-10'));
      expect(feb.label, '2028-02-01 to 2028-02-29');
      final before = ReportPeriod.monthBefore(const BusinessDate('2026-01-15'));
      expect(before.label, '2025-12-01 to 2025-12-31');
    });

    test('the fiscal year runs July to June', () {
      expect(
        ReportPeriod.fiscalYearOf(const BusinessDate('2026-03-01')).label,
        '2025-07-01 to 2026-06-30',
      );
      expect(
        ReportPeriod.fiscalYearOf(const BusinessDate('2026-09-26')).label,
        '2026-07-01 to 2027-06-30',
      );
    });

    test('a row that does not fit its columns is refused', () {
      expect(
        () => ReportTable(
          id: 'x',
          title: 'X',
          period: _september,
          columns: const [ReportColumn('Amount', CellKind.money)],
          rows: const [
            ReportRow(['not money']),
          ],
        ),
        throwsArgumentError,
      );
    });
  });
}
