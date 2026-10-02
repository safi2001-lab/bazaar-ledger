import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

/// The reports saying what the books mean, the money owed both ways, and
/// the charts drawn from the tables (M58, M46), each proved here without a
/// database.
const _today = BusinessDate('2026-10-03');
final _day = ReportPeriod.day(_today);
final _september = ReportPeriod(
  const BusinessDate('2026-09-01'),
  const BusinessDate('2026-09-30'),
);

Money _rs(int rupees) => Money.rupees(rupees);

TransactionRow _tx(
  String number,
  String type, {
  int total = 0,
  String? partyId,
  String party = '',
  bool forHome = false,
  String status = 'posted',
}) => TransactionRow(
  id: 'id-$number',
  date: _today,
  number: number,
  type: type,
  partyId: partyId,
  party: party,
  total: _rs(total),
  paid: _rs(total),
  balance: Money.zero,
  status: status,
  forHome: forHome,
);

DayBookEntry _entry(String kind, String narration, {int amount = 0}) =>
    DayBookEntry(
      date: _today,
      entryNo: 'JV-$kind',
      sourceType: kind,
      narration: narration,
      amount: _rs(amount),
    );

ExpenseVoucher _voucher(
  String no,
  int rupees, {
  String head = 'Rent',
  bool home = false,
  bool goods = false,
  String note = 'Kiraya',
}) => ExpenseVoucher(
  documentId: 'id-$no',
  date: _today,
  docNo: no,
  headId: home ? 'drawings' : head,
  head: home ? "Owner's Drawings" : head,
  isDirect: false,
  paidFrom: goods ? 'Inventory' : 'Cash in Hand',
  amount: _rs(rupees),
  balance: Money.zero,
  note: note,
  forHome: home,
  goods: goods,
);

LoanPosting _posting(
  String no,
  String date, {
  int borrowed = 0,
  int repaid = 0,
  int interest = 0,
  int charges = 0,
}) => LoanPosting(
  entryId: 'je-$no',
  entryNo: no,
  date: BusinessDate(date),
  narration: no,
  loanDebit: _rs(repaid),
  loanCredit: _rs(borrowed),
  interest: _rs(interest),
  charges: _rs(charges),
);

List<ReportRow> _lines(ReportTable t) =>
    t.rows.where((r) => r.style == RowStyle.line).toList();

Object? _total(ReportTable t, String column) =>
    t.totals.single.cells[t.columns.indexWhere((c) => c.title == column)];

void main() {
  group('what the books mean', () {
    test('the shop\'s own income is other income, and a charge on a khata '
        'a charge, each summed apart', () {
      final t = allTransactions(_day, [
        _tx('INC-1', TransactionType.charge, total: 3000),
        _tx(
          'INC-2',
          TransactionType.charge,
          total: 500,
          partyId: 'rashid',
          party: 'Rashid Traders',
        ),
      ]);
      expect(
        [for (final r in _lines(t)) r.cells[2]],
        ['Other income', 'Charge'],
      );
      final byType = {
        for (final r in t.rows.where((r) => r.style == RowStyle.subtotal))
          r.cells[2]: r.cells[4],
      };
      expect(byType, {'Charge': _rs(500), 'Other income': _rs(3000)});
      expect(t.notes, contains(startsWith('Other income is the shop')));
      expect(
        const ReportFilters(transactionType: TransactionType.charge).describe(),
        ['Type: Charge or other income'],
      );
    });

    test('the home\'s spending and udhaar let go are their own kinds in all '
        'transactions, and a write-off is not money paid in', () {
      final t = allTransactions(_day, [
        _tx('EXP-1', TransactionType.expense, total: 4000),
        _tx('EXP-2', TransactionType.expense, total: 15000, forHome: true),
        _tx('PI-1', TransactionType.paymentIn, total: 950, partyId: 'k'),
        _tx('WO-2627-0001', TransactionType.paymentIn, total: 1000),
        _tx('SD-2627-0001', TransactionType.paymentIn, total: 50),
      ]);
      expect(
        [for (final r in _lines(t)) r.cells[2]],
        [
          'Expense',
          "Owner's drawings (ghar)",
          'Payment in',
          'Written off',
          'Settlement discount',
        ],
      );
      expect(
        [for (final r in _lines(t)) r.cells.last],
        ['Paid', 'Paid', 'Cleared', '', ''],
      );
      final byType = {
        for (final r in t.rows.where((r) => r.style == RowStyle.subtotal))
          r.cells[2]: r.cells[4],
      };
      expect(byType['Expense'], _rs(4000));
      expect(byType["Owner's drawings (ghar)"], _rs(15000));
      expect(byType['Payment in'], _rs(950));
      expect(byType['Written off'], _rs(1000));
      expect(byType['Settlement discount'], _rs(50));
    });

    test('the day book names the shop\'s income, the home\'s spending, a '
        'loan and udhaar let go', () {
      final t = dayBook(_day, [
        _entry('other_income', 'Debit note INC-1 for Rashid'),
        _entry(TransactionType.otherIncome, 'Other income INC-2: Commission'),
        _entry(TransactionType.ownerDrawings, 'Ghar ka kharcha EXP-2'),
        _entry('loan', 'Loan from Meezan Bank'),
        _entry('payment', 'Written off WO-2627-0001: Shehr chhor gaya'),
        _entry('payment', 'Settlement discount SD-2627-0001'),
        _entry('payment', 'Receipt PI-1'),
      ]);
      expect(
        [for (final r in _lines(t)) r.cells[2]],
        [
          'Charge',
          'Other income',
          "Owner's drawings (ghar)",
          'Loan',
          'Written off',
          'Settlement discount',
          'Payment',
        ],
      );
    });

    test('the expense reports leave the home\'s spending out and show it '
        'apart, goods taken home said so', () {
      final vouchers = [
        _voucher('EXP-1', 4000),
        _voucher('EXP-2', 15000, home: true, note: 'School fees'),
        _voucher('EXP-3', 1000, home: true, goods: true, note: 'Ghee'),
      ];
      final tx = expenseTransactions(_day, vouchers);
      expect(_lines(tx), hasLength(1));
      expect(_total(tx, 'Amount'), _rs(4000));
      expect(tx.summary.first.amount, _rs(4000));
      expect(tx.summary.last.label, homeTile);
      expect(tx.summary.last.amount, _rs(16000));
      expect(
        tx.notes.last,
        'Ghar ka kharcha, 2 entries for Rs 16,000.00, Rs 1,000.00 of it '
        "goods taken home at cost, is the owner's drawings, not the shop's "
        'expense: it is left out of every figure here, as it is out of the '
        'profit and loss.',
      );

      final heads = expenseCategories(_day, vouchers);
      expect(_total(heads, 'Amount'), _rs(4000));
      expect(
        heads.rows.any((r) => r.cells.first == "Owner's Drawings"),
        isFalse,
      );
      final items = expenseItems(_day, vouchers);
      expect(_total(items, 'Amount'), _rs(4000));
      expect(items.summary.last.amount, _rs(16000));

      // A period with none of the home's says nothing about it.
      final shopOnly = expenseTransactions(_day, [_voucher('EXP-1', 4000)]);
      expect(shopOnly.summary.map((f) => f.label), isNot(contains(homeTile)));
      expect(shopOnly.notes, hasLength(1));
    });

    test('sales by item has khula maal as one row, all of it profit, and '
        'in the total', () {
      final t = salesByItem(_september, [
        ItemSales(
          itemId: 'oil',
          itemName: 'Cooking Oil 5L',
          unitCode: 'pcs',
          qtySold: Qty.units(4),
          qtyReturned: Qty.zero,
          salesValue: _rs(2400),
          returnsValue: Money.zero,
          cost: _rs(2000),
          returnedCost: Money.zero,
        ),
        ItemSales(
          itemName: ItemTrade.looseLines,
          unitCode: '',
          qtySold: Qty.units(3),
          qtyReturned: Qty.zero,
          salesValue: _rs(450),
          returnsValue: Money.zero,
          cost: Money.zero,
          returnedCost: Money.zero,
          isLoose: true,
        ),
      ]);
      final loose = _lines(t).last;
      expect(loose.cells, [
        ItemTrade.looseLines,
        null,
        '',
        _rs(450),
        null,
        _rs(450),
        null,
      ]);
      expect(loose.link, isNull);
      expect(_lines(t).first.link?.kind, ReportLinkKind.item);
      expect(_total(t, 'Sales'), _rs(2850));
      expect(_total(t, 'Profit'), _rs(850));
      expect(t.notes.last, startsWith(ItemTrade.looseLines));
    });

    test('a statement calls a write-off and a settlement discount what they '
        'were', () {
      LedgerEntry e(String reference, int amount, int after) => LedgerEntry(
        id: reference,
        kind: 'payment',
        reference: reference,
        dateLocal: '2026-09-20',
        amount: _rs(amount),
        balanceAfter: _rs(after),
      );
      final t = partyStatement(
        partyName: 'Akbar',
        period: _september,
        entries: [
          LedgerEntry(
            id: 'b',
            kind: 'sale',
            reference: 'S-1',
            dateLocal: '2026-09-01',
            amount: _rs(3000),
            balanceAfter: _rs(3000),
          ),
          e('PI-2627-0001', -500, 2500),
          e('SD-2627-0001', -100, 2400),
          e('WO-2627-0001', -2400, 0),
        ],
      );
      expect(
        [for (final r in _lines(t)) r.cells[1]],
        ['Bill', 'Payment', 'Settlement discount', 'Written off'],
      );
    });

    test('the Z report keeps the home\'s spending apart, and names its '
        'figures for the hub\'s Today strip', () {
      final t = dailySummary(
        _day,
        DayFigures(
          bills: 2,
          sales: _rs(800),
          returns: 0,
          returnsValue: Money.zero,
          discount: Money.zero,
          linesSold: 2,
          salesTaxable: _rs(800),
          salesCost: _rs(500),
          returnsTaxable: Money.zero,
          returnsCost: Money.zero,
          expenses: 1,
          expensesValue: _rs(4000),
          tenders: const [],
          udhaar: UdhaarGiven(bills: 1, amount: _rs(500)),
          counts: const [],
          takenHome: 2,
          takenHomeValue: _rs(16000),
        ),
        showProfit: true,
      );
      expect(
        t.rows.firstWhere((r) => r.cells.first == 'Expenses, 1 voucher').cells,
        ['Expenses, 1 voucher', _rs(4000)],
      );
      expect(
        t.rows
            .firstWhere((r) => r.cells.first == 'Ghar ka kharcha, 2 entries')
            .cells
            .last,
        _rs(16000),
      );
      expect(
        [for (final f in t.summary) f.label],
        [
          DayFigureLabel.netSales,
          DayFigureLabel.collected,
          DayFigureLabel.udhaarGiven,
          DayFigureLabel.expenses,
          DayFigureLabel.grossProfit,
        ],
      );
      expect(t.summary[2].amount, _rs(500));
      expect(t.summary.last.amount, _rs(300));
    });

    test('changed and cancelled bills say what an edit was, whose PIN let it '
        'through, and count udhaar let go and the closed books', () {
      ChangeRecord change(
        String action, {
        int? was,
        int? amount,
        String? allowedBy,
        String? reason,
      }) => ChangeRecord(
        date: _today,
        time: '14:15',
        action: action,
        who: 'Bilal',
        summary: action,
        reference: 'X-1',
        was: was == null ? null : _rs(was),
        amount: amount == null ? null : _rs(amount),
        allowedBy: allowedBy,
        reason: reason,
      );
      final t = changedBills(_day, [
        change('EXPENSE_EDITED', was: 5000, amount: 500, reason: 'Ek sifar'),
        change('DOCUMENT_VOIDED', amount: 2500, allowedBy: 'Malik Sahib'),
        change(
          'BAD_DEBT_WRITTEN_OFF',
          amount: 1000,
          reason: 'Shehr chhor gaya',
        ),
        change('SETTLEMENT_DISCOUNT_GIVEN', amount: 50),
        change('LOAN_ENTRY_CANCELLED', amount: 25000),
        change(closedBooksOverrideAction, allowedBy: 'Malik Sahib'),
        change(booksReopenedAction),
      ]);
      expect(
        [for (final c in t.columns) c.title],
        [
          'Date',
          'Time',
          'What',
          'Number',
          'Party',
          'Was',
          'Amount',
          'Who',
          'Allowed by',
          'Reason',
        ],
      );
      expect(_lines(t).first.cells.sublist(5, 7), [_rs(5000), _rs(500)]);
      expect(_lines(t)[1].cells[8], 'Malik Sahib');
      expect(
        [for (final r in _lines(t)) r.cells[2]],
        [
          'Expense edited',
          'Voided',
          'Written off',
          'Settlement discount',
          'Loan entry cancelled',
          'Let into closed books',
          'Books opened again',
        ],
      );
      expect(
        {for (final f in t.summary) f.label: f.count},
        {
          'Voids': 2,
          'Returns': 0,
          'Edits': 1,
          'Let go': 2,
          'Closed books': 2,
          'By PIN': 2,
        },
      );
      for (final code in [
        'BAD_DEBT_WRITTEN_OFF',
        'SETTLEMENT_DISCOUNT_GIVEN',
        'LOAN_ENTRY_CANCELLED',
        closedBooksOverrideAction,
        booksReopenedAction,
      ]) {
        expect(changeActions, contains(code));
      }
      expect(ReportFilters(minAmount: _rs(1000)).describe(), [
        'Rs 1,000.00 or more',
      ]);
    });

    test(
      'the cash flow names other income, loans and the home\'s spending',
      () {
        final t = cashflow(_september, MoneyBalance.zero, [
          MoneyFlow(
            kind: TransactionType.otherIncome,
            inCash: false,
            moneyIn: _rs(3000),
            moneyOut: Money.zero,
          ),
          MoneyFlow(
            kind: 'loan',
            inCash: false,
            moneyIn: _rs(495000),
            moneyOut: _rs(25000),
          ),
          MoneyFlow(
            kind: TransactionType.ownerDrawings,
            inCash: true,
            moneyIn: Money.zero,
            moneyOut: _rs(15000),
          ),
        ]);
        final labels = [for (final r in _lines(t)) r.cells.first];
        expect(
          labels,
          containsAll([
            'Other income',
            'Loans taken',
            'Loans paid back',
            "Taken for the home (owner's drawings)",
          ]),
        );
      },
    );
  });

  group('money owed', () {
    test('udhaar by due date buckets each customer, the latest first, owing '
        'the khata\'s balance', () {
      final t = receivablesByDueDate(_today, const [
        DueAgeingRow(
          partyId: 'b',
          name: 'Bilal',
          notYetDue: Money.rupees(500),
          opening: Money.rupees(1000),
        ),
        DueAgeingRow(partyId: 'a', name: 'Akbar', over90: Money.rupees(2000)),
        DueAgeingRow(
          partyId: 'r',
          name: 'Rashid Traders',
          notYetDue: Money.rupees(1700),
          upTo30: Money.rupees(2000),
          advance: Money.rupees(200),
        ),
        DueAgeingRow(partyId: 'k', name: 'Kamran'),
      ]);
      expect(
        [for (final r in _lines(t)) r.cells.first],
        ['Akbar', 'Rashid Traders', 'Bilal'],
      );
      expect([
        for (final c in t.columns.skip(1).take(5)) c.title,
      ], dueBucketColumns);
      expect(_lines(t)[1].cells.last, _rs(3500));
      expect(_lines(t)[1].cells[7], _rs(-200), reason: 'an advance comes off');
      expect(_lines(t).first.link?.kind, ReportLinkKind.party);
      expect(_total(t, 'Owed'), _rs(7000));
      expect(t.summary.first.amount, _rs(7000));
      expect(t.summary[1].amount, _rs(4000));
      expect(t.summary.last.count, 2);
      expect(t.notes, hasLength(3));
    });

    test('bad debts and settlement discounts: a cancelled one is listed and '
        'counted nowhere', () {
      AllowanceRow row(
        String no,
        AllowanceKind kind,
        int rupees, {
        bool cancelled = false,
        String date = '2026-09-10',
      }) => AllowanceRow(
        paymentId: no,
        paymentNo: no,
        kind: kind,
        partyId: 'p-$no',
        partyName: 'Party $no',
        dateLocal: date,
        amount: _rs(rupees),
        reason: 'Reason $no',
        byName: 'Malik Sahib',
        cancelled: cancelled,
      );
      final t = badDebts(_september, [
        row('WO-2', AllowanceKind.writeOff, 200, cancelled: true),
        row('SD-1', AllowanceKind.settlementDiscount, 50, date: '2026-09-01'),
        row('WO-1', AllowanceKind.writeOff, 1000),
      ]);
      expect([for (final r in _lines(t)) r.cells[1]], ['SD-1', 'WO-1', 'WO-2']);
      expect(_lines(t).last.cells.last, 'Cancelled, not counted');
      expect(_lines(t)[1].cells.sublist(2, 7), [
        'Written off',
        'Party WO-1',
        'Reason WO-1',
        'Malik Sahib',
        _rs(1000),
      ]);
      expect(_total(t, 'Amount'), _rs(1050));
      expect(t.totals.single.cells.last, '1 cancelled');
      expect(
        [for (final f in t.summary) f.amount],
        [_rs(1000), _rs(50), _rs(1050)],
      );
    });

    test('every loan on one page, each outstanding its statement\'s closing, '
        'and a tap opens the loan', () async {
      final source = _Loans();
      final t = await loanReport(
        source,
        firmId: 'f',
        period: _september,
        filters: ReportFilters.none,
      );
      expect(t.id, 'loans');
      expect(_lines(t), hasLength(1), reason: 'the paid-off one is left off');
      final row = _lines(t).single;
      expect(row.cells, [
        'Loan from Meezan Bank',
        'Meezan Bank',
        '2026-07-01',
        _rs(482644),
        Money.zero,
        _rs(25000),
        _rs(7400),
        Money.zero,
        _rs(457644),
      ]);
      expect(row.link?.kind, ReportLinkKind.loan);
      expect(row.link?.id, 'meezan');
      expect(_total(t, 'Outstanding'), _rs(457644));
      expect(t.summary.first.amount, _rs(457644));
    });

    test('a loan statement narrowed to one loan is that loan\'s, from the '
        'builder the loan\'s own screen uses', () async {
      final t = await loanReport(
        _Loans(),
        firmId: 'f',
        period: _september,
        filters: const ReportFilters(loanId: 'meezan'),
      );
      final own = buildLoanStatement(
        name: 'Loan from Meezan Bank',
        postings: _Loans.meezan,
        from: _september.from,
        to: _september.to,
      );
      expect(t.id, 'loan_statement');
      expect(t.title, 'Loan statement: Loan from Meezan Bank');
      expect(_lines(t), hasLength(1));
      expect(_total(t, 'Outstanding'), own.closing);
      expect(t.notes.first, startsWith('Lent by Meezan Bank on 2026-07-01'));
    });

    test('report engine every M58 report has its own case, and only the '
        'due-date ageing is as of today', () {
      expect(moneyOwedReportKinds, hasLength(3));
      for (final kind in moneyOwedReportKinds) {
        expect(ReportEngine.showsCost(kind), isFalse, reason: '$kind');
      }
      expect(ReportEngine.isAsOfToday(ReportKind.receivablesByDueDate), isTrue);
      expect(ReportEngine.isAsOfToday(ReportKind.loanStatement), isFalse);
      expect(ReportEngine.isAsOfToday(ReportKind.badDebts), isFalse);
      expect(
        const ReportFilters(loanId: 'x', loanName: 'Loan from HBL').describe(),
        ['Loan: Loan from HBL'],
      );
      expect(
        const ReportFilters(loanId: 'x').only({ReportFilter.party}).isEmpty,
        isTrue,
      );
    });
  });

  group('charts', () {
    ReportTable byDay(Map<String, int> days, ReportPeriod period) =>
        salesByDay(period, [
          for (final e in days.entries)
            DaySales(
              date: BusinessDate(e.key),
              bills: 1,
              sales: _rs(e.value),
              returns: Money.zero,
              received: _rs(e.value),
              onUdhaar: Money.zero,
            ),
        ]);

    test('a trend draws every day of the period, a quiet day as nothing, '
        'and comes to the table\'s total', () {
      final week = ReportPeriod(
        const BusinessDate('2026-09-01'),
        const BusinessDate('2026-09-07'),
      );
      final table = byDay({'2026-09-02': 1200, '2026-09-05': 800}, week);
      final chart = chartOf(
        table,
        const ChartSpec.trend(label: 'Date', value: 'Sales', everyDay: true),
      )!;
      expect(chart.form, ChartForm.trend);
      expect(chart.points, hasLength(7));
      expect(chart.points.first.label, '2026-09-01');
      expect(chart.points.first.value, Money.zero);
      expect(chart.points[1].value, _rs(1200));
      expect(chart.total, _total(table, 'Sales'));
      expect(chart.peak, _rs(1200));
      expect(chart.points[1].shareBp, 6000);
    });

    test('a day\'s bills are one column on the sale report\'s chart', () {
      BillRow bill(String no, String date, int total) => BillRow(
        documentId: no,
        date: BusinessDate(date),
        docNo: no,
        docType: TransactionType.sale,
        party: '',
        taxable: _rs(total),
        tax: Money.zero,
        total: _rs(total),
        paid: _rs(total),
        balance: Money.zero,
        cost: Money.zero,
      );
      final table = saleReport(_september, [
        bill('S-1', '2026-09-03', 500),
        bill('S-2', '2026-09-03', 700),
        bill('S-3', '2026-09-04', 100),
      ]);
      final chart = chartOf(
        table,
        const ChartSpec.trend(label: 'Date', value: 'Total', everyDay: true),
      )!;
      expect(chart.points, hasLength(30));
      expect(chart.points[2].value, _rs(1200));
      expect(chart.points[2].link, isNull, reason: 'two bills, not one');
      expect(chart.points[3].link?.id, 'S-3');
      expect(chart.total, _total(table, 'Total'));
    });

    test('ranked: the top ten largest first, the rest summed, nothing or '
        'less left out and said so', () {
      PartyTrade trade(String id, {int sales = 0, int purchases = 0}) =>
          PartyTrade(
            partyId: id,
            name: id == 'sup' ? 'Supplier' : 'Party ${id.substring(1)}',
            sales: _rs(sales),
            saleReturns: Money.zero,
            purchases: _rs(purchases),
            purchaseReturns: Money.zero,
            salesTaxable: _rs(sales),
            returnsTaxable: Money.zero,
            cost: Money.zero,
            returnedCost: Money.zero,
          );
      final table = salePurchaseByParty(_september, [
        for (var i = 1; i <= 12; i++) trade('p$i', sales: i * 100),
        trade('sup', purchases: 5000),
      ]);
      final chart = chartOf(
        table,
        const ChartSpec.ranked(label: 'Party', value: 'Sales'),
      )!;
      expect(chart.points, hasLength(11));
      expect(chart.points.first.label, 'Party 12');
      expect(chart.points.first.link?.id, 'p12');
      expect(chart.points.last.isRest, isTrue);
      expect(chart.points.last.label, 'Rest (2)');
      expect(chart.points.last.value, _rs(300));
      expect(chart.leftOut, 1, reason: 'the supplier sold nothing to');
      expect(chart.total, _total(table, 'Sales'));
      expect(
        Money.sum(chart.points.map((p) => p.value)),
        _total(table, 'Sales'),
      );
    });

    test('a ring keeps the table\'s order and folds the smallest into the '
        'rest', () {
      final table = paymentModeSummary(_september, [
        for (final (mode, rupees) in [
          ('cash', 5000),
          ('bank_transfer', 300),
          ('jazzcash', 1500),
          ('easypaisa', 100),
          ('raast', 50),
          ('card', 40),
          ('cheque', 30),
        ])
          TenderTotal(
            mode: mode,
            counterCount: 1,
            counter: _rs(rupees),
            khataCount: 0,
            khata: Money.zero,
          ),
      ], UdhaarGiven(bills: 1, amount: _rs(2000)));
      final chart = chartOf(
        table,
        const ChartSpec.ring(label: 'Paid by', value: 'Sales paid by it'),
      )!;
      expect(
        [for (final p in chart.points) p.label],
        ['Cash', 'Bank', 'JazzCash', 'EasyPaisa', 'Udhaar', 'Rest (3)'],
      );
      expect(chart.points.last.value, _rs(120));
      expect(chart.total, _total(table, 'Sales paid by it'));
      expect(chart.ordered, isFalse);
    });

    test(
      'a ring of the total keeps every bucket in order, an empty one too',
      () {
        final table = receivablesByDueDate(_today, const [
          DueAgeingRow(
            partyId: 'a',
            name: 'Akbar',
            notYetDue: Money.rupees(500),
            over90: Money.rupees(1500),
          ),
        ]);
        final chart = chartOf(
          table,
          const ChartSpec.ringOfTotal(dueBucketColumns),
        )!;
        expect([for (final p in chart.points) p.label], dueBucketColumns);
        expect(
          [for (final p in chart.points) p.value],
          [_rs(500), Money.zero, Money.zero, Money.zero, _rs(1500)],
        );
        expect(chart.points.last.shareBp, 7500);
        expect(chart.total, _rs(2000));
        expect(chart.ordered, isTrue);
      },
    );

    test('a chart whose column was struck for a cashier is no chart', () {
      final table = salesByItem(_september, [
        ItemSales(
          itemName: 'Oil',
          unitCode: 'pcs',
          qtySold: Qty.units(1),
          qtyReturned: Qty.zero,
          salesValue: _rs(600),
          returnsValue: Money.zero,
          cost: _rs(500),
          returnedCost: Money.zero,
        ),
      ]).withoutCostColumns();
      expect(
        chartOf(table, const ChartSpec.ranked(label: 'Item', value: 'Profit')),
        isNull,
      );
      expect(
        chartOf(table, const ChartSpec.ranked(label: 'Item', value: 'Sales')),
        isNotNull,
      );
      expect(chartOf(table, const ChartSpec.ringOfTotal(['Nowhere'])), isNull);
    });
  });
}

/// Two loans: Meezan's, standing, and a relative's, paid off in August.
final class _Loans implements LoanReportSource {
  static final meezan = [
    _posting('JV-1', '2026-07-01', borrowed: 500000, charges: 5000),
    _posting('JV-2', '2026-08-20', repaid: 17356, interest: 7644),
    _posting('JV-3', '2026-09-20', repaid: 25000, interest: 7400),
  ];

  static final uncle = [
    _posting('JV-4', '2026-07-05', borrowed: 50000),
    _posting('JV-5', '2026-08-05', repaid: 50000),
  ];

  @override
  Future<List<LoanView>> loans(String firmId) async => [
    LoanView(
      id: 'meezan',
      code: '2401',
      name: 'Loan from Meezan Bank',
      owed: _rs(457644),
      terms: LoanTerms(
        lender: 'Meezan Bank',
        amount: _rs(500000),
        takenOn: const BusinessDate('2026-07-01'),
        receiptEntryId: 'je-JV-1',
        fee: _rs(5000),
      ),
    ),
    LoanView(
      id: 'uncle',
      code: '2402',
      name: 'Loan from Chacha',
      owed: Money.zero,
      terms: LoanTerms(
        lender: 'Chacha',
        amount: _rs(50000),
        takenOn: const BusinessDate('2026-07-05'),
        receiptEntryId: 'je-JV-4',
      ),
    ),
  ];

  @override
  Future<List<LoanPosting>> loanPostings(String firmId, String loanId) async =>
      loanId == 'meezan' ? meezan : uncle;
}
