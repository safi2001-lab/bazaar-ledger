import 'dart:math';

import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Bonus and slabs the way the trade runs (M43): the arithmetic, before any
/// database is near it.
void main() {
  const calculator = SaleCalculator();
  const untaxed = TaxContext(
    isSellerRegistered: false,
    buyerIsRegistered: false,
    buyerIsOnAtl: null,
    province: 'punjab',
    pricesIncludeTax: false,
    ruleVersion: 'untaxed-v1',
  );

  SaleLineDraft paid(
    String itemId,
    int qty, {
    int rupees = 100,
    int discountBp = 0,
    Money? off,
    bool free = false,
    int? base,
  }) => SaleLineDraft(
    itemId: itemId,
    itemName: itemId,
    qty: Qty.units(qty),
    baseQty: Qty.units(base ?? qty),
    unitCode: 'pcs',
    rate: free ? Rate.zero : Rate.rupees(rupees),
    discountBp: discountBp,
    explicitDiscount: off,
    isFreeItem: free,
  );

  BonusOffer tenPlusOne({
    String item = 'soap',
    String? freeItem,
    int buy = 10,
    int free = 1,
  }) => BonusOffer(
    rule: BonusRule(
      buy: Qty.units(buy),
      free: Qty.units(free),
      freeItemId: freeItem,
    ),
    buyBase: Qty.units(buy),
    freeBase: Qty.units(free),
    freeItemId: freeItem ?? item,
    freeItemName: freeItem ?? item,
    freeUnitId: 'u-pcs',
    freeUnitCode: 'pcs',
  );

  group('bonus', () {
    final book = SchemeBook(bonuses: {'soap': tenPlusOne()});

    int freeOn(List<SaleLineDraft> lines) => book
        .bonusFor(SchemeBook.paidBaseOf(lines))
        .fold(0, (n, g) => n + g.baseQty.inThousandths ~/ 1000);

    test('whole sets only: nine earn nothing, ten one, nineteen one, '
        'twenty two', () {
      expect(freeOn([paid('soap', 9)]), 0);
      expect(freeOn([paid('soap', 10)]), 1);
      expect(freeOn([paid('soap', 19)]), 1);
      expect(freeOn([paid('soap', 20)]), 2);
    });

    test('every paid line of the item counts together; a free line, a loose '
        'line and another item earn nothing', () {
      expect(freeOn([paid('soap', 6), paid('soap', 4)]), 1);
      expect(freeOn([paid('soap', 9), paid('soap', 5, free: true)]), 0);
      expect(
        freeOn([
          paid('soap', 9),
          paid('oil', 30),
          SaleLineDraft(
            itemId: null,
            itemName: 'Pyaz',
            qty: Qty.units(10),
            baseQty: Qty.units(10),
            unitCode: 'kg',
            rate: Rate.rupees(80),
          ),
        ]),
        0,
      );
    });

    test('counted on what leaves the shelf: a carton of 24 is 24 pieces', () {
      // Two cartons of 24 rung as two "ctn" lines: 48 pieces, four sets.
      expect(freeOn([paid('soap', 2, base: 48)]), 4);
    });

    test('property: never more than whole sets of what was paid, and never '
        'less as more is bought', () {
      final random = Random(43);
      for (var round = 0; round < 300; round++) {
        final buy = 1 + random.nextInt(24);
        final free = 1 + random.nextInt(5);
        final b = SchemeBook(
          bonuses: {'soap': tenPlusOne(buy: buy, free: free)},
        );
        var before = 0;
        for (var qty = 0; qty <= 3 * buy + 2; qty++) {
          final given = b
              .bonusFor({'soap': Qty.units(qty)})
              .fold(0, (n, g) => n + g.baseQty.inThousandths);
          expect(given, (qty ~/ buy) * free * 1000);
          expect(given >= before, isTrue);
          before = given;
        }
      }
    });

    test('the free line is at no rate, marked free, carries no discount and '
        'costs what the goods cost', () {
      final grant = book.bonusFor({'soap': Qty.units(10)}).single;
      final free = grant.toLine().withUnitCost(Rate.rupees(60));
      expect(free.isFreeItem, isTrue);
      expect(free.rate, Rate.zero);
      final sale = calculator.calculate(
        SaleDraft(
          lines: [paid('soap', 10).withUnitCost(Rate.rupees(60)), free],
          billDiscount: const Money.rupees(100),
          roundToRupee: false,
        ),
        untaxed,
      );
      final line = sale.lines.last;
      expect(line.gross, Money.zero);
      expect(line.totalDiscount, Money.zero, reason: 'no share of the bill');
      expect(line.lineTotal, Money.zero);
      expect(line.cost, const Money.rupees(60));
      expect(sale.total, const Money.rupees(900));
      expect(sale.cost, const Money.rupees(660), reason: 'eleven at Rs 60');
    });

    test('another item given free is that item, in its own unit', () {
      final b = SchemeBook(
        bonuses: {'shampoo': tenPlusOne(item: 'shampoo', freeItem: 'soap')},
      );
      final grant = b.bonusFor({'shampoo': Qty.units(20)}).single;
      final line = grant.toLine();
      expect(grant.forItemId, 'shampoo');
      expect(line.itemId, 'soap');
      expect(line.baseQty, Qty.units(2));
      expect(b.freeAllowed({'shampoo': Qty.units(20)}), {'soap': Qty.units(2)});
    });
  });

  group('quantity slabs', () {
    const item = ItemSummary(
      id: 'oil',
      name: 'Oil',
      unitId: 'u-pcs',
      unitCode: 'pcs',
      unitDecimals: 0,
      saleRate: Rate.rupees(50),
      stockOnHand: Qty.zero,
      tracksStock: true,
      vipRate: Rate.rupees(45),
    );
    final book = SchemeBook(
      slabs: {
        'oil': [
          QtySlab(from: Qty.units(12), rate: const Rate.rupees(46)),
          QtySlab(from: Qty.units(24), rate: const Rate.rupees(44)),
        ],
      },
    );

    test('the slab the quantity reaches: 11 at 50, a dozen at 46, a carton '
        'at 44', () {
      expect(
        book.priceAt(item, PriceTier.retail, Qty.units(11)),
        Rate.rupees(50),
      );
      expect(
        book.priceAt(item, PriceTier.retail, Qty.units(12)),
        Rate.rupees(46),
      );
      expect(
        book.priceAt(item, PriceTier.retail, Qty.units(23)),
        Rate.rupees(46),
      );
      expect(
        book.priceAt(item, PriceTier.retail, Qty.units(24)),
        Rate.rupees(44),
      );
    });

    test('only where it is lower than the customer\'s own price: a VIP on 45 '
        'pays 45 for a dozen and 44 for a carton', () {
      expect(book.priceAt(item, PriceTier.vip, Qty.units(1)), Rate.rupees(45));
      expect(book.priceAt(item, PriceTier.vip, Qty.units(12)), Rate.rupees(45));
      expect(book.priceAt(item, PriceTier.vip, Qty.units(24)), Rate.rupees(44));
    });

    test('an item with no slabs is priced exactly as before', () {
      expect(
        SchemeBook.empty.priceAt(item, PriceTier.retail, Qty.units(500)),
        priceFor(item, PriceTier.retail),
      );
    });
  });

  group('bill slabs', () {
    final book = SchemeBook(
      billSlabs: [
        BillSlab(from: const Money.rupees(5000), percentBp: 200),
        BillSlab(from: const Money.rupees(20000), percentBp: 300),
      ],
    );

    test('the slab the bill reaches, on what the lines come to after their '
        'own discounts', () {
      final lines = [
        paid('oil', 40, rupees: 130), // 5,200
        paid('rice', 1, rupees: 500, off: const Money.rupees(300)), // 200
      ];
      final value = SchemeBook.billValueOf(lines);
      expect(value, const Money.rupees(5400));
      final hit = book.billSlabFor(value)!;
      expect(hit.slab.percentBp, 200);
      expect(hit.discount, const Money.rupees(108));
      expect(book.billSlabFor(const Money.rupees(4999)), isNull);
      expect(
        book.billSlabFor(const Money.rupees(20000))!.discount,
        const Money.rupees(600),
      );
    });

    test('property: the slab discount goes down the bill-discount path and '
        'the lines give back exactly it, to the paisa', () {
      final random = Random(5000);
      for (var round = 0; round < 200; round++) {
        final lines = [
          for (var i = 0; i < 1 + random.nextInt(6); i++)
            paid(
              'item-$i',
              1 + random.nextInt(40),
              rupees: 1 + random.nextInt(900),
              discountBp: random.nextBool() ? random.nextInt(1500) : 0,
            ),
        ];
        final value = SchemeBook.billValueOf(lines);
        final hit = book.billSlabFor(value);
        final discount = hit?.discount ?? Money.zero;
        final sale = calculator.calculate(
          SaleDraft(lines: lines, billDiscount: discount, roundToRupee: false),
          untaxed,
        );
        expect(
          Money.sum([for (final l in sale.lines) l.apportionedBillDiscount]),
          discount,
        );
        expect(sale.taxable, value - discount);
        if (value >= const Money.rupees(5000)) expect(hit, isNotNull);
      }
    });

    test('labels and refusals', () {
      expect(BillSlab(from: Money.zero, percentBp: 250).percentLabel, '2.5%');
      expect(BillSlab(from: Money.zero, percentBp: 200).percentLabel, '2%');
      expect(BillSlab(from: Money.zero, percentBp: 125).percentLabel, '1.25%');
      expect(
        () => BillSlab.checked([
          BillSlab(from: const Money.rupees(5000), percentBp: 300),
          BillSlab(from: const Money.rupees(20000), percentBp: 200),
        ]),
        throwsA(
          isA<SchemeRefused>().having(
            (r) => r.problem,
            'problem',
            SchemeProblem.slabOutOfOrder,
          ),
        ),
      );
      expect(
        () => BillSlab.checked([
          BillSlab(from: const Money.rupees(5000), percentBp: 6000),
        ]),
        throwsA(isA<SchemeRefused>()),
      );
    });
  });

  group('keeping a scheme', () {
    test('an item\'s scheme reads back as it was kept, integers only', () {
      final scheme = ItemScheme(
        itemId: 'soap',
        bonus: BonusRule(
          buy: Qty.units(10),
          free: Qty.units(1),
          unitId: 'u-ctn',
        ),
        slabs: [
          QtySlab(from: Qty.units(24), rate: const Rate.rupees(44)),
          QtySlab(from: Qty.units(12), rate: Rate.parse('46.50')),
        ],
      ).checked();
      final json = scheme.toJson();
      expect(json.contains('.'), isFalse, reason: 'no doubles');
      final back = ItemScheme.fromJson('soap', json);
      expect(back.bonus, scheme.bonus);
      expect(back.slabs, scheme.slabs);
      expect(back.slabs.first.from, Qty.units(12), reason: 'smallest first');
      expect(ItemScheme.fromJson('soap', 'not json').isEmpty, isTrue);
      expect(
        BillSlab.listFromJson(
          BillSlab.listToJson([
            BillSlab(from: const Money.rupees(5000), percentBp: 200),
          ]),
        ),
        [BillSlab(from: const Money.rupees(5000), percentBp: 200)],
      );
    });

    test('a scheme that makes no sense is refused with what is wrong', () {
      SchemeProblem problem(ItemScheme s) {
        try {
          s.checked();
        } on SchemeRefused catch (r) {
          return r.problem;
        }
        fail('kept');
      }

      expect(
        problem(
          ItemScheme(
            itemId: 'x',
            bonus: BonusRule(buy: Qty.units(10), free: Qty.zero),
          ),
        ),
        SchemeProblem.bonusEmpty,
      );
      expect(
        problem(
          ItemScheme(
            itemId: 'x',
            slabs: [
              QtySlab(from: Qty.units(12), rate: const Rate.rupees(46)),
              QtySlab(from: Qty.units(24), rate: const Rate.rupees(47)),
            ],
          ),
        ),
        SchemeProblem.slabOutOfOrder,
      );
      expect(
        problem(
          ItemScheme(
            itemId: 'x',
            slabs: [
              QtySlab(from: Qty.units(12), rate: const Rate.rupees(46)),
              QtySlab(from: Qty.units(12), rate: const Rate.rupees(45)),
            ],
          ),
        ),
        SchemeProblem.slabTwice,
      );
    });
  });

  group('a scheme received on a delivery', () {
    const builder = PurchaseBuilder();

    PurchasePosting deliver({
      required int paidQty,
      required int freeQty,
      required Money cost,
      Map<String, CostPosition> positions = const {},
      Money freight = Money.zero,
    }) => builder.build(
      actor: ActorContext(
        firmId: 'firm-1',
        userId: 'user-1',
        deviceId: 'device-1',
        startedAtUtc: DateTime.utc(2026, 10, 3, 9),
      ),
      draft: PurchaseDraft(
        partyId: 'supplier-1',
        freight: freight,
        lines: [
          PurchaseLineDraft(
            itemId: 'soap',
            itemName: 'Soap',
            qty: Qty.units(paidQty),
            baseQty: Qty.units(paidQty),
            unitId: 'u-pcs',
            unitCode: 'pcs',
            rate: Rate.fromPack(cost, Qty.units(paidQty)),
            freeQty: Qty.units(freeQty),
            freeBaseQty: Qty.units(freeQty),
          ),
        ],
      ),
      positions: positions,
      billNumber: const AllocatedNumber(
        formatted: 'PUR-1',
        series: 'PUR',
        sequence: 1,
      ),
      journalNumber: const AllocatedNumber(
        formatted: 'JV-1',
        series: 'JV',
        sequence: 1,
      ),
    );

    test('ten and one free put eleven on the shelf for the ten\'s money, the '
        'free one a row of its own, and the average falls', () {
      final posting = deliver(
        paidQty: 10,
        freeQty: 1,
        cost: const Money.rupees(1000),
      );
      expect(posting.lines, hasLength(2));
      final (paidRow, freeRow) = (posting.lines.first, posting.lines.last);
      expect(paidRow.isFree, isFalse);
      expect(freeRow.isFree, isTrue);
      expect(freeRow.rate, Rate.zero);
      expect(freeRow.lineTotal, Money.zero);
      expect(freeRow.baseQty, Qty.units(1));
      expect(
        paidRow.landedCost + freeRow.landedCost,
        const Money.rupees(1000),
        reason: 'the free carton carries its share of the paid ones\' cost',
      );
      expect(
        freeRow.landedCost,
        const Money.paisa(9090),
      ); // the paisa left over goes to the paid row
      expect(paidRow.avgAfter, Rate.raw(9090909));
      expect(paidRow.balanceAfter, Qty.units(11));
      expect(posting.document.total, const Money.rupees(1000));
      expect(
        Qty.sum([for (final m in posting.stockMovements) m.qtyDelta]),
        Qty.units(11),
      );
      expect(
        Money.sum([for (final m in posting.stockMovements) m.valueDelta]),
        const Money.rupees(1000),
      );
      expect(posting.stockMovements.last.lineNo, freeRow.lineNo);
      posting.assertBalanced();
    });

    test('property: whatever comes free, the shelf takes all of it at the '
        'bill\'s money and the entry balances', () {
      final random = Random(1011);
      for (var round = 0; round < 300; round++) {
        final shelfQty = random.nextInt(50) - 10;
        final posting = deliver(
          paidQty: 1 + random.nextInt(60),
          freeQty: random.nextInt(8),
          cost: Money.paisa(100 + random.nextInt(9000000)),
          freight: Money.paisa(random.nextInt(50000)),
          positions: {
            'soap': CostPosition.onShelf(
              qty: Qty.units(shelfQty),
              avg: Rate.rupees(50 + random.nextInt(100)),
            ),
          },
        );
        posting.assertBalanced();
        expect(
          Money.sum([for (final l in posting.lines) l.landedCost]),
          posting.document.total,
        );
        expect(
          Money.sum([for (final m in posting.stockMovements) m.valueDelta]),
          posting.document.total,
        );
        for (final l in posting.lines.where((l) => l.isFree)) {
          expect(l.lineTotal, Money.zero);
        }
      }
    });
  });
}
