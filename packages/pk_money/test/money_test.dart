import 'dart:math';

import 'package:pk_money/pk_money.dart';
import 'package:test/test.dart';

void main() {
  group('South Asian grouping', _groupingTests);
  group('construction', () {
    test('rupees and paisa compose', () {
      expect(Money.rupees(55, 25).inPaisa, 5525);
      expect(Money.rupees(5525).inPaisa, 552500);
      expect(Money.paisa(552500), Money.rupees(5525));
      expect(Money.zero.inPaisa, 0);
    });

    test('whole and fractional parts carry the sign', () {
      expect(Money.rupees(5, 25).wholeRupees, 5);
      expect(Money.rupees(5, 25).paisaPart, 25);
      expect(Money.rupees(-5, -25).wholeRupees, -5);
      expect(Money.rupees(-5, -25).paisaPart, -25);
    });
  });

  group('parse', () {
    test('accepts the shapes a person actually types', () {
      expect(Money.parse('5525'), Money.rupees(5525));
      expect(Money.parse('5525.25'), Money.rupees(5525, 25));
      expect(Money.parse('5,525.25'), Money.rupees(5525, 25));
      expect(Money.parse('Rs 5,525.25'), Money.rupees(5525, 25));
      expect(Money.parse('rs5525'), Money.rupees(5525));
      expect(Money.parse('PKR 12.50'), Money.rupees(12, 50));
      expect(Money.parse('  -12.50 '), Money.rupees(-12, -50));
      expect(Money.parse('.5'), Money.rupees(0, 50));
      expect(Money.parse('5.'), Money.rupees(5));
      expect(Money.parse('5.5'), Money.rupees(5, 50));
    });

    test('rejects a third decimal rather than truncating it', () {
      // Truncating here would silently under-charge on every such entry.
      expect(Money.tryParse('12.505'), isNull);
      expect(() => Money.parse('12.505'), throwsFormatException);
    });

    test('rejects junk', () {
      for (final bad in ['', '   ', 'abc', '1.2.3', '.', '-', '1-2', '12a']) {
        expect(Money.tryParse(bad), isNull, reason: 'should reject "$bad"');
      }
    });
  });

  group('arithmetic is exact', () {
    test('the classic float failure does not occur', () {
      // 0.1 + 0.2 != 0.3 in IEEE-754. Here it is exact by construction.
      final sum = Money.parse('0.10') + Money.parse('0.20');
      expect(sum, Money.parse('0.30'));
      expect(sum.inPaisa, 30);
    });

    test('a thousand additions of one paisa make exactly ten rupees', () {
      var total = Money.zero;
      for (var i = 0; i < 1000; i++) {
        total += Money.paisa(1);
      }
      expect(total, Money.rupees(10));
    });

    test('the reference cart totals to the paisa', () {
      // The worked example on the design system sheet and the receipt.
      final oil = Money.rupees(2500) * 2;
      final sugar = Rate.perUnit(Money.rupees(150)).amountFor(Qty.parse('3.5'));
      final tea = Money.rupees(1180);
      expect(oil, Money.rupees(5000));
      expect(sugar, Money.rupees(525));
      expect(Money.sum([oil, sugar, tea]), Money.rupees(6705));
    });

    test('comparison and negation', () {
      expect(Money.rupees(5) > Money.rupees(4), isTrue);
      expect(Money.rupees(5) >= Money.rupees(5), isTrue);
      expect(Money.rupees(-5) < Money.zero, isTrue);
      expect((-Money.rupees(5)).inPaisa, -500);
      expect(Money.rupees(-5).abs, Money.rupees(5));
    });
  });

  group('percentBp', () {
    test('the statutory rates land where they should', () {
      final base = Money.rupees(10000);
      expect(base.percentBp(1800), Money.rupees(1800)); // 18% GST
      expect(base.percentBp(400), Money.rupees(400)); //  4% further tax
      expect(base.percentBp(100), Money.rupees(100)); //  1% Asaan Scheme
      expect(base.percentBp(850), Money.rupees(850)); //  8.5% 8th Schedule
      expect(base.percentBp(1275), Money.rupees(1275)); // 12.75%
    });

    test('half-up on an awkward base', () {
      // 18% of Rs 1.11 = 0.1998 -> 20 paisa
      expect(Money.rupees(1, 11).percentBp(1800), Money.paisa(20));
      // 18% of Rs 0.03 = 0.0054 -> 1 paisa
      expect(Money.paisa(3).percentBp(1800), Money.paisa(1));
    });

    test('negatives round symmetrically', () {
      expect(Money.paisa(-3).percentBp(1800), Money.paisa(-1));
    });
  });

  group('rounding to rupee', () {
    test('half-up in both directions', () {
      expect(Money.rupees(5, 50).roundToRupee(), Money.rupees(6));
      expect(Money.rupees(5, 49).roundToRupee(), Money.rupees(5));
      expect(Money.rupees(-5, -50).roundToRupee(), Money.rupees(-6));
    });

    test('the delta is postable and closes the gap exactly', () {
      final amount = Money.rupees(6704, 60);
      final delta = amount.roundingDelta();
      expect(delta, Money.paisa(40));
      expect(amount + delta, Money.rupees(6705));
    });
  });

  group('allocate and split never create or destroy paisa', () {
    test('an indivisible split still sums back', () {
      final parts = Money.paisa(100).split(3);
      expect(parts.map((p) => p.inPaisa), [34, 33, 33]);
      expect(Money.sum(parts), Money.paisa(100));
    });

    test('weighted allocation sums back', () {
      final parts = Money.rupees(100).allocate([1, 1, 1]);
      expect(Money.sum(parts), Money.rupees(100));

      final weighted = Money.paisa(10001).allocate([5000, 2500, 2501]);
      expect(Money.sum(weighted), Money.paisa(10001));
    });

    test('zero-weight shares stay empty and get no remainder', () {
      final parts = Money.paisa(100).allocate([1, 0, 1]);
      expect(parts[1], Money.zero);
      expect(Money.sum(parts), Money.paisa(100));
    });

    test('negative amounts allocate without losing a paisa', () {
      final parts = Money.paisa(-100).split(3);
      expect(Money.sum(parts), Money.paisa(-100));
      expect(parts.every((p) => p.isNegative), isTrue);
    });

    test('property: 2000 random allocations all sum back exactly', () {
      final rng = Random(20260823);
      for (var i = 0; i < 2000; i++) {
        final amount = Money.paisa(rng.nextInt(4000000) - 2000000);
        final count = 1 + rng.nextInt(9);
        final ratios = [
          for (var j = 0; j < count; j++) rng.nextInt(100),
        ];
        if (ratios.every((r) => r == 0)) ratios[0] = 1;

        final parts = amount.allocate(ratios);
        expect(Money.sum(parts), amount,
            reason: 'amount=${amount.inPaisa} ratios=$ratios');
        expect(parts.length, count);
      }
    });

    test('rejects impossible inputs', () {
      expect(() => Money.rupees(1).split(0), throwsArgumentError);
      expect(() => Money.rupees(1).allocate([]), throwsArgumentError);
      expect(() => Money.rupees(1).allocate([0, 0]), throwsArgumentError);
      expect(() => Money.rupees(1).allocate([1, -1]), throwsArgumentError);
    });
  });

  group('formatting', () {
    test('always two decimals, grouped, Latin digits', () {
      expect(Money.rupees(5525).toString(), 'Rs 5,525.00');
      expect(Money.rupees(5525, 25).amountOnly, '5,525.25');
      expect(Money.rupees(0, 5).amountOnly, '0.05');
      expect(Money.zero.amountOnly, '0.00');
      // Lakh grouping, not Western. See the "South Asian grouping" group.
      expect(Money.rupees(1234567, 89).amountOnly, '12,34,567.89');
      expect(Money.rupees(999).amountOnly, '999.00');
      expect(Money.rupees(1000).amountOnly, '1,000.00');
    });

    test('no Arabic-Indic digits ever appear', () {
      // CLDR defaults ur-PK to latn; only ur-IN uses arabext.
      final rendered = Money.rupees(1234567, 89).toString();
      expect(RegExp(r'^[A-Za-z0-9,.\s]+$').hasMatch(rendered), isTrue,
          reason: 'got "$rendered"');
      expect(rendered.contains(RegExp(r'[٠-٩۰-۹]')),
          isFalse);
    });

    test('signed rendering spells out direction', () {
      // Colour is never the only signal — the glyph carries it too.
      expect(Money.rupees(5525).signed, '+ Rs 5,525.00');
      expect(Money.rupees(-1200).signed, '− Rs 1,200.00');
      expect(Money.zero.signed, 'Rs 0.00');
    });

    test('negative amountOnly keeps the minus', () {
      expect(Money.rupees(-1200).amountOnly, '-1,200.00');
    });
  });

  test('sum of nothing is zero', () {
    expect(Money.sum(const []), Money.zero);
  });
}

/// How a Pakistani shopkeeper reads a number.
///
/// CLDR gives `en-PK` and `ur-PK` the pattern `#,##,##0.###` — the last three
/// digits, then twos. Twelve lakh is `12,34,567`. Western grouping reads as
/// `1,234,567` and has to be counted rather than recognised, which on a
/// counter is the difference between a glance and a pause.
void _groupingTests() {
  test('thousands group in threes, as everywhere', () {
    expect(Money.rupees(1).amountOnly, '1.00');
    expect(Money.rupees(999).amountOnly, '999.00');
    expect(Money.rupees(1000).amountOnly, '1,000.00');
    expect(Money.rupees(99999).amountOnly, '99,999.00');
  });

  test('a lakh groups in twos above the thousand', () {
    expect(Money.rupees(100000).amountOnly, '1,00,000.00');
    expect(Money.rupees(1234567).amountOnly, '12,34,567.00');
    expect(
      Money.rupees(200000).amountOnly,
      '2,00,000.00',
      reason: 'the s.21(s) threshold, as a shopkeeper writes it',
    );
  });

  test('a crore keeps grouping in twos', () {
    expect(Money.rupees(10000000).amountOnly, '1,00,00,000.00');
    expect(Money.rupees(123456789).amountOnly, '12,34,56,789.00');
  });

  test('the sign survives grouping', () {
    expect((-Money.rupees(1234567)).amountOnly, '-12,34,567.00');
  });

  test('rates group the same way', () {
    expect(Rate.rupees(1234567).amountOnly, '12,34,567.00');
  });

  test('digits are always Latin, never Arabic-Indic', () {
    // CLDR: ur.xml inherits latn, ur_PK.xml is an empty stub, and only
    // ur_IN.xml selects arabext. A price in Eastern Arabic numerals is a
    // price this market cannot read.
    final rendered = Money.rupees(1234567).amountOnly;
    expect(RegExp(r'^[-0-9,.]+$').hasMatch(rendered), isTrue);
  });
}
