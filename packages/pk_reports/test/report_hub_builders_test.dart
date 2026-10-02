import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

/// The builders behind the reports hub (M33): the transaction and party
/// reports, the date presets and the filters, each total proved here
/// without a database.
final _september = ReportPeriod(
  const BusinessDate('2026-09-01'),
  const BusinessDate('2026-09-30'),
);

BillRow _bill(
  String no, {
  String type = 'sale_invoice',
  int total = 0,
  int paid = 0,
  int? balance,
  int? taxable,
  int cost = 0,
  String party = 'Rashid Traders',
  List<String> modes = const [],
  String date = '2026-09-10',
}) => BillRow(
  documentId: 'id-$no',
  date: BusinessDate(date),
  docNo: no,
  docType: type,
  party: party,
  taxable: Money.rupees(taxable ?? total),
  tax: Money.zero,
  total: Money.rupees(total),
  paid: Money.rupees(paid),
  balance: Money.rupees(balance ?? total - paid),
  cost: Money.rupees(cost),
  modes: modes,
);

LedgerEntry _entry(String date, String kind, int amount, int after) =>
    LedgerEntry(
      id: '$date$kind',
      kind: kind,
      reference: '${kind.toUpperCase()}-$date',
      dateLocal: date,
      amount: Money.rupees(amount),
      balanceAfter: Money.rupees(after),
    );

PartyTrade _trade(
  String name, {
  String? id,
  String? group,
  int sales = 0,
  int saleReturns = 0,
  int purchases = 0,
  int purchaseReturns = 0,
  int cost = 0,
  int returnedCost = 0,
}) => PartyTrade(
  partyId: id,
  name: name,
  group: group,
  sales: Money.rupees(sales),
  saleReturns: Money.rupees(saleReturns),
  purchases: Money.rupees(purchases),
  purchaseReturns: Money.rupees(purchaseReturns),
  salesTaxable: Money.rupees(sales),
  returnsTaxable: Money.rupees(saleReturns),
  cost: Money.rupees(cost),
  returnedCost: Money.rupees(returnedCost),
);

Object? _cell(ReportTable t, String first, [int column = 1]) =>
    t.rows.firstWhere((r) => r.cells.first == first).cells[column];

/// Answers nothing: the engine must refuse before it reads.
final class _NoSource implements ReportSource {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('read ${invocation.memberName}');
}

void main() {
  group('date presets', () {
    const thursday = BusinessDate('2026-10-01');

    test('a week runs Monday to Sunday', () {
      final week = DatePreset.thisWeek.resolve(thursday)!;
      expect(week.from, const BusinessDate('2026-09-28'));
      expect(week.to, const BusinessDate('2026-10-04'));
    });

    test(
      'yesterday on the first of the month is the last of the one before',
      () {
        expect(
          DatePreset.yesterday.resolve(thursday),
          ReportPeriod.day(const BusinessDate('2026-09-30')),
        );
      },
    );

    test(
      'a quarter is three calendar months, and July opens the fiscal one',
      () {
        expect(
          DatePreset.thisQuarter.resolve(const BusinessDate('2026-08-15')),
          ReportPeriod(
            const BusinessDate('2026-07-01'),
            const BusinessDate('2026-09-30'),
          ),
        );
        expect(
          DatePreset.thisQuarter.resolve(thursday),
          ReportPeriod(
            const BusinessDate('2026-10-01'),
            const BusinessDate('2026-12-31'),
          ),
        );
      },
    );

    test('this fiscal year is July to June, and last year the one before', () {
      expect(
        DatePreset.thisFiscalYear.resolve(const BusinessDate('2027-03-05')),
        ReportPeriod(
          const BusinessDate('2026-07-01'),
          const BusinessDate('2027-06-30'),
        ),
      );
      expect(
        DatePreset.lastFiscalYear.resolve(const BusinessDate('2026-07-01')),
        ReportPeriod(
          const BusinessDate('2025-07-01'),
          const BusinessDate('2026-06-30'),
        ),
      );
      expect(DatePreset.custom.resolve(thursday), isNull);
    });
  });

  group('report filters', () {
    const chosen = ReportFilters(
      partyId: 'p1',
      partyName: 'Rashid Traders',
      userId: 'u1',
      userName: 'Bilal',
      paymentStatus: PaymentStatus.unpaid,
      transactionType: TransactionType.sale,
    );

    test('a report keeps only the filters it accepts', () {
      final kept = chosen.only({ReportFilter.party, ReportFilter.user});
      expect(kept.partyId, 'p1');
      expect(kept.userName, 'Bilal');
      expect(kept.paymentStatus, isNull);
      expect(kept.transactionType, isNull);
      expect(chosen.without(ReportFilter.party).partyId, isNull);
      expect(ReportFilters.none.isEmpty, isTrue);
    });

    test('a narrowed report says so at its head', () async {
      expect(chosen.describe(), [
        'Party: Rashid Traders',
        'Type: Sale',
        'Payment: Unpaid',
        'Entered by: Bilal',
      ]);
      final t = saleReport(_september, const []).withFilters(chosen.describe());
      expect(t.filters.first, 'Party: Rashid Traders');
    });
  });

  group('sale report', () {
    test('every bill with what is received and owed, and whether it is '
        'settled', () {
      final t = saleReport(_september, [
        _bill('INV-1', total: 2500, paid: 2500, modes: ['cash']),
        _bill('INV-2', total: 4000, paid: 1000, modes: ['cash', 'jazzcash']),
        _bill('INV-3', total: 1500),
        _bill('SR-1', type: 'sale_return', total: 500),
      ]);
      expect(t.rows, hasLength(4), reason: 'three bills and the total');
      expect(t.rows[0].cells.sublist(6), ['Cash', 'Paid']);
      expect(t.rows[1].cells.sublist(6), ['Cash, JazzCash', 'Partly paid']);
      expect(t.rows[2].cells.last, 'Unpaid');
      expect(t.rows[0].link?.docType, 'sale_invoice');
      expect(t.totals.single.cells.sublist(1, 6), [
        '3 bills',
        null,
        const Money.rupees(8000),
        const Money.rupees(3500),
        const Money.rupees(4500),
      ]);
      expect(
        [for (final f in t.summary) f.amount],
        [
          const Money.rupees(8000),
          const Money.rupees(3500),
          const Money.rupees(4500),
        ],
      );
    });
  });

  group('purchase report', () {
    test('every delivery with what is paid and what is unpaid', () {
      final t = purchaseReport(_september, [
        _bill('PB-1', type: 'purchase_bill', total: 12000, paid: 2000),
      ]);
      expect(t.columns[4].title, 'Paid');
      expect(t.columns[5].title, 'Unpaid');
      expect(t.summary.first.label, 'Total purchase');
      expect(t.totals.single.cells[5], const Money.rupees(10000));
    });
  });

  group('bill-wise profit', () {
    test('each bill at the cost it left at, and a return takes its profit '
        'back', () {
      final t = billWiseProfit(_september, [
        _bill('INV-1', total: 2500, cost: 1500),
        _bill('INV-2', total: 1000, cost: 1100),
        _bill('SR-1', type: 'sale_return', total: 500, cost: 300),
      ]);
      expect(t.rows[0].cells.sublist(3), [
        const Money.rupees(2500),
        const Money.rupees(1500),
        const Money.rupees(1000),
        4000,
      ]);
      expect(t.rows[2].cells[1], 'SR-1 (return)');
      expect(t.rows[2].cells[5], const Money.rupees(-200));
      expect(t.totals.single.cells.sublist(3, 6), [
        const Money.rupees(3000),
        const Money.rupees(2300),
        const Money.rupees(700),
      ]);
      expect(t.notes, contains('1 bill sold below cost.'));
    });
  });

  group('all transactions', () {
    TransactionRow tx(
      String no,
      String type,
      int total, {
      String status = 'posted',
      int paid = 0,
      int balance = 0,
    }) => TransactionRow(
      id: no,
      date: const BusinessDate('2026-09-10'),
      number: no,
      type: type,
      party: 'Rashid Traders',
      total: Money.rupees(total),
      paid: Money.rupees(paid),
      balance: Money.rupees(balance),
      status: status,
    );

    test(
      'every kind is listed, summed by kind, and a void counted nowhere',
      () {
        final t = allTransactions(_september, [
          tx('INV-1', TransactionType.sale, 2500, paid: 2500),
          tx('INV-2', TransactionType.sale, 1000, status: 'void'),
          tx('RCV-1', TransactionType.paymentIn, 700, status: 'cleared'),
          tx('PB-1', TransactionType.purchase, 4000, balance: 4000),
        ]);
        expect(t.rows[1].cells.last, 'Void');
        expect(t.rows[2].cells[2], 'Payment in');
        expect(t.rows[2].link, isNull, reason: 'a payment is not a bill');
        expect(t.rows[3].cells.last, 'Unpaid');
        expect(_cell(t, '', 4), const Money.rupees(2500), reason: 'sales');
        expect(t.summary.first.count, 3);
        expect(t.summary[1].amount, const Money.rupees(2500));
        expect(t.summary[2].amount, const Money.rupees(4000));
        expect(t.totals.single.cells.last, '1 void');
      },
    );
  });

  group('cash flow', () {
    test('opening, plus what came in, less what went out, is the closing, '
        'for the drawer and the bank apart', () {
      final t = cashflow(
        _september,
        const MoneyBalance(cash: Money.rupees(1000), bank: Money.rupees(5000)),
        const [
          MoneyFlow(
            kind: 'sale',
            inCash: true,
            moneyIn: Money.rupees(2500),
            moneyOut: Money.zero,
          ),
          MoneyFlow(
            kind: 'payment',
            inCash: false,
            moneyIn: Money.rupees(700),
            moneyOut: Money.rupees(3000),
          ),
          MoneyFlow(
            kind: 'expense',
            inCash: true,
            moneyIn: Money.zero,
            moneyOut: Money.rupees(500),
          ),
        ],
      );
      expect(t.rows.first.cells.last, const Money.rupees(6000));
      expect(_cell(t, 'Sales at the counter', 3), const Money.rupees(2500));
      expect(_cell(t, 'Received on khatas', 2), const Money.rupees(700));
      expect(_cell(t, 'Paid to parties', 2), const Money.rupees(3000));
      expect(t.totals.single.cells.sublist(1), [
        const Money.rupees(3000),
        const Money.rupees(2700),
        const Money.rupees(5700),
      ]);
      expect(t.summary.last.amount, const Money.rupees(5700));
    });
  });

  group('profit and loss with stock', () {
    test('opening stock and purchases less closing stock arrive at the cost '
        'of goods sold', () {
      final t = profitAndLoss(
        _september,
        [
          AccountMovement(
            code: '4100',
            name: 'Sales',
            type: 'income',
            systemKey: 'sales',
            debit: Money.zero,
            credit: const Money.rupees(10000),
          ),
          AccountMovement(
            code: '5100',
            name: 'Cost of Goods Sold',
            type: 'expense',
            systemKey: 'cogs',
            isDirect: true,
            debit: const Money.rupees(6000),
            credit: Money.zero,
          ),
          AccountMovement(
            code: '5500',
            name: 'Stock Wastage',
            type: 'expense',
            systemKey: 'stock_wastage',
            isDirect: true,
            debit: const Money.rupees(200),
            credit: Money.zero,
          ),
        ],
        stock: const StockFigures(
          opening: Money.rupees(20000),
          purchases: Money.rupees(8000),
          purchaseReturns: Money.rupees(1000),
          closing: Money.rupees(20800),
        ),
      );
      expect(_cell(t, 'Opening stock'), const Money.rupees(20000));
      expect(_cell(t, 'Purchase returns'), const Money.rupees(-1000));
      expect(_cell(t, 'Closing stock'), const Money.rupees(-20800));
      // 20,000 + 8,000 - 1,000 - 20,800 = 6,200; the books say 6,000 went
      // out as goods sold, so 200 left the shelf otherwise: the wastage.
      expect(_cell(t, 'Stock in or out otherwise'), const Money.rupees(-200));
      expect(_cell(t, 'Cost of goods sold'), const Money.rupees(6000));
      expect(_cell(t, 'Stock Wastage'), const Money.rupees(200));
      expect(_cell(t, 'Total cost of sales'), const Money.rupees(6200));
      expect(t.totals.single.cells, ['Net profit', const Money.rupees(3800)]);
    });
  });

  group('party statement', () {
    final customer = [
      _entry('2026-08-20', 'sale', 5000, 5000),
      _entry('2026-09-03', 'sale', 3000, 8000),
      _entry('2026-09-10', 'payment', -6000, 2000),
      _entry('2026-09-12', 'return', -500, 1500),
    ];

    test('a customer\'s account reads as the khata statement does, returns '
        'included', () {
      final t = partyStatementReport(
        period: _september,
        ledgers: PartyLedgers(
          name: 'Rashid Traders',
          partyType: 'customer',
          receivable: customer,
          payable: const [],
        ),
      );
      final khata = partyStatement(
        partyName: 'Rashid Traders',
        period: _september,
        entries: customer,
      );
      expect(
        [for (final r in t.rows) r.cells],
        [for (final r in khata.rows) r.cells],
      );
      expect(_cell(t, '2026-09-12'), 'Goods returned');
      expect(t.rows.last.cells.last, const Money.rupees(1500));
      expect(t.summary.last.amount, const Money.rupees(1500));
    });

    test('a party on both sides has two accounts, never netted', () {
      final t = partyStatementReport(
        period: _september,
        ledgers: PartyLedgers(
          name: 'Malik Mills',
          partyType: 'both',
          receivable: customer,
          payable: [
            _entry('2026-09-05', 'purchase', 12000, 12000),
            _entry('2026-09-20', 'payment', -2000, 10000),
          ],
        ),
      );
      expect(t.rows.first.cells.first, 'What they owe the shop');
      expect(t.totals, hasLength(2));
      expect(t.totals.last.cells.last, const Money.rupees(10000));
      // The delivery is a credit to their account; the payment a debit.
      final delivery = t.rows.firstWhere((r) => r.cells[1] == 'Delivery');
      expect(delivery.cells.sublist(3, 5), [null, const Money.rupees(12000)]);
      expect(
        [for (final f in t.summary) f.label],
        ['Opening balance', 'Owed to us', 'We owe'],
      );
    });

    test('with no party chosen it asks for one', () {
      final t = partyStatementReport(period: _september, ledgers: null);
      expect(t.rows, isEmpty);
      expect(t.notes.single, contains('Choose a party'));
    });
  });

  group('party reports', () {
    final trades = [
      _trade(
        'Rashid Traders',
        id: 'p1',
        group: 'Wholesale',
        sales: 10000,
        saleReturns: 1000,
        cost: 7000,
        returnedCost: 700,
      ),
      _trade('Walk-in customers', sales: 3000, cost: 2000),
      _trade(
        'Punjab Rice Mills',
        id: 'p2',
        purchases: 20000,
        purchaseReturns: 2000,
      ),
      _trade(
        'Bilal Store',
        id: 'p3',
        group: 'Wholesale',
        sales: 2000,
        cost: 2100,
      ),
    ];

    test('profit by party, the most profitable first, summing to the '
        'period\'s profit', () {
      final t = partyProfitAndLoss(_september, trades);
      expect(t.rows.first.cells.sublist(0, 4), [
        'Rashid Traders',
        const Money.rupees(9000),
        const Money.rupees(6300),
        const Money.rupees(2700),
      ]);
      expect(t.rows.first.link?.kind, ReportLinkKind.party);
      expect(t.rows[2].cells.first, 'Bilal Store');
      expect(t.rows[2].cells[3], const Money.rupees(-100));
      expect(t.totals.single.cells.sublist(1, 4), [
        const Money.rupees(14000),
        const Money.rupees(10400),
        const Money.rupees(3600),
      ]);
      expect(
        t.rows.where((r) => r.cells.first == 'Punjab Rice Mills'),
        isEmpty,
        reason: 'sold nothing to them',
      );
    });

    test('sale and purchase by party, each net of what came back', () {
      final t = salePurchaseByParty(_september, trades);
      expect(_cell(t, 'Rashid Traders'), const Money.rupees(9000));
      expect(_cell(t, 'Punjab Rice Mills', 2), const Money.rupees(18000));
      expect(t.totals.single.cells.sublist(1), [
        const Money.rupees(14000),
        const Money.rupees(18000),
      ]);
    });

    test('by party group, a party with no group is Ungrouped and the '
        'walk-ins are their own row', () {
      final t = salePurchaseByPartyGroup(_september, trades);
      expect(_cell(t, 'Wholesale'), 2);
      expect(_cell(t, 'Wholesale', 2), const Money.rupees(11000));
      expect(_cell(t, 'Ungrouped', 3), const Money.rupees(18000));
      expect(_cell(t, 'Walk-in customers'), 0);
      expect(t.totals.single.cells.sublist(2), [
        const Money.rupees(14000),
        const Money.rupees(18000),
      ]);
    });

    test('every party with the khata\'s balance each way, the settled left '
        'out on request', () {
      const parties = [
        PartyBalanceRow(
          partyId: 'p1',
          name: 'Rashid Traders',
          partyType: 'customer',
          receivable: Money.rupees(4500),
          payable: Money.zero,
          phone: '03001234567',
          creditLimit: Money.rupees(10000),
        ),
        PartyBalanceRow(
          partyId: 'p2',
          name: 'Akbar',
          partyType: 'customer',
          receivable: Money.zero,
          payable: Money.zero,
        ),
        PartyBalanceRow(
          partyId: 'p3',
          name: 'Punjab Rice Mills',
          partyType: 'supplier',
          receivable: Money.zero,
          payable: Money.rupees(18000),
        ),
      ];
      final all = allParties(const BusinessDate('2026-09-30'), parties);
      expect(all.rows.first.cells.first, 'Akbar');
      expect(all.totals.single.cells.sublist(4, 6), [
        const Money.rupees(4500),
        const Money.rupees(18000),
      ]);
      final owing = allParties(
        const BusinessDate('2026-09-30'),
        parties,
        withBalanceOnly: true,
      );
      expect(owing.totals.single.cells[1], '2 parties');
    });

    test('what a party bought and sold, item by item', () {
      final t = partyItemsReport(_september, [
        PartyItemTrade(
          itemName: 'Chawal Basmati',
          unitCode: 'kg',
          qtySold: Qty.units(40),
          saleAmount: const Money.rupees(8000),
          qtyPurchased: Qty.zero,
          purchaseAmount: Money.zero,
        ),
        PartyItemTrade(
          itemName: 'Cheeni',
          unitCode: 'kg',
          qtySold: Qty.zero,
          saleAmount: Money.zero,
          qtyPurchased: Qty.units(100),
          purchaseAmount: const Money.rupees(14000),
        ),
      ], partyName: 'Malik Mills');
      expect(t.title, 'Party report by items: Malik Mills');
      expect(t.rows.first.cells.first, 'Chawal Basmati');
      expect(t.totals.single.cells, [
        'Total',
        null,
        null,
        const Money.rupees(8000),
        null,
        const Money.rupees(14000),
      ]);
    });
  });

  group('report engine', () {
    test('a role that may not see costs is refused every report that shows '
        'them, before anything is read', () async {
      const engine = ReportEngine(_NoSourceConst(), canSeeCosts: false);
      for (final kind in ReportKind.values.where(ReportEngine.showsCost)) {
        await expectLater(
          engine.run(
            kind,
            firmId: 'f',
            period: _september,
            today: const BusinessDate('2026-09-30'),
          ),
          throwsA(isA<PermissionDenied>()),
        );
      }
      expect(ReportEngine.showsCost(ReportKind.billWiseProfit), isTrue);
      expect(ReportEngine.showsCost(ReportKind.saleReport), isFalse);
    });

    test('a party statement with no party reads nothing', () async {
      final t = await ReportEngine(_NoSource()).run(
        ReportKind.partyStatement,
        firmId: 'f',
        period: _september,
        today: const BusinessDate('2026-09-30'),
      );
      expect(t.rows, isEmpty);
    });

    test('sales by item still runs for a role that may not see costs, with '
        'the cost, profit and margin struck out', () async {
      final t = await ReportEngine(_ItemsOnly(), canSeeCosts: false).run(
        ReportKind.salesByItem,
        firmId: 'f',
        period: _september,
        today: const BusinessDate('2026-09-30'),
      );
      expect(
        [for (final c in t.columns) c.title],
        ['Item', 'Qty', 'Unit', 'Sales'],
      );
      expect(t.rows.first.cells, [
        'Cooking Oil 5L',
        Qty.units(2),
        'pcs',
        const Money.rupees(5000),
      ]);
      expect(t.totals.single.cells.last, const Money.rupees(5000));
    });

    test('the period before is the same shape: a month, a quarter, a year, '
        'or as many days', () async {
      expect(
        _september.previous,
        ReportPeriod(
          const BusinessDate('2026-08-01'),
          const BusinessDate('2026-08-31'),
        ),
      );
      expect(
        ReportPeriod.quarterOf(const BusinessDate('2026-08-01')).previous,
        ReportPeriod(
          const BusinessDate('2026-04-01'),
          const BusinessDate('2026-06-30'),
        ),
      );
      expect(
        ReportPeriod.fiscalYearOf(const BusinessDate('2026-08-01')).previous,
        ReportPeriod(
          const BusinessDate('2025-07-01'),
          const BusinessDate('2026-06-30'),
        ),
      );
      expect(
        ReportPeriod(
          const BusinessDate('2026-09-21'),
          const BusinessDate('2026-09-30'),
        ).previous,
        ReportPeriod(
          const BusinessDate('2026-09-11'),
          const BusinessDate('2026-09-20'),
        ),
      );
    });

    test('vs the period before is a percentage of what it was, and nothing '
        'when there was nothing', () async {
      expect(
        changeBp(const Money.rupees(1250), const Money.rupees(1000)),
        2500,
      );
      expect(
        changeBp(const Money.rupees(900), const Money.rupees(1000)),
        -1000,
      );
      expect(changeBp(const Money.rupees(900), Money.zero), isNull);
      final before = await ReportEngine(_ItemsOnly()).previousSummary(
        ReportKind.salesByItem,
        firmId: 'f',
        period: _september,
        today: const BusinessDate('2026-09-30'),
      );
      expect(before, isEmpty, reason: 'sales by item has no headline tiles');
    });
  });

  group('sorting', () {
    test('any column, either way, the total kept at the foot', () {
      final t = saleReport(_september, [
        _bill('INV-1', total: 2500, date: '2026-09-01'),
        _bill('INV-2', total: 9000, date: '2026-09-02'),
        _bill('INV-3', total: 1500, date: '2026-09-03'),
      ]);
      final byTotal = sortedRows(t, 3, ascending: false);
      expect(
        [for (final r in byTotal) r.cells[1]],
        ['INV-2', 'INV-1', 'INV-3', '3 bills'],
      );
      final oldestLast = sortedRows(t, 0, ascending: false);
      expect(oldestLast.first.cells[1], 'INV-3');
      expect(oldestLast.last.style, RowStyle.total);
    });

    test('a report with sections keeps its order', () {
      final t = cashflow(_september, MoneyBalance.zero, const []);
      expect(t.isSortable, isFalse);
      expect(sortedRows(t, 1, ascending: true), same(t.rows));
    });
  });
}

/// Reads one day's selling of oil, and nothing else.
final class _ItemsOnly extends _NoSource {
  @override
  Future<List<ItemSales>> itemSales(String firmId, ReportPeriod period) async =>
      [
        ItemSales(
          itemName: 'Cooking Oil 5L',
          unitCode: 'pcs',
          qtySold: Qty.units(2),
          qtyReturned: Qty.zero,
          salesValue: const Money.rupees(5000),
          returnsValue: Money.zero,
          cost: const Money.rupees(4000),
          returnedCost: Money.zero,
        ),
      ];
}

/// [_NoSource], constant, for a constant engine.
final class _NoSourceConst implements ReportSource {
  const _NoSourceConst();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('read ${invocation.memberName}');
}
