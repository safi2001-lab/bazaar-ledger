/// How old the money owed to a shop is.
///
/// A total tells a shopkeeper how much is out. It does not tell them anything
/// they can act on, because Rs 200,000 spread across this month's customers
/// and Rs 200,000 sitting since March are the same number and completely
/// different problems.
///
/// Four buckets, because that is what every accountant, every bank and every
/// competing product uses, and a shopkeeper who has seen one ageing report
/// has seen this one.
library;

import 'package:pk_money/pk_money.dart';

/// How old one debt is, in whole days.
enum AgeBucket {
  /// Not yet a problem. A kiryana shop's normal cycle is a fortnight.
  current(label: '0-30', maxDays: 30),

  /// Late enough to mention when they next come in.
  thirty(label: '31-60', maxDays: 60),

  /// Late enough to send a reminder about.
  sixty(label: '61-90', maxDays: 90),

  /// The one that matters. Money in here rarely improves on its own, and a
  /// shop that cannot see it separately discovers it at stock-take.
  ninety(label: '90+', maxDays: null);

  const AgeBucket({required this.label, required this.maxDays});

  final String label;

  /// Inclusive upper bound in days, or null for the open-ended bucket.
  final int? maxDays;

  /// The bucket a debt [days] old belongs in.
  ///
  /// Negative days — a bill dated in the future, which a shopkeeper doing
  /// next week's paperwork early really does produce — count as current
  /// rather than throwing. It is not the ageing report's job to police dates.
  static AgeBucket forDays(int days) {
    for (final bucket in values) {
      final max = bucket.maxDays;
      if (max == null || days <= max) return bucket;
    }
    return ninety;
  }
}

/// What a shop is owed, by how old it is.
final class Aging {
  const Aging(this.byBucket);

  /// Every bucket, always, including the empty ones. A report that omits a
  /// bucket makes the shopkeeper wonder whether it is empty or broken.
  final Map<AgeBucket, Money> byBucket;

  Money get total => Money.sum(byBucket.values.toList());

  Money operator [](AgeBucket bucket) => byBucket[bucket] ?? Money.zero;

  /// Nothing outstanding at all.
  bool get isClear => !total.isPositive;

  /// Everything older than the shop's normal cycle.
  Money get overdue =>
      this[AgeBucket.thirty] + this[AgeBucket.sixty] + this[AgeBucket.ninety];
}

/// One bill, aged.
final class AgedBill {
  const AgedBill({
    required this.documentId,
    required this.days,
    required this.outstanding,
  });

  final String documentId;
  final int days;
  final Money outstanding;

  AgeBucket get bucket => AgeBucket.forDays(days);
}

/// Buckets [bills] by age.
Aging ageBills(Iterable<AgedBill> bills) {
  final totals = <AgeBucket, Money>{
    for (final bucket in AgeBucket.values) bucket: Money.zero,
  };
  for (final bill in bills) {
    if (!bill.outstanding.isPositive) continue;
    totals[bill.bucket] = totals[bill.bucket]! + bill.outstanding;
  }
  return Aging(totals);
}

/// Whole days between two `YYYY-MM-DD` business dates.
///
/// On the business date, never on a UTC instant. PKT is UTC+5 with no
/// daylight saving, so a bill raised at eight in the evening is a day older
/// than it should be under any UTC arithmetic — and the 90-day bucket is
/// exactly where being a day out starts arguments.
int daysBetween(String fromDateLocal, String toDateLocal) {
  final from = DateTime.parse(fromDateLocal);
  final to = DateTime.parse(toDateLocal);
  return to.difference(from).inDays;
}
