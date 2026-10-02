import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

/// When udhaar falls due, and what became of a promise (M38).
///
/// Pure arithmetic on business dates, asserted at the edges where a day out
/// starts an argument at the counter: month ends, a leap day, the day a
/// bill falls due, the day a promise was for.
void main() {
  group('a due date', () {
    test('is the bill date plus the customer credit days', () {
      expect(dueDateOf('2026-08-01', 15), '2026-08-16');
      expect(dueDateOf('2026-08-20', 15), '2026-09-04');
    });

    test('is the shop usual month for a customer with no terms', () {
      expect(shopUsualCreditDays, AgeBucket.current.maxDays);
      expect(dueDateOf('2026-08-01', null), '2026-08-31');
    });

    test('is the bill date itself for a customer on no credit', () {
      expect(dueDateOf('2026-08-01', 0), '2026-08-01');
    });

    test('crosses a year end and a leap day on the calendar', () {
      expect(dueDateOf('2026-12-20', 15), '2027-01-04');
      expect(dueDateOf('2028-02-20', 9), '2028-02-29');
      expect(dueDateOf('2028-02-20', 10), '2028-03-01');
    });
  });

  group('how late a bill is', () {
    test('due today is not yet late', () {
      expect(DueBucket.forDaysOverdue(0), DueBucket.notYetDue);
      expect(DueBucket.forDaysOverdue(-12), DueBucket.notYetDue);
    });

    test('the buckets are inclusive at the top', () {
      expect(DueBucket.forDaysOverdue(1), DueBucket.upTo30);
      expect(DueBucket.forDaysOverdue(30), DueBucket.upTo30);
      expect(DueBucket.forDaysOverdue(31), DueBucket.upTo60);
      expect(DueBucket.forDaysOverdue(60), DueBucket.upTo60);
      expect(DueBucket.forDaysOverdue(61), DueBucket.upTo90);
      expect(DueBucket.forDaysOverdue(90), DueBucket.upTo90);
      expect(DueBucket.forDaysOverdue(91), DueBucket.over90);
    });

    test('every bucket is present, and they sum back to the total', () {
      BillDue bill(int late, int rupees) => BillDue(
        documentId: '$late',
        docNo: '',
        docType: 'sale_invoice',
        billDateLocal: '',
        dueDateLocal: '',
        outstanding: Money.rupees(rupees),
        daysOverdue: late,
      );
      final aging = ageByDueDate([
        bill(-5, 1000),
        bill(0, 500),
        bill(9, 2000),
        bill(95, 300),
        bill(40, 0),
      ]);
      expect(aging.byBucket.keys, containsAll(DueBucket.values));
      expect(aging[DueBucket.notYetDue], const Money.rupees(1500));
      expect(aging[DueBucket.upTo30], const Money.rupees(2000));
      expect(aging[DueBucket.upTo60], Money.zero);
      expect(aging[DueBucket.over90], const Money.rupees(300));
      expect(aging.total, const Money.rupees(3800));
      expect(aging.overdue, const Money.rupees(2300));
    });

    test('a date is said short this year and with its year otherwise', () {
      expect(shortDate('2026-10-12', thisYear: 2026), '12 Oct');
      expect(shortDate('2027-01-04', thisYear: 2026), '4 Jan 2027');
      expect(shortDate('not a date'), 'not a date');
    });
  });

  group('a promise', () {
    PaymentPromise promise({
      String madeOn = '2026-10-01',
      String until = '2026-10-09',
      int? rupees = 5000,
      int paid = 0,
      String? next,
      String? withdrawn,
    }) => PaymentPromise(
      id: 'p',
      partyId: 'aslam',
      promisedFor: until,
      madeOn: madeOn,
      madeBy: 'Malik Sahib',
      amount: rupees == null ? null : Money.rupees(rupees),
      paidSince: Money.rupees(paid),
      supersededOn: next,
      withdrawnOn: withdrawn,
    );

    test('is pending before its day and due on it', () {
      expect(promise().standingOn('2026-10-05'), PromiseStanding.pending);
      expect(promise().standingOn('2026-10-09'), PromiseStanding.dueToday);
      expect(promise().standingOn('2026-10-09').isLive, isTrue);
    });

    test('is kept by the money, early or on the day', () {
      expect(
        promise(paid: 5000).standingOn('2026-10-03'),
        PromiseStanding.kept,
      );
      expect(
        promise(rupees: null, paid: 200).standingOn('2026-10-20'),
        PromiseStanding.kept,
      );
    });

    test('is broken when its day passes short of what was said', () {
      expect(
        promise(paid: 2000).standingOn('2026-10-10'),
        PromiseStanding.broken,
      );
    });

    test('is replaced by a new one made before its day, not after', () {
      expect(
        promise(next: '2026-10-08').standingOn('2026-10-20'),
        PromiseStanding.replaced,
      );
      expect(
        promise(next: '2026-10-12').standingOn('2026-10-20'),
        PromiseStanding.broken,
      );
    });

    test('taken off stays listed as taken off', () {
      expect(
        promise(withdrawn: '2026-10-02').standingOn('2026-10-20'),
        PromiseStanding.withdrawn,
      );
    });

    test('is for today or a day to come, and for more than nothing', () {
      const today = '2026-10-03';
      expect(
        const PromiseDraft(
          partyId: 'aslam',
          promisedFor: '2026-10-02',
        ).problemOn(today),
        isNotNull,
      );
      expect(
        const PromiseDraft(
          partyId: 'aslam',
          promisedFor: '2026-10-09',
          amount: Money.zero,
        ).problemOn(today),
        isNotNull,
      );
      expect(
        const PromiseDraft(
          partyId: 'aslam',
          promisedFor: '2026-10-03',
        ).problemOn(today),
        isNull,
      );
    });

    test('the days a customer says are one tap each', () {
      // Saturday 3 October 2026.
      final days = promiseDays('2026-10-03');
      expect(days.tomorrow, '2026-10-04');
      expect(days.friday, '2026-10-09');
      expect(days.nextWeek, '2026-10-10');
      expect(days.salaryDay, '2026-11-01');
      // On a Friday, Jumma is next Friday; in December, salary day is in
      // January.
      expect(promiseDays('2026-10-09').friday, '2026-10-16');
      expect(promiseDays('2026-12-15').salaryDay, '2027-01-01');
    });
  });
}
