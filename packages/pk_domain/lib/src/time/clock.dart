/// The application's only source of "now".
///
/// Nothing below the UI calls `DateTime.now()` directly. Every posting rule,
/// every numbering decision and every report boundary takes its instant from
/// here, which is what makes them testable at a fixed moment instead of
/// "whenever the suite happened to run".
abstract interface class Clock {
  DateTime nowUtc();
}

/// The real clock.
final class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// A clock that stands still, and moves only when a test tells it to.
final class FixedClock implements Clock {
  FixedClock(this._now);

  DateTime _now;

  @override
  DateTime nowUtc() => _now.toUtc();

  void set(DateTime instant) => _now = instant.toUtc();

  void advance(Duration by) => _now = _now.add(by);
}

/// Pakistan Standard Time is UTC+05:00 and observes no daylight saving.
///
/// The 2002 experiment was abandoned and the 2008-09 one was scrapped after
/// two months; there has been no DST since. A fixed offset is therefore
/// correct here in a way it would not be in most countries, and it is far
/// safer than trusting a handset whose timezone a shopkeeper may have set
/// wrong — a phone reading UTC would silently file the last five hours of
/// every business day into tomorrow's Day Book.
const Duration pakistanStandardTime = Duration(hours: 5);

/// A calendar date in the shopkeeper's own day, as `YYYY-MM-DD`.
///
/// Reports group on this string, never on an epoch converted at query time.
/// The shop's day ends when the shutter comes down at 11pm PKT, not at 5am the
/// next morning, and "today's sales" must mean what the person at the counter
/// means by it.
extension type const BusinessDate(String value) implements Object {
  /// The business date containing [instant].
  factory BusinessDate.fromUtc(
    DateTime instant, [
    Duration offset = pakistanStandardTime,
  ]) {
    final local = instant.toUtc().add(offset);
    return BusinessDate(_format(local));
  }

  /// The business date now, per [clock].
  factory BusinessDate.now(
    Clock clock, [
    Duration offset = pakistanStandardTime,
  ]) => BusinessDate.fromUtc(clock.nowUtc(), offset);

  /// Parses `YYYY-MM-DD`, rejecting anything else rather than guessing.
  static BusinessDate? tryParse(String input) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input)) return null;
    final year = int.parse(input.substring(0, 4));
    final month = int.parse(input.substring(5, 7));
    final day = int.parse(input.substring(8, 10));
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    // Reject 31 February and friends by round-tripping through DateTime.
    final probe = DateTime.utc(year, month, day);
    if (probe.month != month || probe.day != day) return null;
    return BusinessDate(input);
  }

  int get year => int.parse(value.substring(0, 4));
  int get month => int.parse(value.substring(5, 7));
  int get day => int.parse(value.substring(8, 10));

  /// The Pakistani fiscal year this date falls in, as `2627` for 2026-27.
  ///
  /// The financial year runs 1 July to 30 June, which is also how invoice
  /// series are numbered: `INV-2627-0001`.
  int get fiscalYear {
    final startYear = month >= 7 ? year : year - 1;
    return (startYear % 100) * 100 + ((startYear + 1) % 100);
  }

  BusinessDate addDays(int days) {
    final d = DateTime.utc(year, month, day).add(Duration(days: days));
    return BusinessDate(_format(d));
  }

  static String _format(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
