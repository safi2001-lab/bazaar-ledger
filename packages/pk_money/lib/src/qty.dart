import 'rounding.dart';

/// An exact quantity, stored as a whole number of **thousandths of a base
/// unit** — three decimal places, no `double`.
///
/// The base unit is whatever the item declares: grams for loose goods sold by
/// weight, millilitres for liquids, or "one piece" for countable goods. A
/// 3.5 kg weighing gets stored as `3500` grams, not as `3.5`, so a kiryana
/// shop weighing out spices all day never accumulates binary drift.
///
/// Display units (maund, bori, darzan, thaan, gaz) are aliases layered over
/// this base by a per-item conversion factor. A Pakistani maund is **40 kg**,
/// not the historic British-Indian 37.324 kg — the wheat support price is set
/// per 40 kg.
final class Qty implements Comparable<Qty> {
  /// The quantity in thousandths of a base unit — what the database stores.
  final int inThousandths;

  const Qty._(this.inThousandths);

  /// Wraps a raw thousandths count, exactly as stored in the database.
  const Qty.raw(int thousandths) : inThousandths = thousandths;

  static const Qty zero = Qty._(0);
  static const Qty one = Qty._(1000);

  /// A whole number of base units. `Qty.units(2)` is two pieces.
  const Qty.units(int units) : this._(units * 1000);

  /// Whole units plus thousandths. `Qty.parts(3, 500)` is 3.5.
  const Qty.parts(int units, int thousandths)
      : this._(units * 1000 + thousandths);

  /// Parses a typed quantity: `"2"`, `"3.5"`, `"0.750"`, `"1,250"`.
  ///
  /// Rejects more than three decimals rather than truncating, so a scale
  /// reading of `0.7505` is a visible error and not a silent under-charge.
  factory Qty.parse(String input) {
    final parsed = tryParse(input);
    if (parsed == null) {
      throw FormatException('Not a valid quantity', input);
    }
    return parsed;
  }

  /// Like [Qty.parse] but returns `null` instead of throwing.
  static Qty? tryParse(String input) {
    var s = input.trim().replaceAll(',', '');
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
    final whole = dot < 0 ? s : s.substring(0, dot);
    final frac = dot < 0 ? '' : s.substring(dot + 1);
    if (frac.length > 3) return null;

    final units = whole.isEmpty ? 0 : int.tryParse(whole);
    if (units == null) return null;
    final thousandths = frac.isEmpty ? 0 : int.parse(frac.padRight(3, '0'));

    final total = units * 1000 + thousandths;
    return Qty._(negative ? -total : total);
  }

  bool get isZero => inThousandths == 0;
  bool get isNegative => inThousandths < 0;
  bool get isPositive => inThousandths > 0;

  /// True when this quantity is a whole number of base units, so the UI can
  /// render `2` rather than `2.000` for countable goods.
  bool get isWhole => inThousandths % 1000 == 0;

  Qty operator +(Qty other) => Qty._(inThousandths + other.inThousandths);
  Qty operator -(Qty other) => Qty._(inThousandths - other.inThousandths);
  Qty operator -() => Qty._(-inThousandths);
  Qty operator *(int factor) => Qty._(inThousandths * factor);

  bool operator <(Qty other) => inThousandths < other.inThousandths;
  bool operator <=(Qty other) => inThousandths <= other.inThousandths;
  bool operator >(Qty other) => inThousandths > other.inThousandths;
  bool operator >=(Qty other) => inThousandths >= other.inThousandths;

  Qty get abs => inThousandths < 0 ? Qty._(-inThousandths) : this;

  /// Converts to a display unit whose size is [factorThousandths] base units.
  ///
  /// A maund is 40 kg, so from a gram base that factor is `40000 * 1000`.
  /// Rounds per [mode] because a display unit is a rendering, not a fact —
  /// the stored base-unit count remains authoritative.
  Qty toDisplayUnits(int factorThousandths,
      {RoundingMode mode = RoundingMode.halfUp}) {
    if (factorThousandths <= 0) {
      throw ArgumentError.value(
          factorThousandths, 'factorThousandths', 'must be > 0');
    }
    return Qty._(
        divideRounded(inThousandths * 1000, factorThousandths, mode));
  }

  /// `"3.5"`, `"2"`, `"0.750"` — trailing zeros trimmed, but never past the
  /// decimal point, and never rendering a fractional amount as a whole one.
  ///
  /// The previous build printed `quantity.toInt()`, so 0.750 kg of mutton
  /// displayed in the cart as `0`. That is the bug this getter exists to make
  /// impossible.
  String get display {
    final negative = inThousandths < 0;
    final magnitude = negative ? -inThousandths : inThousandths;
    final units = magnitude ~/ 1000;
    final frac = magnitude % 1000;
    final sign = negative ? '-' : '';

    if (frac == 0) return '$sign$units';

    var tail = frac.toString().padLeft(3, '0');
    while (tail.endsWith('0')) {
      tail = tail.substring(0, tail.length - 1);
    }
    return '$sign$units.$tail';
  }

  @override
  bool operator ==(Object other) =>
      other is Qty && other.inThousandths == inThousandths;

  @override
  int get hashCode => inThousandths.hashCode;

  @override
  int compareTo(Qty other) => inThousandths.compareTo(other.inThousandths);

  @override
  String toString() => display;

  static Qty sum(Iterable<Qty> quantities) {
    var total = 0;
    for (final q in quantities) {
      total += q.inThousandths;
    }
    return Qty._(total);
  }
}
