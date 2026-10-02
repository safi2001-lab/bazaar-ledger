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
  // A tola is 11.664 g, and it converts to grams rather than to kilos on
  // purpose. Thousandths of a kilo are whole grams, and 11.664 g is not a
  // whole number of them — so a jeweller stocks in grams, where a tola is
  // exactly 11664 thousandths, and an item stocked in kilos is refused the
  // conversion rather than quietly rounded. The traditional fractions of a
  // tola are halves, quarters and eighths, and every one of those is exact.
  UnitSpec(
    code: 'tola',
    nameEn: 'Tola (11.664 g)',
    nameUr: 'Tola',
    kind: UnitKind.weight,
    decimals: 3,
  ),
  // Pakistan's seer is metric: a maund is 40 kg and forty seer, so a seer is
  // a kilo exactly. It is kept as its own unit because the older trades still
  // price and order in seer, and printing "1 seer" on a bill a shopkeeper
  // asked for in seer matters more than the arithmetic, which is a no-op.
  //
  // Checked again in M56, because the reference books give another figure.
  // The seer of the tables is 80 tola: 933.10 g (933.104 g, by the 11.6638 g
  // tola), the "UN definition" Pakistan's agricultural conversion factors
  // carry. That seer belongs to the 37.324 kg maund of forty seer, which is
  // the maund this file already refuses. Pakistan went metric in October
  // 1967, its bazaar mann is 40 kg, and forty seer to a 40 kg mann is a kilo
  // a seer; the pao the retail trade weighs out today is a quarter of THAT
  // seer (250 g, or 200 g in some places), not a quarter of 933 g. So the
  // seer stays the kilo the mann is made of. The 933.10 g seer could not be
  // held exactly in any case: stock kept in kilos is whole grams, and
  // 933.104 g is not a whole number of them. It would be rounded to 933 g,
  // a tenth of a gram given away on every seer sold.
  UnitSpec(
    code: 'seer',
    nameEn: 'Seer (1 kg)',
    nameUr: 'Seer',
    kind: UnitKind.weight,
    decimals: 3,
  ),
  // No pao. Retail sells a 250 g pao in most of the country and a 200 g one
  // in parts of it, and the books' pao is a quarter of 933 g. A unit that
  // means three weights charges somebody wrongly; the counter takes 0.25 kg
  // and shows it as "250 g".

  // The packs a shop counts in (M56): an item kept and sold by the carton,
  // the dabba or the packet, and a pharmacy's strips and tablets. They are
  // counts in their own right and ship with no conversion: how many pieces
  // a carton holds is a fact about one item, not about cartons, so it
  // belongs to that item (M45's two-unit quantities), never to the shop.
  UnitSpec(
    code: 'carton',
    nameEn: 'Carton',
    nameUr: 'Carton',
    kind: UnitKind.count,
    decimals: 0,
  ),
  UnitSpec(
    code: 'dabba',
    nameEn: 'Box (dabba)',
    nameUr: 'Dabba',
    kind: UnitKind.count,
    decimals: 0,
  ),
  UnitSpec(
    code: 'packet',
    nameEn: 'Packet',
    nameUr: 'Packet',
    kind: UnitKind.count,
    decimals: 0,
  ),
  UnitSpec(
    code: 'strip',
    nameEn: 'Strip',
    nameUr: 'Patta',
    kind: UnitKind.count,
    decimals: 0,
  ),
  UnitSpec(
    code: 'tablet',
    nameEn: 'Tablet',
    nameUr: 'Goli',
    kind: UnitKind.count,
    decimals: 0,
  ),
];

/// The conversions that come with [defaultUnits].
///
/// A bori is deliberately absent. Flour ships in 10, 40, 50 and 80 kg sacks
/// and the shop decides which one it means, so a bori is created per firm — or
/// per item — rather than shipped with a number baked into it.
const List<UnitConversionSpec> defaultUnitConversions = [
  UnitConversionSpec(
    fromCode: 'dozen',
    toCode: 'pcs',
    factorThousandths: 12000,
  ),
  // 1 g is a thousandth of a kilo, which is exactly one unit of storage.
  UnitConversionSpec(fromCode: 'g', toCode: 'kg', factorThousandths: 1),
  // A Pakistani maund is 40 kg.
  UnitConversionSpec(fromCode: 'maund', toCode: 'kg', factorThousandths: 40000),
  UnitConversionSpec(fromCode: 'ml', toCode: 'l', factorThousandths: 1),
  UnitConversionSpec(fromCode: 'm', toCode: 'cm', factorThousandths: 100000),
  UnitConversionSpec(fromCode: 'gaz', toCode: 'cm', factorThousandths: 91440),
  // 1 tola = 11.664 g. To grams, never to kilos: see the unit above.
  UnitConversionSpec(fromCode: 'tola', toCode: 'g', factorThousandths: 11664),
  UnitConversionSpec(fromCode: 'seer', toCode: 'kg', factorThousandths: 1000),
];
