import 'package:pk_domain/pk_domain.dart';

/// The days a report covers, both ends included.
///
/// Business dates, not instants: "September" is the shop's September, from
/// the shutter going up on the 1st to it coming down on the 30th, whatever
/// the phone's clock thinks the time zone is.
final class ReportPeriod {
  ReportPeriod(this.from, this.to) {
    if (to.value.compareTo(from.value) < 0) {
      throw ArgumentError.value(
        '${from.value}..${to.value}',
        'period',
        'ends before it starts',
      );
    }
  }

  /// One day.
  factory ReportPeriod.day(BusinessDate day) => ReportPeriod(day, day);

  /// The calendar month [day] falls in.
  factory ReportPeriod.monthOf(BusinessDate day) {
    final first = BusinessDate(
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-01',
    );
    final nextMonth = DateTime.utc(day.year, day.month + 1);
    final last = BusinessDate.fromUtc(
      nextMonth.subtract(const Duration(days: 1)),
      Duration.zero,
    );
    return ReportPeriod(first, last);
  }

  /// The month before the one [day] falls in.
  factory ReportPeriod.monthBefore(BusinessDate day) {
    final first = ReportPeriod.monthOf(day).from;
    return ReportPeriod.monthOf(first.addDays(-1));
  }

  /// The Pakistani fiscal year [day] falls in: 1 July to 30 June.
  factory ReportPeriod.fiscalYearOf(BusinessDate day) {
    final startYear = day.month >= 7 ? day.year : day.year - 1;
    return ReportPeriod(
      BusinessDate('${startYear.toString().padLeft(4, '0')}-07-01'),
      BusinessDate('${(startYear + 1).toString().padLeft(4, '0')}-06-30'),
    );
  }

  final BusinessDate from;
  final BusinessDate to;

  bool get isOneDay => from == to;

  /// `2026-09-26`, or `2026-09-01 to 2026-09-30`.
  String get label => isOneDay ? from.value : '${from.value} to ${to.value}';

  bool contains(BusinessDate day) =>
      day.value.compareTo(from.value) >= 0 &&
      day.value.compareTo(to.value) <= 0;

  @override
  bool operator ==(Object other) =>
      other is ReportPeriod && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => label;
}
