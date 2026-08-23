import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// How old the money owed to a shop is.
///
/// A total tells a shopkeeper how much is out and nothing they can act on:
/// Rs 200,000 across this month's customers and Rs 200,000 sitting since
/// March are the same number and completely different problems.
void main() {
  group('which bucket a debt falls in', () {
    test('the boundaries are inclusive at the top', () {
      // Off-by-one here is where an ageing report starts arguments, because
      // 90 and 91 days are the difference between "chase it" and "write it
      // off" in the shopkeeper's head.
      expect(AgeBucket.forDays(0), AgeBucket.current);
      expect(AgeBucket.forDays(30), AgeBucket.current);
      expect(AgeBucket.forDays(31), AgeBucket.thirty);
      expect(AgeBucket.forDays(60), AgeBucket.thirty);
      expect(AgeBucket.forDays(61), AgeBucket.sixty);
      expect(AgeBucket.forDays(90), AgeBucket.sixty);
      expect(AgeBucket.forDays(91), AgeBucket.ninety);
      expect(AgeBucket.forDays(4000), AgeBucket.ninety);
    });

    test('a bill dated in the future is current, not a crash', () {
      // A shopkeeper doing next week's paperwork early really does produce
      // one, and it is not the ageing report's job to police dates.
      expect(AgeBucket.forDays(-5), AgeBucket.current);
    });
  });

  group('days are counted on the business date', () {
    test('across a month boundary', () {
      expect(daysBetween('2026-06-01', '2026-07-01'), 30);
      expect(daysBetween('2026-06-01', '2026-08-30'), 90);
      expect(daysBetween('2026-06-01', '2026-08-31'), 91);
    });

    test('a leap day is a day', () {
      expect(daysBetween('2028-02-28', '2028-03-01'), 2);
    });

    test('the same day is nothing owed for any time at all', () {
      expect(daysBetween('2026-08-23', '2026-08-23'), 0);
    });
  });

  group('bucketing a shop', () {
    test('every bucket is present, including the empty ones', () {
      // A report that omits a bucket makes the shopkeeper wonder whether it
      // is empty or broken.
      final aging = ageBills(const []);

      expect(aging.byBucket.keys, containsAll(AgeBucket.values));
      expect(aging.total, Money.zero);
      expect(aging.isClear, isTrue);
    });

    test('bills land where their age puts them', () {
      final aging = ageBills([
        _bill(days: 5, rupees: 1000),
        _bill(days: 45, rupees: 2000),
        _bill(days: 75, rupees: 3000),
        _bill(days: 200, rupees: 4000),
        _bill(days: 12, rupees: 500),
      ]);

      expect(aging[AgeBucket.current], const Money.rupees(1500));
      expect(aging[AgeBucket.thirty], const Money.rupees(2000));
      expect(aging[AgeBucket.sixty], const Money.rupees(3000));
      expect(aging[AgeBucket.ninety], const Money.rupees(4000));
      expect(aging.total, const Money.rupees(10500));
    });

    test('a settled bill contributes nothing', () {
      final aging = ageBills([
        _bill(days: 200, rupees: 0),
        _bill(days: 200, rupees: 1000),
      ]);

      expect(aging[AgeBucket.ninety], const Money.rupees(1000));
    });

    test('overdue is everything past the shop normal cycle', () {
      // A kiryana shop's cycle is a fortnight. The current bucket is not a
      // problem and must not be in the number a shopkeeper reads as "chase
      // this" — otherwise every shop looks like it is in trouble every day.
      final aging = ageBills([
        _bill(days: 5, rupees: 90000),
        _bill(days: 45, rupees: 2000),
        _bill(days: 200, rupees: 1000),
      ]);

      expect(aging.overdue, const Money.rupees(3000));
      expect(aging.total, const Money.rupees(93000));
    });

    test('the buckets sum back to the total, exactly', () {
      final aging = ageBills([
        for (var days = 0; days < 400; days++)
          _bill(days: days, rupees: 0, paisa: days * 7 + 1),
      ]);

      final summed = Money.sum(aging.byBucket.values.toList());
      expect(summed, aging.total);
      expect(
        aging.total.inPaisa,
        List.generate(400, (d) => d * 7 + 1).reduce((a, b) => a + b),
      );
    });
  });
}

AgedBill _bill({required int days, required int rupees, int paisa = 0}) =>
    AgedBill(
      documentId: 'doc-$days',
      days: days,
      outstanding: Money.paisa(rupees * 100 + paisa),
    );
