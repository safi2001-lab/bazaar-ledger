import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Points, a customer's own prices and the margin on a bill (M66), as pure
/// rules: no database, no clock.
void main() {
  // 1 point per Rs 100 paid; 100 points are Rs 50 off; half a bill at most.
  const rule = LoyaltyRule(from: '2026-10-01');
  const rules = LoyaltyRules([rule]);

  LoyaltyBill bill(
    String no,
    String date, {
    int total = 0,
    int paid = 0,
    int returned = 0,
    int goods = 0,
    int returnedGoods = 0,
    int spent = 0,
    bool isVoid = false,
  }) => LoyaltyBill(
    documentId: no,
    docNo: no,
    date: date,
    total: Money.rupees(total),
    goods: Money.rupees(goods == 0 ? total : goods),
    paid: Money.rupees(paid),
    returned: Money.rupees(returned),
    returnedGoods: Money.rupees(returnedGoods),
    redeemedPoints: spent,
    redeemedValue: rule.valueOf(spent),
    isVoid: isVoid,
  );

  group('points are earned on what is paid', () {
    test('a cash bill earns in whole steps; udhaar earns nothing until it '
        'is paid, part of it as part is paid', () {
      expect(
        bill('1', '2026-10-02', total: 2550, paid: 2550).earnedBy(rules),
        25,
      );
      final udhaar = bill('2', '2026-10-02', total: 2000);
      expect(udhaar.earnedBy(rules), 0);
      expect(udhaar.earnsWhenPaid(rules), 20);
      expect(
        bill('2', '2026-10-02', total: 2000, paid: 1250).earnedBy(rules),
        12,
      );
    });

    test('a bill before the scheme began, or while it is off, earns '
        'nothing; a change of rate changes no point already earned', () {
      expect(bill('0', '2026-09-30', total: 900, paid: 900).earnedBy(rules), 0);
      final raised = rules.withVersion(
        const LoyaltyRule(from: '2026-10-10', earnPoints: 2),
      );
      expect(
        bill('1', '2026-10-05', total: 500, paid: 500).earnedBy(raised),
        5,
      );
      expect(
        bill('2', '2026-10-10', total: 500, paid: 500).earnedBy(raised),
        10,
      );
      final off = rules.withVersion(
        const LoyaltyRule(from: '2026-10-12', isOn: false),
      );
      expect(bill('3', '2026-10-12', total: 500, paid: 500).earnedBy(off), 0);
      expect(bill('1', '2026-10-05', total: 500, paid: 500).earnedBy(off), 5);
    });

    test('a return takes back the points on what came back, and the points '
        'spent on it in the same share; a cancelled bill earns and spends '
        'nothing', () {
      final half = bill(
        '1',
        '2026-10-02',
        total: 1000,
        paid: 1000,
        returned: 500,
        returnedGoods: 500,
        spent: 40,
      );
      expect(half.earnedBy(rules), 5);
      expect(half.spent, 20);
      final cancelled = bill(
        '1',
        '2026-10-02',
        total: 1000,
        paid: 1000,
        spent: 40,
        isVoid: true,
      );
      expect(cancelled.earnedBy(rules), 0);
      expect(cancelled.spent, 0);
    });
  });

  group('a customer\'s standing', () {
    test('earned less spent is what they hold, spent oldest first', () {
      final standing = loyaltyStanding(rules, [
        bill('1', '2026-10-01', total: 3000, paid: 3000),
        bill('2', '2026-10-03', total: 1000, paid: 1000, spent: 20),
      ], today: '2026-10-04');
      expect(standing.earned, 40);
      expect(standing.redeemed, 20);
      expect(standing.redeemedValue, const Money.rupees(10));
      expect(standing.outstanding, 20);
      expect(standing.expired, 0);
    });

    test('points nobody used expire after their months, and the next to go '
        'is said', () {
      const expiring = LoyaltyRules([
        LoyaltyRule(from: '2026-01-01', expiryMonths: 3),
      ]);
      final bills = [
        bill('1', '2026-01-31', total: 1000, paid: 1000),
        bill('2', '2026-02-15', total: 500, paid: 500, spent: 4),
        bill('3', '2026-03-10', total: 700, paid: 700),
      ];
      final before = loyaltyStanding(expiring, bills, today: '2026-04-29');
      expect(before.expired, 0);
      expect(before.expiringNext, (points: 6, on: '2026-04-30'));
      final after = loyaltyStanding(expiring, bills, today: '2026-04-30');
      expect(after.expired, 6, reason: '10 earned, 4 used first');
      expect(after.outstanding, 5 + 7);
      expect(addMonths('2026-01-31', 1), '2026-02-28');
    });

    test(
      'points spent that nobody held are made good from the next earned',
      () {
        final standing = loyaltyStanding(rules, [
          bill('1', '2026-10-02', total: 1000, paid: 1000, spent: 30),
          bill('2', '2026-10-03', total: 5000, paid: 5000),
        ], today: '2026-10-04');
        expect(standing.outstanding, 10 + 50 - 30);
      },
    );
  });

  group('using points', () {
    test('a hundred points are Rs 50, and no more than half the bill', () {
      expect(rule.valueOf(120), const Money.rupees(60));
      expect(rule.pointsWorth(const Money.rupees(60)), 120);
      expect(rule.maxPointsOn(const Money.rupees(400), 1000), 400);
      expect(rule.maxPointsOn(const Money.rupees(400), 90), 90);
    });

    test('a rule that gives the till away is refused before it is kept', () {
      expect(
        () => const LoyaltyRule(
          from: '2026-10-01',
          redeemValue: Money.rupees(10000),
        ).checked(),
        throwsA(
          isA<LoyaltyRefused>().having(
            (r) => r.problem,
            'problem',
            LoyaltyProblem.tooGenerous,
          ),
        ),
      );
      expect(rule.checked(), rule);
      final kept = LoyaltyRules.fromJson(rules.toJson());
      expect(kept.versions, [rule]);
    });
  });

  group('a customer\'s own price', () {
    const atta = ItemSummary(
      id: 'atta',
      name: 'Atta 50kg',
      unitId: 'u-bag',
      unitCode: 'bag',
      unitDecimals: 0,
      saleRate: Rate.rupees(5000),
      wholesaleRate: Rate.rupees(4900),
      stockOnHand: Qty.zero,
      tracksStock: true,
    );
    final book = SchemeBook(
      slabs: {
        'atta': [QtySlab(from: Qty.units(10), rate: const Rate.rupees(4700))],
      },
    );
    final haji = const PartyPrices(
      partyId: 'haji',
    ).withRate('atta', const Rate.rupees(4800));

    test('wins over the tier and the slab', () {
      expect(
        counterPrice(
          atta,
          tier: PriceTier.wholesale,
          baseQty: Qty.units(12),
          book: book,
          own: haji,
        ),
        (rate: const Rate.rupees(4800), source: PriceSource.party),
      );
    });

    test('without one: the slab where lower, else the tier, else the item', () {
      expect(
        counterPrice(
          atta,
          tier: PriceTier.wholesale,
          baseQty: Qty.units(12),
          book: book,
        ),
        (rate: const Rate.rupees(4700), source: PriceSource.slab),
      );
      expect(counterPrice(atta, tier: PriceTier.wholesale, baseQty: Qty.one), (
        rate: const Rate.rupees(4900),
        source: PriceSource.tier,
      ));
      expect(counterPrice(atta, tier: PriceTier.retail, baseQty: Qty.one), (
        rate: const Rate.rupees(5000),
        source: PriceSource.item,
      ));
    });

    test('is kept as integers and read back', () {
      final back = PartyPrices.fromJson('haji', haji.toJson());
      expect(back, haji);
      expect(back.withRate('atta', null).isEmpty, isTrue);
    });
  });

  test('a margin reads as a shopkeeper says it', () {
    expect(marginOf(const Money.rupees(1240), const Money.rupees(9920)), 1250);
    expect(marginLabel(1250), '12.5%');
    expect(marginLabel(-300), '-3%');
  });
}
