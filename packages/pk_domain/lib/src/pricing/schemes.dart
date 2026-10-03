/// Bonus and slabs the way the trade runs (M43): "10+1", cheaper by the
/// carton, and something off a big bill.
///
/// Pakistan's wholesale and pharmacy trade is run on these three, and every
/// one of them is done today on a calculator beside the till. The
/// distributor's salesman says "das pe aik muft" (one free on ten), the
/// wholesaler's board says "darjan pe 46, carton pe 44", and the regular
/// customer who spends Rs 20,000 in one go expects something off it without
/// asking. Vyapar has a free-quantity column the cashier fills in by hand and
/// nothing that works it out; Marg works out all three, on a desktop.
///
/// ## What is decided here, once
///
///  * **A bonus is whole sets only.** Ten paid earns one free; nineteen still
///    earns one; twenty earns two. Marg calls this its "Full" scheme and it
///    is what a salesman means by "10+1". Its "Half" and "All" modes (a part
///    set rounded, or the free goods in proportion) are not offered: no
///    shopkeeper this was built for has asked for half a free soap.
///  * **The free goods are a line of their own**, at no rate, marked free,
///    under the line that earned them. They leave the shelf like any other
///    line and cost what they cost, and the books post that cost exactly as
///    they post the cost of every free line since M0: to Cost of Goods Sold,
///    against Inventory. The goods were given as part of the sale that earned
///    them — the customer paid for ten and took eleven — so their cost is a
///    cost of that sale (IFRS 15 spreads the price across all eleven), and
///    the item's and the bill's margins show what the scheme really cost.
///    They carry no discount, so the discount reports are untouched by them.
///  * **A quantity slab is a price, not a discount.** "12 and up, Rs 46" sets
///    the rate on the line, the way the board on the wall does, and applies
///    only where it is LOWER than the price the customer would otherwise
///    pay: a VIP already on Rs 45 is not charged Rs 46 for buying a dozen.
///    The quantity that counts is what the line takes off the shelf, in the
///    shelf's own unit, so a carton of 24 is 24 pieces whichever way it was
///    rung, and the rate is carried into the carton exactly.
///  * **A bill-value slab is a bill discount.** "Rs 5,000 and up, 2% off" is
///    worked out on what the lines come to after their own discounts, and
///    goes down the one bill-discount path M0 built: split across the lines
///    by value, to the paisa, into Discount Given. It is the owner's
///    decision, set in Settings, so a cashier ringing it is applying the
///    owner's word and not using up their own discount ceiling — the same
///    rule M22 gave a customer's standing discount.
///
/// Pure: no clock, no database. The shop's schemes are read into a
/// [SchemeBook] once and every question is asked of that.
library;

import 'dart:convert';

import 'package:pk_money/pk_money.dart';

import '../ports/app_queries.dart';
import '../sales/sale_draft.dart';
import 'price_tier.dart';

/// Where an item's own scheme is kept: one `settings` row per item, keyed by
/// this and the item's id, holding [ItemScheme.toJson]. One row per item
/// rather than one row for the shop, so two counters each changing a
/// different item's scheme while apart both keep theirs through the LAN
/// sync, as M41's shortage list does.
const schemeItemKeyPrefix = 'scheme.item.';

/// The shop's bill-value slabs, one `settings` row for the whole shop.
const schemeBillSlabsKey = 'scheme.bill_slabs';

/// What was wrong with a scheme the owner typed, for the screen to say in
/// words.
enum SchemeProblem {
  /// "10+0" or "0+1": a bonus needs something bought and something free.
  bonusEmpty,

  /// A slab starting at nothing, or at no rate.
  slabEmpty,

  /// Two slabs from the same quantity, or two bill slabs from one value.
  slabTwice,

  /// A bigger slab at a higher rate, or a bigger bill at a smaller
  /// percentage. Never what a shop means; always a typo.
  slabOutOfOrder,

  /// A bill slab of nothing, or of more than half the bill.
  billSlabPercent,
}

/// Thrown when a scheme cannot be kept, naming what was wrong.
final class SchemeRefused implements Exception {
  const SchemeRefused(this.problem);

  final SchemeProblem problem;

  @override
  String toString() => 'SchemeRefused: ${problem.name}';
}

/// "For every [buy], [free] free": the scheme as the owner typed it.
final class BonusRule {
  const BonusRule({
    required this.buy,
    required this.free,
    this.unitId,
    this.freeItemId,
  });

  /// Paid goods that earn one set, in [unitId].
  final Qty buy;

  /// Free goods per set: in [unitId] when they are the same item, in the
  /// other item's own unit when [freeItemId] names one.
  final Qty free;

  /// The unit both are counted in — a carton for "10+1 cartons" — or null
  /// for the item's own unit.
  final String? unitId;

  /// Another item given free ("buy ten shampoos, a soap free"), or null for
  /// more of the same.
  final String? freeItemId;

  bool get isSameItem => freeItemId == null;

  /// "10+1".
  String get label => '${buy.display}+${free.display}';

  Map<String, Object?> toJson() => {
    'buy': buy.inThousandths,
    'free': free.inThousandths,
    'unit': ?unitId,
    'freeItem': ?freeItemId,
  };

  static BonusRule? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final buy = raw['buy'];
    final free = raw['free'];
    final unit = raw['unit'];
    final freeItem = raw['freeItem'];
    if (buy is! int || free is! int) return null;
    if (unit != null && unit is! String) return null;
    if (freeItem != null && freeItem is! String) return null;
    return BonusRule(
      buy: Qty.raw(buy),
      free: Qty.raw(free),
      unitId: unit as String?,
      freeItemId: freeItem as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BonusRule &&
      other.buy == buy &&
      other.free == free &&
      other.unitId == unitId &&
      other.freeItemId == freeItemId;

  @override
  int get hashCode => Object.hash(buy, free, unitId, freeItemId);
}

/// "[from] and up, [rate] each": one step of an item's quantity slabs.
final class QtySlab {
  const QtySlab({required this.from, required this.rate});

  /// In the item's own unit — pieces, not cartons, so a slab means the same
  /// whichever unit the line was rung in.
  final Qty from;

  /// Per the item's own unit.
  final Rate rate;

  Map<String, Object?> toJson() => {
    'from': from.inThousandths,
    'rate': rate.inMilliPaisa,
  };

  static QtySlab? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final from = raw['from'];
    final rate = raw['rate'];
    if (from is! int || rate is! int) return null;
    return QtySlab(from: Qty.raw(from), rate: Rate.raw(rate));
  }

  @override
  bool operator ==(Object other) =>
      other is QtySlab && other.from == from && other.rate == rate;

  @override
  int get hashCode => Object.hash(from, rate);
}

/// One item's scheme as it is kept: its bonus, its slabs, or both.
final class ItemScheme {
  const ItemScheme({required this.itemId, this.bonus, this.slabs = const []});

  final String itemId;
  final BonusRule? bonus;

  /// Smallest first.
  final List<QtySlab> slabs;

  bool get isEmpty => bonus == null && slabs.isEmpty;

  /// The settings key this is kept under.
  String get settingKey => '$schemeItemKeyPrefix$itemId';

  /// The same scheme with its slabs in order, or refused with what is
  /// wrong. What the owner typed is never kept half-checked.
  ItemScheme checked() {
    final bonus = this.bonus;
    if (bonus != null && (!bonus.buy.isPositive || !bonus.free.isPositive)) {
      throw const SchemeRefused(SchemeProblem.bonusEmpty);
    }
    final sorted = [...slabs]..sort((a, b) => a.from.compareTo(b.from));
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      if (!s.from.isPositive || s.rate.inMilliPaisa <= 0) {
        throw const SchemeRefused(SchemeProblem.slabEmpty);
      }
      if (i > 0 && sorted[i - 1].from == s.from) {
        throw const SchemeRefused(SchemeProblem.slabTwice);
      }
      if (i > 0 && s.rate >= sorted[i - 1].rate) {
        throw const SchemeRefused(SchemeProblem.slabOutOfOrder);
      }
    }
    return ItemScheme(itemId: itemId, bonus: bonus, slabs: sorted);
  }

  /// Integers only, as every number the books keep.
  String toJson() => _encode({
    'bonus': bonus?.toJson(),
    'slabs': [for (final s in slabs) s.toJson()],
  });

  /// What a settings row holds, or an empty scheme for anything it cannot
  /// read — a scheme nobody can read is one nobody gives.
  static ItemScheme fromJson(String itemId, String? source) {
    final root = _decode(source);
    if (root == null) return ItemScheme(itemId: itemId);
    final rawSlabs = root['slabs'];
    final slabs = <QtySlab>[
      if (rawSlabs is List)
        for (final raw in rawSlabs) ?QtySlab.fromJson(raw),
    ]..sort((a, b) => a.from.compareTo(b.from));
    return ItemScheme(
      itemId: itemId,
      bonus: BonusRule.fromJson(root['bonus']),
      slabs: slabs,
    );
  }
}

/// "Bills of [from] and up, [percentBp] off".
final class BillSlab {
  const BillSlab({required this.from, required this.percentBp});

  final Money from;

  /// Basis points: 200 is 2%.
  final int percentBp;

  /// "2%", "2.5%".
  String get percentLabel {
    final whole = percentBp ~/ 100;
    if (percentBp % 100 == 0) return '$whole%';
    final part = (percentBp % 100).toString().padLeft(2, '0');
    return '$whole.${part.endsWith('0') ? part[0] : part}%';
  }

  Map<String, Object?> toJson() => {'from': from.inPaisa, 'bp': percentBp};

  static BillSlab? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final from = raw['from'];
    final bp = raw['bp'];
    if (from is! int || bp is! int) return null;
    return BillSlab(from: Money.paisa(from), percentBp: bp);
  }

  /// [slabs] smallest first, or refused with what is wrong.
  static List<BillSlab> checked(List<BillSlab> slabs) {
    final sorted = [...slabs]..sort((a, b) => a.from.compareTo(b.from));
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      if (!s.from.isPositive) {
        throw const SchemeRefused(SchemeProblem.slabEmpty);
      }
      // Half the bill is already far past anything a shop gives for size;
      // more is a mistyped figure (20 for 2), and it would take the till
      // with it.
      if (s.percentBp <= 0 || s.percentBp > 5000) {
        throw const SchemeRefused(SchemeProblem.billSlabPercent);
      }
      if (i > 0 && sorted[i - 1].from == s.from) {
        throw const SchemeRefused(SchemeProblem.slabTwice);
      }
      if (i > 0 && s.percentBp <= sorted[i - 1].percentBp) {
        throw const SchemeRefused(SchemeProblem.slabOutOfOrder);
      }
    }
    return sorted;
  }

  static String listToJson(List<BillSlab> slabs) => _encode({
    'slabs': [for (final s in slabs) s.toJson()],
  });

  static List<BillSlab> listFromJson(String? source) {
    final root = _decode(source);
    final raw = root?['slabs'];
    return <BillSlab>[
      if (raw is List)
        for (final r in raw) ?BillSlab.fromJson(r),
    ]..sort((a, b) => a.from.compareTo(b.from));
  }

  @override
  bool operator ==(Object other) =>
      other is BillSlab && other.from == from && other.percentBp == percentBp;

  @override
  int get hashCode => Object.hash(from, percentBp);
}

/// What one set of a bonus puts on the bill, worked out into the shelf's
/// terms when the shop's schemes are read.
final class BonusOffer {
  const BonusOffer({
    required this.rule,
    required this.buyBase,
    required this.freeBase,
    required this.freeItemId,
    required this.freeItemName,
    required this.freeUnitId,
    required this.freeUnitCode,
    this.freeItemCode,
    this.freeHsCode,
    this.freeTracksStock = true,
  });

  /// As the owner typed it.
  final BonusRule rule;

  /// Paid goods that earn one set, in the item's own unit.
  final Qty buyBase;

  /// Free goods per set, in the free item's own unit.
  final Qty freeBase;

  final String freeItemId;
  final String freeItemName;

  /// The unit the free line is written in: the scheme's own (a carton for
  /// "10+1 cartons"), or the free item's.
  final String freeUnitId;
  final String freeUnitCode;
  final String? freeItemCode;
  final String? freeHsCode;
  final bool freeTracksStock;

  /// Free goods per set, as the line shows them.
  Qty get freePerSet => rule.free;
}

/// The bonus one item earned on one bill.
final class BonusGrant {
  const BonusGrant({
    required this.forItemId,
    required this.sets,
    required this.offer,
  });

  /// The item whose paid lines earned it.
  final String forItemId;

  /// Whole sets earned.
  final int sets;

  final BonusOffer offer;

  /// As the free line shows it.
  Qty get qty => offer.freePerSet * sets;

  /// What leaves the shelf.
  Qty get baseQty => offer.freeBase * sets;

  /// The free line: no rate, marked free, and costed at post time like any
  /// other line, because the goods cost what they cost.
  SaleLineDraft toLine() => SaleLineDraft(
    itemId: offer.freeItemId,
    itemName: offer.freeItemName,
    itemCode: offer.freeItemCode,
    hsCode: offer.freeHsCode,
    qty: qty,
    baseQty: baseQty,
    unitId: offer.freeUnitId,
    unitCode: offer.freeUnitCode,
    rate: Rate.zero,
    isFreeItem: true,
    tracksStock: offer.freeTracksStock,
  );
}

/// The shop's schemes, read once and asked of at the counter and in the
/// sale path.
final class SchemeBook {
  const SchemeBook({
    this.bonuses = const {},
    this.slabs = const {},
    this.billSlabs = const [],
  });

  static const empty = SchemeBook();

  /// By the id of the item whose paid lines earn it.
  final Map<String, BonusOffer> bonuses;

  /// By item id, smallest first.
  final Map<String, List<QtySlab>> slabs;

  /// Smallest first.
  final List<BillSlab> billSlabs;

  bool get isEmpty => bonuses.isEmpty && slabs.isEmpty && billSlabs.isEmpty;

  /// The slab rate [baseQty] of [itemId] reaches, per the item's own unit,
  /// or null below the first slab.
  Rate? slabRate(String itemId, Qty baseQty) {
    Rate? found;
    for (final s in slabs[itemId] ?? const <QtySlab>[]) {
      if (baseQty >= s.from) found = s.rate;
    }
    return found;
  }

  /// What [item] sells at to a [tier] buyer taking [baseQty] of it, per the
  /// item's own unit: the tier's price, or the slab's where that is lower.
  Rate priceAt(ItemSummary item, PriceTier tier, Qty baseQty) {
    final tierRate = priceFor(item, tier);
    final slab = slabRate(item.id, baseQty);
    return slab != null && slab < tierRate ? slab : tierRate;
  }

  /// What each item's paid lines take off the shelf, in its own unit. A free
  /// line earns nothing, and a loose line (M37) has no item to earn for.
  static Map<String, Qty> paidBaseOf(Iterable<SaleLineDraft> lines) {
    final paid = <String, Qty>{};
    for (final l in lines) {
      final id = l.itemId;
      if (id == null || l.isFreeItem) continue;
      paid[id] = (paid[id] ?? Qty.zero) + l.baseQty;
    }
    return paid;
  }

  /// The bonus each item earns on [paidBase] (see [paidBaseOf]), in the
  /// order the items were first rung.
  List<BonusGrant> bonusFor(Map<String, Qty> paidBase) => [
    for (final MapEntry(key: itemId, value: qty) in paidBase.entries)
      if (bonuses[itemId] case final offer?)
        if (_sets(qty, offer) case final sets when sets > 0)
          BonusGrant(forItemId: itemId, sets: sets, offer: offer),
  ];

  static int _sets(Qty paid, BonusOffer offer) {
    if (!offer.buyBase.isPositive || !offer.freeBase.isPositive) return 0;
    if (!paid.isPositive) return 0;
    return paid.inThousandths ~/ offer.buyBase.inThousandths;
  }

  /// How much of each item may go out free on a bill whose paid lines take
  /// [paidBase] off the shelf, in the free item's own unit: what the
  /// schemes give, and nothing more.
  Map<String, Qty> freeAllowed(Map<String, Qty> paidBase) {
    final allowed = <String, Qty>{};
    for (final g in bonusFor(paidBase)) {
      final id = g.offer.freeItemId;
      allowed[id] = (allowed[id] ?? Qty.zero) + g.baseQty;
    }
    return allowed;
  }

  /// What the lines come to after their own discounts, the figure a bill
  /// slab is reached on — worked out the way the sale calculator works out
  /// what it splits a bill discount over, so the two never disagree.
  static Money billValueOf(
    Iterable<SaleLineDraft> lines, {
    RoundingMode mode = RoundingMode.halfUp,
  }) {
    var value = Money.zero;
    for (final l in lines) {
      if (l.isFreeItem) continue;
      final gross = l.rate.amountFor(l.qty, mode: mode);
      final off =
          l.explicitDiscount ?? gross.percentBp(l.discountBp, mode: mode);
      value += gross - off;
    }
    return value;
  }

  /// The slab a bill worth [value] reaches, and what it takes off; null
  /// below the first.
  ({BillSlab slab, Money discount})? billSlabFor(
    Money value, {
    RoundingMode mode = RoundingMode.halfUp,
  }) {
    BillSlab? found;
    for (final s in billSlabs) {
      if (value >= s.from) found = s;
    }
    if (found == null || !value.isPositive) return null;
    return (
      slab: found,
      discount: value.percentBp(found.percentBp, mode: mode),
    );
  }
}

/// Integers, strings, lists and maps only, the same as the cart's draft: a
/// double here would be a rounding nobody asked for.
String _encode(Map<String, Object?> value) => jsonEncode(value);

Map<String, Object?>? _decode(String? source) {
  if (source == null || source.trim().isEmpty) return null;
  try {
    final parsed = jsonDecode(source);
    return parsed is Map<String, Object?> ? parsed : null;
  } on FormatException {
    return null;
  }
}
