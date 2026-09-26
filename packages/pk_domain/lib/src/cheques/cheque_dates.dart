/// When a cheque can be banked.
///
/// A post-dated cheque is the ordinary instrument of wholesale credit in this
/// market: goods go out on the 1st against a cheque dated the 30th. Its date
/// is a calendar day in Pakistan, not an instant, and it is stored as the
/// first instant of that day in PKT so that "due today" means what the
/// shopkeeper means by it whatever the phone's timezone says.
library;

import '../time/clock.dart';

/// The instant [due] is stored as: 00:00 on that day, Pakistan time.
int chequeDueUtcMillis(BusinessDate due) => DateTime.utc(
  due.year,
  due.month,
  due.day,
).subtract(pakistanStandardTime).millisecondsSinceEpoch;

/// The day a stored cheque date falls on, in Pakistan.
BusinessDate chequeDueDate(int utcMillis) => BusinessDate.fromUtc(
  DateTime.fromMillisecondsSinceEpoch(utcMillis, isUtc: true),
);

/// Whole days from [today] to [due]: negative once it has passed.
int daysUntil(BusinessDate today, BusinessDate due) => DateTime.utc(
  due.year,
  due.month,
  due.day,
).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
