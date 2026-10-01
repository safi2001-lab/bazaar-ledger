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

  group('owed to suppliers', () {
    test('the same ageing, headed for suppliers', () {
      final t = payablesByAge(const BusinessDate('2026-09-26'), [
        const PartyReceivable(
          name: 'Dalda Distributors',
          opening: Money.zero,
          upTo30: Money.rupees(80000),
          upTo60: Money.rupees(20000),
          upTo90: Money.zero,
          over90: Money.zero,
          advance: Money.zero,
        ),
      ]);
      expect(t.title, 'Owed to suppliers');
      expect(t.columns.first.title, 'Supplier');
      expect(t.totals.single.cells.last, const Money.rupees(100000));
    });
  });

  group('trial balance', () {
    test('each account on its side, and the two sides agree', () {
      final t = trialBalance(const BusinessDate('2026-09-26'), [
        _account('1010', 'Cash in Hand', 'asset', debit: 7000, credit: 1000),
        _account('4100', 'Sales', 'income', credit: 5000, key: 'sales'),
        _account('3050', 'Opening Balances', 'equity', credit: 1000),
        _account('6100', 'Rent', 'expense', debit: 0),
      ]);
      expect(t.rows.first.cells, [
        '1010',
        'Cash in Hand',
        const Money.rupees(6000),
        null,
      ]);
      expect(t.rows, hasLength(4), reason: 'the empty account is left out');
      expect(t.totals.single.cells.sublist(2), [
        const Money.rupees(6000),
        const Money.rupees(6000),
      ]);
      expect(t.notes.single, 'Debits and credits agree.');
    });
  });

  group('balance sheet', () {
    test('what the shop has equals what it owes and what is the owner\'s', () {
      final t = balanceSheet(const BusinessDate('2026-09-26'), [
        _account('1010', 'Cash in Hand', 'asset', debit: 6000),
        _account('1200', 'Inventory', 'asset', debit: 3000),
        _account('2100', 'Payables', 'liability', credit: 2000),
        _account('3050', 'Opening Balances', 'equity', credit: 5000),
        _account('4100', 'Sales', 'income', credit: 5000, key: 'sales'),
        _account(
          '5100',
          'Cost of Goods Sold',
          'expense',
          debit: 3000,
          direct: true,
        ),
      ]);
      expect(_cell(t, 'Total assets'), const Money.rupees(9000));
      expect(_cell(t, 'Total liabilities'), const Money.rupees(2000));
      expect(_cell(t, 'Profit to date'), const Money.rupees(2000));
      expect(t.totals.single.cells.last, const Money.rupees(9000));
      expect(t.notes.first, startsWith('What the shop has equals'));
    });
  });

  group('expiry', () {
    test('expired and soon-to-expire batches, soonest first', () {
      LotOnHand lot(String no, String? expiry) => LotOnHand(
        lotId: no,
        itemId: 'p',
        itemName: 'Panadol strip',
        lotNo: no,
        qty: Qty.units(10),
        cost: Rate.rupees(30),
        expiry: expiry == null ? null : BusinessDate(expiry),
      );
      final t = expiryReport(const BusinessDate('2026-09-26'), [
        lot('FAR', '2027-12-31'),
        lot('SOON', '2026-10-26'),
        lot('GONE', '2026-09-20'),
        lot('NONE', null),
      ]);
      expect([for (final r in t.rows) r.cells[1]], ['GONE', 'SOON', null]);
      expect(t.rows.first.cells[3], -6);
      expect(t.rows[1].cells[3], 30);
      expect(t.totals.single.cells.last, const Money.rupees(600));
      expect(t.notes.first, startsWith('1 batch is past its date'));
    });
  });

  group('tax', () {
    test('the sales tax summary nets what returns gave back', () {
      final t = salesTaxSummary(_september, [
        const TaxLine(
          code: 'ST_STD_18',
          kind: 'sales_tax',
          rateBp: 1800,
          base: Money.rupees(10000),
          amount: Money.rupees(1800),
          isReturn: false,
        ),
        const TaxLine(
          code: 'FURTHER_4',
          kind: 'further_tax',
          rateBp: 400,
          base: Money.rupees(5000),
          amount: Money.rupees(200),
          isReturn: false,
        ),
        const TaxLine(
          code: 'ST_RETURN',
          kind: 'sales_tax',
          rateBp: 0,
          base: Money.rupees(1000),
          amount: Money.rupees(180),
          isReturn: true,
        ),
      ]);
      expect(_cell(t, 'Sales tax owed', 3), const Money.rupees(1620));
      expect(_cell(t, 'Further tax owed', 3), const Money.rupees(200));
      expect(t.totals.single.cells.last, const Money.rupees(1820));
    });

    test('Tajir Dost is one per cent of each month', () {
      final t = tajirDost(_september, {
        '2026-09': const Money.rupees(450000),
        '2026-08': const Money.rupees(300000),
      });
      expect(t.rows.first.cells, [
        '2026-08',
        const Money.rupees(300000),
        const Money.rupees(3000),
      ]);
      expect(t.totals.single.cells.last, const Money.rupees(7500));
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

  group('statement of account', () {
    LedgerEntry e(String date, String kind, int amount, int after) =>
        LedgerEntry(
          id: '$date$kind',
          kind: kind,
          reference: '${kind.toUpperCase()}-$date',
          dateLocal: date,
          amount: Money.rupees(amount),
          balanceAfter: Money.rupees(after),
        );
    final ledger = [
      e('2026-08-20', 'sale', 5000, 5000),
      e('2026-09-03', 'sale', 3000, 8000),
      e('2026-09-10', 'payment', -6000, 2000),
      e('2026-09-25', 'charge', 500, 2500),
      e('2026-10-02', 'sale', 1000, 3500),
    ];

    test('opens on what was owed before, and closes on what is owed at the '
        'end', () {
      final t = partyStatement(
        partyName: 'Rashid Traders',
        period: _september,
        entries: ledger,
      );
      expect(t.title, 'Statement of account: Rashid Traders');
      expect(t.rows.first.cells.last, const Money.rupees(5000));
      expect(t.rows, hasLength(5), reason: 'opening, three in September, end');
      final end = t.rows.last.cells;
      expect(end[3], const Money.rupees(3500), reason: 'billed and charged');
      expect(end[4], const Money.rupees(6000), reason: 'paid');
      expect(end[5], const Money.rupees(2500));
      expect(_cell(t, '2026-09-10', 4), const Money.rupees(6000));
    });

    test('a month with nothing in it still says what is owed', () {
      final t = partyStatement(
        partyName: 'Rashid Traders',
        period: ReportPeriod(
          const BusinessDate('2026-07-01'),
          const BusinessDate('2026-07-31'),
        ),
        entries: ledger,
      );
      expect(t.rows, hasLength(2));
      expect(t.rows.last.cells.last, Money.zero);
    });
  });

  group('purchase register', () {
    test('every bill in the period, returns taken off the totals', () {
      final t = purchaseRegister(_september, [
        PurchaseRegisterLine(
          date: const BusinessDate('2026-09-02'),
          docNo: 'PB-1',
          supplier: 'Punjab Rice Mills',
          supplierBillNo: 'PRM/771',
          supplierNtn: '1234567-8',
          taxable: const Money.rupees(10000),
          tax: const Money.rupees(1800),
          total: const Money.rupees(11800),
          owed: const Money.rupees(5000),
        ),
        PurchaseRegisterLine(
          date: const BusinessDate('2026-09-09'),
          docNo: 'PR-1',
          supplier: 'Punjab Rice Mills',
          taxable: const Money.rupees(1000),
          tax: const Money.rupees(180),
          total: const Money.rupees(1180),
          owed: Money.zero,
          isReturn: true,
        ),
      ]);
      final total = t.rows.last.cells;
      expect(total[5], const Money.rupees(9000));
      expect(total[6], const Money.rupees(1620));
      expect(total[7], const Money.rupees(10620));
      expect(total[8], const Money.rupees(5000));
      expect(t.rows[1].cells[1], 'PR-1 (return)');
      expect(t.rows[1].cells[7], const Money.rupees(-1180));
    });
  });
}
