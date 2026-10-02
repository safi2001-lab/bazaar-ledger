import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// The shop's money and the home's, other income, and goods taken home
/// (M47), as pure rules: no database, every figure exact to the paisa.
void main() {
  // 3 October 2026, mid-morning in Lahore.
  final actor = ActorContext(
    firmId: 'firm',
    userId: 'owner',
    deviceId: 'counter-1',
    startedAtUtc: DateTime.utc(2026, 10, 3, 6),
  );
  const number = AllocatedNumber(
    formatted: 'INC-2627-0001',
    series: 'INC',
    sequence: 1,
  );
  const journal = AllocatedNumber(
    formatted: 'JV-2627-00001',
    series: 'JV',
    sequence: 1,
  );

  ExpensePosting expense(ExpenseDraft draft) => const ExpenseBuilder().build(
    actor: actor,
    draft: draft,
    expenseNumber: number,
    journalNumber: journal,
    ledgerAccountId: draft.isPaidNow ? 'cash' : null,
  );

  group('shop money', () {
    test('the home\'s spending is posted to the owner\'s drawings, its '
        'head ignored', () {
      final posting = expense(
        const ExpenseDraft(
          accountSystemKey: 'rent',
          amount: Money.rupees(15000),
          note: 'School fees',
          paymentAccountId: 'pa-cash',
          forHome: true,
        ),
      );
      expect(posting.forHome, isTrue);
      expect(posting.headSystemKey, ownerDrawingsKey);
      expect(posting.journal.lines.first.accountSystemKey, ownerDrawingsKey);
      expect(posting.journal.lines.last.accountSystemKey, '#cash');
      expect(posting.journal.narration, startsWith('Ghar ka kharcha'));
    });

    test('a head of the shop\'s own is named by its account, and a tag must '
        'be an expense tag', () {
      final posting = expense(
        const ExpenseDraft(
          accountSystemKey: '#acct-diesel',
          amount: Money.rupees(5000),
          note: 'Diesel',
          paymentAccountId: 'pa-cash',
          tag: 'expense:recurring:b1',
        ),
      );
      expect(posting.journal.lines.first.accountSystemKey, '#acct-diesel');
      expect(posting.costCentre, 'expense:recurring:b1');
      expect(
        () => expense(
          const ExpenseDraft(
            accountSystemKey: 'rent',
            amount: Money.rupees(5000),
            note: 'Kiraya',
            paymentAccountId: 'pa-cash',
            tag: 'loan:acct-1',
          ),
        ),
        throwsA(isA<ExpenseRefused>()),
      );
      expect(isExpenseHeadKey('#'), isFalse);
      expect(isExpenseHeadKey('cogs'), isFalse);
    });

    test('other income is cash or bank against Other Income, with no party '
        'and nothing owed, tagged with its head', () {
      final posting = const OtherIncomeBuilder().build(
        actor: actor,
        draft: OtherIncomeDraft(
          headKey: 'rent_received',
          amount: const Money.rupees(8000),
          paymentAccountId: 'pa-bank',
          receivedOn: const BusinessDate('2026-10-01'),
          fromName: '  Ustad Tailor  ',
        ),
        number: number,
        journalNumber: journal,
        ledgerAccountId: 'bank',
        headName: 'Rent received',
      );
      expect(posting.document.docType, 'other_income');
      expect(posting.document.partyId, isNull);
      expect(posting.document.balance, Money.zero);
      expect(posting.document.paid, const Money.rupees(8000));
      expect(posting.document.partyNameSnapshot, 'Ustad Tailor');
      expect(posting.document.docDateLocal, '2026-10-01');
      expect(posting.journal.sourceType, 'other_income');
      final lines = posting.journal.lines;
      expect(lines.first.accountSystemKey, '#bank');
      expect(lines.first.debit, const Money.rupees(8000));
      expect(lines.last.accountSystemKey, 'other_income');
      expect(lines.last.credit, const Money.rupees(8000));
      expect(posting.costCentre, 'income:rent_received');
      expect(incomeHeadOfTag(posting.costCentre), 'rent_received');
      expect(incomeHeadOfTag('loan:x'), isNull);
    });

    test('other income of nothing, from a day not yet come, or under '
        '"other" with no word of what it was is refused', () {
      OtherIncomePosting build(OtherIncomeDraft draft) =>
          const OtherIncomeBuilder().build(
            actor: actor,
            draft: draft,
            number: number,
            journalNumber: journal,
            ledgerAccountId: 'bank',
            headName: 'Other income',
          );
      expect(
        () => build(
          const OtherIncomeDraft(
            headKey: 'interest',
            amount: Money.zero,
            paymentAccountId: 'pa',
            receivedOn: BusinessDate('2026-10-03'),
          ),
        ),
        throwsA(isA<OtherIncomeRefused>()),
      );
      expect(
        () => build(
          const OtherIncomeDraft(
            headKey: 'interest',
            amount: Money.rupees(10),
            paymentAccountId: 'pa',
            receivedOn: BusinessDate('2026-10-04'),
          ),
        ),
        throwsA(isA<OtherIncomeRefused>()),
      );
      expect(
        () => build(
          const OtherIncomeDraft(
            headKey: 'other',
            amount: Money.rupees(10),
            paymentAccountId: 'pa',
            receivedOn: BusinessDate('2026-10-03'),
          ),
        ),
        throwsA(isA<OtherIncomeRefused>()),
      );
      expect(isIncomeHeadKey('own_01hzx'), isTrue);
      expect(isIncomeHeadKey("x' OR 1"), isFalse);
    });

    test('goods taken home leave at their average cost, against the owner, '
        'with the stock row that takes them off the shelf', () {
      final posting = goodsTakenHome(
        actor: actor,
        draft: GoodsTakenHomeDraft(
          itemId: 'ghee',
          qty: Qty.parts(1, 500),
          note: 'Eid',
        ),
        item: HomeGoodsItem(
          name: 'Dalda Ghee',
          unitCode: 'kg',
          averageCost: Rate.rupees(480),
          onHand: Qty.units(10),
          tracksStock: true,
          tracksLots: false,
        ),
        number: number,
        journalNumber: journal,
        drawingsAccountId: 'drawings',
        inventoryAccountId: 'inventory',
      );
      expect(posting.value, const Money.rupees(720));
      expect(posting.document.docType, 'expense');
      expect(posting.journal.lines.first.accountSystemKey, '#drawings');
      expect(posting.journal.lines.last.accountSystemKey, '#inventory');
      expect(posting.movement.qtyDelta, Qty.raw(-1500));
      expect(posting.movement.valueDelta, const Money.rupees(-720));
      expect(posting.movement.txnType, 'adjustment');
    });

    test('goods kept by batch, with no cost, or more than the shelf holds '
        'are refused', () {
      HomeGoodsPosting take({bool lots = false, int cost = 480, int qty = 2}) =>
          goodsTakenHome(
            actor: actor,
            draft: GoodsTakenHomeDraft(itemId: 'ghee', qty: Qty.units(qty)),
            item: HomeGoodsItem(
              name: 'Dalda Ghee',
              unitCode: 'kg',
              averageCost: Rate.rupees(cost),
              onHand: Qty.units(10),
              tracksStock: true,
              tracksLots: lots,
            ),
            number: number,
            journalNumber: journal,
            drawingsAccountId: 'drawings',
            inventoryAccountId: 'inventory',
          );
      expect(() => take(lots: true), throwsA(isA<ExpenseRefused>()));
      expect(() => take(cost: 0), throwsA(isA<ExpenseRefused>()));
      expect(() => take(qty: 11), throwsA(isA<ExpenseRefused>()));
      expect(take(qty: 10).value, const Money.rupees(4800));
    });

    test('a monthly bill keeps what it was told, and refuses a day off the '
        'calendar', () {
      const bill = MonthlyBill(
        id: 'b1',
        headKey: '#acct-diesel',
        amount: Money.rupees(9000),
        note: 'Generator diesel',
        day: 10,
        paymentAccountId: 'pa-cash',
        skippedMonth: '2026-10',
      );
      final back = MonthlyBill.fromJson('b1', bill.toJson())!;
      expect(back.headKey, '#acct-diesel');
      expect(back.paymentAccountId, 'pa-cash');
      expect(back.skippedMonth, '2026-10');
      expect(MonthlyBill.fromJson('b1', 'not json'), isNull);
      expect(
        () => checkMonthlyBill(
          const MonthlyBill(
            id: 'b2',
            headKey: 'rent',
            amount: Money.rupees(1),
            note: 'Kiraya',
            day: 32,
          ),
        ),
        throwsA(isA<MonthlyBillRefused>()),
      );
      final (first, last) = monthSpan(const BusinessDate('2027-02-14'));
      expect(first, const BusinessDate('2027-02-01'));
      expect(last, const BusinessDate('2027-02-28'));
    });
  });
}
