/// What a unit measures.
enum UnitKind { count, weight, volume, length }

/// One unit of measure, as shipped on first run.
final class UnitSpec {
  const UnitSpec({
    required this.code,
    required this.nameEn,
    required this.nameUr,
    required this.kind,
    required this.decimals,
    this.isBase = false,
  });

  final String code;
  final String nameEn;
  final String nameUr;
  final UnitKind kind;

  /// How many decimal places the counter offers. Pieces get none — a cashier
  /// must not be able to sell 2.5 shampoo bottles by mistyping.
  final int decimals;

  /// Stock is stored in the base unit of its kind. Everything else is a
  /// display alias with a conversion factor.
  final bool isBase;
}

/// A conversion between two units: 1 [fromCode] is [factorThousandths] / 1000
/// of [toCode].
final class UnitConversionSpec {
  const UnitConversionSpec({
    required this.fromCode,
    required this.toCode,
    required this.factorThousandths,
  });

  final String fromCode;
  final String toCode;
  final int factorThousandths;
}

/// The units a new firm starts with.
///
/// The base unit of each kind is the one a Pakistani shop quotes prices in:
/// per kilo, per litre, per piece. Quantities are integer thousandths of the
/// base, so a kilo base resolves to the gram — finer than any counter scale in
/// the market reads, and it means 50 g of cardamom is the exact integer 50.
///
/// Length is the exception: its base is the centimetre, not the metre, because
/// a gaz is 36 inches — 91.44 cm — and thousandths of a metre could not hold
/// that as an integer.
const List<UnitSpec> defaultUnits = [
  UnitSpec(
    code: 'pcs',
    nameEn: 'Piece',
    nameUr: 'Adad',
    kind: UnitKind.count,
    decimals: 0,
    isBase: true,
  ),
  UnitSpec(
    code: 'dozen',
    nameEn: 'Dozen',
    nameUr: 'Darzan',
    kind: UnitKind.count,
    decimals: 2,
  ),
  UnitSpec(
    code: 'kg',
    nameEn: 'Kilogram',
    nameUr: 'Kilo',
    kind: UnitKind.weight,
    decimals: 3,
    isBase: true,
  ),
  UnitSpec(
    code: 'g',
    nameEn: 'Gram',
    nameUr: 'Gram',
    kind: UnitKind.weight,
    decimals: 3,
  ),
  // A Pakistani maund is 40 kg. The historic British-Indian maund of 37.324 kg
  // is not what anyone means: the wheat support price is announced per 40 kg.
  UnitSpec(
    code: 'maund',
    nameEn: 'Maund (40 kg)',
    nameUr: 'Mann',
    kind: UnitKind.weight,
    decimals: 3,
  ),
  UnitSpec(
    code: 'l',
    nameEn: 'Litre',
    nameUr: 'Litre',
    kind: UnitKind.volume,
    decimals: 3,
    isBase: true,
  ),
  UnitSpec(
    code: 'ml',
    nameEn: 'Millilitre',
    nameUr: 'Millilitre',
    kind: UnitKind.volume,
    decimals: 3,
  ),
  UnitSpec(
    code: 'cm',
    nameEn: 'Centimetre',
    nameUr: 'Centimetre',
    kind: UnitKind.length,
    decimals: 1,
    isBase: true,
  ),
  UnitSpec(
    code: 'm',
    nameEn: 'Metre',
    nameUr: 'Meter',
    kind: UnitKind.length,
    decimals: 2,
  ),
  // The cloth trade's gaz is 36 inches.
  UnitSpec(
    code: 'gaz',
    nameEn: 'Gaz (36 in)',
    nameUr: 'Gaz',
    kind: UnitKind.length,
    decimals: 2,
  ),
];

/// The conversions that come with [defaultUnits].
///
/// A bori is deliberately absent. Flour ships in 10, 40, 50 and 80 kg sacks
/// and the shop decides which one it means, so a bori is created per firm — or
/// per item — rather than shipped with a number baked into it.
const List<UnitConversionSpec> defaultUnitConversions = [
  UnitConversionSpec(fromCode: 'dozen', toCode: 'pcs', factorThousandths: 12000),
  // 1 g is a thousandth of a kilo, which is exactly one unit of storage.
  UnitConversionSpec(fromCode: 'g', toCode: 'kg', factorThousandths: 1),
  // A Pakistani maund is 40 kg.
  UnitConversionSpec(
    fromCode: 'maund',
    toCode: 'kg',
    factorThousandths: 40000,
  ),
  UnitConversionSpec(fromCode: 'ml', toCode: 'l', factorThousandths: 1),
  UnitConversionSpec(fromCode: 'm', toCode: 'cm', factorThousandths: 100000),
  UnitConversionSpec(fromCode: 'gaz', toCode: 'cm', factorThousandths: 91440),
];
