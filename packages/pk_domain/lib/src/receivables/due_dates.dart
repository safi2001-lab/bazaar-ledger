/// When a bill on udhaar falls due, and how late it now is (M38).
///
/// The khata knew how old every bill was and nothing about when it was
/// meant to be paid. A wholesaler who gives a retailer fifteen days and a
/// kiryana that lets a household run to salary day were chased by the same
/// clock — the bill's age — so a customer inside their terms read as late,
/// and one a week past them read as fine because the month was not up.
///
/// ## Derived, never stored
///
/// A bill's due date is its date plus the customer's credit days, worked
/// out whenever it is read. It is not written onto the bill. Two reasons:
///
///  * no schema change was open to this milestone (v8 is held by another),
///    and a column added later is one an old bill never had;
///  * the shopkeeper's own words for it are "Aslam ko pandrah din ka
///    udhaar hai" — a term on the customer, not a date on the paper.
///
/// The consequence is deliberate and said on the party form: changing a
/// customer's credit days moves the due date of every bill they still owe
/// on. Giving Aslam thirty days instead of fifteen is the shop deciding to
/// wait longer for what he owes now, as well as for what he buys next.
///
/// ## A customer with no terms
///
/// Is held to the shop's usual month, [shopUsualCreditDays]. That is the
/// same thirty days the ageing report has always treated as current (M3),
/// so a shop that never sets a term sees exactly the "overdue" figure it
/// saw before; and a household khata settled on salary day is a month.
/// Zero days is a term of its own: due the day it was bought.
library;

import 'package:pk_money/pk_money.dart';

import '../time/clock.dart';

/// How long a customer with no credit days of their own is given.
///
/// The top of the ageing report's current bucket (`AgeBucket.current`),
/// kept equal to it on purpose: a shop that sets no terms is chased on the
/// same day the old report started calling a bill late.
const shopUsualCreditDays = 30;

/// The day a bill dated [billDateLocal] is due, for a customer given
/// [creditDays] (null: the shop's usual month).
///
/// Business dates in, business date out, `YYYY-MM-DD`. Never through a UTC
/// instant: PKT has no daylight saving, but a bill raised at eight in the
/// evening is already tomorrow in UTC arithmetic, and a due date a day
/// early is a customer chased a day before they were told.
String dueDateOf(String billDateLocal, int? creditDays) {
  final days = creditDays ?? shopUsualCreditDays;
  return BusinessDate(billDateLocal).addDays(days < 0 ? 0 : days).value;
}

/// How far past its due date one bill is, in buckets.
///
/// The same edges as the bill-age report (M3), with the current bucket
/// split in two by what actually matters to a shop chasing money: whether
/// the customer is late at all.
enum DueBucket {
  /// Inside the customer's terms, including the day it falls due.
  notYetDue(maxDaysOverdue: 0),

  /// A month or less past due.
  upTo30(maxDaysOverdue: 30),

  /// One to two months past due.
  upTo60(maxDaysOverdue: 60),

  /// Two to three months past due.
  upTo90(maxDaysOverdue: 90),

  /// More than three months past due: the money that rarely comes back on
  /// its own, and the list a write-off is decided from (M44).
  over90(maxDaysOverdue: null);

  const DueBucket({required this.maxDaysOverdue});

  /// Inclusive upper bound, in days past due; null for the open end.
  final int? maxDaysOverdue;

  /// The numeric label the chips print. [notYetDue] has none of its own —
  /// it is said in words by the screen.
  String get label => switch (this) {
    notYetDue => '0',
    upTo30 => '1-30',
    upTo60 => '31-60',
    upTo90 => '61-90',
    over90 => '90+',
  };

  /// The bucket for a bill [daysOverdue] past its due date. Zero (due
  /// today) and anything negative (not due yet) are [notYetDue].
  static DueBucket forDaysOverdue(int daysOverdue) {
    for (final bucket in values) {
      final max = bucket.maxDaysOverdue;
      if (max == null || daysOverdue <= max) return bucket;
    }
    return over90;
  }

  bool get isOverdue => this != notYetDue;
}

/// One open bill, with when it falls due.
final class BillDue {
  const BillDue({
    required this.documentId,
    required this.docNo,
    required this.docType,
    required this.billDateLocal,
    required this.dueDateLocal,
    required this.outstanding,
    required this.daysOverdue,
  });

  final String documentId;

  /// The number on the paper.
  final String docNo;

  /// `sale_invoice`, or `other_income` for a charge put on the khata.
  final String docType;
  final String billDateLocal;
  final String dueDateLocal;
  final Money outstanding;

  /// Days since it fell due: positive is late, zero is due today, negative
  /// is the days still to go.
  final int daysOverdue;

  DueBucket get bucket => DueBucket.forDaysOverdue(daysOverdue);
  bool get isOverdue => daysOverdue > 0;
  bool get isDueToday => daysOverdue == 0;
}

/// What a shop is owed, by how late it is.
final class DueAging {
  const DueAging(this.byBucket);

  /// Every bucket, always, including the empty ones — for the same reason
  /// the bill-age report keeps them: a missing bucket reads as broken.
  final Map<DueBucket, Money> byBucket;

  Money operator [](DueBucket bucket) => byBucket[bucket] ?? Money.zero;

  Money get total => Money.sum(byBucket.values.toList());

  /// Everything past its due date.
  Money get overdue => Money.sum([
    for (final b in DueBucket.values)
      if (b.isOverdue) this[b],
  ]);

  bool get isClear => !total.isPositive;
}

/// Buckets [bills] by days overdue.
DueAging ageByDueDate(Iterable<BillDue> bills) {
  final totals = <DueBucket, Money>{
    for (final b in DueBucket.values) b: Money.zero,
  };
  for (final bill in bills) {
    if (!bill.outstanding.isPositive) continue;
    totals[bill.bucket] = totals[bill.bucket]! + bill.outstanding;
  }
  return DueAging(totals);
}

/// `12 Oct` from `2026-10-12`: how a due date is said on a shop's screen.
///
/// English month names, because that is what a Roman Urdu reader reads on
/// a calendar and on a bill; the Urdu-script reminder has its own (see
/// `reminder_templates.dart`). The year is added only when it is not
/// [thisYear], so this month's dates stay short on a small phone.
String shortDate(String dateLocal, {int? thisYear}) {
  final date = BusinessDate.tryParse(dateLocal);
  if (date == null) return dateLocal;
  final month = _months[date.month - 1];
  return thisYear == null || thisYear == date.year
      ? '${date.day} $month'
      : '${date.day} $month ${date.year}';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
