import 'rounding.dart';

/// An exact amount of Pakistani rupees, stored as a whole number of **paisa**.
///
/// There is no `double` in this type and none may be introduced. The entire
/// reason this package exists is that the previous build stored money in
/// `REAL` columns and then hid the drift behind a `> 0.01` tolerance in its
/// ledger balance check. A ledger that only balances to within a paisa is not
/// a ledger.
///
/// Construct from rupees with [Money.rupees] or [Money.parse]; construct from
/// storage with [Money.paisa]. Formatting always emits Latin digits — Unicode
/// CLDR defaults `ur-PK` to `latn`, and a billing app is the last place to
/// surprise someone with `۱۲۳۴`.
final class Money implements Comparable<Money> {
  /// The amount as a whole number of paisa — exactly what the database stores.
  final int inPaisa;

  const Money._(this.inPaisa);

  /// Wraps a raw paisa count, exactly as stored in the database.
  const Money.paisa(int paisa) : inPaisa = paisa;

  /// Zero rupees.
  static const Money zero = Money._(0);

  /// Builds from whole [rupees] plus optional [paisa].
  ///
  /// `Money.rupees(55, 25)` is `Rs 55.25`. [paisa] may exceed 99 and may be
  /// negative; it is simply added.
  const Money.rupees(int rupees, [int paisa = 0])
      : this._(rupees * 100 + paisa);

  /// Parses a human-entered amount: `"5525"`, `"5525.5"`, `"5,525.25"`,
  /// `"Rs 5525.25"`, `"-12.50"`.
  ///
  /// Accepts at most two decimal places and throws [FormatException]
  /// otherwise, so a mistyped third digit is never silently truncated into a
  /// wrong price. Returns null-free results only; callers wanting leniency
  /// should use [tryParse].
  factory Money.parse(String input) {
    final parsed = tryParse(input);
    if (parsed == null) {
      throw FormatException('Not a valid rupee amount', input);
    }
    return parsed;
  }

  /// Like [Money.parse] but returns `null` instead of throwing.
  static Money? tryParse(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;

    // Drop a leading currency marker and any grouping separators.
    s = s.replaceAll(RegExp(r'^(rs\.?|pkr)\s*', caseSensitive: false), '');
    s = s.replaceAll(',', '').replaceAll('٬', '').trim();
    if (s.isEmpty) return null;

    var negative = false;
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1).trim();
    } else if (s.startsWith('+')) {
      s = s.substring(1).trim();
    }

    // A bare sign, or nothing left after stripping one, is not an amount.
    if (s.isEmpty) return null;
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(s) || s == '.') return null;

    final dot = s.indexOf('.');
    final String whole;
    final String frac;
    if (dot < 0) {
      whole = s;
      frac = '';
    } else {
      whole = s.substring(0, dot);
      frac = s.substring(dot + 1);
    }
    if (frac.length > 2) return null;

    final rupees = whole.isEmpty ? 0 : int.tryParse(whole);
    if (rupees == null) return null;
    final paisa = frac.isEmpty ? 0 : int.parse(frac.padRight(2, '0'));

    final total = scaleOrThrow(rupees, 100, 'amount') + paisa;
    return Money._(negative ? -total : total);
  }

  /// The whole-rupee part, truncated toward zero. `Rs -5.25` gives `-5`.
  int get wholeRupees => inPaisa ~/ 100;

  /// The paisa remainder, carrying the sign of the amount.
  int get paisaPart => inPaisa.remainder(100);

  bool get isZero => inPaisa == 0;
  bool get isNegative => inPaisa < 0;
  bool get isPositive => inPaisa > 0;

  Money operator +(Money other) => Money._(inPaisa + other.inPaisa);
  Money operator -(Money other) => Money._(inPaisa - other.inPaisa);
  Money operator -() => Money._(-inPaisa);

  /// Scales by a whole factor. Exact — no rounding is possible.
  Money operator *(int factor) => Money._(inPaisa * factor);

  bool operator <(Money other) => inPaisa < other.inPaisa;
  bool operator <=(Money other) => inPaisa <= other.inPaisa;
  bool operator >(Money other) => inPaisa > other.inPaisa;
  bool operator >=(Money other) => inPaisa >= other.inPaisa;

  Money get abs => inPaisa < 0 ? Money._(-inPaisa) : this;

  /// Applies a percentage given in **basis points** (1 bp = 0.01%).
  ///
  /// 18% GST is `1800`, the 4% further tax under s.3(1A) is `400`, and the
  /// Fixed Tax Asaan Scheme's 1% is `100`. Basis points keep every statutory
  /// rate — including 8.5% and 12.75% — expressible as an exact integer.
  Money percentBp(int basisPoints,
          {RoundingMode mode = RoundingMode.halfUp}) =>
      Money._(divideRounded(inPaisa * basisPoints, 10000, mode));

  /// Rounds to the nearest whole rupee. Used for invoice-level round-off.
  Money roundToRupee({RoundingMode mode = RoundingMode.halfUp}) =>
      Money._(divideRounded(inPaisa, 100, mode) * 100);

  /// The adjustment [roundToRupee] would apply, as its own amount, so it can
  /// be posted to a dedicated round-off account instead of vanishing.
  Money roundingDelta({RoundingMode mode = RoundingMode.halfUp}) =>
      roundToRupee(mode: mode) - this;

  /// Splits this amount across [parts] shares that sum back to exactly this
  /// amount — no paisa created, none destroyed.
  ///
  /// Remainder paisa go to the earliest shares (largest-remainder), which is
  /// the convention a shopkeeper expects when splitting a bill three ways.
  List<Money> split(int parts) {
    if (parts <= 0) {
      throw ArgumentError.value(parts, 'parts', 'must be > 0');
    }
    return allocate(List<int>.filled(parts, 1));
  }

  /// Distributes this amount in proportion to [ratios], losing nothing.
  ///
  /// Used for apportioning a bill-level discount or a freight charge back
  /// across lines. Every ratio must be >= 0 and at least one must be > 0.
  List<Money> allocate(List<int> ratios) {
    if (ratios.isEmpty) {
      throw ArgumentError.value(ratios, 'ratios', 'must not be empty');
    }
    var total = 0;
    for (final r in ratios) {
      if (r < 0) {
        throw ArgumentError.value(ratios, 'ratios', 'must all be >= 0');
      }
      total += r;
    }
    if (total == 0) {
      throw ArgumentError.value(ratios, 'ratios', 'must not all be zero');
    }

    // Floor each share toward zero, then hand the remainder out one paisa at
    // a time so the parts always re-sum to the original.
    final shares = <int>[];
    var distributed = 0;
    for (final r in ratios) {
      final share = (inPaisa * r) ~/ total;
      shares.add(share);
      distributed += share;
    }

    var remainder = inPaisa - distributed;
    final step = remainder < 0 ? -1 : 1;
    for (var i = 0; remainder != 0; i = (i + 1) % shares.length) {
      if (ratios[i] == 0) continue;
      shares[i] += step;
      remainder -= step;
    }

    return [for (final s in shares) Money._(s)];
  }

  /// `"5,525.00"` — grouped, always two decimals, always Latin digits.
  String get amountOnly {
    final negative = inPaisa < 0;
    final magnitude = negative ? -inPaisa : inPaisa;
    final rupees = magnitude ~/ 100;
    final paisa = magnitude % 100;

    final grouped = groupSouthAsian(rupees.toString());
    final sign = negative ? '-' : '';
    return '$sign$grouped.${paisa.toString().padLeft(2, '0')}';
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.inPaisa == inPaisa;

  @override
  int get hashCode => inPaisa.hashCode;

  @override
  int compareTo(Money other) => inPaisa.compareTo(other.inPaisa);

  /// `"Rs 5,525.00"` — the app-wide default rendering.
  @override
  String toString() => 'Rs $amountOnly';

  /// `"− Rs 1,200.00"` / `"+ Rs 5,525.00"` — the ledger rendering, where the
  /// sign is spelled out so colour is never the only signal of direction.
  String get signed {
    if (inPaisa == 0) return 'Rs ${abs.amountOnly}';
    final glyph = inPaisa < 0 ? '−' : '+';
    return '$glyph Rs ${abs.amountOnly}';
  }

  /// Sums a collection without an intermediate `double`.
  static Money sum(Iterable<Money> amounts) {
    var total = 0;
    for (final a in amounts) {
      total += a.inPaisa;
    }
    return Money._(total);
  }
}
