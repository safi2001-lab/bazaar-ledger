/// How a division that does not land on a whole minor unit is resolved.
///
/// Pakistani retail convention is half-up on the absolute value, so
/// `Rs 0.005` becomes `Rs 0.01` and `-Rs 0.005` becomes `-Rs 0.01`.
/// That is [RoundingMode.halfUp] and it is the default everywhere.
///
/// The mode a document was posted with is stored **on the document**, so a
/// reprint of a two-year-old invoice reproduces the same paisa it printed the
/// first time even if the app default changes later.
enum RoundingMode {
  /// Ties move away from zero. `0.5 -> 1`, `-0.5 -> -1`. The default.
  halfUp,

  /// Ties move to the nearest even value. `0.5 -> 0`, `1.5 -> 2`.
  /// Statistically unbiased over many roundings; used for tax subtotals where
  /// a rule requires it.
  halfEven,

  /// Always toward zero. `0.9 -> 0`, `-0.9 -> 0`.
  truncate,

  /// Always away from zero. `0.1 -> 1`, `-0.1 -> -1`.
  ceilAbs,
}

/// Divides [numerator] by [denominator] and resolves the remainder per [mode].
///
/// Both arguments are exact integers, so the result is exact — there is no
/// intermediate `double` anywhere in this file and there must never be one.
/// [denominator] must be positive.
int divideRounded(int numerator, int denominator, RoundingMode mode) {
  if (denominator <= 0) {
    throw ArgumentError.value(denominator, 'denominator', 'must be > 0');
  }

  final negative = numerator < 0;
  // Work on the magnitude so every mode behaves symmetrically about zero.
  final magnitude = negative ? -numerator : numerator;
  final quotient = magnitude ~/ denominator;
  final remainder = magnitude % denominator;

  if (remainder == 0) return negative ? -quotient : quotient;

  final int result;
  switch (mode) {
    case RoundingMode.truncate:
      result = quotient;
    case RoundingMode.ceilAbs:
      result = quotient + 1;
    case RoundingMode.halfUp:
      // remainder * 2 >= denominator  <=>  remainder >= denominator / 2,
      // expressed without division so it stays exact for odd denominators.
      result = (remainder * 2 >= denominator) ? quotient + 1 : quotient;
    case RoundingMode.halfEven:
      final twice = remainder * 2;
      if (twice > denominator) {
        result = quotient + 1;
      } else if (twice < denominator) {
        result = quotient;
      } else {
        result = quotient.isEven ? quotient : quotient + 1;
      }
  }

  return negative ? -result : result;
}

/// Refuses a value that would wrap a 64-bit integer.
///
/// A pasted figure that overflows does not throw in Dart; it wraps, and the
/// sign flips. `Money.parse('92233720368547758.07')` used to return a
/// NEGATIVE amount, silently, on a screen where the shopkeeper had just typed
/// a number. Every scaling multiplication in this package goes through here.
int scaleOrThrow(int value, int factor, String what) {
  const maxSafe = 9223372036854775807;
  if (value != 0 && value.abs() > maxSafe ~/ factor) {
    throw FormatException(
      '$what is too large to represent exactly: $value x $factor overflows',
    );
  }
  return value * factor;
}

/// Groups a run of digits the way this market reads them.
///
/// CLDR gives `en-PK` and `ur-PK` the pattern `#,##,##0.###`: the last three
/// digits, then twos. A shopkeeper reads `12,34,567` — twelve lakh — and has
/// to stop and count `1,234,567`. Western grouping here would be the one
/// localisation decision in this package made by default rather than on
/// purpose, in a file that goes out of its way to get Latin digits right.
///
/// Crore and above keep grouping in twos: `1,00,00,000`.
String groupSouthAsian(String digits) {
  if (digits.length <= 3) return digits;
  final head = digits.substring(0, digits.length - 3);
  final tail = digits.substring(digits.length - 3);

  final buffer = StringBuffer();
  for (var i = 0; i < head.length; i++) {
    if (i > 0 && (head.length - i) % 2 == 0) buffer.write(',');
    buffer.write(head[i]);
  }
  return '$buffer,$tail';
}
