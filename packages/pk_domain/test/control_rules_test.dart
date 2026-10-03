import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// The rules M68 keeps, without a database: credit control's judgement, the
/// day the books close by themselves, the random check's draw and the
/// month's shrinkage.
void main() {
  final today = BusinessDate('2026-10-03');

  CreditVerdict judge(
    CreditPolicy policy, {
    required CreditStanding before,
    Money owed = const Money.rupees(1000),
    bool byCheque = false,
  }) => judgeCredit(
    policy: policy,
    before: before,
    after: before.withBill(owed, today),
    today: today,
    givesCredit: owed.isPositive,
    byCheque: byCheque,
  );

  group('credit control', () {
    test('each rule bites past its line and not on it', () {
      const policy = CreditPolicy(
        limit: Money.rupees(5000),
        limitMode: CreditMode.block,
        maxOpenBills: 3,
        billsMode: CreditMode.warn,
        maxDays: 30,
        daysMode: CreditMode.block,
      );
      // Rs 4,000 owed on two bills, the oldest thirty days: a Rs 1,000 bill
      // lands on the limit exactly and is the third bill. Nothing bites.
      final onTheLine = judge(
        policy,
        before: CreditStanding(
          balance: const Money.rupees(4000),
          openBills: 2,
          oldestOpenBill: today.addDays(-30),
        ),
      );
      expect(onTheLine.isClear, isTrue);

      // A paisa over, a fourth bill, a bill thirty-one days old.
      final past = judge(
        policy,
        before: CreditStanding(
          balance: const Money.paisa(400001),
          openBills: 3,
          oldestOpenBill: today.addDays(-31),
        ),
      );
      expect(past.breaches.map((b) => b.rule), [
        CreditRule.limit,
        CreditRule.bills,
        CreditRule.days,
      ]);
      expect(past.blocks, isTrue);
      expect(past.blocking.map((b) => b.rule), [
        CreditRule.limit,
        CreditRule.days,
      ]);
      expect(past.of(CreditRule.limit)!.after, const Money.paisa(500001));
      expect(past.of(CreditRule.bills)!.count, 4);
      expect(past.of(CreditRule.days)!.count, 31);
      expect(past.words(), contains('a bill 31 days old unpaid'));
    });

    test('cash answers to no rule; a cheque only to a bounce', () {
      const policy = CreditPolicy(
        limit: Money.rupees(1),
        limitMode: CreditMode.block,
        maxOpenBills: 0,
        billsMode: CreditMode.block,
        bounceMode: CreditMode.block,
      );
      const bounced = CreditStanding(
        balance: Money.rupees(45000),
        openBills: 4,
        bouncedCheques: 1,
      );
      expect(judge(policy, before: bounced, owed: Money.zero).isClear, isTrue);
      final cheque = judge(
        policy,
        before: bounced,
        owed: Money.zero,
        byCheque: true,
      );
      expect(cheque.breaches.single.rule, CreditRule.bounce);
      expect(cheque.breaches.single.owed, const Money.rupees(45000));

      // Paid up, the bounce is made good and stops biting.
      const madeGood = CreditStanding(balance: Money.zero, bouncedCheques: 1);
      expect(
        judge(
          policy,
          before: madeGood,
          owed: Money.zero,
          byCheque: true,
        ).isClear,
        isTrue,
      );
    });

    test('a customer\'s own rule stands over the shop\'s, and a temporary '
        'limit over the permanent one until its day has passed', () {
      const shop = CreditDefaults(
        limitMode: CreditMode.block,
        maxOpenBills: 3,
        billsMode: CreditMode.block,
        maxDays: 30,
      );
      final own = PartyCreditRules(
        maxOpenBills: 6,
        billsMode: CreditMode.warn,
        noDaysRule: true,
        tempLimit: const Money.rupees(50000),
        tempUntil: BusinessDate('2026-10-09'),
      );
      final friday = CreditPolicy.of(
        partyLimit: const Money.rupees(10000),
        own: own,
        shop: shop,
        today: BusinessDate('2026-10-09'),
      );
      expect(friday.limit, const Money.rupees(50000));
      expect(friday.limitIsTemporary, isTrue);
      expect(friday.limitMode, CreditMode.block);
      expect(friday.maxOpenBills, 6);
      expect(friday.billsMode, CreditMode.warn);
      expect(friday.maxDays, isNull);

      final saturday = CreditPolicy.of(
        partyLimit: const Money.rupees(10000),
        own: own,
        shop: shop,
        today: BusinessDate('2026-10-10'),
      );
      expect(saturday.limit, const Money.rupees(10000));
      expect(saturday.limitIsTemporary, isFalse);
      expect(own.tempLapsedOn(BusinessDate('2026-10-10')), isTrue);
    });

    test('rules are kept as JSON and read back; nonsense is the standard', () {
      final own = PartyCreditRules(
        limitMode: CreditMode.block,
        maxOpenBills: 2,
        bounceMode: CreditMode.off,
        tempLimit: const Money.rupees(75000),
        tempUntil: BusinessDate('2026-10-31'),
      );
      expect(PartyCreditRules.fromJson(own.toJson()), own);
      const shop = CreditDefaults(maxDays: 45, daysMode: CreditMode.block);
      expect(CreditDefaults.fromJson(shop.toJson()), shop);
      expect(CreditDefaults.fromJson('not json'), CreditDefaults.standard);
      expect(PartyCreditRules.fromJson(null).isNone, isTrue);
      // The standard is the counter before M68: the limit and a bounce warn.
      expect(CreditDefaults.standard.limitMode, CreditMode.warn);
      expect(CreditDefaults.standard.bounceMode, CreditMode.warn);
      expect(CreditDefaults.standard.maxOpenBills, isNull);
    });
  });

  group('days that lock themselves', () {
    test('older than N days closes the day N+1 days back, and moves with the '
        'calendar', () {
      const lock = AutoLock(mode: AutoLockMode.olderThan, days: 2);
      expect(lock.closedThroughOn(today)!.value, '2026-09-30');
      expect(lock.closedThroughOn(today.addDays(1))!.value, '2026-10-01');
      expect(
        const AutoLock(
          mode: AutoLockMode.olderThan,
          days: 0,
        ).closedThroughOn(today)!.value,
        '2026-10-02',
      );
      const atClose = AutoLock(mode: AutoLockMode.atDayClose);
      expect(atClose.closedThroughOn(today), isNull);
      expect(
        atClose.closedThroughOn(today, lastDayClosed: today)!.value,
        '2026-10-03',
      );
      expect(AutoLock.off.closedThroughOn(today), isNull);
      expect(AutoLock.fromJson(lock.toJson()), lock);
      expect(
        laterClosing(
          BusinessDate('2026-09-30'),
          BusinessDate('2026-10-01'),
        )!.value,
        '2026-10-01',
      );
      expect(laterClosing(null, null), isNull);
    });
  });

  group('the random stock check', () {
    List<StockCheckCandidate> shelf() => [
      for (var i = 0; i < 10; i++)
        StockCheckCandidate(
          itemId: 'item$i',
          name: 'Item $i',
          unitCode: 'pcs',
          // item9 moves the most; item0 not at all.
          movedValue: Money.rupees(i * 1000),
          stockValue: Money.rupees(i * 100),
        ),
    ];

    test('the draw is weighted to fast movers and dear stock, never names an '
        'item twice, and leaves out what it is told to', () {
      final counts = <String, int>{};
      for (var seed = 0; seed < 2000; seed++) {
        final picked = pickForCheck(
          candidates: shelf(),
          exclude: const {},
          size: 1,
          seed: seed,
        );
        counts.update(picked.single.itemId, (n) => n + 1, ifAbsent: () => 1);
      }
      // Weights 10 to 1: the fast mover about ten times as often as the dead
      // item, which is still drawn.
      expect(counts['item9']!, greaterThan(counts['item0']! * 5));
      expect(counts['item0'], isNotNull);

      final five = pickForCheck(
        candidates: shelf(),
        exclude: {'item9', 'item8'},
        size: 5,
        seed: 7,
      );
      expect(five, hasLength(5));
      expect(five.map((c) => c.itemId).toSet(), hasLength(5));
      expect(five.map((c) => c.itemId), isNot(contains('item9')));
      expect(five.map((c) => c.itemId), isNot(contains('item8')));
      // The same day draws the same items.
      expect(
        pickForCheck(
          candidates: shelf().reversed.toList(),
          exclude: {'item9', 'item8'},
          size: 5,
          seed: 7,
        ).map((c) => c.itemId),
        five.map((c) => c.itemId),
      );
      expect(
        stockCheckSeed('firm', today, 0),
        stockCheckSeed('firm', today, 0),
      );
    });

    test('shrinkage is what was missing less what turned up, by the month it '
        'was posted', () {
      StockCheck posted(String on, Money value) => StockCheck(
        id: on,
        date: BusinessDate(on),
        location: 'MAIN',
        status: StockCheckStatus.posted,
        postedOn: BusinessDate(on),
        lines: [
          StockCheckLine(
            itemId: 'oil',
            name: 'Oil',
            unitCode: 'pcs',
            counted: Qty.units(1),
            book: Qty.units(2),
            posted: Qty.units(-1),
            postedValue: value,
          ),
        ],
      );
      final months = shrinkageByMonth([
        posted('2026-09-12', const Money.rupees(-600)),
        posted('2026-10-01', const Money.rupees(-450)),
        posted('2026-10-02', const Money.rupees(150)),
        StockCheck.fromJson(
          posted(
            '2026-10-03',
            const Money.rupees(-9999),
          ).copyWith(status: StockCheckStatus.dropped).toJson(),
        )!,
      ]);
      expect(months.map((m) => m.month), ['2026-10', '2026-09']);
      expect(months.first.checks, 2);
      expect(months.first.short, const Money.rupees(450));
      expect(months.first.over, const Money.rupees(150));
      expect(months.first.net, const Money.rupees(300));
      expect(months.last.net, const Money.rupees(600));
    });
  });

  group('cashier mode', () {
    test('only a named salesman of a shop in cashier mode is one', () {
      const mode = CashierMode(on: true, salesmen: {'ali'});
      expect(mode.isSalesman('ali'), isTrue);
      expect(mode.isSalesman('bilal'), isFalse);
      expect(CashierMode.fromJson(mode.toJson()), mode);
      expect(const CashierMode(salesmen: {'ali'}).isSalesman('ali'), isFalse);
    });
  });
}
