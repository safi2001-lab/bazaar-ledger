/// Days that lock themselves (M68).
///
/// M42 gave the owner closed books: a date, set by hand, on or before which
/// nothing is written without their PIN and a reason. A date set by hand is
/// a date that is a fortnight stale the week the owner is busy. Marg calls
/// the answer auto-freeze, Tally "days allowed for back-dated vouchers": the
/// owner says once how far back the counter may reach, and the date moves
/// on by itself every day.
///
/// Two ways, the owner's choice:
///
///  * **Older than N days** -- every day more than N days old is closed.
///    With N = 2, on the 3rd the 30th and everything before it is closed;
///    on the 4th, the 1st joins it. N = 0 closes everything before today.
///  * **When the drawer is counted** -- the day the drawer was last counted
///    at day close (M9) is closed from the moment it is counted. A sale rung
///    after the count is a sale the count did not see, so it needs the
///    owner, exactly as a back-dated bill does.
///
/// Not a second lock. It moves M42's date and is kept by M42's write path:
/// the same refusal in words, the same owner's PIN and reason to let one
/// entry in, the same audit row. The write path works the date out for
/// itself on every write, so a phone left open past midnight is closed at
/// midnight; the date kept in settings is moved on as well, with a
/// `BOOKS_CLOSED` row saying it moved by itself, so the closing screen and
/// the list of entries that reached this phone from a counter afterwards
/// both read it.
library;

import 'dart:convert';

import '../time/clock.dart';

/// The settings key the rule is kept under, as JSON.
const autoLockSetting = 'books.auto_lock';

/// How days lock themselves.
enum AutoLockMode {
  /// They do not; the owner closes the books by hand (M42).
  off,

  /// Every day more than [AutoLock.days] old.
  olderThan,

  /// The day the drawer was last counted, from the moment it is counted.
  atDayClose,
}

/// The owner's rule for days that lock themselves.
final class AutoLock {
  const AutoLock({this.mode = AutoLockMode.off, this.days = 2});

  static const off = AutoLock();

  final AutoLockMode mode;

  /// For [AutoLockMode.olderThan]: how many days back stay open.
  final int days;

  bool get isOn => mode != AutoLockMode.off;

  /// The last day closed by this rule on [today], or null when it closes
  /// none. [lastDayClosed] is the day the drawer was last counted (M9).
  BusinessDate? closedThroughOn(
    BusinessDate today, {
    BusinessDate? lastDayClosed,
  }) => switch (mode) {
    AutoLockMode.off => null,
    AutoLockMode.olderThan => today.addDays(-(days < 0 ? 1 : days + 1)),
    AutoLockMode.atDayClose => lastDayClosed,
  };

  String toJson() => jsonEncode({'mode': mode.name, 'days': days});

  static AutoLock fromJson(String? text) {
    if (text == null || text.trim().isEmpty) return off;
    try {
      final map = jsonDecode(text);
      if (map is! Map<String, Object?>) return off;
      final mode = AutoLockMode.values
          .where((m) => m.name == map['mode'])
          .firstOrNull;
      final days = map['days'];
      return AutoLock(
        mode: mode ?? AutoLockMode.off,
        days: days is int && days >= 0 && days <= maxAutoLockDays ? days : 2,
      );
    } on FormatException {
      return off;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AutoLock && other.mode == mode && other.days == days;

  @override
  int get hashCode => Object.hash(mode, days);
}

/// The most days back the counter may be left open by the rule: a year.
const maxAutoLockDays = 366;

/// The later of two closing dates, either of which may be none.
BusinessDate? laterClosing(BusinessDate? a, BusinessDate? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.value.compareTo(b.value) >= 0 ? a : b;
}
