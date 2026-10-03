import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// The bills that come round (M63): when each falls due, before any
/// database is near it, and what the phone makes of one by itself.
void main() {
  BusinessDate d(String value) => BusinessDate(value);

  RecurringBill bill({
    RepeatEvery every = const RepeatEvery.weekly(DateTime.monday),
    String start = '2026-10-01',
    String? end,
    int? times,
    String? done,
    bool paused = false,
    String? ended,
    List<RecurringLine>? lines,
    RecurringPrices prices = RecurringPrices.today,
    Money billDiscount = Money.zero,
  }) => RecurringBill(
    id: 'r1',
    partyId: 'hotel',
    partyName: 'Hotel Al-Madina',
    lines:
        lines ??
        [
          RecurringLine(
            itemId: 'milk',
            name: 'Doodh',
            qty: Qty.units(20),
            unitCode: 'ltr',
            rate: Rate.rupees(200),
          ),
        ],
    every: every,
    startOn: d(start),
    endOn: end == null ? null : d(end),
    times: times,
    doneThrough: done == null ? null : d(done),
    paused: paused,
    endedOn: ended == null ? null : d(ended),
    prices: prices,
    billDiscount: billDiscount,
  );

  group('repeating bill schedule', () {
    test('a weekly bill comes due on its day and not before', () {
      // 1 Oct 2026 is a Thursday; the first Monday is the 5th.
      final canteen = bill();
      expect(canteen.dueOn(d('2026-10-03')), isEmpty);
      expect(canteen.dueOn(d('2026-10-04')), isEmpty);
      expect(canteen.dueOn(d('2026-10-05')), [d('2026-10-05')]);
      expect(canteen.nextAfter(d('2026-10-03')), d('2026-10-05'));
      final made = canteen.handledThrough(d('2026-10-05'));
      expect(made.dueOn(d('2026-10-11')), isEmpty);
      expect(made.dueOn(d('2026-10-12')), [d('2026-10-12')]);
      expect(made.nextAfter(d('2026-10-05')), d('2026-10-12'));
    });

    test('a monthly bill on the 31st falls on the last day of a short month, '
        'and back on the 31st after it', () {
      final office = bill(
        every: const RepeatEvery.monthly(31),
        start: '2027-01-01',
      );
      expect(office.occurrences(through: d('2027-04-30')), [
        d('2027-01-31'),
        d('2027-02-28'),
        d('2027-03-31'),
        d('2027-04-30'),
      ]);
    });

    test(
      'every so many days counts from the start, and daily is every day',
      () {
        expect(
          bill(
            every: const RepeatEvery.everyDays(14),
          ).occurrences(through: d('2026-11-01')),
          [d('2026-10-01'), d('2026-10-15'), d('2026-10-29')],
        );
        expect(
          bill(
            every: const RepeatEvery.daily(),
          ).occurrences(through: d('2026-10-03')),
          [d('2026-10-01'), d('2026-10-02'), d('2026-10-03')],
        );
      },
    );

    test('days the app was not opened are all owed, oldest first', () {
      final milk = bill(every: const RepeatEvery.daily(), done: '2026-10-01');
      final owed = milk.dueOn(d('2026-10-04'));
      expect(owed, [d('2026-10-02'), d('2026-10-03'), d('2026-10-04')]);
      final due = RecurringDue(bill: milk, dates: owed);
      expect(due.missed, isTrue);
      expect(due.latest, d('2026-10-04'));
      expect(
        RecurringDue(bill: milk, dates: [d('2026-10-04')]).missed,
        isFalse,
      );
    });

    test('a paused bill never comes due, and an ended one never again', () {
      expect(
        bill(
          every: const RepeatEvery.daily(),
          paused: true,
        ).dueOn(d('2026-12-31')),
        isEmpty,
      );
      final ended = bill(every: const RepeatEvery.daily(), ended: '2026-10-02');
      expect(ended.dueOn(d('2026-12-31')), isEmpty);
      expect(ended.nextAfter(d('2026-10-02')), isNull);
      expect(ended.isOver(d('2026-10-02')), isTrue);
    });

    test('an end date and a count both stop it', () {
      final until = bill(every: const RepeatEvery.daily(), end: '2026-10-03');
      expect(until.occurrences(through: d('2026-10-31')), hasLength(3));
      expect(until.nextAfter(d('2026-10-03')), isNull);
      final sixTimes = bill(every: const RepeatEvery.monthly(1), times: 6);
      final all = sixTimes.occurrences(through: d('2027-12-31'));
      expect(all, hasLength(6));
      expect(all.last, d('2027-03-01'));
      expect(
        sixTimes.handledThrough(d('2027-03-01')).isOver(d('2027-03-01')),
        isTrue,
      );
    });

    test('nonsense is refused in words before it is kept', () {
      expect(
        () => bill(lines: const []).check(),
        throwsA(
          isA<RecurringRefused>().having(
            (r) => r.problem,
            'problem',
            RecurringProblem.noLines,
          ),
        ),
      );
      expect(
        () => bill(every: const RepeatEvery.weekly(9)).check(),
        throwsA(isA<RecurringRefused>()),
      );
      expect(
        () => bill(end: '2026-09-01').check(),
        throwsA(isA<RecurringRefused>()),
      );
      expect(() => bill(times: 0).check(), throwsA(isA<RecurringRefused>()));
      // Read from a row nobody checked, it falls on no day at all.
      expect(
        bill(every: const RepeatEvery.weekly(9)).dueOn(d('2026-12-31')),
        isEmpty,
      );
      expect(
        bill(every: const RepeatEvery.everyDays(0)).nextAfter(d('2026-10-01')),
        isNull,
      );
    });

    test('a change saved from a screen keeps the pause, the end and the day '
        'last handled that the books hold', () {
      final kept = bill(done: '2026-10-12', paused: true);
      final edited = bill(
        done: '2026-10-05',
        every: const RepeatEvery.weekly(DateTime.tuesday),
      ).keepingStateOf(kept);
      expect(edited.every, const RepeatEvery.weekly(DateTime.tuesday));
      expect(edited.paused, isTrue);
      expect(edited.doneThrough, d('2026-10-12'));
      expect(
        bill(done: '2026-10-19').keepingStateOf(kept).doneThrough,
        d('2026-10-19'),
      );
    });

    test('kept as JSON of integers and strings, and read back the same', () {
      final kept = bill(
        every: const RepeatEvery.everyDays(3),
        end: '2027-01-01',
        done: '2026-10-04',
        prices: RecurringPrices.fixed,
        billDiscount: const Money.rupees(50),
        lines: [
          RecurringLine(
            itemId: null,
            name: 'Pyaz',
            qty: Qty.parse('2.5'),
            unitCode: 'kg',
            rate: Rate.rupees(80),
            discountBp: 500,
          ),
        ],
      );
      final back = RecurringBill.fromJson('r1', kept.toJson())!;
      expect(back.toJson(), kept.toJson());
      expect(back.every, const RepeatEvery.everyDays(3));
      expect(back.lines.single.isLoose, isTrue);
      expect(back.lines.single.qty, Qty.parse('2.5'));
      expect(RecurringBill.fromJson('r1', 'not json'), isNull);
      expect(RecurringBill.fromJson('r1', '{"v":99}'), isNull);
    });
  });

  group('a repeating bill made by itself', () {
    ItemSummary milk({Rate? wholesale}) => ItemSummary(
      id: 'milk',
      name: 'Doodh',
      unitId: 'ltr',
      unitCode: 'ltr',
      unitDecimals: 3,
      saleRate: Rate.rupees(220),
      wholesaleRate: wholesale ?? Rate.rupees(200),
      stockOnHand: Qty.units(100),
      tracksStock: true,
    );

    test("today's prices are the customer's tier, the item's slab where it "
        'is lower, and their standing discount', () {
      final book = SchemeBook(
        slabs: {
          'milk': [QtySlab(from: Qty.units(20), rate: Rate.rupees(190))],
        },
      );
      final draft = recurringSaleDraft(
        bill(),
        items: {'milk': milk()},
        tier: PriceTier.wholesale,
        standingBp: 200,
        book: book,
        units: UnitConverter(const []),
        roundToRupee: true,
      );
      final line = draft.lines.single;
      expect(line.rate, Rate.rupees(190), reason: 'the slab beats wholesale');
      expect(line.discountBp, 200);
      expect(line.baseQty, Qty.units(20));
      expect(draft.partyId, 'hotel');
      expect(draft.tenders, isEmpty, reason: 'on udhaar');
    });

    test("fixed prices keep the bill's own rates and discounts", () {
      final draft = recurringSaleDraft(
        bill(
          prices: RecurringPrices.fixed,
          billDiscount: const Money.rupees(100),
          lines: [
            RecurringLine(
              itemId: 'milk',
              name: 'Doodh',
              qty: Qty.units(20),
              unitCode: 'ltr',
              rate: Rate.rupees(180),
              discountBp: 100,
            ),
          ],
        ),
        items: {'milk': milk()},
        tier: PriceTier.retail,
        standingBp: 500,
        book: SchemeBook.empty,
        units: UnitConverter(const []),
        roundToRupee: true,
      );
      expect(draft.lines.single.rate, Rate.rupees(180));
      expect(draft.lines.single.discountBp, 100);
      expect(draft.billDiscount, const Money.rupees(100));
    });

    test('the bonus a scheme gives goes under its line, and a big bill '
        "takes the shop's slab", () {
      final book = SchemeBook(
        bonuses: {
          'milk': BonusOffer(
            rule: BonusRule(buy: Qty.units(10), free: Qty.units(1)),
            buyBase: Qty.units(10),
            freeBase: Qty.units(1),
            freeItemId: 'milk',
            freeItemName: 'Doodh',
            freeUnitId: 'ltr',
            freeUnitCode: 'ltr',
          ),
        },
        billSlabs: [BillSlab(from: const Money.rupees(1000), percentBp: 200)],
      );
      final draft = recurringSaleDraft(
        bill(),
        items: {'milk': milk()},
        tier: PriceTier.retail,
        standingBp: 0,
        book: book,
        units: UnitConverter(const []),
        roundToRupee: true,
      );
      expect(draft.lines, hasLength(2));
      expect(draft.lines.last.isFreeItem, isTrue);
      expect(draft.lines.last.qty, Qty.units(2));
      // Twenty litres at Rs 220 is Rs 4,400; 2% of it.
      expect(draft.billDiscount, const Money.rupees(88));
    });

    test('an item no longer kept stops the bill and is named, never '
        'dropped quietly', () {
      expect(
        () => recurringSaleDraft(
          bill(),
          items: const {},
          tier: PriceTier.retail,
          standingBp: 0,
          book: SchemeBook.empty,
          units: UnitConverter(const []),
          roundToRupee: true,
        ),
        throwsA(
          isA<RecurringRefused>()
              .having((r) => r.problem, 'problem', RecurringProblem.itemGone)
              .having((r) => r.names, 'names', ['Doodh']),
        ),
      );
    });
  });
}
