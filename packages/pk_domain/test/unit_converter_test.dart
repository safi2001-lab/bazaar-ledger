import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// Changing what a quantity is measured in, without changing the quantity.
///
/// This is the arithmetic behind buying flour by the maund and selling it by
/// the kilo, and it is the arithmetic a shop's stock figure is made of. It
/// gets the same treatment as money: integers only, exact or refused, never a
/// rounding that quietly puts the ledger and the invoice out of step.
void main() {
  // The ids the seeded units get. Real ones are ULIDs; these read better.
  const pcs = 'pcs';
  const dozen = 'dozen';
  const kg = 'kg';
  const g = 'g';
  const maund = 'maund';
  const tola = 'tola';
  const seer = 'seer';

  UnitConverter shopUnits([List<UnitEdge> extra = const []]) => UnitConverter([
    // 1 dozen = 12 pcs.
    const UnitEdge(fromUnitId: dozen, toUnitId: pcs, factorThousandths: 12000),
    // 1 g = one thousandth of a kilo — exactly one unit of storage.
    const UnitEdge(fromUnitId: g, toUnitId: kg, factorThousandths: 1),
    // A Pakistani maund is 40 kg.
    const UnitEdge(fromUnitId: maund, toUnitId: kg, factorThousandths: 40000),
    const UnitEdge(fromUnitId: tola, toUnitId: g, factorThousandths: 11664),
    const UnitEdge(fromUnitId: seer, toUnitId: kg, factorThousandths: 1000),
    ...extra,
  ]);

  group('the everyday conversions', () {
    test('a dozen is twelve pieces', () {
      expect(
        shopUnits().convert(Qty.one, fromUnitId: dozen, toUnitId: pcs),
        Qty.units(12),
      );
    });

    test('two and a half dozen is thirty pieces', () {
      expect(
        shopUnits().convert(Qty.parse('2.5'), fromUnitId: dozen, toUnitId: pcs),
        Qty.units(30),
      );
    });

    test('a maund is forty kilos, and forty kilos is a maund', () {
      final units = shopUnits();
      expect(
        units.convert(Qty.one, fromUnitId: maund, toUnitId: kg),
        Qty.units(40),
      );
      // Backwards too. A shopkeeper who buys atta by the maund and sells it
      // by the kilo needs the arithmetic to run in both directions, and the
      // database stores each pair once.
      expect(
        units.convert(Qty.units(40), fromUnitId: kg, toUnitId: maund),
        Qty.one,
      );
    });

    test('a seer is a kilo, because Pakistan metricated', () {
      // A maund is 40 kg and forty seer, so a seer is a kilo exactly. The
      // historic British-Indian maund of 37.324 kg is not what anyone means.
      expect(
        shopUnits().convert(Qty.units(40), fromUnitId: seer, toUnitId: kg),
        shopUnits().convert(Qty.one, fromUnitId: maund, toUnitId: kg),
      );
    });

    test('750 grams stays 750 grams through a kilo and back', () {
      final units = shopUnits();
      final inKg = units.convert(Qty.units(750), fromUnitId: g, toUnitId: kg);
      expect(inKg, Qty.parse('0.750'));
      expect(
        units.convert(inKg, fromUnitId: kg, toUnitId: g),
        Qty.units(750),
        reason: 'a round trip that loses anything is a round trip that steals',
      );
    });
  });

  group('chains', () {
    test('a maund of flour reaches grams through kilos', () {
      // Two hops, maund → kg → g. A shop that stocks in grams and buys in
      // maunds is unusual but not impossible, and the path exists.
      expect(
        shopUnits().convert(Qty.one, fromUnitId: maund, toUnitId: g),
        Qty.units(40000),
      );
    });

    test('a dozen cannot become a kilo', () {
      // Count and weight are not the same thing, and there is no edge between
      // them. Refused, rather than answered with a number.
      expect(
        () => shopUnits().convert(Qty.one, fromUnitId: dozen, toUnitId: kg),
        throwsA(isA<UnitConversionException>()),
      );
    });
  });

  group('tola, which is where exactness earns its keep', () {
    test('a tola is 11.664 grams', () {
      expect(
        shopUnits().convert(Qty.one, fromUnitId: tola, toUnitId: g),
        Qty.parse('11.664'),
      );
    });

    test('the traditional fractions are all exact', () {
      final units = shopUnits();
      for (final (fraction, grams) in const [
        ('0.5', '5.832'),
        ('0.25', '2.916'),
        ('0.125', '1.458'),
      ]) {
        expect(
          units.convert(Qty.parse(fraction), fromUnitId: tola, toUnitId: g),
          Qty.parse(grams),
          reason: '$fraction tola',
        );
      }
    });

    test('a tola cannot be expressed in a stock kept in kilos', () {
      // Thousandths of a kilo are whole grams, and 11.664 g is not a whole
      // number of them. A jeweller stocks in grams. Rounding here would put
      // a third of a gram of gold a day into the gap between what the ledger
      // says and what is in the safe.
      expect(
        () => shopUnits().convert(Qty.one, fromUnitId: tola, toUnitId: kg),
        throwsA(
          isA<UnitConversionException>().having(
            (e) => e.message,
            'message',
            contains('would not come out even'),
          ),
        ),
      );
    });

    test('and the counter can ask first', () {
      final units = shopUnits();
      expect(units.canConvert(Qty.one, fromUnitId: tola, toUnitId: g), isTrue);
      expect(
        units.canConvert(Qty.one, fromUnitId: tola, toUnitId: kg),
        isFalse,
        reason:
            'a unit that cannot be sold in is greyed out, not offered '
            'and then refused at the moment of saving the bill',
      );
    });
  });

  group("one shop's bori is not another's", () {
    const bori = 'bori';
    const flour = 'item-flour';
    const rice = 'item-rice';

    UnitConverter withBoris() => shopUnits([
      // The shop's default sack, if it has one.
      const UnitEdge(fromUnitId: bori, toUnitId: kg, factorThousandths: 50000),
      // Flour comes in 80 kg sacks at this shop.
      const UnitEdge(
        fromUnitId: bori,
        toUnitId: kg,
        factorThousandths: 80000,
        itemId: flour,
      ),
    ]);

    test('an item with its own sack size uses it', () {
      expect(
        withBoris().convert(
          Qty.one,
          fromUnitId: bori,
          toUnitId: kg,
          itemId: flour,
        ),
        Qty.units(80),
        reason: 'flour ships in 80 kg sacks at this shop',
      );
    });

    test('an item without one falls back to the shop', () {
      expect(
        withBoris().convert(
          Qty.one,
          fromUnitId: bori,
          toUnitId: kg,
          itemId: rice,
        ),
        Qty.units(50),
      );
    });

    test('and the shop-wide conversion is unaffected by either', () {
      expect(
        withBoris().convert(Qty.one, fromUnitId: bori, toUnitId: kg),
        Qty.units(50),
      );
    });
  });

  group('the same price, per a different unit', () {
    test('a hundred a piece is twelve hundred a dozen', () {
      expect(
        shopUnits().convertRate(
          const Rate.rupees(100),
          fromUnitId: pcs,
          toUnitId: dozen,
        ),
        const Rate.rupees(1200),
      );
    });

    test('and back again, losing nothing', () {
      final units = shopUnits();
      final perDozen = units.convertRate(
        const Rate.rupees(100),
        fromUnitId: pcs,
        toUnitId: dozen,
      );
      expect(
        units.convertRate(perDozen, fromUnitId: dozen, toUnitId: pcs),
        const Rate.rupees(100),
      );
    });

    test('a rate per kilo becomes a rate per maund', () {
      // Atta at Rs 120 a kilo is Rs 4,800 a maund, and a shopkeeper who
      // quotes by the maund is quoting that number.
      expect(
        shopUnits().convertRate(
          const Rate.rupees(120),
          fromUnitId: kg,
          toUnitId: maund,
        ),
        const Rate.rupees(4800),
      );
    });

    test('a price that will not come out even is refused', () {
      // Rs 100 a kilo is 11.664 rupees a tola... but the item would have to
      // be stocked in grams for a tola to exist at all, and Rs 100 a gram is
      // Rs 1,166.40 a tola, which IS exact. The refusal that matters is the
      // one where the arithmetic does not land on a whole milli-paisa.
      expect(
        shopUnits().convertRate(
          const Rate.rupees(100),
          fromUnitId: g,
          toUnitId: tola,
        ),
        Rate.raw(const Rate.rupees(100).inMilliPaisa * 11664 ~/ 1000),
      );
    });

    test('a rate converts to itself without consulting anything', () {
      expect(
        UnitConverter(
          const [],
        ).convertRate(const Rate.rupees(250), fromUnitId: kg, toUnitId: kg),
        const Rate.rupees(250),
      );
    });
  });

  group('the edges of the thing', () {
    test('a unit converts to itself without consulting anything', () {
      expect(
        UnitConverter(
          const [],
        ).convert(Qty.parse('3.75'), fromUnitId: kg, toUnitId: kg),
        Qty.parse('3.75'),
      );
    });

    test('zero is zero in any unit', () {
      expect(
        shopUnits().convert(Qty.zero, fromUnitId: maund, toUnitId: g),
        Qty.zero,
      );
    });

    test('an unknown unit is refused, not guessed at', () {
      expect(
        () => shopUnits().convert(Qty.one, fromUnitId: 'thaan', toUnitId: kg),
        throwsA(isA<UnitConversionException>()),
      );
    });

    test('what a counter may offer for an item', () {
      // Everything reachable from kilos: the whole weight family, and nothing
      // from the count family.
      final reachable = shopUnits().reachableFrom(kg);
      expect(reachable, containsAll(<String>[kg, g, maund, seer, tola]));
      expect(reachable, isNot(contains(pcs)));
      expect(reachable, isNot(contains(dozen)));
    });

    test('a very large quantity does not overflow into nonsense', () {
      // Ten thousand maunds of wheat is a warehouse, not a shop, but the
      // arithmetic should still be arithmetic.
      expect(
        shopUnits().convert(Qty.units(10000), fromUnitId: maund, toUnitId: g),
        Qty.units(400000000),
      );
    });
  });
}
