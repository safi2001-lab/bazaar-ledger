import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// The reports say what the books mean (M58), against a real database,
/// through the services the screens use, each figure tied to the books.
///
/// Chishti Kiryana Store, Lahore, from June to the 3rd of October 2026:
///
///  * 1 June: cooking oil comes in, twenty tins at Rs 500; Akbar (fifteen
///    days' credit) takes Rs 3,000 on udhaar; Bilal (no credit) opens his
///    khata owing Rs 1,000.
///  * 1 July: a Rs 5 lakh loan from Meezan Bank into the bank, Rs 5,000 fee.
///  * 20 August: Rashid (the shop's usual month) takes Rs 2,000; the bank is
///    paid Rs 25,000, Rs 7,644 of it interest.
///  * 1 September: Kamran takes Rs 1,000. 20 September: Rashid Rs 1,200.
///  * 2 October: generator diesel, on a head of the shop's own.
///  * 3 October: Bilal Rs 500 on udhaar; Rs 300 of loose onions for cash;
///    Rs 3,000 commission into the bank; a Rs 500 charge on Rashid's khata;
///    the rent; Rs 15,000 of school fees and two tins taken home; Rs 1,000
///    of Akbar's written off; Kamran settles Rs 950 with Rs 50 let go; Rs 200
///    of Rashid's written off and the write-off cancelled.
void main() {
  late FixedClock clock;
  late AppServices shop;
  late String firmId;
  late String cash;
  late String bank;
  late String oil;
  late String pcs;
  late String akbar;
  late String rashid;
  late String bilal;
  late String kamran;
  late String loan;

  const today = BusinessDate('2026-10-03');
  final sinceJune = ReportPeriod(const BusinessDate('2026-06-01'), today);

  void on(String day) => clock.set(DateTime.parse('${day}T06:00:00Z'));

  Future<void> sell(int rupees, {String? to, String? name, int qty = 1}) =>
      shop.postSale(
        shop.actorNow(),
        SaleDraft(
          lines: [
            SaleLineDraft(
              itemId: oil,
              itemName: 'Cooking Oil 5L',
              qty: Qty.units(qty),
              baseQty: Qty.units(qty),
              unitId: pcs,
              unitCode: 'pcs',
              rate: Rate.rupees(rupees ~/ qty),
            ),
          ],
          partyId: to,
          partyName: name,
        ),
      );

  Future<String> customer(String name, {int? days, int opening = 0}) =>
      shop.catalogue.addParty(
        shop.actorNow(),
        PartyDraft(
          name: name,
          creditDays: days,
          openingBalance: Money.rupees(opening),
        ),
      );

  setUp(() async {
    clock = FixedClock(DateTime.utc(2026, 6, 1, 6));
    shop = await openInMemoryServices(clock: clock);
    await shop.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    firmId = (await shop.queries.currentFirm())!.id;
    final accounts = await shop.queries.paymentAccounts(firmId);
    cash = accounts.firstWhere((a) => a.modeLabel == 'cash').id;
    bank = accounts.firstWhere((a) => a.modeLabel == 'bank_transfer').id;
    pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs').id;

    oil = await shop.catalogue.addItem(
      shop.actorNow(),
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: pcs,
        saleRate: Rate.rupees(600),
        openingStock: Qty.units(20),
        openingRate: Rate.rupees(500),
      ),
    );
    akbar = await customer('Akbar', days: 15);
    rashid = await customer('Rashid Traders');
    bilal = await customer('Bilal', days: 0, opening: 1000);
    kamran = await customer('Kamran');
    await sell(3000, to: akbar, name: 'Akbar');

    on('2026-07-01');
    loan = await shop.loans.take(
      LoanDraft(
        lender: 'Meezan Bank',
        amount: const Money.rupees(500000),
        fee: const Money.rupees(5000),
        intoPaymentAccountId: bank,
        takenOn: const BusinessDate('2026-07-01'),
        rateBp: 1800,
        termMonths: 24,
        instalment: const Money.rupees(25000),
      ),
    );

    on('2026-08-20');
    await sell(2000, to: rashid, name: 'Rashid Traders');
    await shop.loans.repay(
      RepaymentDraft(
        loanId: loan,
        paid: const Money.rupees(25000),
        interest: const Money.rupees(7644),
        fromPaymentAccountId: bank,
        paidOn: const BusinessDate('2026-08-20'),
      ),
    );

    on('2026-09-01');
    await sell(1000, to: kamran, name: 'Kamran');
    on('2026-09-20');
    await sell(1200, to: rashid, name: 'Rashid Traders');

    on('2026-10-02');
    final diesel = await shop.shopMoney.addExpenseHead(
      name: 'Generator diesel',
      isDirect: false,
    );
    await shop.recordExpense(
      shop.actorNow(),
      ExpenseDraft(
        accountSystemKey: '#$diesel',
        amount: const Money.rupees(700),
        note: 'Hafte ka diesel',
        paymentAccountId: cash,
      ),
    );

    on('2026-10-03');
    await sell(500, to: bilal, name: 'Bilal');
    await shop.postSale(
      shop.actorNow(),
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: null,
            itemName: 'Pyaz',
            qty: Qty.units(2),
            baseQty: Qty.units(2),
            unitCode: 'kg',
            rate: Rate.rupees(150),
            tracksStock: false,
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: cash,
            mode: 'cash',
            amount: const Money.rupees(300),
          ),
        ],
      ),
    );
    await shop.shopMoney.recordOtherIncome(
      OtherIncomeDraft(
        headKey: 'commission',
        amount: const Money.rupees(3000),
        paymentAccountId: bank,
        receivedOn: today,
        fromName: 'Jubilee Insurance',
      ),
    );
    await shop.chargeParty(
      shop.actorNow(),
      DebitNoteDraft(
        partyId: rashid,
        partyName: 'Rashid Traders',
        amount: const Money.rupees(500),
        note: 'Bounced cheque ka bank charge',
      ),
    );
    await shop.recordExpense(
      shop.actorNow(),
      ExpenseDraft(
        accountSystemKey: 'rent',
        amount: const Money.rupees(4000),
        note: 'October ka kiraya',
        paymentAccountId: cash,
      ),
    );
    await shop.recordExpense(
      shop.actorNow(),
      ExpenseDraft(
        accountSystemKey: 'rent',
        amount: const Money.rupees(15000),
        note: 'Bachon ki school fees',
        paymentAccountId: cash,
        forHome: true,
      ),
    );
    await shop.shopMoney.takeGoodsHome(
      GoodsTakenHomeDraft(itemId: oil, qty: Qty.units(2), note: 'Ghar ke liye'),
    );
    await shop.udhaar.writeOff(
      akbar,
      reason: 'Shehr chhor gaya',
      amount: const Money.rupees(1000),
    );
    await shop.udhaar.settleWithDiscount(
      ReceiptDraft(
        partyId: kamran,
        amount: const Money.rupees(950),
        mode: 'cash',
        paymentAccountId: cash,
      ),
      discount: const Money.rupees(50),
      reason: 'Khulay paisay nahi thay',
    );
    final mistake = await shop.udhaar.writeOff(
      rashid,
      reason: 'Galti se',
      amount: const Money.rupees(200),
    );
    await shop.corrections.cancelPayment(
      shop.actorNow(),
      paymentId: mistake.paymentId,
      reason: 'Galat khata',
    );
  });

  tearDown(() => shop.close());

  Future<ReportTable> run(
    ReportKind kind, {
    ReportPeriod? period,
    ReportFilters filters = ReportFilters.none,
  }) => shop.reports.run(
    kind,
    firmId: firmId,
    period: period ?? ReportPeriod.day(today),
    today: today,
    filters: filters,
  );

  List<ReportRow> lines(ReportTable t) =>
      t.rows.where((r) => r.style == RowStyle.line).toList();

  Object? total(ReportTable t, String column) =>
      t.totals.single.cells[t.columns.indexWhere((c) => c.title == column)];

  Object? cell(ReportTable t, String first, [int at = 1]) =>
      t.rows.where((r) => r.cells.first == first).firstOrNull?.cells[at];

  Money? figure(ReportTable t, String label) =>
      t.summary.where((f) => f.label == label).firstOrNull?.amount;

  Future<Money> balance(bool Function(ChartAccount) which) async =>
      (await shop.queries.chartOfAccounts(firmId)).firstWhere(which).onItsSide;

  group('what the books mean', () {
    test('the day book and all transactions call the shop\'s own income '
        'other income, and a charge on a khata a charge', () async {
      final book = await run(ReportKind.dayBook);
      final types = [for (final r in lines(book)) r.cells[2]];
      expect(types, contains('Other income'));
      expect(types, contains('Charge'));
      expect(
        lines(book).firstWhere((r) => r.cells[2] == 'Other income').cells[3],
        'Jubilee Insurance',
      );

      final all = await run(ReportKind.allTransactions);
      final kinds = [for (final r in lines(all)) r.cells[2]];
      expect(kinds.where((k) => k == 'Other income'), hasLength(1));
      expect(kinds.where((k) => k == 'Charge'), hasLength(1));
      final byType = {
        for (final r in all.rows.where((r) => r.style == RowStyle.subtotal))
          r.cells[2]: r.cells[4],
      };
      expect(byType['Other income'], const Money.rupees(3000));
      expect(byType['Charge'], const Money.rupees(500));

      final flow = await run(ReportKind.cashflow);
      expect(cell(flow, 'Other income', 2), const Money.rupees(3000));
      final year = await run(ReportKind.cashflow, period: sinceJune);
      expect(cell(year, 'Loans taken', 2), const Money.rupees(495000));
      expect(cell(year, 'Loans paid back', 2), const Money.rupees(25000));
    });

    test('the home\'s spending is never in an expense report, and is shown '
        'apart beside the shop\'s', () async {
      final vouchers = await run(ReportKind.expenseTransactions);
      expect(lines(vouchers), hasLength(1));
      expect(total(vouchers, 'Amount'), const Money.rupees(4000));
      expect(figure(vouchers, homeTile), const Money.rupees(16000));
      expect(
        vouchers.notes.last,
        contains('Rs 1,000.00 of it goods taken home at cost'),
      );

      final heads = await run(ReportKind.expenseCategories);
      expect(total(heads, 'Amount'), const Money.rupees(4000));
      expect(figure(heads, homeTile), const Money.rupees(16000));
      final items = await run(ReportKind.expenseItems);
      expect(total(items, 'Amount'), const Money.rupees(4000));
      expect([
        for (final r in lines(items)) r.cells[1],
      ], isNot(contains('Bachon ki school fees')));

      // The profit and loss never had it: rent, the bad debt and the
      // settlement discount are the day's expenses, and nothing else.
      final pnl = await run(ReportKind.profitAndLoss);
      expect(cell(pnl, "Owner's Drawings"), isNull);
      expect(cell(pnl, 'Total expenses'), const Money.rupees(4000 + 1000 + 50));
      final byHead = await run(ReportKind.expenses);
      expect(cell(byHead, "Owner's Drawings"), isNull);

      // The night's Z report keeps it apart too.
      final z = await run(ReportKind.dailySummary);
      expect(cell(z, 'Expenses, 1 voucher'), const Money.rupees(4000));
      expect(cell(z, 'Ghar ka kharcha, 2 entries'), const Money.rupees(16000));
      expect(figure(z, DayFigureLabel.expenses), const Money.rupees(4000));
      expect(figure(z, DayFigureLabel.udhaarGiven), const Money.rupees(500));

      // The day book and all transactions name it, and the cash flow too.
      final book = await run(ReportKind.dayBook);
      expect(
        [
          for (final r in lines(book)) r.cells[2],
        ].where((k) => k == "Owner's drawings (ghar)"),
        hasLength(2),
      );
      final all = await run(ReportKind.allTransactions);
      expect(
        [for (final r in lines(all)) r.cells[2]].where((k) => k == 'Expense'),
        hasLength(1),
      );
      final flow = await run(ReportKind.cashflow);
      expect(
        cell(flow, "Taken for the home (owner's drawings)", 1),
        const Money.rupees(15000),
      );
      expect(cell(flow, 'Expenses', 1), const Money.rupees(4000));

      // The trading account says where the tins went.
      final trading = await run(ReportKind.profitAndLoss, period: sinceJune);
      expect(trading.notes.last, contains('taken home by the owner'));
    });

    test('sales by item has khula maal as one row, and comes to every '
        'bill\'s sales', () async {
      final items = await run(ReportKind.salesByItem, period: sinceJune);
      final loose = lines(
        items,
      ).firstWhere((r) => r.cells.first == ItemTrade.looseLines);
      expect(loose.cells[3], const Money.rupees(300));
      expect(loose.cells[1], isNull, reason: 'nothing to count it in');
      expect(loose.cells[4], isNull, reason: 'no cost on record');
      expect(total(items, 'Sales'), const Money.rupees(8000));

      final bills = await run(ReportKind.billWiseProfit, period: sinceJune);
      expect(total(items, 'Sales'), total(bills, 'Sale amount'));
      // A shop that charges no tax: the bills' own totals are the same.
      final sales = await run(ReportKind.saleReport, period: sinceJune);
      expect(total(items, 'Sales'), total(sales, 'Total'));
      expect(total(items, 'Profit'), total(bills, 'Profit'));
    });

    test('a write-off and a settlement discount read as what they were, '
        'and are not money paid in', () async {
      final all = await run(ReportKind.allTransactions);
      final kinds = [for (final r in lines(all)) r.cells[2]];
      expect(kinds.where((k) => k == 'Written off'), hasLength(2));
      expect(kinds.where((k) => k == 'Settlement discount'), hasLength(1));
      final byType = {
        for (final r in all.rows.where((r) => r.style == RowStyle.subtotal))
          r.cells[2]: r.cells[4],
      };
      expect(byType['Payment in'], const Money.rupees(950));
      expect(byType['Written off'], const Money.rupees(1000));
      expect(byType['Settlement discount'], const Money.rupees(50));

      final book = await run(ReportKind.dayBook);
      expect([
        for (final r in lines(book)) r.cells[2],
      ], containsAll(['Written off', 'Settlement discount', 'Payment']));

      final statement = await run(
        ReportKind.partyStatement,
        filters: ReportFilters(partyId: akbar, partyName: 'Akbar'),
        period: sinceJune,
      );
      final off = lines(
        statement,
      ).firstWhere((r) => r.cells[1] == 'Written off');
      expect(off.cells[4], const Money.rupees(1000));
    });
  });

  group('money owed both ways', () {
    test('the loan statement closes on the loan account\'s balance, and all '
        'loans on the balance sheet\'s', () async {
      final owed = await balance((a) => a.id == loan);
      expect(owed, const Money.rupees(500000 - 17356));

      final one = await run(
        ReportKind.loanStatement,
        period: sinceJune,
        filters: ReportFilters(loanId: loan, loanName: 'Loan from Meezan Bank'),
      );
      expect(one.id, 'loan_statement');
      expect(total(one, 'Outstanding'), owed);
      expect(total(one, 'Principal paid'), const Money.rupees(17356));
      expect(total(one, 'Interest'), const Money.rupees(7644));
      expect(one.filters, ['Loan: Loan from Meezan Bank']);

      final all = await run(ReportKind.loanStatement, period: sinceJune);
      expect(all.id, 'loans');
      final row = lines(all).single;
      expect(row.cells.sublist(0, 3), [
        'Loan from Meezan Bank',
        'Meezan Bank',
        '2026-07-01',
      ]);
      expect(row.link?.kind, ReportLinkKind.loan);
      expect(total(all, 'Outstanding'), owed);
      expect(total(all, 'Received'), const Money.rupees(500000));
      expect(total(all, 'Principal repaid'), const Money.rupees(17356));
      expect(total(all, 'Interest'), const Money.rupees(7644));
      final sheet = await run(ReportKind.balanceSheet);
      expect(cell(sheet, 'Loan from Meezan Bank'), owed);

      // The same statement the loan's own screen draws.
      final own = await shop.loans.statement(loan, period: sinceJune);
      expect(own.closing, total(one, 'Outstanding'));

      final choices = await shop.reports.choices(firmId, ReportFilter.loan);
      expect(choices.single.id, loan);
    });

    test(
      'udhaar by due date buckets each bill by days past due, adds up to '
      'the udhaar pack\'s ageing, and owes what Udhaar by age owes',
      () async {
        final t = await run(ReportKind.receivablesByDueDate);
        Object? at(String who, String column) => lines(t)
            .firstWhere((r) => r.cells.first == who)
            .cells[t.columns.indexWhere((c) => c.title == column)];

        expect(lines(t).first.cells.first, 'Akbar', reason: 'most late first');
        expect(at('Akbar', 'Over 90 days late'), const Money.rupees(2000));
        expect(
          at('Rashid Traders', '1-30 days late'),
          const Money.rupees(2000),
        );
        expect(at('Rashid Traders', 'Not yet due'), const Money.rupees(1700));
        expect(at('Bilal', 'Not yet due'), const Money.rupees(500));
        expect(at('Bilal', 'Opening'), const Money.rupees(1000));
        expect(
          lines(t).where((r) => r.cells.first == 'Kamran'),
          isEmpty,
          reason: 'settled',
        );

        final pack = await shop.udhaar.queries.dueAging(
          firmId,
          asOfDateLocal: today.value,
        );
        expect(total(t, 'Not yet due'), pack[DueBucket.notYetDue]);
        expect(total(t, '1-30 days late'), pack[DueBucket.upTo30]);
        expect(total(t, '31-60 days late'), pack[DueBucket.upTo60]);
        expect(total(t, '61-90 days late'), pack[DueBucket.upTo90]);
        expect(total(t, 'Over 90 days late'), pack[DueBucket.over90]);

        final byAge = await run(ReportKind.receivables);
        expect(total(t, 'Owed'), total(byAge, 'Owed'));
        expect(total(t, 'Owed'), const Money.rupees(7200));
        expect(figure(t, 'Overdue'), const Money.rupees(4000));
      },
    );

    test('bad debts and settlement discounts list who, why, how much and who '
        'let it go, the cancelled one counted nowhere, and land on the '
        'profit and loss', () async {
      final t = await run(ReportKind.badDebts);
      expect(lines(t), hasLength(3));
      final akbars = lines(t).firstWhere((r) => r.cells[3] == 'Akbar');
      expect(akbars.cells.sublist(2, 7), [
        'Written off',
        'Akbar',
        'Shehr chhor gaya',
        'Malik Sahib',
        const Money.rupees(1000),
      ]);
      expect(
        lines(t).firstWhere((r) => r.cells[3] == 'Rashid Traders').cells.last,
        'Cancelled, not counted',
      );
      expect(figure(t, 'Written off'), const Money.rupees(1000));
      expect(figure(t, 'Settlement discounts'), const Money.rupees(50));

      final pnl = await run(ReportKind.profitAndLoss);
      expect(cell(pnl, 'Bad Debts'), figure(t, 'Written off'));
      expect(
        cell(pnl, 'Settlement Discount'),
        figure(t, 'Settlement discounts'),
      );
    });
  });

  test('changed and cancelled bills say what was let go and why, what an '
      'edit was, and whose PIN let a cancel through', () async {
    final rent = (await shop.queries.recentExpenses(
      firmId,
    )).firstWhere((e) => e.note == 'October ka kiraya');
    await shop.corrections.editExpense(
      shop.actorNow(),
      documentId: rent.id,
      draft: ExpenseDraft(
        accountSystemKey: 'rent',
        amount: const Money.rupees(400),
        note: 'October ka kiraya',
        paymentAccountId: cash,
      ),
      reason: 'Ek sifar ziyada',
    );
    // Data Lock on: the owner's PIN lets the cancel of Bilal's bill through.
    final owner = shop.currentUser!.id;
    await shop.setPin(owner, '1947');
    await shop.audit.setDataLock(on: true);
    shop.audit.prompt = (ask) async =>
        ApprovalAnswer(userId: owner, pin: '1947');
    final bill = (await shop.udhaar.queries.billsDue(
      firmId,
      bilal,
      asOfDateLocal: today.value,
    )).first;
    await shop.voidDocument(
      shop.actorNow(),
      documentId: bill.documentId,
      reason: 'Galat gahak',
    );

    final t = await run(ReportKind.changedBills);
    ReportRow row(String what, [String? number]) => lines(t).firstWhere(
      (r) => r.cells[2] == what && (number == null || r.cells[3] == number),
    );
    final akbars = lines(
      t,
    ).firstWhere((r) => r.cells[2] == 'Written off' && r.cells[4] == 'Akbar');
    expect(akbars.cells[6], const Money.rupees(1000));
    expect(akbars.cells.last, 'Shehr chhor gaya', reason: 'from the payment');
    expect(row('Settlement discount').cells.last, 'Khulay paisay nahi thay');
    final edited = row('Expense edited');
    expect(edited.cells.sublist(5, 7), [
      const Money.rupees(4000),
      const Money.rupees(400),
    ]);
    expect(edited.cells.last, 'Ek sifar ziyada');
    final voided = row('Voided', bill.docNo);
    expect(voided.cells[8], 'Malik Sahib');
    expect(voided.cells.last, 'Galat gahak');
    expect(edited.cells[8], '', reason: 'Data Lock was off then');

    final big = await run(
      ReportKind.changedBills,
      filters: const ReportFilters(minAmount: Money.rupees(500)),
    );
    expect([
      for (final r in lines(big)) r.cells[2],
    ], isNot(contains('Settlement discount')));
    expect(
      lines(
        big,
      ).every((r) => (r.cells[6]! as Money) >= const Money.rupees(500)),
      isTrue,
    );
    expect(big.filters, ['Rs 500.00 or more']);
  });

  test('the expense list reads a head of the shop\'s own', () async {
    final list = await shop.queries.recentExpenses(firmId);
    final diesel = list.firstWhere((e) => e.note == 'Hafte ka diesel');
    expect(diesel.head, startsWith('#'));
    expect(diesel.amount, const Money.rupees(700));
  });
}
