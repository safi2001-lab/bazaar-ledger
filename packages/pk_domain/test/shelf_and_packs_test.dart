import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// The arithmetic of M53, with no database: what a bill takes off the
/// shelf, which items it would take below nothing and under which rule, and
/// what a pack holds.
void main() {
  SaleLineDraft line(String? itemId, Qty base, {bool tracksStock = true}) =>
      SaleLineDraft(
        itemId: itemId,
        itemName: itemId ?? 'Pyaz',
        qty: base,
        baseQty: base,
        unitCode: 'kg',
        rate: Rate.rupees(100),
        tracksStock: tracksStock,
      );

  ShelfState shelf(
    String id,
    Qty onHand,
    NegativeStock rule, {
    bool tracksStock = true,
    String unit = 'kg',
  }) => ShelfState(
    itemId: id,
    itemName: id,
    unitCode: unit,
    onHand: onHand,
    rule: rule,
    tracksStock: tracksStock,
  );

  group('the shelf a bill wants', () {
    test('every line of an item counts together, and nothing else counts', () {
      final wanted = shelfWanted([
        line('atta', Qty.units(40)),
        line('atta', Qty.units(20)),
        line('cheeni', Qty.parse('1.5')),
        line(null, Qty.units(3)),
        line('delivery', Qty.one, tracksStock: false),
        line('ghee', Qty.zero),
      ]);
      expect(wanted, {'atta': Qty.units(60), 'cheeni': Qty.parse('1.5')});
    });

    test('only what goes below nothing is short, and an item that sells on '
        'never is', () {
      final short = shelfShortfalls(
        {
          'atta': Qty.units(700),
          'cheeni': Qty.units(5),
          'ghee': Qty.units(9),
          'chai': Qty.units(4),
          'bag': Qty.units(2),
        },
        {
          'atta': shelf('atta', Qty.units(600), NegativeStock.warn),
          'cheeni': shelf('cheeni', Qty.units(5), NegativeStock.block),
          'ghee': shelf('ghee', Qty.units(1), NegativeStock.allow),
          'chai': shelf('chai', Qty.units(3), NegativeStock.block),
          'bag': shelf(
            'bag',
            Qty.zero,
            NegativeStock.block,
            tracksStock: false,
          ),
        },
      );
      expect(short.map((s) => (s.itemId, s.rule, s.shortBy)), [
        ('atta', NegativeStock.warn, Qty.units(100)),
        ('chai', NegativeStock.block, Qty.one),
      ]);
      expect(short.first.onHandWords, '600 kg');
    });

    test('a shelf already below nothing is short of any sale at all', () {
      final short = shelfShortfalls(
        {'atta': Qty.parse('0.25')},
        {'atta': shelf('atta', Qty.parse('-1.5'), NegativeStock.warn)},
      );
      expect(short.single.onHandWords, '-1 kg 500 g');
      expect(short.single.wantedWords, '250 g');
    });

    test('a rule reads back from what the column holds', () {
      for (final rule in NegativeStock.values) {
        expect(NegativeStock.fromCode(rule.code), rule);
      }
      expect(NegativeStock.fromCode(null), isNull);
      expect(NegativeStock.fromCode('sometimes'), isNull);
      expect(
        NegativeStock.shopDefault,
        NegativeStock.warn,
        reason: 'a shop that never chose is asked, never silent',
      );
    });

    test('only a blocked item is refused at the service, and the refusal says '
        'how much there is', () async {
      final actor = ActorContext(
        firmId: 'F',
        userId: 'U',
        deviceId: 'D',
        startedAtUtc: DateTime.utc(2026, 10, 3),
      );
      final reader = _Shelf({
        'atta': shelf('atta', Qty.units(600), NegativeStock.warn),
        'chai': shelf('chai', Qty.units(3), NegativeStock.block, unit: 'pcs'),
      });

      await refuseBlockedShortfalls(reader, actor, [
        line('atta', Qty.units(700)),
      ], locationCode: 'MAIN');

      await expectLater(
        refuseBlockedShortfalls(reader, actor, [
          line('atta', Qty.units(700)),
          line('chai', Qty.units(4)),
        ], locationCode: 'VAN-1'),
        throwsA(
          isA<ShelfRefused>()
              .having((e) => e.short.map((s) => s.itemId), 'items', ['chai'])
              .having((e) => '$e', 'words', contains('Only 3 pcs of chai')),
        ),
      );
      expect(reader.asked, ['MAIN', 'VAN-1']);
    });
  });

  group('packs', () {
    const pcs = 'pcs';
    const kg = 'kg';
    final units = UnitConverter(const [
      UnitEdge(fromUnitId: 'dozen', toUnitId: pcs, factorThousandths: 12000),
      UnitEdge(fromUnitId: 'maund', toUnitId: kg, factorThousandths: 40000),
      UnitEdge(
        fromUnitId: 'carton',
        toUnitId: pcs,
        factorThousandths: 24000,
        itemId: 'gala',
      ),
      UnitEdge(
        fromUnitId: 'bori',
        toUnitId: kg,
        factorThousandths: 50000,
        itemId: 'atta',
      ),
    ]);

    test("an item's packs are its own conversions into its unit", () {
      expect(
        packsOf(
          units,
          itemId: 'gala',
          baseUnitId: pcs,
          codes: const {'carton': 'carton'},
        ),
        [ItemPack(unitId: 'carton', size: Qty.units(24))],
      );
      expect(packsOf(units, itemId: 'cheeni', baseUnitId: kg), isEmpty);
    });

    test('a carton of 24 sells 24 pieces at 24 times the price, exactly', () {
      expect(
        units.convert(
          Qty.parse('1.5'),
          fromUnitId: 'carton',
          toUnitId: pcs,
          itemId: 'gala',
        ),
        Qty.units(36),
      );
      expect(
        units.convertRate(
          Rate.rupees(50),
          fromUnitId: pcs,
          toUnitId: 'carton',
          itemId: 'gala',
        ),
        Rate.rupees(1200),
      );
      const carton = ItemPack(unitId: 'carton', size: Qty.units(24));
      expect(carton.inBase(Qty.parse('1.5')), Qty.units(36));
      expect(
        () => const ItemPack(unitId: 'x', size: Qty.raw(1)).inBase(Qty.raw(1)),
        throwsA(isA<UnitConversionException>()),
      );
    });

    test('a pack that cannot be kept says why', () {
      ItemPack pack(String unit, int size) =>
          ItemPack(unitId: unit, size: Qty.units(size));
      expect(
        packProblem([pack('carton', 24)], baseUnitId: pcs, shopUnits: units),
        isNull,
      );
      expect(
        packProblem([pack('dozen', 10)], baseUnitId: pcs, shopUnits: units),
        contains('already has a size'),
      );
      expect(
        packProblem([pack(pcs, 10)], baseUnitId: pcs),
        contains('counted in'),
      );
      expect(
        packProblem([pack('carton', 24), pack('carton', 12)], baseUnitId: pcs),
        contains('twice'),
      );
      expect(
        packProblem([pack('carton', 0)], baseUnitId: pcs),
        contains('hold something'),
      );
    });

    test('a shop counts in the bori now, a weight with no size of its own', () {
      final bori = defaultUnits.singleWhere((u) => u.code == 'bori');
      expect(bori.kind, UnitKind.weight);
      expect(bori.isBase, isFalse);
      expect(bori.decimals, 0);
      expect(
        defaultUnitConversions.where(
          (c) => c.fromCode == 'bori' || c.toCode == 'bori',
        ),
        isEmpty,
      );
      expect(packUnitCodes, containsAll(['carton', 'dabba', 'bori']));
      expect(packUnitCodes, isNot(contains('dozen')));
    });
  });
}

final class _Shelf implements ShelfReader {
  _Shelf(this.states);

  final Map<String, ShelfState> states;
  final asked = <String>[];

  @override
  Future<Map<String, ShelfState>> shelfFor(
    ActorContext actor,
    Iterable<String> itemIds, {
    required String locationCode,
  }) async {
    asked.add(locationCode);
    return {for (final id in itemIds) id: ?states[id]};
  }
}
