import 'dart:math';

import 'package:pk_money/pk_money.dart';
import 'package:test/test.dart';

void main() {
  group('Qty display — the regression that defined this package', () {
    test('a fractional weight never renders as a whole number', () {
      // The previous build rendered `quantity.toInt()`, so 0.750 kg of mutton
      // showed in the cart as "0" while the line total was computed correctly.
      final mutton = Qty.parse('0.750');
      expect(mutton.display, '0.75');
      expect(mutton.display, isNot('0'));
      expect(mutton.isZero, isFalse);
      expect(mutton.isWhole, isFalse);
    });

    test('whole quantities render without a decimal tail', () {
      expect(Qty.units(2).display, '2');
      expect(Qty.parse('2.000').display, '2');
      expect(Qty.units(2).isWhole, isTrue);
    });

    test('trailing zeros trim, significant ones do not', () {
      expect(Qty.parse('3.500').display, '3.5');
      expect(Qty.parse('3.5').display, '3.5');
      expect(Qty.parse('0.005').display, '0.005');
      expect(Qty.parse('0.050').display, '0.05');
      expect(Qty.parse('-1.250').display, '-1.25');
    });
  });

  group('Qty parse', () {
    test('accepts what a scale or a cashier produces', () {
      expect(Qty.parse('2').inThousandths, 2000);
      expect(Qty.parse('3.5').inThousandths, 3500);
      expect(Qty.parse('0.750').inThousandths, 750);
      expect(Qty.parse('1,250').inThousandths, 1250000);
      expect(Qty.parse('.5').inThousandths, 500);
    });

    test('rejects a fourth decimal rather than truncating', () {
      // A scale reading of 0.7505 must be a visible error, not a silent
      // under-charge.
      expect(Qty.tryParse('0.7505'), isNull);
    });

    test('rejects junk', () {
      for (final bad in ['', 'abc', '1.2.3', '.', '-', '2kg']) {
        expect(Qty.tryParse(bad), isNull, reason: 'should reject "$bad"');
      }
    });
  });

  group('Qty arithmetic', () {
    test('adds and subtracts exactly', () {
      expect(Qty.parse('0.1') + Qty.parse('0.2'), Qty.parse('0.3'));
      var total = Qty.zero;
      for (var i = 0; i < 1000; i++) {
        total += Qty.raw(1);
      }
      expect(total, Qty.one);
    });

    test('display-unit conversion, with the correct Pakistani maund', () {
      // Base unit grams. A maund is 40 kg — not the historic 37.324 kg.
      const maundInGrams = 40000;
      final oneMaund = Qty.units(maundInGrams);
      expect(oneMaund.toDisplayUnits(maundInGrams * 1000), Qty.one);

      final halfMaund = Qty.units(20000);
      expect(halfMaund.toDisplayUnits(maundInGrams * 1000).display, '0.5');
    });

    test('rejects a non-positive conversion factor', () {
      expect(() => Qty.one.toDisplayUnits(0), throwsArgumentError);
    });
  });

  group('Rate x Qty — the one multiplication in the application', () {
    test('the reference line: Rs 150.00/kg x 3.5 kg = Rs 525.00', () {
      final rate = Rate.perUnit(Money.rupees(150));
      expect(rate.amountFor(Qty.parse('3.5')), Money.rupees(525));
    });

    test('whole units behave', () {
      final rate = Rate.perUnit(Money.rupees(2500));
      expect(rate.amountFor(Qty.units(2)), Money.rupees(5000));
      expect(rate.amountFor(Qty.zero), Money.zero);
      expect(Rate.zero.amountFor(Qty.units(99)), Money.zero);
    });

    test('sub-paisa rates survive — loose atta by the gram', () {
      // Rs 132 for a 10 kg bag, base unit gram: 1.32 paisa per gram.
      // A paisa-precision rate could only hold 1 or 2 — a 25% error a scoop.
      final perGram = Rate.fromPack(Money.rupees(132), Qty.units(10000));
      expect(perGram.inMilliPaisa, 1320);

      // The rate is fractional, but every amount it produces is whole paisa.
      expect(perGram.amountFor(Qty.units(10000)), Money.rupees(132));
      expect(perGram.amountFor(Qty.units(1000)), Money.rupees(13, 20));
      expect(perGram.amountFor(Qty.units(500)), Money.rupees(6, 60));
      expect(perGram.amountFor(Qty.units(1)), Money.paisa(1)); // 1.32 -> 1

      // Selling the bag a kilo at a time must not drift from the bag price.
      final tenKilosSeparately =
          Money.sum([for (var i = 0; i < 10; i++) perGram.amountFor(Qty.units(1000))]);
      expect(tenKilosSeparately, Money.rupees(132));
    });

    test('pro-rata loose sale never exceeds the pack MRP', () {
      // Drug Pricing Policy: a strip cut may not exceed the pro-rata printed
      // MRP. Ten tablets at Rs 137.00 the pack divides exactly, so this case
      // alone proves nothing — the second assertion below is entailed by the
      // first and could never fail on its own.
      final perTablet = Rate.fromPack(Money.rupees(137), Qty.units(10));
      expect(perTablet.amountFor(Qty.units(10)), Money.rupees(137));

      // The case that matters is a pack that does NOT divide exactly. The
      // milli-paisa rate carries a thousand times the resolution of the
      // amount, so most packs divide cleanly and prove nothing; the ones that
      // do not are large. Half-up on a 3-paisa pack of five thousand units
      // rounds each unit up and comes back to 5 paisa for a 3-paisa pack.
      final overpriced =
          Rate.fromPack(Money.paisa(3), Qty.units(5000), mode: RoundingMode.halfUp);
      expect(
        overpriced.amountFor(Qty.units(5000)) > Money.paisa(3),
        isTrue,
        reason: 'this is the behaviour the default must not have',
      );

      // The default truncates, and then the pack never costs more than the
      // pack. The policy says a loose sale "shall not exceed the pro-rata MRP
      // printed on the pack", so the fraction of a paisa the shop cannot
      // charge is the shop's to lose.
      final safe = Rate.fromPack(Money.paisa(3), Qty.units(5000));
      expect(safe.amountFor(Qty.units(5000)) <= Money.paisa(3), isTrue);

      // And it holds everywhere, not only there.
      for (var pack = 1; pack <= 60; pack++) {
        for (final size in const [2, 3, 7, 11, 13, 97, 250, 1000, 3000, 5000]) {
          final rate = Rate.fromPack(Money.paisa(pack), Qty.units(size));
          expect(
            rate.amountFor(Qty.units(size)) <= Money.paisa(pack),
            isTrue,
            reason: 'a $size-unit pack at $pack paisa priced above itself',
          );
        }
      }
    });

    test('a figure too large to represent is refused, never wrapped', () {
      // Dart does not throw on integer overflow; it wraps, and the sign
      // flips. A pasted figure used to come back as a NEGATIVE amount on a
      // screen where the shopkeeper had just typed a positive one.
      expect(() => Money.parse('92233720368547759'), throwsFormatException);
      expect(() => Qty.parse('9223372036854776'), throwsFormatException);
      expect(() => Rate.parse('92233720368548'), throwsFormatException);

      // The largest value that IS representable still parses, so the guard is
      // a boundary and not a blanket refusal.
      expect(Money.parse('92233720368547758'), isNotNull);

      // And an amount a real shop could plausibly reach still parses.
      expect(Money.parse('99999999.99'), Money.paisa(9999999999));
      expect(Rate.parse('99999999.99'), isNotNull);
    });

    test('rounding is half-up and symmetric about zero', () {
      final rate = Rate.raw(500); // half a paisa per base unit
      expect(rate.amountFor(Qty.units(1)), Money.paisa(1)); // 0.5 -> 1
      expect(rate.amountFor(Qty.units(2)), Money.paisa(1)); // 1.0 exact
      expect(rate.amountFor(Qty.units(3)), Money.paisa(2)); // 1.5 -> 2
      expect(rate.amountFor(Qty.units(-1)), Money.paisa(-1)); // -0.5 -> -1
      expect(rate.amountFor(Qty.units(-3)), Money.paisa(-2));

      // Ties can also be sent to even where a tax rule demands it.
      expect(
        rate.amountFor(Qty.units(1), mode: RoundingMode.halfEven),
        Money.paisa(0),
      );
      expect(
        rate.amountFor(Qty.units(3), mode: RoundingMode.halfEven),
        Money.paisa(2),
      );
    });

    test('the overflow guard throws instead of wrapping silently', () {
      final absurd = Rate.raw(1 << 62);
      expect(() => absurd.amountFor(Qty.units(1 << 20)), throwsStateError);
    });

    test('property: 5000 random lines round to within half a paisa', () {
      final rng = Random(20260823);
      for (var i = 0; i < 5000; i++) {
        final rate = Rate.raw(rng.nextInt(100000000));
        final qty = Qty.raw(rng.nextInt(1000000));
        final amount = rate.amountFor(qty);

        // Recompute the exact product and check the rounding is the nearest
        // paisa, using only integer maths.
        final product = rate.inMilliPaisa * qty.inThousandths;
        final exactFloor = product ~/ 1000000;
        final remainder = product % 1000000;
        final expected =
            remainder * 2 >= 1000000 ? exactFloor + 1 : exactFloor;
        expect(amount.inPaisa, expected,
            reason: 'rate=${rate.inMilliPaisa} qty=${qty.inThousandths}');
      }
    });
  });

  group('Rate parse and format', () {
    test('accepts up to five decimals, rejects six', () {
      expect(Rate.parse('150').inMilliPaisa, 15000000);
      expect(Rate.parse('150.50').inMilliPaisa, 15050000);
      expect(Rate.parse('Rs 1,850.255').inMilliPaisa, 185025500);
      expect(Rate.tryParse('1.123456'), isNull);
    });

    test('renders at least two decimals and trims sub-paisa zeros', () {
      expect(Rate.perUnit(Money.rupees(150)).amountOnly, '150.00');
      expect(Rate.perUnit(Money.rupees(1850)).amountOnly, '1,850.00');
      expect(Rate.parse('1850.255').amountOnly, '1,850.255');
      expect(Rate.parse('0.185').toString(), 'Rs 0.185');
    });

    test('the pharmacy 15% retailer discount is a basis-point adjustment', () {
      final mrp = Rate.perUnit(Money.rupees(1000));
      expect(mrp.percentBp(1500), Rate.perUnit(Money.rupees(150)));
    });
  });

  group('rounding modes', () {
    test('halfUp moves ties away from zero', () {
      expect(divideRounded(5, 10, RoundingMode.halfUp), 1);
      expect(divideRounded(-5, 10, RoundingMode.halfUp), -1);
      expect(divideRounded(4, 10, RoundingMode.halfUp), 0);
    });

    test('halfEven moves ties to even', () {
      expect(divideRounded(5, 10, RoundingMode.halfEven), 0);
      expect(divideRounded(15, 10, RoundingMode.halfEven), 2);
      expect(divideRounded(25, 10, RoundingMode.halfEven), 2);
      expect(divideRounded(-5, 10, RoundingMode.halfEven), 0);
    });

    test('truncate and ceilAbs are symmetric about zero', () {
      expect(divideRounded(9, 10, RoundingMode.truncate), 0);
      expect(divideRounded(-9, 10, RoundingMode.truncate), 0);
      expect(divideRounded(1, 10, RoundingMode.ceilAbs), 1);
      expect(divideRounded(-1, 10, RoundingMode.ceilAbs), -1);
    });

    test('exact division is untouched by the mode', () {
      for (final mode in RoundingMode.values) {
        expect(divideRounded(100, 10, mode), 10);
        expect(divideRounded(-100, 10, mode), -10);
      }
    });

    test('rejects a non-positive denominator', () {
      expect(() => divideRounded(1, 0, RoundingMode.halfUp), throwsArgumentError);
    });
  });
}
