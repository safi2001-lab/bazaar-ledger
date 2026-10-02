import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

/// The builders behind the business status, staff and time, tax, expense
/// and order reports, and the night's Z report (M35), each total proved
/// here without a database.
final _september = ReportPeriod(
  const BusinessDate('2026-09-01'),
  const BusinessDate('2026-09-30'),
);
const _today = BusinessDate('2026-09-26');

Money _rs(int rupees) => Money.rupees(rupees);

Object? _cell(ReportTable t, String first, [int column = 1]) =>
    t.rows.firstWhere((r) => r.cells.first == first).cells[column];

List<ReportRow> _lines(ReportTable t) =>
    t.rows.where((r) => r.style == RowStyle.line).toList();

StaffSales _staff(
  String name, {
  int bills = 0,
  int sales = 0,
  int before = 0,
  int discount = 0,
  int discounted = 0,
  int returns = 0,
  int returned = 0,
  int voids = 0,
  int voided = 0,
}) => StaffSales(
  id: 'id-$name',
  name: name,
  detail: 'cashier',
  bills: bills,
  sales: _rs(sales),
  salesBeforeDiscount: _rs(before),
  discount: _rs(discount),
  discountedBills: discounted,
  returns: returns,
  returnsValue: _rs(returned),
  voids: voids,
  voidsValue: _rs(voided),
);

AnnexLine _annex({
  String type = 'sale_invoice',
  String? party = 'Rashid Traders',
  bool registered = false,
  String? ntn,
  String? cnic,
  String? hs = '1006.3090',
  String unit = 'kg',
  int value = 1000,
  int salesTax = 180,
  int furtherTax = 0,
  int? rateBp = 1800,
  String? code = 'ST_STD_18',
  String? rule,
  String? reference,
  String? reason,
}) => AnnexLine(
  documentId: 'doc',
  docType: type,
  docNo: 'INV-0001',
  date: const BusinessDate('2026-09-15'),
  partyName: party,
  ntn: ntn,
  cnic: cnic,
  isRegistered: registered,
  partyProvince: 'Sindh',
  shopProvince: 'punjab',
  hsCode: hs,
  itemName: 'Chawal Basmati',
  qty: Qty.units(10),
  unitCode: unit,
  value: _rs(value),
  salesTax: _rs(salesTax),
  furtherTax: _rs(furtherTax),
  salesTaxRateBp: rateBp,
  taxCode: code,
  exemptRule: rule,
  reference: reference,
  reason: reason,
);

ExpenseVoucher _voucher(
  String note, {
  String head = 'Utilities',
  bool direct = false,
  int amount = 100,
  String date = '2026-09-10',
  int owed = 0,
}) => ExpenseVoucher(
  documentId: 'exp-$note-$date',
  date: BusinessDate(date),
  docNo: 'EXP-$date',
  headId: 'head-$head',
  head: head,
  isDirect: direct,
  paidFrom: 'Golak',
  amount: _rs(amount),
  balance: _rs(owed),
  note: note,
);

void main() {
  group('bank statement', () {
    test('opening, every deposit and withdrawal with the balance after it, '
        'and the closing', () {
      final t = bankStatement(_september, [
        BankStatementAccount(
          accountId: 'bank',
          name: 'Meezan Bank',
          kind: 'bank',
          opening: _rs(10000),
          lines: [
            BankLine(
              date: const BusinessDate('2026-09-03'),
              description: 'Received from Rashid',
              reference: 'RCPT-0004',
              party: 'Rashid Traders',
              deposit: _rs(5000),
              withdrawal: Money.zero,
            ),
            BankLine(
              date: const BusinessDate('2026-09-09'),
              description: 'Paid to Punjab Rice Mills',
              party: 'Punjab Rice Mills',
              deposit: Money.zero,
              withdrawal: _rs(3000),
            ),
          ],
        ),
      ]);
      expect(t.title, 'Bank statement: Meezan Bank');
      final lines = _lines(t);
      expect(lines.map((r) => r.cells.last), [_rs(15000), _rs(12000)]);
      expect(lines.first.cells[1], 'Received from Rashid RCPT-0004');
      expect(lines.first.cells[3], isNull, reason: 'no withdrawal');
      final closing = t.totals.single;
      expect(closing.cells.sublist(3), [_rs(3000), _rs(5000), _rs(12000)]);
      expect(t.summary.map((f) => f.amount), [
        _rs(10000),
        _rs(5000),
        _rs(3000),
        _rs(12000),
      ]);
    });

    test('several accounts are each a section, and all of them a total', () {
      BankStatementAccount account(String name, int opening, int deposit) =>
          BankStatementAccount(
            accountId: name,
            name: name,
            kind: 'wallet',
            opening: _rs(opening),
            lines: [
              BankLine(
                date: _today,
                description: 'Sale',
                deposit: _rs(deposit),
                withdrawal: Money.zero,
              ),
            ],
          );
      final t = bankStatement(_september, [
        account('Bank', 100, 50),
        account('Mobile wallets', 0, 25),
      ]);
      expect(t.rows.where((r) => r.style == RowStyle.heading), hasLength(2));
      expect(t.totals.single.cells.sublist(1), [
        'All accounts',
        null,
        Money.zero,
        _rs(75),
        _rs(175),
      ]);
      expect(t.isSortable, isFalse);
    });

    test('with no account used, it says so rather than showing nothing', () {
      final t = bankStatement(_september, const []);
      expect(t.totals.single.cells[1], 'No bank or wallet account');
    });
  });

  group('discounts', () {
    test('by party: the most given first, as a share of the bills before '
        'it, and what suppliers took off', () {
      final t = discountByParty(_september, [
        PartyDiscount(
          name: 'Walk-in customers',
          saleBills: 3,
          salesBeforeDiscount: _rs(1000),
          discountGiven: _rs(50),
          purchaseBills: 0,
          purchasesBeforeDiscount: Money.zero,
          discountReceived: Money.zero,
        ),
        PartyDiscount(
          partyId: 'rashid',
          name: 'Rashid Traders',
          saleBills: 2,
          salesBeforeDiscount: _rs(4000),
          discountGiven: _rs(400),
          purchaseBills: 1,
          purchasesBeforeDiscount: _rs(2000),
          discountReceived: _rs(100),
        ),
        PartyDiscount(
          partyId: 'akbar',
          name: 'Akbar',
          saleBills: 0,
          salesBeforeDiscount: Money.zero,
          discountGiven: Money.zero,
          purchaseBills: 0,
          purchasesBeforeDiscount: Money.zero,
          discountReceived: Money.zero,
        ),
      ]);
      expect(
        _lines(t).map((r) => r.cells.first),
        ['Rashid Traders', 'Walk-in customers'],
        reason: 'a party with no discount either way is left out',
      );
      expect(_cell(t, 'Rashid Traders', 4), 1000, reason: '400 of 4,000');
      expect(_lines(t).first.link?.id, 'rashid');
      expect(_cell(t, 'Total', 3), _rs(450));
      expect(_cell(t, 'Total', 6), _rs(100));
    });

    test('by cashier: the highest share first, each bill for whoever rang '
        'it', () {
      final t = discountByCashier(_september, [
        _staff('Malik', bills: 10, before: 10000, discount: 100),
        _staff('Bilal', bills: 4, before: 2000, discount: 200, discounted: 4),
        _staff('Nobody', bills: 0),
      ]);
      expect(_lines(t).map((r) => r.cells.first), ['Bilal', 'Malik']);
      expect(_cell(t, 'Bilal', 6), 1000);
      expect(_cell(t, 'Total', 5), _rs(300));
      expect(_cell(t, 'Total', 6), 250, reason: '300 of 12,000');
    });
  });

  group('how customers pay', () {
    test('the average days to pay, the late ones and the overdue, the '
        'slowest first', () {
      final t = paymentPerformance(_september, _today, [
        PaymentRecord(
          partyId: 'akbar',
          name: 'Akbar',
          creditDays: 30,
          udhaarBills: 3,
          settledBills: 2,
          daysToSettle: 75,
          paidLate: 1,
          overdueBills: 0,
          overdue: Money.zero,
          open: _rs(500),
        ),
        PaymentRecord(
          partyId: 'rashid',
          name: 'Rashid Traders',
          creditDays: 15,
          udhaarBills: 2,
          settledBills: 0,
          daysToSettle: 0,
          paidLate: 0,
          overdueBills: 1,
          overdue: _rs(3000),
          open: _rs(3000),
        ),
      ]);
      expect(_lines(t).map((r) => r.cells.first), ['Rashid Traders', 'Akbar']);
      expect(_cell(t, 'Akbar', 4), 38, reason: '75 days over 2 bills');
      expect(_cell(t, 'Rashid Traders', 4), isNull, reason: 'none settled');
      expect(_cell(t, 'Total', 4), 38);
      expect(_cell(t, 'Total', 7), _rs(3000));
      expect(t.summary.map((f) => f.label), [
        'Udhaar bills',
        'Average days to pay',
        'Overdue',
      ]);
    });

    test('the defaulters, the most overdue first, with the days past due', () {
      final t = defaulterList(_today, [
        DefaulterRow(
          partyId: 'akbar',
          name: 'Akbar',
          creditDays: 30,
          open: _rs(800),
          overdue: _rs(800),
          overdueBills: 1,
          oldestBill: const BusinessDate('2026-08-01'),
        ),
        DefaulterRow(
          partyId: 'rashid',
          name: 'Rashid Traders',
          phone: '0300 4471203',
          creditDays: 7,
          open: _rs(5000),
          overdue: _rs(2000),
          overdueBills: 1,
          oldestBill: const BusinessDate('2026-09-10'),
          creditLimit: _rs(10000),
          lastPayment: const BusinessDate('2026-09-20'),
        ),
      ]);
      expect(_lines(t).map((r) => r.cells.first), ['Rashid Traders', 'Akbar']);
      expect(_cell(t, 'Akbar', 4), 26, reason: '56 days old, 30 allowed');
      expect(_cell(t, 'Akbar', 9), 'Never');
      expect(_cell(t, 'Rashid Traders', 4), 9);
      expect(_cell(t, 'Total', 6), _rs(2800));
      expect(t.period.label, '2026-09-26');
    });
  });

  group('staff and time', () {
    test('sales by cashier: bills, average, discount, returns, voids and '
        'net, the biggest first', () {
      final t = salesByStaff(_september, [
        _staff('Bilal', bills: 2, sales: 1001, returns: 1, returned: 100),
        _staff('Malik', bills: 3, sales: 3000, voids: 1, voided: 500),
      ], by: StaffGrouping.user);
      expect(t.id, 'sales_by_cashier');
      expect(_lines(t).map((r) => r.cells.first), ['Malik', 'Bilal']);
      expect(_cell(t, 'Bilal', 4), Money.paisa(50050));
      expect(_cell(t, 'Bilal', 10), _rs(901));
      expect(_cell(t, 'Malik', 8), 1);
      expect(_cell(t, 'Total', 3), _rs(4001));
      expect(_cell(t, 'Total', 10), _rs(3901));
      final byCounter = salesByStaff(_september, [
        _staff('Counter 1', bills: 1, sales: 10),
      ], by: StaffGrouping.device);
      expect(byCounter.columns.first.title, 'Counter');
      expect(byCounter.title, 'Sales by counter');
    });

    test('each tender of a split bill is its own line, and the sales paid '
        'add up to the sales with the udhaar', () {
      final t = paymentModeSummary(_september, [
        TenderTotal(
          mode: 'jazzcash',
          counterCount: 1,
          counter: _rs(300),
          khataCount: 0,
          khata: Money.zero,
        ),
        TenderTotal(
          mode: 'cash',
          counterCount: 2,
          counter: _rs(1500),
          khataCount: 1,
          khata: _rs(2000),
        ),
      ], UdhaarGiven(bills: 1, amount: _rs(200)));
      expect(_lines(t).map((r) => r.cells.first), [
        'Cash',
        'JazzCash',
        'Udhaar',
      ]);
      expect(_cell(t, 'Cash', 1), 3);
      expect(_cell(t, 'Cash', 4), _rs(3500));
      expect(_cell(t, 'Udhaar', 2), _rs(200));
      expect(_cell(t, 'Udhaar', 4), isNull, reason: 'udhaar is not money');
      expect(_cell(t, 'Total', 2), _rs(2000), reason: '1,800 paid + 200');
      expect(_cell(t, 'Total', 4), _rs(3800));
      expect(t.summary.map((f) => f.amount), [_rs(2000), _rs(3800), _rs(200)]);
    });

    test('hourly sales fill the quiet hours between the first and the last, '
        'and name the busiest', () {
      final t = hourlySales(_september, [
        HourSales(hour: 9, bills: 2, sales: _rs(1000)),
        HourSales(hour: 12, bills: 1, sales: _rs(3000)),
      ]);
      expect(_lines(t).map((r) => r.cells.first), [
        '09:00-10:00',
        '10:00-11:00',
        '11:00-12:00',
        '12:00-13:00',
      ]);
      expect(_cell(t, '10:00-11:00', 2), Money.zero);
      expect(_cell(t, '12:00-13:00', 4), 7500);
      expect(_cell(t, 'Total', 3), _rs(1333) + Money.paisa(33));
      expect(t.notes.first, contains('12:00-13:00'));
      expect(hourLabel(23), '23:00-00:00');
    });

    test('the Z report: sales less returns, money by mode, udhaar, '
        'expenses, profit and the drawer', () {
      final day = DayFigures(
        bills: 3,
        sales: _rs(10000),
        returns: 1,
        returnsValue: _rs(500),
        discount: _rs(100),
        linesSold: 7,
        salesTaxable: _rs(10000),
        salesCost: _rs(7000),
        returnsTaxable: _rs(500),
        returnsCost: _rs(400),
        expenses: 1,
        expensesValue: _rs(1000),
        tenders: [
          TenderTotal(
            mode: 'cash',
            counterCount: 2,
            counter: _rs(6000),
            khataCount: 1,
            khata: _rs(2000),
          ),
        ],
        udhaar: UdhaarGiven(bills: 1, amount: _rs(4000)),
        counts: [
          DrawerCount(
            time: '21:40',
            expected: _rs(7000),
            counted: _rs(6900),
            closedBy: 'Malik Sahib',
          ),
        ],
      );
      final t = dailySummary(ReportPeriod.day(_today), day, showProfit: true);
      expect(t.title, 'Day summary (Z report)');
      expect(_cell(t, 'Sales, 3 bills'), _rs(10000));
      expect(_cell(t, 'Returns, 1 return'), -_rs(500));
      expect(_cell(t, 'Net sales'), _rs(9500));
      expect(_cell(t, 'Cash'), _rs(8000));
      expect(_cell(t, 'Given, 1 bill'), _rs(4000));
      expect(_cell(t, 'Recovered'), _rs(2000));
      expect(_cell(t, 'Gross profit'), _rs(2900));
      expect(_cell(t, 'Short'), _rs(100));
      expect(t.columns, hasLength(2), reason: 'one line on a 58mm roll');

      final cashier = dailySummary(
        ReportPeriod.day(_today),
        day,
        showProfit: false,
      );
      expect(cashier.rows.any((r) => r.cells.first == 'Gross profit'), isFalse);
      expect(
        cashier.summary.map((f) => f.label),
        isNot(contains('Gross profit')),
      );
    });

    test('a day not closed says so', () {
      final t = dailySummary(
        ReportPeriod.day(_today),
        const DayFigures(
          bills: 0,
          sales: Money.zero,
          returns: 0,
          returnsValue: Money.zero,
          discount: Money.zero,
          linesSold: 0,
          salesTaxable: Money.zero,
          salesCost: Money.zero,
          returnsTaxable: Money.zero,
          returnsCost: Money.zero,
          expenses: 0,
          expensesValue: Money.zero,
          tenders: [],
          udhaar: UdhaarGiven.none,
          counts: [],
        ),
        showProfit: true,
      );
      expect(t.rows.any((r) => r.cells.first == 'Not closed yet'), isTrue);
    });

    test('changed and cancelled bills say what, who, when and why', () {
      final t = changedBills(_september, [
        const ChangeRecord(
          date: _today,
          time: '14:15',
          action: 'DOCUMENT_VOIDED',
          who: 'Bilal',
          summary: 'Voided INV-0004',
          reference: 'INV-0004',
          amount: Money.rupees(2500),
          reason: 'Rung by mistake',
          documentId: 'inv4',
          docType: 'sale_invoice',
        ),
        const ChangeRecord(
          date: _today,
          time: '15:00',
          action: 'SALE_RETURNED',
          who: 'Malik',
          summary: 'Return',
        ),
        const ChangeRecord(
          date: _today,
          time: '16:00',
          action: 'EXPENSE_EDITED',
          who: 'Malik',
          summary: 'Edited',
        ),
      ]);
      expect(_lines(t).first.cells.sublist(2), [
        'Voided',
        'INV-0004',
        '',
        const Money.rupees(2500),
        'Bilal',
        'Rung by mistake',
      ]);
      expect(_lines(t).first.link?.id, 'inv4');
      expect(t.summary.map((f) => f.count), [1, 1, 1]);
    });
  });

  group('taxes', () {
    test('the tax report: output tax less returns against input tax, by '
        'party with NTN and STRN', () {
      final t = taxReport(_september, [
        PartyTax(
          partyId: 'rashid',
          name: 'Rashid Traders',
          ntn: '1234567-8',
          salesValue: _rs(10000),
          salesTax: _rs(1800),
          furtherTax: _rs(400),
          returnsValue: _rs(1000),
          returnsTax: _rs(220),
          purchasesValue: Money.zero,
          inputTax: Money.zero,
          purchaseReturnsValue: Money.zero,
          purchaseReturnsTax: Money.zero,
        ),
        PartyTax(
          partyId: 'mill',
          name: 'Punjab Rice Mills',
          strn: '3277876123456',
          salesValue: Money.zero,
          salesTax: Money.zero,
          furtherTax: Money.zero,
          returnsValue: Money.zero,
          returnsTax: Money.zero,
          purchasesValue: _rs(5000),
          inputTax: _rs(900),
          purchaseReturnsValue: Money.zero,
          purchaseReturnsTax: Money.zero,
        ),
      ]);
      expect(_lines(t).first.cells, [
        'Rashid Traders',
        '1234567-8',
        '',
        _rs(9000),
        _rs(1980),
        Money.zero,
        Money.zero,
        _rs(1980),
      ]);
      expect(_cell(t, 'Total', 4), _rs(1980));
      expect(_cell(t, 'Total', 6), _rs(900));
      expect(_cell(t, 'Total', 7), _rs(1080));
    });

    test('the tax rate report splits by regime, returns on their own '
        'footing, and lands on the sales tax report\'s total', () {
      final rates = [
        RateTax(
          kind: 'sales_tax',
          code: 'ST_STD_18',
          rateBp: 1800,
          isReturn: false,
          lines: 4,
          value: _rs(10000),
          tax: _rs(1800),
        ),
        RateTax(
          kind: 'sales_tax',
          code: 'ST_3RD_18',
          rateBp: 1800,
          isReturn: false,
          lines: 1,
          value: _rs(1000),
          tax: _rs(180),
        ),
        RateTax(
          kind: 'further_tax',
          code: 'FURTHER_4',
          rateBp: 400,
          isReturn: false,
          lines: 2,
          value: _rs(5000),
          tax: _rs(200),
        ),
        RateTax(
          kind: 'sales_tax',
          code: 'ST_RED_10',
          rateBp: 1000,
          isReturn: false,
          lines: 1,
          value: _rs(100),
          tax: _rs(10),
        ),
        const RateTax(
          kind: 'none',
          code: 'exempt',
          rateBp: 0,
          isReturn: false,
          lines: 1,
          value: Money.rupees(300),
          tax: Money.zero,
        ),
        const RateTax(
          kind: 'none',
          rateBp: 0,
          isReturn: false,
          lines: 2,
          value: Money.rupees(700),
          tax: Money.zero,
        ),
        RateTax(
          kind: 'sales_tax',
          code: 'ST_STD_18',
          rateBp: 1800,
          isReturn: true,
          lines: 1,
          value: _rs(1000),
          tax: _rs(180),
        ),
      ];
      final t = taxRateReport(_september, rates);
      expect(_lines(t).map((r) => r.cells.first), [
        'Standard rate',
        'Reduced rate',
        'Third Schedule, on retail price',
        'Exempt',
        'No sales tax charged',
        'Further tax',
        'Standard rate',
      ]);
      expect(_lines(t).last.cells.sublist(2), [-1, -_rs(1000), -_rs(180)]);
      expect(_cell(t, 'Exempt'), isNull, reason: 'no rate for exempt');
      expect(_cell(t, 'Sales tax', 4), _rs(1810));
      expect(_cell(t, 'Further tax', 4), _rs(200));
      expect(t.totals.single.cells.last, _rs(2010));
      expect(
        _cell(t, 'Sales tax', 3),
        _rs(11100),
        reason: 'everything sales tax was charged on, or not, less returns',
      );
      final summary = salesTaxSummary(_september, [
        for (final r in rates)
          if (r.kind != 'none')
            TaxLine(
              code: r.isReturn ? 'ST_RETURN' : r.code!,
              kind: r.kind,
              rateBp: r.rateBp,
              base: r.value,
              amount: r.tax,
              isReturn: r.isReturn,
            ),
      ]);
      expect(t.totals.single.cells.last, summary.totals.single.cells.last);
    });

    test('sales by HS code, net of returns, the lines with no code last', () {
      final t = salesByHsCode(_september, [
        const HsCodeSales(
          lines: 2,
          items: 1,
          value: Money.rupees(50),
          salesTax: Money.zero,
          furtherTax: Money.zero,
          returnsValue: Money.zero,
          returnsSalesTax: Money.zero,
          returnsFurtherTax: Money.zero,
          example: 'Dhaga',
        ),
        HsCodeSales(
          hsCode: '1006.3090',
          example: 'Chawal Basmati',
          lines: 3,
          items: 2,
          value: _rs(3000),
          salesTax: _rs(540),
          furtherTax: _rs(40),
          returnsValue: _rs(1000),
          returnsSalesTax: _rs(180),
          returnsFurtherTax: _rs(40),
        ),
      ]);
      expect(_lines(t).map((r) => r.cells.first), ['1006.3090', 'No HS code']);
      expect(_lines(t).first.cells.sublist(4), [
        _rs(2000),
        _rs(360),
        Money.zero,
        _rs(360),
      ]);
      expect(t.notes.last, startsWith('2 lines have no HS code'));
    });
  });

  group('annex registers', () {
    test('Annex-C carries FBR\'s Domestic Sales Invoice columns, B to AD, in '
        'its order', () {
      final t = annexC(_september, [_annex()]);
      expect(t.columns, hasLength(29));
      final titles = t.columns.map((c) => c.title).toList();
      expect(titles.first, 'Buyer Registration No');
      expect(titles[10], 'Rate');
      expect(titles[11], contains('hidden'), reason: 'column M');
      expect(titles[12], 'Quantity', reason: 'column N');
      expect(titles[14], 'Value of Sales Excluding Sales Tax');
      expect(titles[18], 'Further Tax', reason: 'column T');
      expect(titles.last, 'Additional Sales Tax Rate', reason: 'column AD');
      expect(t.totals, isEmpty, reason: 'rows to paste, and nothing else');
    });

    test('a registered buyer, a walk-in, and a return as a credit note', () {
      final t = annexC(_september, [
        _annex(registered: true, ntn: '1234567-8', furtherTax: 0),
        _annex(party: null, rateBp: 1800),
        _annex(
          type: 'sale_return',
          value: 500,
          salesTax: 90,
          reference: 'INV-0001',
          reason: 'Dabba pichka hua',
        ),
        _annex(
          code: 'ST_3RD_18',
          value: 847,
          salesTax: 153,
          unit: 'tola',
          hs: '22021010',
        ),
      ]);
      final rows = _lines(t);
      expect(rows[0].cells.sublist(0, 11), [
        '1234567-8',
        'Rashid Traders',
        'Registered',
        'PUNJAB',
        'SINDH',
        'Sale Invoice',
        'INV-0001',
        '15-Sep-2026',
        '1006.3090:-',
        'Goods at standard rate (default)',
        1800,
      ]);
      expect(rows[0].cells.sublist(12, 16), [
        Qty.units(10),
        'KG',
        _rs(1000),
        _rs(180),
      ]);
      expect(rows[1].cells.sublist(0, 3), [
        '',
        'Walk-in customer',
        'Retail Consumer',
      ]);
      expect(rows[2].cells[5], 'Credit Note');
      expect(rows[2].cells[14], _rs(500), reason: 'never below nothing');
      expect(rows[2].cells.sublist(23, 26), [
        'INV-0001',
        'Return of goods',
        'Dabba pichka hua',
      ]);
      expect(rows[3].cells[8], '2202.1010:-');
      expect(rows[3].cells[9], '3rd Schedule Goods');
      expect(rows[3].cells[16], _rs(1000), reason: 'the retail price');
      expect(rows[3].cells[21], '3rd Schedule goods');
      expect(rows[3].cells[13], 'tola');
      expect(t.notes.join(' '), contains('no unit for tola'));
      expect(t.summary.first.count, 4);
    });

    test('Annex-A carries FBR\'s Domestic Purchase Invoice columns, B to AB, '
        'and goods sent back are a debit note', () {
      final t = annexA(_september, [
        _annex(
          type: 'purchase_bill',
          party: 'Punjab Rice Mills',
          registered: true,
          cnic: '35202-1234567-1',
          salesTax: 0,
          rateBp: null,
          code: null,
        ),
        _annex(
          type: 'purchase_return',
          party: 'Punjab Rice Mills',
          salesTax: 0,
          rateBp: null,
          code: null,
          reference: 'PRM/771',
        ),
        _annex(),
      ]);
      expect(t.columns, hasLength(27));
      expect(t.columns.last.title, 'Product Description');
      final rows = _lines(t);
      expect(rows, hasLength(2), reason: 'a sale is not a purchase');
      expect(rows[0].cells.sublist(0, 6), [
        '3520212345671',
        'Punjab Rice Mills',
        'Registered',
        'SINDH',
        'PUNJAB',
        'Purchase Invoice',
      ]);
      expect(rows[1].cells[5], 'Debit Note');
      expect(rows[1].cells[23], 'PRM/771');
    });

    test('the template\'s own names for a province, a unit and an HS code', () {
      expect(fbrProvince('kpk'), 'KHYBER PAKHTUNKHWA');
      expect(fbrProvince('Islamabad'), 'CAPITAL TERRITORY');
      expect(fbrProvince('Mars'), isNull);
      expect(fbrUnit('pcs'), 'Numbers, pieces, units');
      expect(fbrUnit('maund'), '40KG');
      expect(fbrUnit('gaz'), isNull);
      expect(fbrHsCode(' 1006.3090 '), '1006.3090:-');
      expect(fbrHsCode('ABC'), 'ABC');
      expect(fbrHsCode(null), '');
      expect(fbrDate(const BusinessDate('2026-01-05')), '05-Jan-2026');
    });
  });

  group('expenses', () {
    test('every voucher, and its total', () {
      final t = expenseTransactions(_september, [
        _voucher('Shutter rent', head: 'Rent', amount: 1000),
        _voucher('Bijli bill', amount: 400, owed: 400),
      ]);
      expect(_cell(t, 'Total', 5), _rs(1400));
      expect(_cell(t, 'Total', 6), _rs(400));
      expect(_lines(t).first.cells[3], 'Rent');
    });

    test('by head, direct apart from indirect, adding up to the vouchers', () {
      final t = expenseCategories(_september, [
        _voucher('Shutter rent', head: 'Rent', amount: 1000),
        _voucher('Bijli bill', amount: 400),
        _voucher('Bijli bill', amount: 600, date: '2026-09-20'),
        _voucher('Rickshaw', head: 'Freight', direct: true, amount: 200),
      ]);
      expect(t.rows.first.cells.first, 'Direct expenses');
      expect(_cell(t, 'Utilities', 2), _rs(1000));
      expect(_cell(t, 'Utilities', 1), 2);
      expect(_cell(t, 'Total direct expenses', 2), _rs(200));
      expect(_cell(t, 'Total indirect expenses', 2), _rs(2000));
      expect(t.totals.single.cells.sublist(1), [4, _rs(2200), 10000]);
    });

    test('an item is what the voucher was for, capitals, spacing and a '
        'full stop ignored, within its head', () {
      final t = expenseItems(_september, [
        _voucher('Bijli bill', amount: 400),
        _voucher('bijli  bill.', amount: 600, date: '2026-09-20'),
        _voucher('Gas bill', amount: 1000),
        _voucher('Bijli bill', head: 'Rent', amount: 50),
      ]);
      expect(_lines(t).map((r) => [r.cells[0], r.cells[1], r.cells[2]]), [
        ['Utilities', 'Gas bill', 1],
        ['Utilities', 'bijli  bill.', 2],
        ['Rent', 'Bijli bill', 1],
      ]);
      expect(_lines(t)[1].cells[3], _rs(1000));
      expect(_lines(t)[1].cells[4], 5000, reason: 'half of Utilities');
      expect(_lines(t)[1].cells[5], '2026-09-20');
      expect(expenseItemKey('  BIJLI   Bill. '), 'bijli bill');
    });
  });

  group('orders', () {
    OpenOrder order(String no, String type, String date, {String? until}) =>
        OpenOrder(
          documentId: 'id-$no',
          docType: type,
          docNo: no,
          date: BusinessDate(date),
          party: 'Rashid Traders',
          total: _rs(1000),
          lines: 2,
          validUntil: until == null ? null : BusinessDate(until),
        );

    test('open quotations, the oldest first, with their age and whether '
        'they have expired', () {
      final t = openQuotations(_today, [
        order('QT-2', 'quotation', '2026-09-20', until: '2026-10-05'),
        order('QT-1', 'quotation', '2026-09-01', until: '2026-09-15'),
        order('DC-1', 'delivery_challan', '2026-09-01'),
      ]);
      expect(_lines(t).map((r) => r.cells[1]), ['QT-1', 'QT-2']);
      expect(_cell(t, '2026-09-01', 5), 25);
      expect(_lines(t).first.cells.last, 'Expired');
      expect(_lines(t).last.cells.last, 'Valid');
      expect(t.summary.map((f) => f.count ?? f.amount), [2, _rs(2000), 1]);
    });

    test('challans not yet billed, and the items on both', () {
      final t = openChallans(_today, [
        order('DC-1', 'delivery_challan', '2026-09-24'),
      ]);
      expect(_lines(t).single.cells[5], 2);
      final items = openOrderItems(_today, [
        OpenOrderItem(
          itemName: 'Cooking Oil 5L',
          unitCode: 'pcs',
          docType: 'delivery_challan',
          qty: Qty.units(3),
          value: _rs(7500),
          documents: 1,
        ),
        OpenOrderItem(
          itemName: 'Chawal Basmati',
          unitCode: 'kg',
          docType: 'quotation',
          qty: Qty.units(20),
          value: _rs(3000),
          documents: 2,
        ),
      ]);
      expect(_lines(items).first.cells.sublist(0, 2), [
        'Cooking Oil 5L',
        'Challans',
      ]);
      expect(items.summary.map((f) => f.amount), [_rs(3000), _rs(7500)]);
    });
  });

  group('report engine', () {
    test('the open orders and the defaulters are as of today', () {
      for (final kind in businessReportsAsOfToday) {
        expect(ReportEngine.isAsOfToday(kind), isTrue, reason: '$kind');
      }
      expect(ReportEngine.isAsOfToday(ReportKind.dailySummary), isFalse);
      expect(ReportEngine.isAsOfToday(ReportKind.annexC), isFalse);
    });

    test('every M35 report is built through its own case, and none of them '
        'shows cost through and through', () {
      expect(businessReportKinds, hasLength(22));
      for (final kind in businessReportKinds) {
        expect(ReportEngine.showsCost(kind), isFalse, reason: '$kind');
      }
    });

    test('the Z report reaches a role that may not see costs without its '
        'gross profit', () async {
      final engine = ReportEngine(_DaySource(), canSeeCosts: false);
      final t = await engine.run(
        ReportKind.dailySummary,
        firmId: 'f',
        period: ReportPeriod.day(_today),
        today: _today,
      );
      expect(t.rows.any((r) => r.cells.first == 'Gross profit'), isFalse);
      final owner = await ReportEngine(_DaySource()).run(
        ReportKind.dailySummary,
        firmId: 'f',
        period: ReportPeriod.day(_today),
        today: _today,
      );
      expect(owner.rows.any((r) => r.cells.first == 'Gross profit'), isTrue);
    });

    test('a narrowed report says by which account and which head', () {
      const f = ReportFilters(
        accountId: 'a1',
        accountName: 'Meezan Bank',
        expenseHeadId: 'h1',
        expenseHeadName: 'Rent',
        partyId: 'p',
      );
      expect(f.only({ReportFilter.moneyAccount}).describe(), [
        'Account: Meezan Bank',
      ]);
      expect(f.without(ReportFilter.moneyAccount).accountId, isNull);
      expect(f.without(ReportFilter.moneyAccount).expenseHeadId, 'h1');
      expect(f.has(ReportFilter.expenseHead), isTrue);
      expect(f.copyWith(accountId: 'a2').accountId, 'a2');
      expect(ReportFilters.none.isEmpty, isTrue);
      expect(const ReportFilters(accountId: 'x').isEmpty, isFalse);
    });
  });
}

/// Answers the Z report's one read with a quiet day.
final class _DaySource implements ReportSource {
  @override
  Future<DayFigures> dayFigures(String firmId, ReportPeriod period) async =>
      DayFigures(
        bills: 1,
        sales: _rs(100),
        returns: 0,
        returnsValue: Money.zero,
        discount: Money.zero,
        linesSold: 1,
        salesTaxable: _rs(100),
        salesCost: _rs(60),
        returnsTaxable: Money.zero,
        returnsCost: Money.zero,
        expenses: 0,
        expensesValue: Money.zero,
        tenders: const [],
        udhaar: UdhaarGiven.none,
        counts: const [],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('read ${invocation.memberName}');
}
