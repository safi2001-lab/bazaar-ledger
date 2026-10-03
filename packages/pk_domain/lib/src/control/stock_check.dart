/// A shelf counted at random, a few items a day (M68).
///
/// Nobody in a kiryana counts the whole shop. Marg's "random stock check"
/// is the answer wholesalers use instead: each morning the system names a
/// handful of items, the boy counts just those, and whatever is missing
/// shows up within days rather than at the year's stock-taking -- by which
/// time nobody can say which week it went.
///
/// The pick is weighted the way loss is: an item that moves a lot, or that
/// is worth a lot sitting on the shelf, is where a few missing pieces cost
/// the most and where they are easiest to hide. Every item can still be
/// picked, so a slow item that has quietly walked out is found in time. The
/// same item is never picked two days running.
///
/// Counting writes nothing to the books: what was counted, against what the
/// books said at that moment, is kept on the check. The differences reach
/// the books only when the owner approves them, each as a stock adjustment
/// with the reason "Random check" through the one stock-correction path
/// (M1): the shelf moves by exactly what the count found, valued at the
/// item's average cost, and the loss goes to Stock Wastage as every other
/// shortfall does. A sale between the count and the approval is a sale from
/// both the shelf and the books, so the difference found is the difference
/// posted.
library;

import 'dart:convert';
import 'dart:math';

import 'package:pk_money/pk_money.dart';

import '../time/clock.dart';

/// The settings key the shop's rule is kept under, as JSON.
const stockCheckSettingsKey = 'stockcheck.settings';

/// The settings key prefix each check is kept under:
/// `stockcheck.check.<id>`, one row per check.
const stockCheckKeyPrefix = 'stockcheck.check.';

/// The reason every adjustment a check posts carries.
const stockCheckReason = 'Random check';

/// Audit codes.
const stockCheckPickedAction = 'STOCK_CHECK_PICKED';
const stockCheckCountedAction = 'STOCK_CHECK_COUNTED';
const stockCheckPostedAction = 'STOCK_CHECK_POSTED';
const stockCheckDroppedAction = 'STOCK_CHECK_DROPPED';

/// The shop's rule: how many items, and whether a check is picked each day
/// by itself.
final class StockCheckRule {
  const StockCheckRule({this.size = 5, this.daily = false});

  static const standard = StockCheckRule();

  /// Items to a check.
  final int size;

  /// Whether a check is picked the first time the day's check is looked
  /// for. Off, a check is picked only when somebody asks.
  final bool daily;

  String toJson() => jsonEncode({'size': size, 'daily': daily});

  static StockCheckRule fromJson(String? text) {
    if (text == null || text.trim().isEmpty) return standard;
    try {
      final map = jsonDecode(text);
      if (map is! Map<String, Object?>) return standard;
      final size = map['size'];
      return StockCheckRule(
        size: size is int && size >= 1 && size <= maxStockCheckSize ? size : 5,
        daily: map['daily'] == true,
      );
    } on FormatException {
      return standard;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is StockCheckRule && other.size == size && other.daily == daily;

  @override
  int get hashCode => Object.hash(size, daily);
}

/// The most items one check may name.
const maxStockCheckSize = 50;

/// Where a check stands.
enum StockCheckStatus {
  /// Picked; some items still to count.
  open,

  /// Every item counted; waiting on the owner.
  counted,

  /// The owner approved it and the differences are in the books.
  posted,

  /// Set aside without posting anything.
  dropped;

  static StockCheckStatus parse(Object? code) =>
      values.where((s) => s.name == code).firstOrNull ?? open;
}

/// One item on a check.
final class StockCheckLine {
  const StockCheckLine({
    required this.itemId,
    required this.name,
    required this.unitCode,
    this.counted,
    this.book,
    this.countedBy,
    this.posted,
    this.postedValue,
  });

  final String itemId;
  final String name;
  final String unitCode;

  /// What was on the shelf, in the item's base unit; null until counted.
  final Qty? counted;

  /// What the books said at the moment it was counted.
  final Qty? book;

  /// Who counted it.
  final String? countedBy;

  /// The shelf's movement posted for it, and its value at cost (negative
  /// for a shortfall), once the check is posted.
  final Qty? posted;
  final Money? postedValue;

  bool get isCounted => counted != null && book != null;

  /// Counted less the books: negative is missing.
  Qty? get difference =>
      isCounted ? Qty.raw(counted!.inThousandths - book!.inThousandths) : null;

  StockCheckLine countedAs(
    Qty shelf, {
    required Qty books,
    required String by,
  }) => StockCheckLine(
    itemId: itemId,
    name: name,
    unitCode: unitCode,
    counted: shelf,
    book: books,
    countedBy: by,
  );

  StockCheckLine postedAs(Qty moved, Money value) => StockCheckLine(
    itemId: itemId,
    name: name,
    unitCode: unitCode,
    counted: counted,
    book: book,
    countedBy: countedBy,
    posted: moved,
    postedValue: value,
  );

  Map<String, Object?> toMap() => {
    'item': itemId,
    'name': name,
    'unit': unitCode,
    'counted': ?counted?.inThousandths,
    'book': ?book?.inThousandths,
    'by': ?countedBy,
    'posted': ?posted?.inThousandths,
    'value': ?postedValue?.inPaisa,
  };

  static StockCheckLine? fromMap(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final item = raw['item'];
    if (item is! String) return null;
    Qty? qty(Object? v) => v is int ? Qty.raw(v) : null;
    final value = raw['value'];
    return StockCheckLine(
      itemId: item,
      name: raw['name'] is String ? raw['name']! as String : '',
      unitCode: raw['unit'] is String ? raw['unit']! as String : '',
      counted: qty(raw['counted']),
      book: qty(raw['book']),
      countedBy: raw['by'] is String ? raw['by']! as String : null,
      posted: qty(raw['posted']),
      postedValue: value is int ? Money.paisa(value) : null,
    );
  }
}

/// One random check: the day, the items, and what became of it.
final class StockCheck {
  const StockCheck({
    required this.id,
    required this.date,
    required this.location,
    required this.lines,
    this.status = StockCheckStatus.open,
    this.pickedBy,
    this.postedOn,
    this.approvedBy,
    this.approvedByName,
    this.note,
  });

  final String id;

  /// The day it was picked for.
  final BusinessDate date;

  /// The shelf it counts: `MAIN`, or a van (M18).
  final String location;
  final List<StockCheckLine> lines;
  final StockCheckStatus status;
  final String? pickedBy;

  /// The day its differences reached the books.
  final BusinessDate? postedOn;

  /// Whose word posted it.
  final String? approvedBy;
  final String? approvedByName;

  /// Why it was set aside, or what the owner said approving it.
  final String? note;

  bool get isOpen =>
      status == StockCheckStatus.open || status == StockCheckStatus.counted;

  bool get allCounted => lines.every((l) => l.isCounted);

  /// Lines the count found different from the books.
  List<StockCheckLine> get differing => [
    for (final l in lines)
      if (l.difference case final d? when !d.isZero) l,
  ];

  /// What was posted short, as a positive sum.
  Money get shortValue => Money.sum([
    for (final l in lines)
      if (l.postedValue case final v? when v.isNegative) -v,
  ]);

  /// What was posted over.
  Money get overValue => Money.sum([
    for (final l in lines)
      if (l.postedValue case final v? when v.isPositive) v,
  ]);

  StockCheck copyWith({
    List<StockCheckLine>? lines,
    StockCheckStatus? status,
    BusinessDate? postedOn,
    String? approvedBy,
    String? approvedByName,
    String? note,
  }) => StockCheck(
    id: id,
    date: date,
    location: location,
    lines: lines ?? this.lines,
    status: status ?? this.status,
    pickedBy: pickedBy,
    postedOn: postedOn ?? this.postedOn,
    approvedBy: approvedBy ?? this.approvedBy,
    approvedByName: approvedByName ?? this.approvedByName,
    note: note ?? this.note,
  );

  String toJson() => jsonEncode({
    'id': id,
    'date': date.value,
    'location': location,
    'status': status.name,
    'pickedBy': ?pickedBy,
    'postedOn': ?postedOn?.value,
    'approvedBy': ?approvedBy,
    'approvedByName': ?approvedByName,
    'note': ?note,
    'lines': [for (final l in lines) l.toMap()],
  });

  static StockCheck? fromJson(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    try {
      final map = jsonDecode(text);
      if (map is! Map<String, Object?>) return null;
      final id = map['id'];
      final date = map['date'] is String
          ? BusinessDate.tryParse(map['date']! as String)
          : null;
      final rawLines = map['lines'];
      if (id is! String || date == null || rawLines is! List) return null;
      final posted = map['postedOn'];
      String? read(String key) =>
          map[key] is String ? map[key]! as String : null;
      return StockCheck(
        id: id,
        date: date,
        location: read('location') ?? 'MAIN',
        status: StockCheckStatus.parse(map['status']),
        pickedBy: read('pickedBy'),
        postedOn: posted is String ? BusinessDate.tryParse(posted) : null,
        approvedBy: read('approvedBy'),
        approvedByName: read('approvedByName'),
        note: read('note'),
        lines: [for (final raw in rawLines) ?StockCheckLine.fromMap(raw)],
      );
    } on FormatException {
      return null;
    }
  }
}

/// An item the picker may name, with what makes it worth counting.
final class StockCheckCandidate {
  const StockCheckCandidate({
    required this.itemId,
    required this.name,
    required this.unitCode,
    required this.movedValue,
    required this.stockValue,
  });

  final String itemId;
  final String name;
  final String unitCode;

  /// What left the shelf in the last thirty days, at cost: how fast it
  /// moves, in the one unit every item shares.
  final Money movedValue;

  /// What is on the shelf now, at cost.
  final Money stockValue;

  /// Fast movers count double: a few pieces short of an item that sells
  /// all day is where loss hides best.
  int get score => movedValue.inPaisa * 2 + stockValue.inPaisa;
}

/// Picks up to [size] of [candidates] for a check, none of [exclude].
///
/// Weighted by rank: the candidates are ordered by [StockCheckCandidate.
/// score], and the one at the top is [candidates.length] times as likely
/// to be drawn as the one at the bottom, which is still possible. By rank
/// rather than by the score itself, so one very dear item cannot be drawn
/// every day and a shop of cheap items still gets a spread. Drawn without
/// putting back, so a check never names an item twice.
///
/// [seed] makes the draw the same each time it is asked for the same day,
/// so two phones asked for the morning's check, or the same phone asked
/// twice, name the same items.
List<StockCheckCandidate> pickForCheck({
  required List<StockCheckCandidate> candidates,
  required Set<String> exclude,
  required int size,
  required int seed,
}) {
  final pool =
      [
        for (final c in candidates)
          if (!exclude.contains(c.itemId)) c,
      ]..sort((a, b) {
        final byScore = a.score.compareTo(b.score);
        return byScore != 0 ? byScore : a.itemId.compareTo(b.itemId);
      });
  final random = Random(seed);
  // Weight of pool[i] is i + 1: the lowest score 1, the highest n.
  final weights = [for (var i = 0; i < pool.length; i++) i + 1];
  final picked = <StockCheckCandidate>[];
  while (picked.length < size && pool.isNotEmpty) {
    final total = weights.fold<int>(0, (sum, w) => sum + w);
    // Two draws of 26 bits make one of 52: past what one nextInt can
    // reach for a shop of tens of thousands of items.
    final draw =
        ((random.nextInt(1 << 26) << 26) | random.nextInt(1 << 26)) % total;
    var at = 0;
    var running = weights.first;
    while (running <= draw) {
      at++;
      running += weights[at];
    }
    picked.add(pool.removeAt(at));
    weights.removeAt(at);
  }
  return picked;
}

/// A seed for the draw: the same for the same shop, day and turn.
///
/// FNV-1a over the text, rather than `String.hashCode`, which Dart does not
/// promise to keep the same from one build to the next.
int stockCheckSeed(String firmId, BusinessDate date, int turn) {
  var hash = 0x811c9dc5;
  for (final unit in '$firmId|${date.value}|$turn'.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// What the random checks of one month found.
final class Shrinkage {
  const Shrinkage({
    required this.month,
    required this.checks,
    required this.short,
    required this.over,
  });

  /// `YYYY-MM`.
  final String month;

  /// Checks posted in the month.
  final int checks;

  /// Value of what was missing, and of what turned up, at cost.
  final Money short;
  final Money over;

  /// What the shop lost on balance: missing less found.
  Money get net => short - over;
}

/// The posted checks of [checks], month by month, newest first.
List<Shrinkage> shrinkageByMonth(Iterable<StockCheck> checks) {
  final byMonth = <String, List<StockCheck>>{};
  for (final c in checks) {
    if (c.status != StockCheckStatus.posted) continue;
    final on = c.postedOn ?? c.date;
    byMonth.putIfAbsent(on.value.substring(0, 7), () => []).add(c);
  }
  final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final m in months)
      Shrinkage(
        month: m,
        checks: byMonth[m]!.length,
        short: Money.sum([for (final c in byMonth[m]!) c.shortValue]),
        over: Money.sum([for (final c in byMonth[m]!) c.overValue]),
      ),
  ];
}
