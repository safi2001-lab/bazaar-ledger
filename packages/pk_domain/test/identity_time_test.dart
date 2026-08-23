import 'dart:math';

import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

void main() {
  group('ULID', () {
    test('is 26 Crockford base32 characters', () {
      final gen = UlidGenerator();
      for (var i = 0; i < 100; i++) {
        final id = gen.next();
        expect(id, hasLength(26));
        expect(UlidGenerator.isValid(id), isTrue);
        // Crockford omits I, L, O and U so a handwritten id cannot be
        // misread — which matters the first time someone reads one down a
        // phone line to support.
        expect(id, isNot(matches(RegExp('[ILOU]'))));
      }
    });

    test('sorts lexicographically in creation order', () {
      // The sales list pages by primary key with no secondary sort. If this
      // ever stops holding, every keyset-paginated screen in the app silently
      // starts returning rows out of order.
      final clock = FixedClock(DateTime.utc(2026, 8, 23, 9));
      final gen = UlidGenerator(now: clock.nowUtc);
      final ids = <String>[];
      for (var i = 0; i < 500; i++) {
        ids.add(gen.next());
        if (i % 7 == 0) clock.advance(const Duration(milliseconds: 1));
      }
      final sorted = [...ids]..sort();
      expect(ids, equals(sorted));
    });

    test('is strictly increasing inside a single millisecond', () {
      // Fifteen barcodes scanned in one second must produce lines that sort
      // the way they were rung up.
      final clock = FixedClock(DateTime.utc(2026, 8, 23, 9));
      final gen = UlidGenerator(now: clock.nowUtc);
      var previous = gen.next();
      for (var i = 0; i < 2000; i++) {
        final id = gen.next();
        expect(id.compareTo(previous), greaterThan(0));
        previous = id;
      }
    });

    test('does not go backwards when the clock does', () {
      // A shopkeeper correcting the date in Settings, or an NTP step, must not
      // produce an id that sorts before rows already written.
      // Repeated with fresh entropy each time: an implementation that
      // redrew the random block instead of incrementing it would pass this
      // about half the time, which is exactly how it first got written.
      for (var i = 0; i < 64; i++) {
        final clock = FixedClock(DateTime.utc(2026, 8, 23, 9));
        final gen = UlidGenerator(now: clock.nowUtc);
        final before = gen.next();
        clock.advance(const Duration(days: -3));
        final after = gen.next();
        expect(after.compareTo(before), greaterThan(0));
      }
    });

    test('does not repeat across 20,000 ids', () {
      final gen = UlidGenerator();
      final seen = <String>{};
      for (var i = 0; i < 20000; i++) {
        expect(seen.add(gen.next()), isTrue);
      }
    });

    test('two generators seeded identically still diverge', () {
      // Two counters in one shop, both starting at the same instant.
      final clock = FixedClock(DateTime.utc(2026, 8, 23, 9));
      final a = UlidGenerator(random: Random(1), now: clock.nowUtc);
      final b = UlidGenerator(random: Random(2), now: clock.nowUtc);
      expect(a.next(), isNot(b.next()));
    });

    test('round-trips its timestamp', () {
      final instant = DateTime.utc(2026, 8, 23, 14, 30, 55, 123);
      final gen = UlidGenerator(now: () => instant);
      expect(UlidGenerator.timestampOf(gen.next()), instant);
    });

    test('rejects a value that is not a ULID', () {
      expect(UlidGenerator.isValid(''), isFalse);
      expect(UlidGenerator.isValid('01J8ZQK7V9C3M4N5P6Q7R8S9T'), isFalse);
      expect(UlidGenerator.isValid('01J8ZQK7V9C3M4N5P6Q7R8S9TU'), isFalse);
      expect(() => UlidGenerator.timestampOf('nope'), throwsFormatException);
    });
  });

  group('BusinessDate', () {
    test('uses the shopkeeper day, not the UTC day', () {
      // 8pm in Lahore on the 23rd is 3pm UTC on the 23rd — same day. But 2am
      // PKT on the 24th is 9pm UTC on the 23rd, and that sale belongs to the
      // 24th's Day Book, which is the one the shopkeeper will be looking at.
      expect(
        BusinessDate.fromUtc(DateTime.utc(2026, 8, 23, 15)).value,
        '2026-08-23',
      );
      expect(
        BusinessDate.fromUtc(DateTime.utc(2026, 8, 23, 21)).value,
        '2026-08-24',
      );
      // The last minute of the shop's day.
      expect(
        BusinessDate.fromUtc(DateTime.utc(2026, 8, 23, 18, 59)).value,
        '2026-08-23',
      );
      expect(
        BusinessDate.fromUtc(DateTime.utc(2026, 8, 23, 19, 0)).value,
        '2026-08-24',
      );
    });

    test('derives the Pakistani fiscal year, which starts 1 July', () {
      expect(BusinessDate('2026-06-30').fiscalYear, 2526);
      expect(BusinessDate('2026-07-01').fiscalYear, 2627);
      expect(BusinessDate('2026-12-31').fiscalYear, 2627);
      expect(BusinessDate('2027-06-30').fiscalYear, 2627);
      expect(BusinessDate('2027-07-01').fiscalYear, 2728);
    });

    test('parses only YYYY-MM-DD, and only real dates', () {
      expect(BusinessDate.tryParse('2026-08-23')?.value, '2026-08-23');
      for (final bad in [
        '',
        '23-08-2026',
        '2026-8-23',
        '2026-02-31',
        '2026-13-01',
        '2026-00-10',
        'today',
      ]) {
        expect(BusinessDate.tryParse(bad), isNull, reason: 'rejects "$bad"');
      }
    });

    test('adds days across a month boundary', () {
      expect(BusinessDate('2026-08-30').addDays(3).value, '2026-09-02');
      expect(BusinessDate('2026-03-01').addDays(-1).value, '2026-02-28');
    });
  });

  group('HLC', () {
    late FixedClock clock;
    late HlcClock counter1;

    setUp(() {
      clock = FixedClock(DateTime.utc(2026, 8, 23, 9));
      counter1 = HlcClock(deviceId: 'DEVICE-ONE', clock: clock);
    });

    test('sorts causally as a plain string', () {
      // This is the property the whole design rests on: SQLite can index it,
      // ORDER BY works, and the merge rule is a string comparison.
      final stamps = <String>[];
      for (var i = 0; i < 50; i++) {
        stamps.add(counter1.next().value);
        if (i % 3 == 0) clock.advance(const Duration(milliseconds: 1));
      }
      final sorted = [...stamps]..sort();
      expect(stamps, equals(sorted));
    });

    test('advances the counter when the wall clock has not moved', () {
      final a = counter1.next();
      final b = counter1.next();
      expect(a.millis, b.millis);
      expect(b.counter, a.counter + 1);
      expect(b > a, isTrue);
    });

    test('resets the counter when the wall clock moves on', () {
      counter1.next();
      counter1.next();
      clock.advance(const Duration(milliseconds: 5));
      final next = counter1.next();
      expect(next.counter, 0);
    });

    test('still moves forward when the wall clock moves backwards', () {
      // The single most common real-world case: two Android handsets whose
      // clocks disagree, and a shopkeeper who has just fixed one by hand.
      final before = counter1.next();
      clock.advance(const Duration(hours: -2));
      final after = counter1.next();
      expect(after > before, isTrue);
    });

    test('a merged timestamp is newer than both inputs', () {
      final counter2 = HlcClock(deviceId: 'DEVICE-TWO', clock: clock);
      final fromPeer = counter2.next();
      final mine = counter1.next();
      final merged = counter1.merge(fromPeer);
      expect(merged > fromPeer, isTrue);
      expect(merged > mine, isTrue);
    });

    test('two devices converge on the same order after exchanging', () {
      final clockB = FixedClock(DateTime.utc(2026, 8, 23, 9, 0, 0, 400));
      final counter2 = HlcClock(deviceId: 'DEVICE-TWO', clock: clockB);

      final a1 = counter1.next();
      final b1 = counter2.next();

      counter1.merge(b1);
      counter2.merge(a1);

      final a2 = counter1.next();
      final b2 = counter2.next();

      // Whatever each device does next is ordered after everything it has
      // seen, on both sides.
      expect(a2 > b1, isTrue);
      expect(b2 > a1, isTrue);
    });

    test('refuses a peer whose clock is implausibly far ahead', () {
      // A device set to 2031 would otherwise win every conflict for five
      // years, and nobody would ever work out why their edits kept vanishing.
      final wrong = Hlc.of(
        millis: clock.nowUtc().millisecondsSinceEpoch +
            const Duration(days: 400).inMilliseconds,
        counter: 0,
        deviceId: 'DEVICE-WRONG',
      );
      expect(() => counter1.merge(wrong), throwsA(isA<HlcDriftException>()));
      expect(
        HlcDriftException(
          remote: wrong,
          localMillis: clock.nowUtc().millisecondsSinceEpoch,
          maxDrift: const Duration(hours: 1),
        ).toString(),
        contains('Check the date and time'),
      );
    });

    test('resumes from the last timestamp this device wrote', () {
      // Recovery on startup: the outbox holds the highest HLC we ever issued,
      // so there is no separate counter to keep in step or lose in a crash.
      final earlier = counter1.next();
      final resumed = HlcClock(
        deviceId: 'DEVICE-ONE',
        clock: FixedClock(DateTime.utc(2026, 8, 23, 8)),
        lastSeen: earlier,
      );
      expect(resumed.next() > earlier, isTrue);
    });

    test('parses and rejects', () {
      final stamp = counter1.next();
      final parsed = Hlc.tryParse(stamp.value);
      expect(parsed, stamp);
      expect(parsed!.deviceId, 'DEVICE-ONE');
      for (final bad in ['', 'nope', '12-34-56', 'ZZZZZZZZZZZZ-0000-DEV']) {
        expect(Hlc.tryParse(bad), isNull, reason: 'rejects "$bad"');
      }
    });
  });

  group('ActorContext', () {
    test('stamps every row in one operation with one instant', () {
      final clock = FixedClock(DateTime.utc(2026, 8, 23, 15, 30));
      final actor = ActorContext.now(
        firmId: 'F1',
        userId: 'U1',
        deviceId: 'D1',
        clock: clock,
      );
      // The clock moves while the transaction runs; the context does not.
      clock.advance(const Duration(seconds: 11));
      expect(actor.startedAtUtc, DateTime.utc(2026, 8, 23, 15, 30));
      expect(actor.businessDate.value, '2026-08-23');
      expect(actor.businessDate.fiscalYear, 2627);
    });

    test('refuses an empty identity', () {
      expect(
        () => ActorContext(
          firmId: '',
          userId: 'U1',
          deviceId: 'D1',
          startedAtUtc: DateTime.utc(2026),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
