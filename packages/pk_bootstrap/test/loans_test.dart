import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// Loans the shop has taken, their repayments and a statement for each
/// (M48), through the services the screens use, against a real database.
void main() {
  late FixedClock clock;
  late AppServices shop;
  late String firmId;
  late String cash;
  late String bank;

  setUp(() async {
    clock = FixedClock(DateTime.utc(2026, 8, 1, 6));
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
  });

  tearDown(() => shop.close());

  BusinessDate today() => BusinessDate.now(clock);

  Future<ChartAccount> account(bool Function(ChartAccount) which) async =>
      (await shop.queries.chartOfAccounts(firmId)).firstWhere(which);

  Future<String> borrow({
    int rupees = 500000,
    int fee = 0,
    String into = 'bank',
    String takenOn = '2026-07-01',
  }) => shop.loans.take(
    LoanDraft(
      lender: 'Meezan Bank',
      amount: Money.rupees(rupees),
      fee: Money.rupees(fee),
      intoPaymentAccountId: into == 'bank' ? bank : cash,
      takenOn: BusinessDate(takenOn),
      rateBp: 1800,
      termMonths: 24,
      instalment: const Money.rupees(25000),
    ),
  );

  Future<String> payBack(
    String loan, {
    required int paid,
    int interest = 0,
    int charges = 0,
  }) => shop.loans.repay(
    RepaymentDraft(
      loanId: loan,
      paid: Money.rupees(paid),
      interest: Money.rupees(interest),
      charges: Money.rupees(charges),
      fromPaymentAccountId: bank,
      paidOn: today(),
    ),
  );

  Future<ReportTable> run(ReportKind kind, ReportPeriod period) =>
      shop.reports.run(kind, firmId: firmId, period: period, today: today());

  Object? row(ReportTable t, String first) =>
      t.rows.where((r) => r.cells.first == first).firstOrNull?.cells[1];

  Future<void> expectBooksBalance() async {
    final trial = await run(ReportKind.trialBalance, ReportPeriod.day(today()));
    final totals = trial.rows.last.cells;
    expect(totals[totals.length - 2], totals.last);
    final sheet = await run(ReportKind.balanceSheet, ReportPeriod.day(today()));
    expect(sheet.notes.first, startsWith('What the shop has equals'));
    expect(await shop.database.findLedgerImbalances(), isEmpty);
  }

  group('loans', () {
    test('taking a loan raises the bank and the liability, the fee is a '
        'cost, and the books balance', () async {
      final loan = await borrow(fee: 5000);

      final bankAccount = await account((a) => a.systemKey == 'bank');
      expect(bankAccount.onItsSide, const Money.rupees(495000));
      final loanAccount = await account((a) => a.id == loan);
      expect(loanAccount.name, 'Loan from Meezan Bank');
      expect(loanAccount.type, 'liability');
      expect(loanAccount.onItsSide, const Money.rupees(500000));
      expect(int.parse(loanAccount.code), inInclusiveRange(2401, 2999));

      final sheet = await run(
        ReportKind.balanceSheet,
        ReportPeriod.day(today()),
      );
      expect(row(sheet, 'Loan from Meezan Bank'), const Money.rupees(500000));
      final pl = await run(
        ReportKind.profitAndLoss,
        ReportPeriod.fiscalYearOf(today()),
      );
      expect(row(pl, 'Loan Processing Fee'), const Money.rupees(5000));
      await expectBooksBalance();

      final listed = (await shop.loans.list()).single;
      expect(listed.owed, const Money.rupees(500000));
      expect(listed.terms!.lender, 'Meezan Bank');
      expect(listed.terms!.instalment, const Money.rupees(25000));
    });

    test('a repayment splits principal from interest, and the interest '
        'reaches the profit and loss', () async {
      final loan = await borrow();
      final suggested = await shop.loans.suggestRepayment(loan, today());
      expect(suggested.paid, const Money.rupees(25000));
      // Rs 5 lakh at 18% for the 31 days of July.
      expect(suggested.interest, Money.parse('7643.84'));

      await payBack(loan, paid: 25000, interest: 7644, charges: 250);

      expect(
        (await account((a) => a.id == loan)).onItsSide,
        const Money.rupees(500000 - 17106),
      );
      final pl = await run(
        ReportKind.profitAndLoss,
        ReportPeriod.fiscalYearOf(today()),
      );
      expect(row(pl, 'Loan Interest'), const Money.rupees(7644));
      expect(row(pl, 'Loan Charges'), const Money.rupees(250));
      expect(row(pl, 'Net loss'), const Money.rupees(-7894));
      await expectBooksBalance();
    });

    test('the statement closes on the loan account\'s balance', () async {
      final loan = await borrow();
      await payBack(loan, paid: 25000, interest: 7644);
      clock.set(DateTime.utc(2026, 9, 1, 6));
      // A month of interest only: nothing comes off the loan.
      await payBack(loan, paid: 7400, interest: 7400);

      final st = await shop.loans.statement(loan);
      expect(st.opening, Money.zero);
      expect(st.lines, hasLength(3));
      expect(st.lines.last.repaid, Money.zero);
      expect(st.lines.last.interest, const Money.rupees(7400));
      expect(st.interest, const Money.rupees(7644 + 7400));
      expect(st.closing, (await account((a) => a.id == loan)).onItsSide);

      final august = await shop.loans.statement(
        loan,
        period: ReportPeriod.monthOf(const BusinessDate('2026-08-15')),
      );
      expect(august.opening, const Money.rupees(500000));
      expect(august.closing, const Money.rupees(500000 - 17356));

      final table = loanStatementTable(
        st,
        terms: (await shop.loans.list()).single.terms,
      );
      expect(table.rows.last.cells.last, st.closing);
      expect(reportToCsv(table), contains('Principal paid'));
    });

    test('a principal over what is owed is refused, and nothing is '
        'written', () async {
      final loan = await borrow(rupees: 50000);
      final before = await shop.database
          .customSelect('SELECT COUNT(*) AS n FROM journal_entries')
          .getSingle();

      await expectLater(
        payBack(loan, paid: 60000),
        throwsA(
          isA<LoanRefused>().having(
            (r) => r.reason,
            'reason',
            contains('still owed'),
          ),
        ),
      );
      final after = await shop.database
          .customSelect('SELECT COUNT(*) AS n FROM journal_entries')
          .getSingle();
      expect(after.read<int>('n'), before.read<int>('n'));
      expect(
        (await account((a) => a.id == loan)).onItsSide,
        const Money.rupees(50000),
      );
    });

    test('a cancelled repayment puts back what was owed', () async {
      final loan = await borrow();
      await payBack(loan, paid: 25000, interest: 7644);
      final repayment = (await shop.loans.postings(loan)).last;

      await shop.loans.cancel(
        loanId: loan,
        entryId: repayment.entryId,
        reason: 'Paid from the wrong account',
      );

      expect(
        (await account((a) => a.id == loan)).onItsSide,
        const Money.rupees(500000),
      );
      expect(
        (await account((a) => a.systemKey == 'bank')).onItsSide,
        const Money.rupees(500000),
      );
      final pl = await run(
        ReportKind.profitAndLoss,
        ReportPeriod.fiscalYearOf(today()),
      );
      expect(row(pl, 'Loan Interest'), Money.zero);
      final st = await shop.loans.statement(loan);
      expect(st.lines.last.kind, LoanLineKind.cancelled);
      expect(st.repaid, Money.zero);
      expect(st.closing, const Money.rupees(500000));
      await expectLater(
        shop.loans.cancel(
          loanId: loan,
          entryId: repayment.entryId,
          reason: 'Again',
        ),
        throwsA(isA<LoanRefused>()),
      );
      await expectBooksBalance();
    });

    test('a loan cannot be cancelled while a repayment stands; once it is '
        'cancelled, the loan can be', () async {
      final loan = await borrow(fee: 2000);
      await payBack(loan, paid: 25000, interest: 7644);
      final postings = await shop.loans.postings(loan);

      await expectLater(
        shop.loans.cancel(
          loanId: loan,
          entryId: postings.first.entryId,
          reason: 'Entered by mistake',
        ),
        throwsA(isA<LoanRefused>()),
      );
      await shop.loans.cancel(
        loanId: loan,
        entryId: postings.last.entryId,
        reason: 'Entered by mistake',
      );
      await shop.loans.cancel(
        loanId: loan,
        entryId: postings.first.entryId,
        reason: 'Entered by mistake',
      );

      final listed = (await shop.loans.list()).single;
      expect(listed.cancelled, isTrue);
      expect(listed.owed, Money.zero);
      expect(
        (await account((a) => a.systemKey == 'bank')).onItsSide,
        Money.zero,
      );
      await expectLater(payBack(loan, paid: 1000), throwsA(isA<LoanRefused>()));
      await expectBooksBalance();
    });

    test('a loan in cash is cash in the drawer', () async {
      await borrow(rupees: 50000, into: 'cash');
      expect(
        await shop.queries.cashInDrawer(firmId),
        const Money.rupees(50000),
      );
    });

    test('only the owner and the accountant take loans, and a free shop '
        'pays one back but cannot start one', () async {
      final loan = await borrow();
      await shop.setPin(shop.currentUser!.id, '1947');
      final bilal = await shop.addStaff(
        name: 'Bilal',
        role: Role.cashier,
        pin: '2468',
      );
      final munshi = await shop.addStaff(
        name: 'Munshi Aslam',
        role: Role.accountant,
        pin: '1357',
      );
      await shop.lock();
      await shop.signIn(bilal, '2468');
      await expectLater(borrow(), throwsA(isA<PermissionDenied>()));
      await expectLater(
        payBack(loan, paid: 1000),
        throwsA(isA<PermissionDenied>()),
      );
      await expectLater(shop.loans.list(), throwsA(isA<PermissionDenied>()));

      await shop.lock();
      await shop.signIn(munshi, '1357');
      await payBack(loan, paid: 1000);

      shop.plans.pinForTests(Plan.free);
      await expectLater(borrow(), throwsA(isA<PlanRequired>()));
      await payBack(loan, paid: 1000);
      expect(
        (await shop.loans.statement(loan)).closing,
        const Money.rupees(498000),
      );
    });

    test('a second loan from the same bank is an account of its own', () async {
      final first = await borrow();
      final second = await borrow(rupees: 100000);
      expect(first, isNot(second));
      final names = [for (final l in await shop.loans.list()) l.name];
      expect(names, ['Loan from Meezan Bank', 'Loan from Meezan Bank (2)']);
      final groups = await shop.database
          .customSelect(
            "SELECT COUNT(*) AS n FROM accounts WHERE system_key = 'loans'",
          )
          .getSingle();
      expect(groups.read<int>('n'), 1);
    });
  });
}
