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

  /// The week [day] falls in, Monday to Sunday (M33).
  ///
  /// Monday first, as the bank and the wholesaler's weekly round count it;
  /// Friday's half day is still the middle of the shop's week.
  factory ReportPeriod.weekOf(BusinessDate day) {
    final weekday = DateTime.utc(day.year, day.month, day.day).weekday;
    final monday = day.addDays(1 - weekday);
    return ReportPeriod(monday, monday.addDays(6));
  }

  /// The quarter [day] falls in (M33). Pakistan's fiscal year starts on
  /// 1 July, so its quarters are the calendar's: July to September is both
  /// the first fiscal quarter and the third calendar one.
  factory ReportPeriod.quarterOf(BusinessDate day) {
    final firstMonth = ((day.month - 1) ~/ 3) * 3 + 1;
    final first = BusinessDate(
      '${day.year.toString().padLeft(4, '0')}-'
      '${firstMonth.toString().padLeft(2, '0')}-01',
    );
    final last = ReportPeriod.monthOf(
      BusinessDate(
        '${day.year.toString().padLeft(4, '0')}-'
        '${(firstMonth + 2).toString().padLeft(2, '0')}-01',
      ),
    ).to;
    return ReportPeriod(first, last);
  }

  final BusinessDate from;
  final BusinessDate to;

  bool get isOneDay => from == to;

  /// The period just before this one, of the same shape (M33): the month
  /// before a month, the quarter before a quarter, the fiscal year before a
  /// fiscal year, and otherwise as many days again, ending the day before.
  /// What "vs last month" compares with.
  ReportPeriod get previous {
    final dayBefore = from.addDays(-1);
    if (this == ReportPeriod.monthOf(from)) {
      return ReportPeriod.monthOf(dayBefore);
    }
    if (this == ReportPeriod.quarterOf(from)) {
      return ReportPeriod.quarterOf(dayBefore);
    }
    if (this == ReportPeriod.fiscalYearOf(from)) {
      return ReportPeriod.fiscalYearOf(dayBefore);
    }
    final days =
        DateTime.utc(
          to.year,
          to.month,
          to.day,
        ).difference(DateTime.utc(from.year, from.month, from.day)).inDays +
        1;
    return ReportPeriod(from.addDays(-days), dayBefore);
  }

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

/// The periods a report screen offers, as the shop says them (M33). Custom
/// is any two dates the shopkeeper picks; the rest are worked out from
/// today's business date, so "this month" on the 1st is the 1st alone.
enum DatePreset {
  today,
  yesterday,
  thisWeek,
  thisMonth,
  lastMonth,
  thisQuarter,

  /// 1 July to 30 June, the year the return is filed for.
  thisFiscalYear,
  lastFiscalYear,
  custom;

  /// The days this preset covers when the business date is [day]. Custom
  /// has none of its own: the screen holds the dates the shopkeeper picked.
  ReportPeriod? resolve(BusinessDate day) => switch (this) {
    DatePreset.today => ReportPeriod.day(day),
    DatePreset.yesterday => ReportPeriod.day(day.addDays(-1)),
    DatePreset.thisWeek => ReportPeriod.weekOf(day),
    DatePreset.thisMonth => ReportPeriod.monthOf(day),
    DatePreset.lastMonth => ReportPeriod.monthBefore(day),
    DatePreset.thisQuarter => ReportPeriod.quarterOf(day),
    DatePreset.thisFiscalYear => ReportPeriod.fiscalYearOf(day),
    DatePreset.lastFiscalYear => ReportPeriod.fiscalYearOf(
      ReportPeriod.fiscalYearOf(day).from.addDays(-1),
    ),
    DatePreset.custom => null,
  };
}
