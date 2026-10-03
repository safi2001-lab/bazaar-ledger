import 'package:pk_money/pk_money.dart';

import 'packs.dart';
import 'unit_converter.dart';

/// A quantity as the shop says it out loud (M56, M45).
///
/// "1.500 kg" is how a scale prints; "dedh kilo", one kilo and five hundred
/// grams, is how a shopkeeper reads it back. Users of every billing app in
/// this market complain about the same thing — decimals of a kilo nobody
/// can picture ("0.4756") — so a weight in kilos with grams in it is shown
/// as kilos and grams:
///
/// ```text
/// 1.5 kg    →  1 kg 500 g
/// 0.75 kg   →  750 g
/// 2 kg      →  2 kg
/// -0.25 kg  →  -250 g
/// ```
///
/// Kilos only, because that is where it is exact and unambiguous: stock is
/// held in thousandths of the item's unit, and a thousandth of a kilo is a
/// whole gram, so the split never rounds. Everything else — pieces, litres,
/// maunds — reads as the number and its unit, as before.
///
/// An item counted in cartons as well (M45) reads through its own
/// [CountingLadder] instead: this is that ladder with no packs on it.
String quantityWords(Qty qty, String unitCode) =>
    CountingLadder(baseCode: unitCode).words(qty);

// ---------------------------------------------------------------------------
// What a unit is called
// ---------------------------------------------------------------------------

/// The names a shop writes on a chit, where they are shorter than the code.
///
/// "2 ctn + 5 pcs", "3 doz + 4 pcs": the abbreviations every carton and
/// every wholesaler's parchi already uses. Only the three long codes the
/// shop ships with are shortened; a unit the shop made itself keeps its own
/// name, because a shortening nobody chose is a word nobody recognises.
const _shortNames = {'carton': 'ctn', 'dozen': 'doz', 'packet': 'pkt'};

/// On paper the piece shortens too, so that "2 ctn 5 pc" fits the quantity
/// beside the amount on a 58 mm roll.
const _paperNames = {..._shortNames, 'pcs': 'pc'};

/// [code] as the screen writes it beside a count of packs: `ctn`, `doz`.
String shortUnitName(String code) => _shortNames[code] ?? code;

/// [code] as the paper writes it: `ctn`, `pc`.
String paperUnitName(String code) => _paperNames[code] ?? code;

/// What a cashier may type for a unit besides its own code, in English,
/// Roman Urdu and Urdu script (M45).
///
/// The words a shop actually says at the counter: peti for a carton, darjan
/// for a dozen, adad and nag for pieces, kilo, mann, bori, patta, goli.
/// Matched whole first and then by their start, so "c" is a carton and "k"
/// a kilo wherever nothing else on the item starts the same way. Kept to the
/// units the shop ships with; a unit the shop names itself is typed by its
/// own code.
const unitAliases = <String, List<String>>{
  'pcs': [
    'pc',
    'piece',
    'pieces',
    'adad',
    'nag',
    'dana',
    'dane',
    'عدد',
    'نگ',
    'دانہ',
    'دانے',
    'پیس',
  ],
  'dozen': ['doz', 'dz', 'darjan', 'darzan', 'darjen', 'درجن'],
  'carton': ['ctn', 'cartons', 'karton', 'peti', 'petti', 'کارٹن', 'پیٹی'],
  'dabba': ['dabbe', 'dabbay', 'dibba', 'box', 'ڈبہ', 'ڈبا', 'ڈبے'],
  'packet': ['pkt', 'pack', 'packets', 'paket', 'پیکٹ'],
  'strip': ['strips', 'patta', 'pattay', 'patte', 'پتہ', 'پتا', 'پتے'],
  'tablet': ['tab', 'tablets', 'goli', 'goliyan', 'گولی', 'گولیاں'],
  'bori': ['boriyan', 'sack', 'بوری', 'بوریاں'],
  'kg': ['kgs', 'kilo', 'kilos', 'kilogram', 'کلو', 'کلوگرام'],
  'g': ['gm', 'gms', 'gram', 'grams', 'گرام'],
  'maund': ['mann', 'man', 'mun', 'من'],
  'seer': ['ser', 'سیر'],
  'l': ['ltr', 'litre', 'liter', 'litres', 'لیٹر'],
  'ml': ['ملی'],
};

/// The unit a base unit breaks down into, a thousandth of it each.
///
/// So "1 kg 250" is a kilo and 250 grams, the way a shopkeeper calls a
/// weight across the counter, and is exact: a thousandth of a kilo is the
/// gram stock is already counted in.
const _smallerUnit = {'kg': 'g', 'l': 'ml'};

/// Words between the parts of a typed quantity that only join them.
const _joining = {'aur', 'and', 'or', 'اور'};

// ---------------------------------------------------------------------------
// The ladder
// ---------------------------------------------------------------------------

/// How one item is counted: its packs, largest first, and then its own unit
/// (M45).
///
/// Vyapar's top review of September 2026, +403 people: a carton shown as
/// "0.4756". Nobody stocks 0.4756 of a carton. A shop counts the shelf the
/// way it is stacked — two cartons and five loose — so a quantity, held in
/// the item's base unit as always, is shown as the largest whole pack and
/// what is left over, never as a decimal of a pack:
///
/// ```text
/// 53 pcs, a carton of 24      →  2 ctn + 5 pcs
/// 62 kg, a bori of 50         →  1 bori + 12 kg
/// 62.5 kg, a bori of 50       →  1 bori + 12 kg 500 g
/// 40 pcs, sold by the dozen   →  3 doz + 4 pcs
/// 48 pcs, a carton of 24      →  2 ctn
/// ```
///
/// Nothing here converts anything: the packs come from the item's own
/// conversions (M53), the split is integer division of thousandths, and
/// what it shows adds back to exactly what the shelf holds. The same ladder
/// reads what a cashier types ("2 ctn 5", "2c 5p", "1 kg 250") back into
/// the base unit, exactly or not at all — see [read].
final class CountingLadder {
  CountingLadder({
    required this.baseCode,
    Iterable<ItemPack> packs = const [],
    Iterable<ItemPack> alsoReads = const [],
    this.baseDecimals = 3,
  }) : rungs = _rungsOf(packs),
       _alsoReads = List.unmodifiable(alsoReads);

  /// The item's own unit: what its stock is counted in.
  final String baseCode;

  /// The packs a quantity is shown in, largest first. Each holds more than
  /// one of the base unit; a "pack" of one piece, or of half of one, would
  /// only repeat the base unit under another name.
  final List<ItemPack> rungs;

  /// Further units a cashier may type but which are not shown: the shop's
  /// dozen and mann, its gram, wherever they convert into this item exactly.
  final List<ItemPack> _alsoReads;

  /// How many decimals the base unit takes at the counter: none for pieces,
  /// so "1.5 pcs" is refused here as it is everywhere else.
  final int baseDecimals;

  /// Whether the item has any pack to count in.
  bool get hasPacks => rungs.isNotEmpty;

  static List<ItemPack> _rungsOf(Iterable<ItemPack> packs) {
    final sorted = [
      for (final p in packs)
        if (p.size > Qty.one) p,
    ]..sort((a, b) => b.size.compareTo(a.size));
    final codes = <String>{};
    final sizes = <int>{};
    return List.unmodifiable([
      for (final p in sorted)
        // One rung per name and per size: two packs of one size would split
        // the same pieces two ways, and the first is as true as the second.
        if (codes.add(_codeOf(p)) && sizes.add(p.size.inThousandths)) p,
    ]);
  }

  static String _codeOf(ItemPack p) => p.unitCode ?? p.unitId;

  /// [qty], in the base unit, as the screen shows it: "2 ctn + 5 pcs".
  String words(Qty qty) {
    final parts = _split(qty, paper: false).parts;
    return _signed(qty, parts.join(' + '), parts.length);
  }

  /// [qty], in the base unit, as the paper prints it: "2 ctn 5 pc".
  ///
  /// No plus signs and the shorter names, because a till roll is 32
  /// characters wide on 58 mm paper and the amount needs its room.
  String paperWords(Qty qty) {
    final parts = _split(qty, paper: true).parts;
    return _signed(qty, parts.join(' '), parts.length);
  }

  /// Whether [qty] reads in at least one pack: "2 ctn + 5 pcs" does, "5
  /// pcs" and "1 kg 500 g" do not.
  bool countsInPacks(Qty qty) => _split(qty, paper: false).inPacks;

  // A shelf sold below nothing (M53) reads as a whole that is missing, not
  // as two cartons missing and five pieces over: "-(2 ctn + 5 pcs)".
  static String _signed(Qty qty, String text, int parts) => !qty.isNegative
      ? text
      : parts > 1
      ? '-($text)'
      : '-$text';

  ({List<String> parts, bool inPacks}) _split(Qty qty, {required bool paper}) {
    var rest = qty.abs.inThousandths;
    final parts = <String>[];
    for (final rung in rungs) {
      final size = rung.size.inThousandths;
      final count = rest ~/ size;
      if (count == 0) continue;
      final code = _codeOf(rung);
      parts.add('$count ${paper ? paperUnitName(code) : shortUnitName(code)}');
      rest -= count * size;
    }
    final inPacks = parts.isNotEmpty;
    if (rest != 0 || parts.isEmpty) {
      parts.add(_baseWords(Qty.raw(rest), paper: paper));
    }
    return (parts: parts, inPacks: inPacks);
  }

  /// What is left once the packs are counted, in the base unit: kilos with
  /// grams in them as kilos and grams (M56), everything else as the figure
  /// and its unit. Never negative; the sign is the caller's.
  String _baseWords(Qty qty, {required bool paper}) {
    if (baseCode == 'kg' && !qty.isWhole) {
      final grams = qty.inThousandths;
      final kilos = grams ~/ 1000;
      final rest = grams % 1000;
      return kilos == 0 ? '$rest g' : '$kilos kg $rest g';
    }
    if (baseCode.isEmpty) return qty.display;
    return '${qty.display} ${paper ? paperUnitName(baseCode) : baseCode}';
  }

  // -------------------------------------------------------------------------
  // Reading what was typed
  // -------------------------------------------------------------------------

  /// What a cashier typed in the quantity box, read in this item's units, or
  /// null when it cannot be read exactly.
  ///
  /// ```text
  /// "2 ctn 5", "2c 5p", "2 ctn + 5 pcs", "2ctn5", "۲ کارٹن ۵"  →  53 pcs
  /// "2 peti 5 adad"                                         →  53 pcs
  /// "1 kg 250", "1 kilo 250 gram", "1.25 kg"                →  1.25 kg
  /// "1 mann 5"                                              →  45 kg
  /// "53", "1.5"                                             →  as typed
  /// ```
  ///
  /// A figure on its own, with no unit, is [CountReading.bare]: it is in
  /// whatever unit the box was already in, exactly as it always was, so
  /// nothing a cashier types today changes meaning. A figure after a pack is
  /// in the base unit ("2 ctn 5" is five pieces); a figure after the base
  /// unit is in its smaller unit ("1 kg 250" is 250 grams).
  ///
  /// Refused rather than rounded: a pack and a half of an odd size, half a
  /// piece of something sold whole, a word that names nothing on this item.
  /// The counter says it did not understand, and the cashier types it again;
  /// a guess at what was meant is a wrong quantity on a bill.
  CountReading? read(String typed) {
    final tokens = [
      for (final m in _token.allMatches(_normalise(typed)))
        if (!_joining.contains(m[0])) m[0]!,
    ];
    if (tokens.isEmpty) return null;

    final pairs = <(Qty, _Unit?)>[];
    var i = 0;
    while (i < tokens.length) {
      if (!_isFigure(tokens[i])) return null;
      final figure = Qty.tryParse(tokens[i]);
      if (figure == null) return null;
      i++;
      _Unit? unit;
      if (i < tokens.length && !_isFigure(tokens[i])) {
        unit = _unitFor(tokens[i]);
        if (unit == null) return null;
        i++;
      }
      pairs.add((figure, unit));
    }

    if (pairs.length == 1 && pairs.single.$2 == null) {
      return CountReading._(pairs.single.$1, bare: true);
    }

    var total = 0;
    _Unit? last;
    for (final (figure, named) in pairs) {
      final unit = named ?? _after(last);
      if (unit == null) return null;
      final thousandths = figure.inThousandths * unit.size.inThousandths;
      if (thousandths % 1000 != 0) return null;
      total += thousandths ~/ 1000;
      last = unit;
    }
    if (total % _step != 0) return null;
    return CountReading._(Qty.raw(total), bare: false);
  }

  /// The smallest step the base unit allows, in thousandths: 1000 for a
  /// piece, 1 for a kilo.
  int get _step {
    var step = 1;
    for (var d = baseDecimals.clamp(0, 3); d < 3; d++) {
      step *= 10;
    }
    return step;
  }

  /// The unit a figure typed with none is in, after [last]: the base unit
  /// after a pack, the base unit's smaller unit after the base unit.
  _Unit? _after(_Unit? last) {
    if (last == null) return null;
    if (last.size > Qty.one) return _base;
    if (last.code == baseCode) {
      final smaller = _smallerUnit[baseCode];
      return smaller == null ? null : _Unit(smaller, Qty.raw(1));
    }
    return null;
  }

  _Unit get _base => _Unit(baseCode, Qty.one);

  /// Every unit this ladder understands, the item's own packs first so that
  /// its own carton wins over any other of the same name.
  late final List<_Unit> _units = () {
    final seen = <String>{};
    final smaller = _smallerUnit[baseCode];
    return [
      for (final u in [
        for (final p in rungs) _Unit(_codeOf(p), p.size),
        _base,
        if (smaller != null) _Unit(smaller, Qty.raw(1)),
        for (final p in _alsoReads)
          if (p.size.isPositive) _Unit(_codeOf(p), p.size),
      ])
        if (u.code.isNotEmpty && seen.add(u.code)) u,
    ];
  }();

  _Unit? _unitFor(String word) {
    bool isBase(_Unit u) => u.code == baseCode;

    final exact = [
      for (final u in _units)
        if (u.names.contains(word)) u,
    ];
    if (exact.isNotEmpty) return exact.where(isBase).firstOrNull ?? exact.first;

    final found = [
      for (final u in _units)
        if (u.names.any((n) => n.startsWith(word))) u,
    ];
    if (found.length < 2) return found.firstOrNull;
    // Two units answer to it: "p" is a piece and a packet. The piece wins
    // where its own name starts that way, being what the shelf is counted
    // in. Otherwise nothing does — "d" might be a dozen, a dabba or a dana —
    // and the cashier is asked to say which: twelve pieces read as one is a
    // wrong bill.
    return found
        .where((u) => isBase(u) && u.ownNames.any((n) => n.startsWith(word)))
        .firstOrNull;
  }

  // -------------------------------------------------------------------------
  // The carton calculator
  // -------------------------------------------------------------------------

  /// [rate], a price per [per] of the base unit, said per each of the item's
  /// packs and per its own unit (M45): the carton calculator a wholesaler
  /// keeps beside the till, "Rs 960 a carton is Rs 40 a piece".
  ///
  /// Exact where the price comes out exactly. Where it does not — Rs 1,000
  /// a carton of 24 is Rs 41.666... a piece — it is given to the nearest
  /// paisa and marked as such, because this is a figure to read, not a
  /// price to charge: a bill only ever carries a price the converter moved
  /// exactly. The unit [per] already is is left out.
  List<PackPrice> pricesFrom(Rate rate, {required Qty per}) {
    if (!per.isPositive) return const [];
    return [
      for (final (code, size) in [
        for (final p in rungs) (_codeOf(p), p.size),
        if (baseCode.isNotEmpty) (baseCode, Qty.one),
      ])
        if (size != per) _priceAt(rate, from: per, to: size, code: code),
    ];
  }

  static PackPrice _priceAt(
    Rate rate, {
    required Qty from,
    required Qty to,
    required String code,
  }) {
    final scaled = rate.inMilliPaisa * to.inThousandths;
    if (scaled % from.inThousandths == 0) {
      return PackPrice._(code, Rate.raw(scaled ~/ from.inThousandths), true);
    }
    // To the paisa, which is 1000 milli-paisa.
    final paisa = divideRounded(
      scaled,
      from.inThousandths * 1000,
      RoundingMode.halfUp,
    );
    return PackPrice._(code, Rate.raw(paisa * 1000), false);
  }
}

/// One line of the carton calculator: a price per [unitCode].
final class PackPrice {
  const PackPrice._(this.unitCode, this.rate, this.exact);

  final String unitCode;
  final Rate rate;

  /// False when [rate] is the nearest paisa to a price that does not come
  /// out even, which the screen says with "≈".
  final bool exact;
}

/// A quantity a cashier typed, as [CountingLadder.read] understood it.
final class CountReading {
  const CountReading._(this.qty, {required this.bare});

  /// In the ladder's base unit, unless [bare].
  final Qty qty;

  /// A figure with no unit — "53", "1.5" — which is in the unit the box was
  /// already in, as it always was.
  final bool bare;
}

/// One unit the reader knows: what it is called and what it holds.
final class _Unit {
  _Unit(this.code, this.size);

  final String code;

  /// In thousandths of the base unit.
  final Qty size;

  /// Its code and the shortenings of it: "pcs", "pc".
  late final Set<String> ownNames = {
    code.toLowerCase(),
    shortUnitName(code).toLowerCase(),
    paperUnitName(code).toLowerCase(),
  };

  /// Everything it answers to: its own names and the words the counter
  /// says for it.
  late final Set<String> names = {...ownNames, ...?unitAliases[code]};
}

final _token = RegExp(r'\d+(?:\.\d+)?|\.\d+|[^\s\d.,+&]+');

bool _isFigure(String token) {
  final c = token.codeUnitAt(0);
  return c == 0x2E || (c >= 0x30 && c <= 0x39);
}

/// Urdu and Arabic digits into the ones the parser reads, lower case, and a
/// thousands comma ("1,000") taken out so it is not read as two figures.
String _normalise(String typed) {
  final out = StringBuffer();
  for (final r in typed.runes) {
    if (r >= 0x06F0 && r <= 0x06F9) {
      out.writeCharCode(0x30 + r - 0x06F0);
    } else if (r >= 0x0660 && r <= 0x0669) {
      out.writeCharCode(0x30 + r - 0x0660);
    } else if (r == 0x066B) {
      out.write('.');
    } else {
      out.writeCharCode(r);
    }
  }
  return out.toString().toLowerCase().replaceAllMapped(
    RegExp(r'(\d),(\d{3})(?!\d)'),
    (m) => '${m[1]}${m[2]}',
  );
}

// ---------------------------------------------------------------------------
// One shop's ladders
// ---------------------------------------------------------------------------

/// Every item's ladder, from the shop's conversions (M45).
///
/// Built once from the converter the counter already holds, with each
/// item's own conversions indexed by item, so a stock list or a stock report
/// of twenty thousand items finds each one's carton without walking every
/// conversion the shop has for every row.
final class CountingBook {
  CountingBook(this.units, {Map<String, String> codes = const {}})
    : _codes = Map.unmodifiable(codes),
      _own = _index(units.edges);

  /// No conversions at all: every quantity reads as its figure, kilos as
  /// kilos and grams. What a screen shows before the conversions load.
  static final CountingBook none = CountingBook(UnitConverter(const []));

  final UnitConverter units;

  /// Each unit's code, by its id.
  final Map<String, String> _codes;

  final Map<String, List<UnitEdge>> _own;

  static Map<String, List<UnitEdge>> _index(List<UnitEdge> edges) {
    final out = <String, List<UnitEdge>>{};
    for (final e in edges) {
      final item = e.itemId;
      if (item != null) out.putIfAbsent(item, () => []).add(e);
    }
    return out;
  }

  /// The id of the unit called [code], if the shop has one.
  String? _idOf(String code) {
    for (final e in _codes.entries) {
      if (e.value == code) return e.key;
    }
    return null;
  }

  /// [itemId]'s packs: its own conversions into its unit (M53).
  ///
  /// The unit is known by its id where the caller has it, and otherwise by
  /// its code — a report row carries only the code.
  List<ItemPack> packsOf(
    String itemId, {
    String? baseUnitId,
    String? baseUnitCode,
  }) {
    final to =
        baseUnitId ?? (baseUnitCode == null ? null : _idOf(baseUnitCode));
    return [
      for (final e in _own[itemId] ?? const <UnitEdge>[])
        if (to == null || e.toUnitId == to)
          ItemPack(
            unitId: e.fromUnitId,
            unitCode: _codes[e.fromUnitId],
            size: Qty.raw(e.factorThousandths),
          ),
    ];
  }

  /// The code of the unit [itemId]'s packs count into — its own unit —
  /// where it has a pack; null where it has none.
  String? baseCodeOf(String itemId) {
    final edges = _own[itemId];
    return edges == null || edges.isEmpty ? null : _codes[edges.first.toUnitId];
  }

  /// How [itemId] is shown: its packs, and [countedInUnitId] — the unit a
  /// line is being sold in, the shop's dozen or mann — where that holds a
  /// whole number of thousandths of the base unit and more than one of it.
  ///
  /// [itemId] is null for something with no item behind it, a loose line
  /// (M37), which is counted in its unit alone.
  CountingLadder ladder({
    String? itemId,
    required String baseUnitCode,
    String? baseUnitId,
    int baseDecimals = 3,
    String? countedInUnitId,
  }) {
    final base = baseUnitId ?? _idOf(baseUnitCode);
    final packs = itemId == null
        ? <ItemPack>[]
        : packsOf(itemId, baseUnitId: base, baseUnitCode: baseUnitCode);
    final also = countedInUnitId;
    if (also != null &&
        base != null &&
        also != base &&
        !packs.any((p) => p.unitId == also)) {
      if (_sizeOf(also, base, itemId) case final size? when size > Qty.one) {
        packs.add(ItemPack(unitId: also, unitCode: _codes[also], size: size));
      }
    }
    return CountingLadder(
      baseCode: baseUnitCode,
      packs: packs,
      baseDecimals: baseDecimals,
    );
  }

  /// [ladder], and also every other unit of the shop's that converts into
  /// this item exactly — its dozen, its mann, its gram — for reading what a
  /// cashier types. Not for showing: a stock list that turned every forty
  /// shampoos into "3 doz + 4 pcs" would be counting in a way the shop
  /// does not.
  CountingLadder entryLadder({
    String? itemId,
    required String baseUnitCode,
    String? baseUnitId,
    int baseDecimals = 3,
    String? countedInUnitId,
  }) {
    final shown = ladder(
      itemId: itemId,
      baseUnitCode: baseUnitCode,
      baseUnitId: baseUnitId,
      baseDecimals: baseDecimals,
      countedInUnitId: countedInUnitId,
    );
    final base = baseUnitId ?? _idOf(baseUnitCode);
    if (base == null) return shown;
    final known = {for (final p in shown.rungs) p.unitId};
    return CountingLadder(
      baseCode: baseUnitCode,
      packs: shown.rungs,
      baseDecimals: baseDecimals,
      alsoReads: [
        for (final MapEntry(key: id, value: code) in _codes.entries)
          if (id != base && !known.contains(id))
            if (_sizeOf(id, base, itemId) case final size?)
              ItemPack(unitId: id, unitCode: code, size: size),
      ],
    );
  }

  /// How much one [unitId] holds in [baseUnitId], through the converter, or
  /// null when it does not convert exactly.
  Qty? _sizeOf(String unitId, String baseUnitId, String? itemId) {
    try {
      final size = units.convert(
        Qty.one,
        fromUnitId: unitId,
        toUnitId: baseUnitId,
        itemId: itemId,
      );
      return size.isPositive ? size : null;
    } on UnitConversionException {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// On paper
// ---------------------------------------------------------------------------

/// A bill line's quantity as the shop counts it, for the printed bill and
/// its PDF (M45), or null when the figure on the line already says it.
///
/// [qty] in [unitCode] is the line as billed, the figure the rate
/// multiplies; [baseQty] in [baseCode] is what left the shelf. A line sold
/// in a pack counts in the size it was sold at, worked out from the line
/// itself — a carton sold at 24 reprints as a carton of 24 after the shop
/// makes the next one 20 — and otherwise in the item's [packs].
///
/// ```text
/// 53 pcs, a carton of 24    →  2 ctn 5 pc      (in packs)
/// 1.5 kg                    →  1 kg 500 g
/// 2 carton                  →  null: "2 ctn" is what the line says
/// 5 pcs                     →  null
/// ```
({String words, bool inPacks})? paperQuantity({
  required Qty qty,
  required String unitCode,
  required Qty baseQty,
  required String baseCode,
  List<ItemPack> packs = const [],
}) {
  final ladder = lineLadder(
    qty: qty,
    unitCode: unitCode,
    baseQty: baseQty,
    baseCode: baseCode,
    packs: packs,
  );
  final words = ladder.paperWords(baseQty);
  final figure = unitCode.isEmpty
      ? qty.display
      : '${qty.display} ${paperUnitName(unitCode)}';
  if (words == figure) return null;
  return (words: words, inPacks: ladder.countsInPacks(baseQty));
}

/// The ladder a written line is counted on: the item's [packs], with the
/// unit the line was billed in sized from the line itself — [baseQty] over
/// [qty] — so a carton sold at 24 is a carton of 24 whatever the item's
/// carton holds today.
CountingLadder lineLadder({
  required Qty qty,
  required String unitCode,
  required Qty baseQty,
  required String baseCode,
  List<ItemPack> packs = const [],
}) {
  final own = [...packs];
  if (unitCode != baseCode && !qty.isZero) {
    final scaled = baseQty.inThousandths * 1000;
    if (scaled % qty.inThousandths == 0) {
      own
        ..removeWhere((p) => (p.unitCode ?? p.unitId) == unitCode)
        ..insert(
          0,
          ItemPack(
            unitId: unitCode,
            unitCode: unitCode,
            size: Qty.raw((scaled ~/ qty.inThousandths).abs()),
          ),
        );
    }
  }
  return CountingLadder(baseCode: baseCode, packs: own);
}
