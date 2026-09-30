import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

void main() {
  // One batch: 1 kg of chilli and 200 g of salt make 10 packs, and the
  // packets and the work cost Rs 50.
  final masala = BomDraft(
    name: 'Mirch masala 100g',
    outputItemId: 'pack',
    outputQty: Qty.units(10),
    overhead: const Money.rupees(50),
    lines: [
      BomLineDraft(itemId: 'chilli', qty: Qty.units(1)),
      BomLineDraft(itemId: 'salt', qty: Qty.raw(200)),
    ],
  );

  Map<String, ComponentOnHand> shelf({Qty? chilli}) => {
    'chilli': ComponentOnHand(
      itemId: 'chilli',
      name: 'Red chilli',
      onHand: chilli ?? Qty.units(5),
      avgCost: Rate.rupees(800),
      unitCode: 'kg',
    ),
    'salt': ComponentOnHand(
      itemId: 'salt',
      name: 'Salt',
      onHand: Qty.units(10),
      avgCost: Rate.rupees(50),
      unitCode: 'kg',
    ),
  };

  group('assembly', () {
    test('a run costs its components plus the work', () {
      final plan = planAssembly(
        bom: masala,
        runs: 2,
        components: shelf(),
        output: CostPosition.zero,
      );
      expect(plan.outputQty, Qty.units(20));
      expect(plan.uses.map((u) => (u.itemId, u.qty)), [
        ('chilli', Qty.units(2)),
        ('salt', Qty.raw(400)),
      ]);
      // 2 kg chilli at 800 + 0.4 kg salt at 50 = 1,620; work 2 x 50 = 100.
      expect(plan.componentsCost, const Money.rupees(1620));
      expect(plan.overhead, const Money.rupees(100));
      expect(plan.outputAvgAfter, Rate.rupees(86), reason: '1,720 / 20 packs');
    });

    test('the finished goods average with what is already on the shelf', () {
      final plan = planAssembly(
        bom: masala,
        runs: 1,
        components: shelf(),
        output: CostPosition.onShelf(qty: Qty.units(10), avg: Rate.rupees(90)),
      );
      // 10 at 90 on the shelf, 10 more at (810 + 50) / 10 = 86: 88 each.
      expect(plan.outputAvgAfter, Rate.rupees(88));
    });

    test('a run the shelf cannot cover is refused, naming what is short', () {
      expect(
        () => planAssembly(
          bom: masala,
          runs: 3,
          components: shelf(chilli: Qty.units(2)),
          output: CostPosition.zero,
        ),
        throwsA(
          isA<AssemblyRefused>().having(
            (e) => e.reason,
            'reason',
            allOf(contains('Red chilli'), contains('3')),
          ),
        ),
      );
    });

    test('a recipe that cannot be made is refused before it is kept', () {
      BomDraft with_({String name = 'x', List<BomLineDraft>? lines}) =>
          BomDraft(
            name: name,
            outputItemId: 'pack',
            outputQty: Qty.units(1),
            lines: lines ?? [BomLineDraft(itemId: 'salt', qty: Qty.units(1))],
          );
      for (final bad in [
        with_(name: ' '),
        with_(lines: const []),
        with_(
          lines: [BomLineDraft(itemId: 'pack', qty: Qty.units(1))],
        ),
        with_(
          lines: [
            BomLineDraft(itemId: 'salt', qty: Qty.units(1)),
            BomLineDraft(itemId: 'salt', qty: Qty.units(2)),
          ],
        ),
        with_(
          lines: [BomLineDraft(itemId: 'salt', qty: Qty.zero)],
        ),
      ]) {
        expect(bad.check, throwsA(isA<AssemblyRefused>()));
      }
    });
  });
}
