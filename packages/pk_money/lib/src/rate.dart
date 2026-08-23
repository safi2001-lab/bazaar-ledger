import 'money.dart';
import 'qty.dart';
import 'rounding.dart';

/// A unit price, stored as a whole number of **milli-paisa per base unit** —
/// three digits finer than a paisa.
///
/// A rate needs more precision than an amount does. Loose atta from a Rs 132
/// ten-kilo bag, sold by the gram, is 1.32 paisa per gram — a rate a
/// paisa-precision column could only store as 1 or 2, which is a 25% pricing
/// error on every scoop. The *amount* still lands on a whole paisa; only the
/// rate carries the extra digits.
///
/// 1 rupee = 100 paisa = 100,000 milli-paisa.
final class Rate implements Comparable<Rate> {
  /// The rate in milli-paisa per base unit — what the database stores.
  final int inMilliPaisa;

  const Rate._(this.inMilliPaisa);

  /// Wraps a raw milli-paisa rate, exactly as stored in the database.
  const Rate.raw(int milliPaisa) : inMilliPaisa = milliPaisa;

  static const Rate zero = Rate._(0);

  static const int _milliPaisaPerRupee = 100000;

  /// A rate expressed in whole rupees per base unit.
  const Rate.rupees(int rupees) : this._(rupees * _milliPaisaPerRupee);

  /// A rate equal to a [Money] amount per one base unit.
  ///
  /// `Rate.perUnit(Money.rupees(150))` is Rs 150.00 per kilo when the base
  /// unit is a kilo, or per piece when it is a piece.
  Rate.perUnit(Money price) : this._(price.inPaisa * 1000);

  /// Derives a per-base-unit rate from a pack price.
  ///
  /// A 5 kg bag of basmati at Rs 1,650 with a gram base unit is
  /// `Rate.fromPack(Money.rupees(1650), Qty.units(5000))`. This is also how a
  /// pharmacy's pro-rata loose-sale price is computed: the pack MRP divided
  /// by the pack size, which the Drug Pricing Policy requires a strip-cut
  /// sale not to exceed.
  ///
  /// Rounds **down** by default, and that default is a legal requirement
  /// rather than a preference. Half-up here can price the whole pack above
  /// the pack: a 3-paisa pack of two units rounds 1.5 up to 2 milli-paisa
  /// each, and two of them come to 4 paisa. The Drug Pricing Policy says the
  /// MRP on a loose sale "shall not exceed the pro-rata MRP printed on the
  /// pack", so the fraction of a paisa the shop cannot charge is the shop's
  /// to lose.
  factory Rate.fromPack(Money packPrice, Qty packSize,
      {RoundingMode mode = RoundingMode.truncate}) {
    if (packSize.inThousandths <= 0) {
      throw ArgumentError.value(packSize, 'packSize', 'must be > 0');
    }
    // paisa * 1000 (to milli) * 1000 (qty is thousandths) = paisa * 1e6
    return Rate._(divideRounded(
        packPrice.inPaisa * 1000000, packSize.inThousandths, mode));
  }

  /// Parses a typed rate: `"150"`, `"150.50"`, `"1,850.255"`.
  ///
  /// Accepts up to five decimal places — two for paisa plus three for the
  /// sub-paisa precision — and rejects anything finer rather than truncating.
  factory Rate.parse(String input) {
    final parsed = tryParse(input);
    if (parsed == null) {
      throw FormatException('Not a valid rate', input);
    }
    return parsed;
  }

  /// Like [Rate.parse] but returns `null` instead of throwing.
  static Rate? tryParse(String input) {
    var s = input.trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(RegExp(r'^(rs\.?|pkr)\s*', caseSensitive: false), '');
    s = s.replaceAll(',', '').trim();
    if (s.isEmpty) return null;

    var negative = false;
    if (s.startsWith('-')) {
      negative = true;
      s = s.substring(1).trim();
    }

    // A bare sign, or nothing left after stripping one, is not an amount.
    if (s.isEmpty) return null;
    if (!RegExp(r'^\d*\.?\d*$').hasMatch(s) || s == '.') return null;

    final dot = s.indexOf('.');
    final whole = dot < 0 ? s : s.substring(0, dot);
    final frac = dot < 0 ? '' : s.substring(dot + 1);
    if (frac.length > 5) return null;

    final rupees = whole.isEmpty ? 0 : int.tryParse(whole);
    if (rupees == null) return null;
    final sub = frac.isEmpty ? 0 : int.parse(frac.padRight(5, '0'));

    final total = scaleOrThrow(rupees, _milliPaisaPerRupee, 'rate') + sub;
    return Rate._(negative ? -total : total);
  }

  bool get isZero => inMilliPaisa == 0;

  Rate operator +(Rate other) => Rate._(inMilliPaisa + other.inMilliPaisa);
  Rate operator -(Rate other) => Rate._(inMilliPaisa - other.inMilliPaisa);
  Rate operator -() => Rate._(-inMilliPaisa);

  bool operator <(Rate other) => inMilliPaisa < other.inMilliPaisa;
  bool operator <=(Rate other) => inMilliPaisa <= other.inMilliPaisa;
  bool operator >(Rate other) => inMilliPaisa > other.inMilliPaisa;
  bool operator >=(Rate other) => inMilliPaisa >= other.inMilliPaisa;

  /// The *portion* of this rate a percentage in basis points comes to.
  ///
  /// Not an adjusted rate: `Rate.rupees(1000).percentBp(-1500)` is minus
  /// Rs 150, not Rs 850. The statutory 15% pharmacy retailer discount is
  /// therefore `rate + rate.percentBp(-1500)`, or `rate.percentBp(8500)`.
  Rate percentBp(int basisPoints, {RoundingMode mode = RoundingMode.halfUp}) =>
      Rate._(divideRounded(inMilliPaisa * basisPoints, 10000, mode));

  /// Multiplies this rate by [quantity] to give an exact line amount in whole
  /// paisa.
  ///
  /// This is the single multiplication in the whole application where money
  /// meets quantity, which is why it lives here and is tested to death:
  ///
  ///     amountPaisa = rate.milliPaisa * qty.thousandths / 1_000_000
  ///
  /// Throws [StateError] rather than silently wrapping if the intermediate
  /// product would exceed the 64-bit range.
  Money amountFor(Qty quantity, {RoundingMode mode = RoundingMode.halfUp}) {
    final r = inMilliPaisa;
    final q = quantity.inThousandths;
    if (r == 0 || q == 0) return Money.zero;

    // Guard the intermediate product before it can wrap.
    const maxSafe = 9223372036854775807; // 2^63 - 1
    final absR = r < 0 ? -r : r;
    final absQ = q < 0 ? -q : q;
    if (absR > maxSafe ~/ absQ) {
      throw StateError(
          'Line amount overflows: rate $inMilliPaisa mp x qty $q. '
          'Split the line or check the entered price.');
    }

    return Money.paisa(divideRounded(r * q, 1000000, mode));
  }

  /// `"150.00"`, `"1,850.255"` — grouped, at least two decimals, trailing
  /// sub-paisa zeros trimmed, always Latin digits.
  String get amountOnly {
    final negative = inMilliPaisa < 0;
    final magnitude = negative ? -inMilliPaisa : inMilliPaisa;
    final rupees = magnitude ~/ _milliPaisaPerRupee;
    final sub = magnitude % _milliPaisaPerRupee;

    final grouped = groupSouthAsian(rupees.toString());

    var tail = sub.toString().padLeft(5, '0');
    while (tail.length > 2 && tail.endsWith('0')) {
      tail = tail.substring(0, tail.length - 1);
    }

    final sign = negative ? '-' : '';
    return '$sign$grouped.$tail';
  }

  @override
  bool operator ==(Object other) =>
      other is Rate && other.inMilliPaisa == inMilliPaisa;

  @override
  int get hashCode => inMilliPaisa.hashCode;

  @override
  int compareTo(Rate other) => inMilliPaisa.compareTo(other.inMilliPaisa);

  @override
  String toString() => 'Rs $amountOnly';
}
