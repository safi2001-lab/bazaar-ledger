import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// The bazaar's own weights and counts, and the money that goes with them
/// (M56).
///
/// Grain and atta are quoted by the mann and handed over by the kilo. The
/// one thing that may not happen between the two is a rounding: a price
/// per mann and a price per kilo are the same price, and a sale written in
/// either comes to the same paisa, rounded once, half up, at the end — the
/// M0 rule for every line in the app.
void main() {
  /// The shop's units as a new firm gets them, ids standing in for codes.
  UnitConverter shipped() => UnitConverter([
    for (final c in defaultUnitConversions)
      UnitEdge(
        fromUnitId: c.fromCode,
        toUnitId: c.toCode,
        factorThousandths: c.factorThousandths,
      ),
  ]);

  group('bazaar units', () {
    test('a mann is forty kilos exactly, both ways', () {
      final units = shipped();
      expect(
        units.convert(Qty.one, fromUnitId: 'maund', toUnitId: 'kg'),
        Qty.units(40),
      );
      expect(
        units.convert(Qty.parse('2.5'), fromUnitId: 'maund', toUnitId: 'kg'),
        Qty.units(100),
      );
      // A quarter of a mann is ten kilos, and an eighth is five: the
      // fractions the grain market actually trades in are all exact.
      expect(
        units.convert(Qty.parse('0.125'), fromUnitId: 'maund', toUnitId: 'kg'),
        Qty.units(5),
      );
      expect(
        units.convert(Qty.units(100), fromUnitId: 'kg', toUnitId: 'maund'),
        Qty.parse('2.5'),
      );
    });

    test('a price per mann is the price per kilo times forty, exactly', () {
      final units = shipped();
      expect(
        units.convertRate(
          Rate.rupees(120),
          fromUnitId: 'kg',
          toUnitId: 'maund',
        ),
        Rate.rupees(4800),
      );
      // And an awkward one back again: Rs 4,833.33 a mann is Rs 120.83325
      // a kilo — to the sub-paisa the rate is kept in, not rounded to
      // Rs 120.83.
      final perKg = units.convertRate(
        Rate.parse('4833.33'),
        fromUnitId: 'maund',
        toUnitId: 'kg',
      );
      expect(perKg, Rate.parse('120.83325'));
      expect(
        units.convertRate(perKg, fromUnitId: 'kg', toUnitId: 'maund'),
        Rate.parse('4833.33'),
      );
    });

    test('a sale written in mann or in kilos comes to the same paisa, rounded '
        'once', () {
      final units = shipped();
      final perMaund = Rate.parse('4833.33');
      final maunds = Qty.parse('1.333');

      final kilos = units.convert(maunds, fromUnitId: 'maund', toUnitId: 'kg');
      final perKg = units.convertRate(
        perMaund,
        fromUnitId: 'maund',
        toUnitId: 'kg',
      );
      expect(kilos, Qty.parse('53.32'));

      // 4,833.33 x 1.333 = 6,442.82889, rounded once, half up.
      expect(perMaund.amountFor(maunds), Money.paisa(644283));
      expect(perKg.amountFor(kilos), Money.paisa(644283));

      // Why the rate is never rounded on the way: priced at Rs 120.83 a
      // kilo, the same sack would come to 6,442.66 — seventeen paisa the
      // bill and the stock value would disagree about for ever.
      expect(Rate.parse('120.83').amountFor(kilos), Money.paisa(644266));
    });

    test('a seer is the kilo forty of which make the 40 kg mann', () {
      final units = shipped();
      expect(
        units.convert(Qty.units(40), fromUnitId: 'seer', toUnitId: 'kg'),
        units.convert(Qty.one, fromUnitId: 'maund', toUnitId: 'kg'),
      );
      // The tables' 80-tola seer is 933.104 g, and stock in kilos is whole
      // grams. It could only ever have been carried as a rounding.
      final eightyTola = units.convert(
        Qty.units(80),
        fromUnitId: 'tola',
        toUnitId: 'g',
      );
      expect(eightyTola, Qty.parse('933.12'));
      expect(eightyTola.isWhole, isFalse);
    });

    test('a new shop counts in cartons, dabbas, packets, strips and tablets, '
        'and has no pao', () {
      final byCode = {for (final u in defaultUnits) u.code: u};
      for (final code in ['carton', 'dabba', 'packet', 'strip', 'tablet']) {
        expect(byCode[code]?.kind, UnitKind.count, reason: code);
        expect(byCode[code]?.decimals, 0, reason: code);
        expect(byCode[code]?.isBase, isFalse, reason: code);
        // A pack's size is a fact about one item, so none ships with a
        // conversion of its own.
        expect(
          defaultUnitConversions.where(
            (c) => c.fromCode == code || c.toCode == code,
          ),
          isEmpty,
          reason: code,
        );
      }
      expect(byCode.containsKey('pao'), isFalse);
      // Still exactly one base unit of each kind.
      for (final kind in UnitKind.values) {
        expect(
          defaultUnits.where((u) => u.kind == kind && u.isBase),
          hasLength(1),
          reason: kind.name,
        );
      }
    });

    test('a dozen is twelve pieces and its price follows', () {
      final units = shipped();
      expect(
        units.convert(Qty.parse('1.5'), fromUnitId: 'dozen', toUnitId: 'pcs'),
        Qty.units(18),
      );
      expect(
        units.convertRate(
          Rate.rupees(25),
          fromUnitId: 'pcs',
          toUnitId: 'dozen',
        ),
        Rate.rupees(300),
      );
    });
  });
}
