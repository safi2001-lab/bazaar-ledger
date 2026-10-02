import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// The shop's money and the home's kept apart, other income in the books,
/// and the monthly bills remembered (M47), through the services the screens
/// use, against a real database.
void main() {
  late FixedClock clock;
  late AppServices shop;
  late String firmId;
  late String cash;
  late String bank;

  setUp(() async {
    // 3 October 2026, mid-morning in Lahore.
    clock = FixedClock(DateTime.utc(2026, 10, 3, 6));
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

  Future<ReportTable> run(ReportKind kind) => shop.reports.run(
    kind,
    firmId: firmId,
    period: ReportPeriod(
      BusinessDate('2026-10-01'),
      BusinessDate('2026-10-31'),
    ),
    today: today(),
  );

  Object? row(ReportTable t, String first) =>
      t.rows.where((r) => r.cells.first == first).firstOrNull?.cells[1];

  bool hasRow(ReportTable t, String first) =>
      t.rows.any((r) => r.cells.first == first);

  Future<Money> balance(bool Function(ChartAccount) which) async =>
      (await shop.queries.chartOfAccounts(firmId)).firstWhere(which).onItsSide;

  Future<void> expectBooksBalance() async {
    final trial = await run(ReportKind.trialBalance);
    final totals = trial.rows.last.cells;
    expect(totals[totals.length - 2], totals.last);
    final sheet = await run(ReportKind.balanceSheet);
    expect(sheet.notes.first, startsWith('What the shop has equals'));
    expect(await shop.database.findLedgerImbalances(), isEmpty);
    expect((await shop.checkHealth()).findings, isEmpty);
  }

  Future<RecordedExpense> spend({
    required int rupees,
    String head = 'rent',
    bool home = false,
    String note = 'October ka kiraya',
    String? tag,
  }) => shop.recordExpense(
    shop.actorNow(),
    ExpenseDraft(
      accountSystemKey: head,
      amount: Money.rupees(rupees),
      note: note,
      paymentAccountId: cash,
      forHome: home,
      tag: tag,
    ),
  );

  Future<RecordedOtherIncome> earn({
    required int rupees,
    String head = 'rent_received',
    String? from,
    String into = 'bank',
    String note = '',
  }) => shop.shopMoney.recordOtherIncome(
    OtherIncomeDraft(
      headKey: head,
      amount: Money.rupees(rupees),
      paymentAccountId: into == 'bank' ? bank : cash,
      receivedOn: today(),
      fromName: from,
      note: note,
    ),
  );

  Future<({String manager, String cashier, String accountant})> staff() async {
    await shop.setPin(shop.currentUser!.id, '1947');
    final manager = await shop.addStaff(
      name: 'Nadeem',
      role: Role.manager,
      pin: '1111',
    );
    final cashier = await shop.addStaff(
      name: 'Bilal',
      role: Role.cashier,
      pin: '2468',
    );
    final accountant = await shop.addStaff(
      name: 'Munshi Aslam',
      role: Role.accountant,
      pin: '1357',
    );
    return (manager: manager, cashier: cashier, accountant: accountant);
  }

  Future<void> signInAs(String userId, String pin) async {
    await shop.lock();
    expect(await shop.signIn(userId, pin), isTrue);
  }

  group('ghar ka kharcha', () {
    test('the home\'s spending never reaches the profit and loss, and lowers '
        'the owner\'s equity', () async {
      await spend(rupees: 40000);
      final fees = await spend(
        rupees: 15000,
        home: true,
        note: 'Bachon ki school fees',
      );

      final lines = await shop.database
          .customSelect(
            'SELECT a.system_key AS k, jl.debit_paisa AS dr, '
            '       jl.credit_paisa AS cr '
            'FROM journal_entries je '
            'JOIN journal_lines jl ON jl.journal_entry_id = je.id '
            'JOIN accounts a ON a.id = jl.account_id '
            "WHERE je.document_id = '${fees.documentId}' ORDER BY jl.line_no",
          )
          .get();
      expect(
        [for (final l in lines) l.read<String>('k')],
        ['owner_drawings', 'cash_in_hand'],
      );
      expect(lines.first.read<int>('dr'), 1500000);

      final pnl = await run(ReportKind.profitAndLoss);
      expect(row(pnl, 'Total expenses'), const Money.rupees(40000));
      expect(hasRow(pnl, "Owner's Drawings"), isFalse);
      expect(row(pnl, 'Net loss'), const Money.rupees(-40000));
      final byHead = await run(ReportKind.expenses);
      expect(hasRow(byHead, "Owner's Drawings"), isFalse);

      final sheet = await run(ReportKind.balanceSheet);
      expect(row(sheet, "Owner's Drawings"), const Money.rupees(-15000));
      expect(row(sheet, 'Profit to date'), const Money.rupees(-40000));
      expect(row(sheet, 'Total equity'), const Money.rupees(-55000));
      expect(
        await balance((a) => a.systemKey == 'cash_in_hand'),
        const Money.rupees(-55000),
      );

      final split = await shop.shopMoney.thisMonth();
      expect(split.shop, const Money.rupees(40000));
      expect(split.home, const Money.rupees(15000));
      final book = await shop.shopMoney.expenseBook();
      expect(book.where((r) => r.forHome).single.headKey, 'owner_drawings');
      await expectBooksBalance();
    });

    test('the home\'s spending is paid now, never left owed to a party', () {
      expect(
        () => const ExpenseBuilder().build(
          actor: shop.actorNow(),
          draft: const ExpenseDraft(
            accountSystemKey: 'misc',
            amount: Money.rupees(500),
            note: 'Ghar ka doodh',
            partyId: 'someone',
            forHome: true,
          ),
          expenseNumber: const AllocatedNumber(
            formatted: 'EXP-1',
            series: 'EXP',
            sequence: 1,
          ),
          journalNumber: const AllocatedNumber(
            formatted: 'JV-1',
            series: 'JV',
            sequence: 1,
          ),
        ),
        throwsA(isA<ExpenseRefused>()),
      );
    });

    test('goods taken home leave the shelf at cost against the owner, and a '
        'cancel puts them back', () async {
      final units = await shop.queries.units(firmId);
      final kg = units.firstWhere((u) => u.code == 'pcs');
      final ghee = await shop.catalogue.addItem(
        shop.actorNow(),
        ItemDraft(
          name: 'Dalda Ghee 1kg',
          baseUnitId: kg.id,
          saleRate: Rate.rupees(600),
          openingStock: Qty.units(10),
          openingRate: Rate.rupees(500),
        ),
      );
      final before = await balance((a) => a.systemKey == 'inventory');

      final taken = await shop.shopMoney.takeGoodsHome(
        GoodsTakenHomeDraft(itemId: ghee, qty: Qty.units(2), note: 'Eid'),
      );
      expect(taken.amount, const Money.rupees(1000));
      expect(
        (await shop.queries.itemById(firmId, ghee))!.stockOnHand,
        Qty.units(8),
      );
      expect(
        await balance((a) => a.systemKey == 'inventory'),
        before - const Money.rupees(1000),
      );
      expect(
        await balance((a) => a.systemKey == 'owner_drawings'),
        const Money.rupees(-1000),
        reason: 'equity reads on its own side: drawings lower it',
      );
      final pnl = await run(ReportKind.profitAndLoss);
      expect(row(pnl, 'Total expenses'), Money.zero);
      final facts = await shop.shopMoney.expenseFacts(taken.documentId);
      expect(facts!.goods, isTrue);
      expect(facts.forHome, isTrue);
      await expectBooksBalance();

      // More than the shelf holds is refused in words.
      await expectLater(
        shop.shopMoney.takeGoodsHome(
          GoodsTakenHomeDraft(itemId: ghee, qty: Qty.units(20)),
        ),
        throwsA(isA<ExpenseRefused>()),
      );

      await shop.corrections.cancelExpense(
        shop.actorNow(),
        documentId: taken.documentId,
        reason: 'Wapas rakh diya',
      );
      expect(
        (await shop.queries.itemById(firmId, ghee))!.stockOnHand,
        Qty.units(10),
      );
      expect(await balance((a) => a.systemKey == 'inventory'), before);
      expect(await balance((a) => a.systemKey == 'owner_drawings'), Money.zero);
      await expectBooksBalance();
    });

    test('a manager cannot post, correct or cancel the home\'s spending; a '
        'cashier cannot post any expense', () async {
      final people = await staff();
      final fees = await spend(rupees: 15000, home: true, note: 'School fees');
      final rent = await spend(rupees: 40000);

      await signInAs(people.manager, '1111');
      expect(shop.shopMoney.canSpendForHome, isFalse);
      await expectLater(
        spend(rupees: 2000, home: true, note: 'Ghar ka sauda'),
        throwsA(isA<PermissionDenied>()),
      );
      await expectLater(
        shop.corrections.cancelExpense(
          shop.actorNow(),
          documentId: fees.documentId,
          reason: 'Galat',
        ),
        throwsA(isA<PermissionDenied>()),
      );
      await expectLater(
        shop.corrections.editExpense(
          shop.actorNow(),
          documentId: rent.documentId,
          draft: ExpenseDraft(
            accountSystemKey: 'rent',
            amount: const Money.rupees(40000),
            note: 'Actually the house rent',
            paymentAccountId: cash,
            forHome: true,
          ),
          reason: 'Ghar ka tha',
        ),
        throwsA(isA<PermissionDenied>()),
      );
      // A shop expense is the manager's to keep, as it always was.
      await spend(rupees: 300, head: 'misc', note: 'Chai');
      final standing = await shop.database
          .customSelect(
            "SELECT COUNT(*) AS n FROM documents WHERE doc_type = 'expense' "
            "AND status = 'posted'",
          )
          .getSingle();
      expect(standing.read<int>('n'), 3, reason: 'nothing was cancelled');

      await signInAs(people.cashier, '2468');
      expect(() => shop.recordExpense, throwsA(isA<PermissionDenied>()));
      await expectLater(
        shop.shopMoney.takeGoodsHome(
          GoodsTakenHomeDraft(itemId: 'x', qty: Qty.units(1)),
        ),
        throwsA(isA<PermissionDenied>()),
      );
      await expectLater(earn(rupees: 100), throwsA(isA<PermissionDenied>()));

      await signInAs(people.accountant, '1357');
      expect(shop.shopMoney.canSpendForHome, isTrue);
      await spend(rupees: 2000, home: true, note: 'Ghar ka sauda');
      await shop.corrections.cancelExpense(
        shop.actorNow(),
        documentId: fees.documentId,
        reason: 'Do baar likh di',
      );
      await expectBooksBalance();
    });
  });

  group('other income', () {
    test('other income reaches the profit and loss as other income, below '
        'gross profit, and a cancel takes it out', () async {
      final rent = await earn(rupees: 8000, from: 'Ustad Tailor (upar wala)');
      await earn(rupees: 1200, head: 'scrap', into: 'cash', note: 'Kabari');

      final pnl = await run(ReportKind.profitAndLoss);
      expect(row(pnl, 'Net sales'), Money.zero);
      expect(row(pnl, 'Other Income'), const Money.rupees(9200));
      expect(row(pnl, 'Total other income'), const Money.rupees(9200));
      expect(row(pnl, 'Net profit'), const Money.rupees(9200));
      expect(
        await balance((a) => a.systemKey == 'bank'),
        const Money.rupees(8000),
      );

      final lines = await shop.database
          .customSelect(
            'SELECT DISTINCT jl.cost_centre AS tag FROM journal_lines jl '
            'JOIN journal_entries je ON je.id = jl.journal_entry_id '
            "WHERE je.document_id = '${rent.documentId}'",
          )
          .get();
      expect(
        [for (final l in lines) l.read<String>('tag')],
        ['income:rent_received'],
      );
      final byHead = await shop.shopMoney.incomeThisMonth();
      expect(byHead['rent_received'], const Money.rupees(8000));
      expect(byHead['scrap'], const Money.rupees(1200));

      await shop.shopMoney.cancelOtherIncome(
        documentId: rent.documentId,
        reason: 'Do baar likh di',
      );
      final after = await run(ReportKind.profitAndLoss);
      expect(row(after, 'Total other income'), const Money.rupees(1200));
      expect(await balance((a) => a.systemKey == 'bank'), Money.zero);
      final detail = await shop.shopMoney.otherIncome(rent.documentId);
      expect(detail!.isCancelled, isTrue);
      expect(detail.voidReason, 'Do baar likh di');
      expect(detail.fromName, 'Ustad Tailor (upar wala)');
      expect(
        [for (final r in await shop.shopMoney.otherIncomes()) r.headKey],
        ['scrap'],
      );
      await expectBooksBalance();
    });

    test('an edited entry leaves one standing at the new amount, tied to the '
        'one it replaced', () async {
      final wrong = await earn(rupees: 80000);
      final fixed = await shop.shopMoney.editOtherIncome(
        documentId: wrong.documentId,
        draft: OtherIncomeDraft(
          headKey: 'rent_received',
          amount: const Money.rupees(8000),
          paymentAccountId: bank,
          receivedOn: today(),
        ),
        reason: 'Galat raqam',
      );
      expect(fixed.cancelledNo, wrong.docNo);
      final standing = await shop.shopMoney.otherIncomes();
      expect(standing.single.amount, const Money.rupees(8000));
      final linked = await shop.database
          .customSelect(
            'SELECT COUNT(*) AS n FROM audit_log '
            "WHERE action_code = 'OTHER_INCOME_EDITED'",
          )
          .getSingle();
      expect(linked.read<int>('n'), 1);
      expect(
        row(await run(ReportKind.profitAndLoss), 'Total other income'),
        const Money.rupees(8000),
      );
      await expectBooksBalance();
    });

    test('the shop\'s income never reaches a khata, and a charge is never '
        'cancelled as the shop\'s income', () async {
      final rashid = await shop.catalogue.addParty(
        shop.actorNow(),
        const PartyDraft(name: 'Rashid Traders'),
      );
      final charge = await shop.chargeParty(
        shop.actorNow(),
        DebitNoteDraft(
          partyId: rashid,
          partyName: 'Rashid Traders',
          amount: const Money.rupees(500),
          note: 'Bounced cheque ka bank charge',
        ),
      );
      await earn(rupees: 3000, head: 'commission', from: 'Rashid Traders');

      final party = await shop.queries.partyById(firmId, rashid);
      expect(party!.balance, const Money.rupees(500));
      final khata = await shop.queries.partyLedger(firmId, rashid);
      expect(khata, hasLength(1));
      expect(
        [for (final r in await shop.shopMoney.otherIncomes()) r.headKey],
        ['commission'],
      );
      await expectLater(
        shop.shopMoney.cancelOtherIncome(
          documentId: charge.id,
          reason: 'Galat',
        ),
        throwsA(isA<VoidRefused>()),
      );
      // M31's charge cancel still takes the charge back from the khata.
      await shop.corrections.cancelCharge(
        shop.actorNow(),
        documentId: charge.id,
        reason: 'Maaf kar diya',
      );
      expect(
        (await shop.queries.partyById(firmId, rashid))!.balance,
        Money.zero,
      );
      await expectBooksBalance();
    });

    test('income under "other" has to say what it was; a day not yet come '
        'and a cheque drawer are refused', () async {
      await expectLater(
        earn(rupees: 100, head: 'other'),
        throwsA(isA<OtherIncomeRefused>()),
      );
      await expectLater(
        shop.shopMoney.recordOtherIncome(
          OtherIncomeDraft(
            headKey: 'interest',
            amount: const Money.rupees(100),
            paymentAccountId: bank,
            receivedOn: today().addDays(1),
          ),
        ),
        throwsA(isA<OtherIncomeRefused>()),
      );
      final cheque = (await shop.queries.paymentAccounts(
        firmId,
      )).where((a) => a.modeLabel == 'cheque').firstOrNull;
      if (cheque != null) {
        await expectLater(
          shop.shopMoney.recordOtherIncome(
            OtherIncomeDraft(
              headKey: 'interest',
              amount: const Money.rupees(100),
              paymentAccountId: cheque.id,
              receivedOn: today(),
            ),
          ),
          throwsA(isA<OtherIncomeRefused>()),
        );
      }
      expect(await shop.shopMoney.otherIncomes(), isEmpty);
    });

    test('a head of income of the shop\'s own is added, used, renamed and '
        'hidden', () async {
      final key = await shop.shopMoney.addIncomeHead(
        'JazzCash load commission',
      );
      await earn(rupees: 450, head: key, into: 'cash');
      expect(
        (await shop.shopMoney.incomeThisMonth())[key],
        const Money.rupees(450),
      );

      await shop.shopMoney.renameIncomeHead('scrap', 'Raddi aur khali boriyan');
      await shop.shopMoney.setIncomeHeadHidden('refund', true);
      final heads = {
        for (final h in await shop.shopMoney.incomeHeads()) h.key: h,
      };
      expect(heads['scrap']!.name, 'Raddi aur khali boriyan');
      expect(heads['refund']!.hidden, isTrue);
      expect(heads[key]!.name, 'JazzCash load commission');
      await expectLater(
        shop.shopMoney.addIncomeHead('raddi aur khali boriyan'),
        throwsA(isA<HeadRefused>()),
      );
      await expectLater(
        earn(rupees: 10, head: 'own_not_a_head'),
        throwsA(isA<OtherIncomeRefused>()),
      );
    });
  });

  group('expense heads', () {
    test('a head of the shop\'s own is used, renamed, hidden, and moved '
        'across the gross profit line', () async {
      final diesel = await shop.shopMoney.addExpenseHead(
        name: 'Generator diesel',
        isDirect: false,
      );
      await spend(rupees: 5000, head: '#$diesel', note: 'Hafte ka diesel');

      var pnl = await run(ReportKind.profitAndLoss);
      expect(row(pnl, 'Generator diesel'), const Money.rupees(5000));
      expect(row(pnl, 'Total expenses'), const Money.rupees(5000));
      expect(row(pnl, 'Gross profit'), Money.zero);

      await shop.shopMoney.renameExpenseHead(diesel, 'Generator ka diesel');
      await shop.shopMoney.setExpenseHeadDirect(diesel, true);
      pnl = await run(ReportKind.profitAndLoss);
      expect(row(pnl, 'Generator ka diesel'), const Money.rupees(5000));
      expect(row(pnl, 'Total cost of sales'), const Money.rupees(5000));
      expect(row(pnl, 'Gross profit'), const Money.rupees(-5000));
      expect(row(pnl, 'Total expenses'), Money.zero);

      await shop.shopMoney.setExpenseHeadHidden(diesel, true);
      final heads = await shop.shopMoney.expenseHeads();
      final mine = heads.firstWhere((h) => h.accountId == diesel);
      expect(mine.hidden, isTrue);
      expect(mine.isDirect, isTrue);
      expect(mine.key, '#$diesel');
      // The shipped heads keep their order, the shop's own before misc.
      expect(
        [for (final h in heads) h.key],
        ['rent', 'salaries', 'utilities', 'freight', '#$diesel', 'misc'],
      );

      final book = await shop.shopMoney.expenseBook();
      expect(book.single.headName, 'Generator ka diesel');
      expect(book.single.headKey, '#$diesel');
      await expectBooksBalance();
    });

    test('an account that is not a head is refused, and so is a name the '
        'chart already has', () async {
      final cogs = (await shop.queries.chartOfAccounts(
        firmId,
      )).firstWhere((a) => a.systemKey == 'cogs');
      await expectLater(
        spend(rupees: 100, head: '#${cogs.id}', note: 'Ulta seedha'),
        throwsA(isA<ExpenseRefused>()),
      );
      await expectLater(
        shop.shopMoney.addExpenseHead(name: 'rent', isDirect: false),
        throwsA(isA<HeadRefused>()),
      );
      await expectLater(
        shop.shopMoney.setExpenseHeadDirect(cogs.id, false),
        throwsA(isA<HeadRefused>()),
      );
    });
  });

  group('monthly bills', () {
    test('a bill is due on its day, paid by the expense it opens, and due '
        'again when that is cancelled', () async {
      final rent = MonthlyBill(
        id: shop.shopMoney.newMonthlyBillId(),
        headKey: 'rent',
        amount: const Money.rupees(40000),
        note: 'Dukaan ka kiraya',
        day: 1,
        paymentAccountId: bank,
      );
      final bijli = MonthlyBill(
        id: shop.shopMoney.newMonthlyBillId(),
        headKey: 'utilities',
        amount: const Money.rupees(9000),
        note: 'LESCO bill',
        day: 10,
      );
      await shop.shopMoney.saveMonthlyBill(rent);
      await shop.shopMoney.saveMonthlyBill(bijli);

      var due = await shop.shopMoney.billsDueNow();
      expect([for (final d in due) d.bill.note], ['Dukaan ka kiraya']);
      expect(due.single.dueOn, BusinessDate('2026-10-01'));

      // Pay now: the expense the card opens, filled in from the bill.
      final draft = due.single.bill.draft(paymentAccountId: bank);
      expect(draft.amount, const Money.rupees(40000));
      expect(draft.tag, 'expense:recurring:${rent.id}');
      final paid = await shop.recordExpense(shop.actorNow(), draft);
      expect(await shop.shopMoney.billsDueNow(), isEmpty);

      await shop.corrections.cancelExpense(
        shop.actorNow(),
        documentId: paid.documentId,
        reason: 'Galat account se',
      );
      due = await shop.shopMoney.billsDueNow();
      expect([for (final d in due) d.bill.note], ['Dukaan ka kiraya']);

      await shop.shopMoney.skipThisMonth(due.single.bill);
      expect(await shop.shopMoney.billsDueNow(), isEmpty);

      // The 10th: bijli is due; rent stays skipped for October.
      clock.set(DateTime.utc(2026, 10, 10, 6));
      due = await shop.shopMoney.billsDueNow();
      expect([for (final d in due) d.bill.note], ['LESCO bill']);

      // November: both come round again.
      clock.set(DateTime.utc(2026, 11, 12, 6));
      due = await shop.shopMoney.billsDueNow();
      expect(
        [for (final d in due) d.bill.note],
        ['Dukaan ka kiraya', 'LESCO bill'],
      );
      await expectBooksBalance();
    });

    test('a bill on the 31st falls due on the last day of a shorter month', () {
      final salaries = MonthlyBill(
        id: 'b1',
        headKey: 'salaries',
        amount: const Money.rupees(25000),
        note: 'Bilal ki tankhwah',
        day: 31,
      );
      expect(salaries.dueIn(2026, 11), BusinessDate('2026-11-30'));
      expect(salaries.dueIn(2027, 2), BusinessDate('2027-02-28'));
      expect(
        billsDue(
          bills: [salaries],
          paidTags: const {},
          today: BusinessDate('2026-11-29'),
        ),
        isEmpty,
      );
      expect(
        billsDue(
          bills: [salaries],
          paidTags: const {},
          today: BusinessDate('2026-11-30'),
        ),
        hasLength(1),
      );
      final back = MonthlyBill.fromJson('b1', salaries.toJson())!;
      expect(back.day, 31);
      expect(back.amount, const Money.rupees(25000));
    });

    test('an expense saved with a reminder keeps the bill, this month '
        'already paid', () async {
      await shop.shopMoney.recordExpense(
        ExpenseDraft(
          accountSystemKey: 'rent',
          amount: const Money.rupees(40000),
          note: 'Dukaan ka kiraya',
          paymentAccountId: cash,
        ),
        remindOnDay: 1,
      );
      final bills = await shop.shopMoney.monthlyBills();
      expect(bills.single.note, 'Dukaan ka kiraya');
      expect(bills.single.day, 1);
      expect(await shop.shopMoney.billsDueNow(), isEmpty);

      clock.set(DateTime.utc(2026, 11, 1, 6));
      expect(await shop.shopMoney.billsDueNow(), hasLength(1));
    });

    test('the home\'s monthly bill is kept and shown only to who may pay '
        'it', () async {
      final people = await staff();
      final fees = MonthlyBill(
        id: shop.shopMoney.newMonthlyBillId(),
        headKey: ownerDrawingsKey,
        amount: const Money.rupees(15000),
        note: 'School fees',
        day: 1,
        forHome: true,
      );
      await shop.shopMoney.saveMonthlyBill(fees);
      expect(await shop.shopMoney.billsDueNow(), hasLength(1));

      await signInAs(people.manager, '1111');
      expect(await shop.shopMoney.billsDueNow(), isEmpty);
      await expectLater(
        shop.shopMoney.removeMonthlyBill(fees),
        throwsA(isA<PermissionDenied>()),
      );
    });
  });
}
