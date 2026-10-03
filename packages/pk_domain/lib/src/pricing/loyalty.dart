/// Points that bring a customer back (M66): "Rs 100 par 1 point", and a
/// hundred points worth Rs 50 off a later bill.
///
/// Vyapar sells this as a premium setting and prints "Total Loyalty Points
/// Rewarded" on its sale report; a Pakistani kiryana does it today with a
/// stamp card, or not at all. Here the counter works it out from the books.
///
/// ## What is decided here, once
///
///  * **Points are earned on what is paid, never on what is owed.** A bill's
///    points are worked out on the smaller of the money that came in against
///    it (cleared: a cheque earns when it clears, a written-off balance
///    never) and what the customer kept of it (its total less what came
///    back). A bill on udhaar earns nothing at the counter, earns as its
///    udhaar is paid, and earns in full the day it is settled. So a point
///    never rewards a bill nobody paid, and a customer who never pays never
///    collects. Named customers only: a walk-in has no khata to keep points
///    on.
///  * **Per bill, in whole steps.** "1 point per Rs 100" on a Rs 250 bill is
///    2 points, as every stamp card and Vyapar count it; the fifty is not
///    carried to the next bill.
///  * **A bill's points follow the bill.** Cancelled, it earns nothing and
///    gives back what it spent; goods returned off it take back the points
///    earned on them (the earning is on what was kept) and give back the
///    points spent on them in the same share of the goods' value.
///  * **Points are a memo, not a liability in the books.** IFRS 15 would
///    hold back part of each sale as deferred revenue until the points are
///    used or lapse. That is right for an airline and wrong for this shop:
///    it needs an estimate of how many points will never be used, which a
///    kiryana cannot make, and it would put a liability on the balance sheet
///    that moves with every bill and that the owner's accountant would have
///    to unpick. Vyapar keeps points as a balance beside the khata; so does
///    this. The money is booked when it is real: a redemption is a discount
///    on the bill that uses the points, down M0's one bill-discount path
///    into Discount Given, on the day it is given. The books balance every
///    day; the points outstanding are a figure on the Loyalty report, in
///    points and in rupees at today's rate, for the owner to see what is
///    promised.
///  * **The rule in force when a bill was made is the bill's rule.** Every
///    change the owner makes is kept as a new version from the moment it is
///    made, so raising the rate gives the next bill more and changes no
///    point already earned, and switching it off stops earning from the next
///    bill and keeps every point earned — the morning's bills included. A
///    bill from before the scheme began earns nothing.
///  * **Expiry, when the owner sets it, is by the bill's day**, the bill's
///    own version saying how many months its points live. Points are used
///    oldest first, so the points that expire are the ones nobody used.
///
/// Pure: no clock, no database. The books are read into [LoyaltyBill]s and
/// every question is asked of those.
library;

import 'dart:convert';

import 'package:pk_money/pk_money.dart';

/// Where the shop's loyalty rule is kept: one `settings` row for the shop,
/// holding every version of the rule ([LoyaltyRules.toJson]).
const loyaltyRulesKey = 'loyalty.rules';

/// Where a bill's spent points are kept: one `settings` row per bill that
/// used points, keyed by this and the bill's id, written in the bill's own
/// commit ([LoyaltyRedemption.toJson]).
const loyaltyRedeemedKeyPrefix = 'loyalty.redeemed.';

/// What was wrong with a rule or a redemption, for the screen to say in
/// words.
enum LoyaltyProblem {
  /// Nothing earned, nothing worth anything, or a figure of no size.
  figures,

  /// Points worth more than half of what earned them: never what a shop
  /// means, always a typo (Rs 50 for Rs 0.50).
  tooGenerous,

  /// A share of a bill outside 1% to 100%.
  cap,

  /// More than ten years of life, or less than none.
  expiry,

  /// Points for a walk-in, or for another customer than the bill's.
  noCustomer,

  /// More points than the customer has.
  notEnough,

  /// More of the bill paid in points than the shop allows.
  overCap,

  /// The shop does not give points today.
  off,

  /// The points and their worth do not agree with today's rate, or are not
  /// on the bill as its discount: a counter left open across a change of
  /// rate, or a redemption that is not what the bill says.
  mismatch,
}

/// Thrown when a rule cannot be kept or points cannot be used, naming why.
final class LoyaltyRefused implements Exception {
  const LoyaltyRefused(this.problem);

  final LoyaltyProblem problem;

  @override
  String toString() => switch (problem) {
    LoyaltyProblem.notEnough =>
      'LoyaltyRefused: the customer does not have that many points.',
    LoyaltyProblem.overCap =>
      'LoyaltyRefused: more of this bill is paid in points than the shop '
          'allows.',
    LoyaltyProblem.off => 'LoyaltyRefused: the shop gives no points today.',
    LoyaltyProblem.noCustomer =>
      'LoyaltyRefused: points are used on their own customer\'s bill.',
    LoyaltyProblem.mismatch =>
      'LoyaltyRefused: the points and their worth are not what the bill '
          'says. Take them off and use them again.',
    _ => 'LoyaltyRefused: ${problem.name}',
  };
}

/// One version of the shop's rule, in force from [from].
final class LoyaltyRule {
  const LoyaltyRule({
    required this.from,
    this.atUtc = 0,
    this.isOn = true,
    this.earnPoints = 1,
    this.earnPer = const Money.rupees(100),
    this.redeemPoints = 100,
    this.redeemValue = const Money.rupees(50),
    this.expiryMonths = 0,
    this.maxBillBp = 5000,
  });

  /// The shop's day this version began, `YYYY-MM-DD`.
  final String from;

  /// The moment it began, in UTC milliseconds; 0 for the start of [from].
  /// A bill posted at or after it is this version's.
  final int atUtc;

  /// [atUtc], or the first moment of [from] in Pakistan when it is 0.
  int get beganUtc {
    if (atUtc > 0) return atUtc;
    final d = DateTime.utc(
      int.parse(from.substring(0, 4)),
      int.parse(from.substring(5, 7)),
      int.parse(from.substring(8, 10)),
    );
    return d.subtract(const Duration(hours: 5)).millisecondsSinceEpoch;
  }

  /// Whether bills of this version earn, and points may be used.
  final bool isOn;

  /// [earnPoints] points for every [earnPer] paid.
  final int earnPoints;
  final Money earnPer;

  /// [redeemPoints] points are worth [redeemValue] off a bill.
  final int redeemPoints;
  final Money redeemValue;

  /// How long a bill's points live, in months; 0 for ever.
  final int expiryMonths;

  /// The most of a bill points may pay, in basis points of what its goods
  /// come to after their own discounts: 5000 is half.
  final int maxBillBp;

  /// The points [paid] earns on one bill: whole steps of [earnPer].
  int pointsFor(Money paid) {
    if (!isOn || !paid.isPositive || !earnPer.isPositive) return 0;
    return paid.inPaisa ~/ earnPer.inPaisa * earnPoints;
  }

  /// What [points] take off a bill, to the paisa below.
  Money valueOf(int points) {
    if (points <= 0 || redeemPoints <= 0) return Money.zero;
    return Money.paisa(points * redeemValue.inPaisa ~/ redeemPoints);
  }

  /// The most points whose worth is no more than [value].
  int pointsWorth(Money value) {
    if (!value.isPositive || !redeemValue.isPositive) return 0;
    return value.inPaisa * redeemPoints ~/ redeemValue.inPaisa;
  }

  /// The most a bill whose goods come to [billValue] may take off in points.
  Money capOn(Money billValue) => billValue.isPositive
      ? billValue.percentBp(maxBillBp, mode: RoundingMode.truncate)
      : Money.zero;

  /// The most points a customer holding [balance] may use on a bill whose
  /// goods come to [billValue].
  int maxPointsOn(Money billValue, int balance) {
    if (!isOn || balance <= 0) return 0;
    final byCap = pointsWorth(capOn(billValue));
    return byCap < balance ? byCap : balance;
  }

  /// The same rule refused with what is wrong, or itself.
  LoyaltyRule checked() {
    if (earnPoints <= 0 ||
        !earnPer.isPositive ||
        redeemPoints <= 0 ||
        !redeemValue.isPositive) {
      throw const LoyaltyRefused(LoyaltyProblem.figures);
    }
    if (maxBillBp <= 0 || maxBillBp > 10000) {
      throw const LoyaltyRefused(LoyaltyProblem.cap);
    }
    if (expiryMonths < 0 || expiryMonths > 120) {
      throw const LoyaltyRefused(LoyaltyProblem.expiry);
    }
    // What the points one step earns are worth, against the step: "1 point
    // per Rs 100, 100 points Rs 50" gives back half a percent. Past half
    // of what was paid is a figure typed in the wrong box, and it would
    // give the till away. Integers throughout: value x 10000 / paid.
    final givenBackBp =
        earnPoints *
        redeemValue.inPaisa *
        10000 ~/
        (redeemPoints * earnPer.inPaisa);
    if (givenBackBp > 5000) {
      throw const LoyaltyRefused(LoyaltyProblem.tooGenerous);
    }
    return this;
  }

  /// What one rupee paid gives back when the points are used, as a
  /// percentage in basis points: the figure the settings screen says.
  int get givenBackBp => redeemPoints <= 0 || !earnPer.isPositive
      ? 0
      : earnPoints *
            redeemValue.inPaisa *
            10000 ~/
            (redeemPoints * earnPer.inPaisa);

  LoyaltyRule copyWith({
    String? from,
    int? atUtc,
    bool? isOn,
    int? earnPoints,
    Money? earnPer,
    int? redeemPoints,
    Money? redeemValue,
    int? expiryMonths,
    int? maxBillBp,
  }) => LoyaltyRule(
    from: from ?? this.from,
    atUtc: atUtc ?? this.atUtc,
    isOn: isOn ?? this.isOn,
    earnPoints: earnPoints ?? this.earnPoints,
    earnPer: earnPer ?? this.earnPer,
    redeemPoints: redeemPoints ?? this.redeemPoints,
    redeemValue: redeemValue ?? this.redeemValue,
    expiryMonths: expiryMonths ?? this.expiryMonths,
    maxBillBp: maxBillBp ?? this.maxBillBp,
  );

  Map<String, Object?> toJson() => {
    'from': from,
    'at': atUtc,
    'on': isOn ? 1 : 0,
    'earn': earnPoints,
    'per': earnPer.inPaisa,
    'pts': redeemPoints,
    'worth': redeemValue.inPaisa,
    'months': expiryMonths,
    'cap': maxBillBp,
  };

  static LoyaltyRule? fromJson(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final from = raw['from'];
    final at = raw['at'] ?? 0;
    final on = raw['on'];
    final earn = raw['earn'];
    final per = raw['per'];
    final pts = raw['pts'];
    final worth = raw['worth'];
    final months = raw['months'] ?? 0;
    final cap = raw['cap'] ?? 10000;
    if (from is! String ||
        at is! int ||
        on is! int ||
        earn is! int ||
        per is! int ||
        pts is! int ||
        worth is! int ||
        months is! int ||
        cap is! int) {
      return null;
    }
    return LoyaltyRule(
      from: from,
      atUtc: at,
      isOn: on == 1,
      earnPoints: earn,
      earnPer: Money.paisa(per),
      redeemPoints: pts,
      redeemValue: Money.paisa(worth),
      expiryMonths: months,
      maxBillBp: cap,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LoyaltyRule &&
      other.from == from &&
      other.atUtc == atUtc &&
      other.isOn == isOn &&
      other.earnPoints == earnPoints &&
      other.earnPer == earnPer &&
      other.redeemPoints == redeemPoints &&
      other.redeemValue == redeemValue &&
      other.expiryMonths == expiryMonths &&
      other.maxBillBp == maxBillBp;

  @override
  int get hashCode => Object.hash(
    from,
    atUtc,
    isOn,
    earnPoints,
    earnPer,
    redeemPoints,
    redeemValue,
    expiryMonths,
    maxBillBp,
  );
}

/// Every version of the shop's rule, oldest first.
final class LoyaltyRules {
  const LoyaltyRules([this.versions = const []]);

  static const none = LoyaltyRules();

  final List<LoyaltyRule> versions;

  /// Whether the shop has ever given points.
  bool get isEmpty => versions.isEmpty;

  /// The version in force at [utcMillis], or null before the first.
  LoyaltyRule? ruleAt(int utcMillis) {
    LoyaltyRule? found;
    for (final v in versions) {
      if (v.beganUtc <= utcMillis) found = v;
    }
    return found;
  }

  /// The last version made on or before [date] (`YYYY-MM-DD`): what a bill
  /// of that day whose moment is not known is counted by.
  LoyaltyRule? ruleOn(String date) {
    LoyaltyRule? found;
    for (final v in versions) {
      if (v.from.compareTo(date) <= 0) found = v;
    }
    return found;
  }

  /// [bill]'s version: the one in force when it was posted.
  LoyaltyRule? ruleFor(LoyaltyBill bill) =>
      bill.postedAtUtc > 0 ? ruleAt(bill.postedAtUtc) : ruleOn(bill.date);

  /// The version in force now: the last made.
  LoyaltyRule? get current => versions.isEmpty ? null : versions.last;

  /// The rules with [rule] in force from its moment. A version made later
  /// than it (a phone whose clock ran ahead) gives way to it.
  LoyaltyRules withVersion(LoyaltyRule rule) => LoyaltyRules([
    for (final v in versions)
      if (v.beganUtc < rule.beganUtc) v,
    rule,
  ]);

  /// Integers and strings only, as every number the books keep.
  String toJson() => jsonEncode({
    'versions': [for (final v in versions) v.toJson()],
  });

  /// What a settings row holds, or no rules for anything it cannot read —
  /// a rule nobody can read is a scheme the shop does not run.
  static LoyaltyRules fromJson(String? source) {
    if (source == null || source.trim().isEmpty) return none;
    try {
      final root = jsonDecode(source);
      if (root is! Map<String, Object?>) return none;
      final raw = root['versions'];
      if (raw is! List) return none;
      final versions = <LoyaltyRule>[
        for (final r in raw) ?LoyaltyRule.fromJson(r),
      ]..sort((a, b) => a.beganUtc.compareTo(b.beganUtc));
      return LoyaltyRules(versions);
    } on FormatException {
      return none;
    }
  }
}

/// Points used on one bill, as the counter asks for them and the bill keeps
/// them.
final class LoyaltyRedemption {
  const LoyaltyRedemption({
    required this.partyId,
    required this.points,
    required this.value,
  });

  /// Whose points.
  final String partyId;

  final int points;

  /// What they took off the bill, part of its bill discount.
  final Money value;

  Map<String, Object?> toMap({String? date}) => {
    'party': partyId,
    'points': points,
    'paisa': value.inPaisa,
    'date': ?date,
  };

  String toJson({String? date}) => jsonEncode(toMap(date: date));

  static LoyaltyRedemption? fromJson(String? source) {
    if (source == null || source.trim().isEmpty) return null;
    try {
      return fromMap(jsonDecode(source));
    } on FormatException {
      return null;
    }
  }

  static LoyaltyRedemption? fromMap(Object? raw) {
    if (raw is! Map<String, Object?>) return null;
    final party = raw['party'];
    final points = raw['points'];
    final paisa = raw['paisa'];
    if (party is! String || points is! int || paisa is! int) return null;
    return LoyaltyRedemption(
      partyId: party,
      points: points,
      value: Money.paisa(paisa),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LoyaltyRedemption &&
      other.partyId == partyId &&
      other.points == points &&
      other.value == value;

  @override
  int get hashCode => Object.hash(partyId, points, value);
}

/// One sale bill of one customer, as the books stand: what loyalty is
/// worked out from.
final class LoyaltyBill {
  const LoyaltyBill({
    required this.documentId,
    required this.docNo,
    required this.date,
    required this.total,
    this.goods = Money.zero,
    this.paid = Money.zero,
    this.returned = Money.zero,
    this.returnedGoods = Money.zero,
    this.redeemedPoints = 0,
    this.redeemedValue = Money.zero,
    this.isVoid = false,
    this.postedAtUtc = 0,
  });

  final String documentId;
  final String docNo;

  /// The bill's day, `YYYY-MM-DD`.
  final String date;

  /// What the bill came to.
  final Money total;

  /// Its goods at their rates, before any discount: what a return's share
  /// of the bill is measured against, so a bill paid wholly in points still
  /// has a size.
  final Money goods;

  /// The money that came in against it and stayed: cleared payments, not
  /// adjustments, not a cheque still in hand.
  final Money paid;

  /// What came back off it: the returns' totals, and their goods at rate.
  final Money returned;
  final Money returnedGoods;

  /// The points spent on it, and what they took off.
  final int redeemedPoints;
  final Money redeemedValue;

  /// Cancelled.
  final bool isVoid;

  /// When it was posted, in UTC milliseconds: which version of the rule it
  /// earns by, and the order of two bills of one day. 0 when not known.
  final int postedAtUtc;

  /// What the customer kept of the bill, in money.
  Money get kept {
    final k = total - returned;
    return k.isNegative ? Money.zero : k;
  }

  /// What earns: the money paid, up to what was kept.
  Money get earning {
    if (isVoid) return Money.zero;
    final p = paid.isNegative ? Money.zero : paid;
    return p < kept ? p : kept;
  }

  /// The points this bill earned, by [rules].
  int earnedBy(LoyaltyRules rules) =>
      isVoid ? 0 : rules.ruleFor(this)?.pointsFor(earning) ?? 0;

  /// The points this bill will have earned once it is paid in full.
  int earnsWhenPaid(LoyaltyRules rules) =>
      isVoid ? 0 : rules.ruleFor(this)?.pointsFor(kept) ?? 0;

  /// The points spent on it that stay spent: none on a cancelled bill, and
  /// less the share of the goods that came back.
  int get spent {
    if (isVoid || redeemedPoints <= 0) return 0;
    if (!returnedGoods.isPositive || !goods.isPositive) return redeemedPoints;
    final back = returnedGoods >= goods
        ? redeemedPoints
        : redeemedPoints * returnedGoods.inPaisa ~/ goods.inPaisa;
    return redeemedPoints - back;
  }
}

/// A customer's points as the books stand.
final class LoyaltyStanding {
  const LoyaltyStanding({
    this.earned = 0,
    this.redeemed = 0,
    this.expired = 0,
    this.outstanding = 0,
    this.redeemedValue = Money.zero,
    this.expiringNext,
    this.lastBill,
  });

  static const nothing = LoyaltyStanding();

  /// Every point earned, less what returns and cancellations took back.
  final int earned;

  /// Every point spent and still spent.
  final int redeemed;

  /// What it took off bills.
  final Money redeemedValue;

  /// Points that lived out their months unused.
  final int expired;

  /// What they hold now. Below nought only when two counters apart spent
  /// the same points; the next points earned make it good.
  final int outstanding;

  /// The next points to expire, and the day, while any will.
  final ({int points, String on})? expiringNext;

  /// The day of their last bill that counts.
  final String? lastBill;
}

/// [bills] of one customer as [rules] count them, on [today] (`YYYY-MM-DD`).
///
/// Points are used oldest first, so what expires is what nobody used: each
/// bill's points are a lot dated by the bill, living the months its day's
/// version gave them; each bill's spent points are taken from the oldest
/// lots alive that day, before the bill's own points arrive (the counter
/// takes them before the money). Every figure of a bill is counted on the
/// bill's own day, as it stands today — a return a week later reduces that
/// bill's points, rather than being an event of its own.
LoyaltyStanding loyaltyStanding(
  LoyaltyRules rules,
  Iterable<LoyaltyBill> bills, {
  required String today,
}) {
  final ordered = [
    for (final b in bills)
      if (b.date.compareTo(today) <= 0) b,
  ]..sort(_byDay);
  if (ordered.isEmpty) return LoyaltyStanding.nothing;

  final lots = <_Lot>[];
  var earned = 0;
  var redeemed = 0;
  var redeemedValue = Money.zero;
  var expired = 0;
  var owing = 0;
  String? lastBill;

  void expireTo(String day) {
    for (final lot in lots) {
      final ends = lot.expires;
      if (ends != null && lot.left > 0 && ends.compareTo(day) <= 0) {
        expired += lot.left;
        lot.left = 0;
      }
    }
  }

  for (final b in ordered) {
    if (b.isVoid) continue;
    lastBill = b.date;
    expireTo(b.date);

    var spend = b.spent;
    if (spend > 0) {
      redeemed += spend;
      // What the points that stayed spent took off, in the share they did.
      redeemedValue += b.redeemedPoints <= 0
          ? Money.zero
          : Money.paisa(b.redeemedValue.inPaisa * spend ~/ b.redeemedPoints);
      for (final lot in lots) {
        if (spend == 0) break;
        final take = lot.left < spend ? lot.left : spend;
        lot.left -= take;
        spend -= take;
      }
      owing += spend;
    }

    var gain = b.earnedBy(rules);
    if (gain > 0) {
      earned += gain;
      // Points spent that nobody held are made good from the next earned.
      final cover = owing < gain ? owing : gain;
      owing -= cover;
      gain -= cover;
      if (gain > 0) {
        final months = rules.ruleFor(b)?.expiryMonths ?? 0;
        lots.add(_Lot(gain, months > 0 ? addMonths(b.date, months) : null));
      }
    }
  }
  expireTo(today);

  final alive = [
    for (final lot in lots)
      if (lot.left > 0) lot,
  ];
  final dated = [
    for (final lot in alive)
      if (lot.expires != null) lot,
  ]..sort((a, b) => a.expires!.compareTo(b.expires!));
  ({int points, String on})? next;
  if (dated.isNotEmpty) {
    final on = dated.first.expires!;
    next = (
      points: dated
          .where((l) => l.expires == on)
          .fold<int>(0, (sum, l) => sum + l.left),
      on: on,
    );
  }

  return LoyaltyStanding(
    earned: earned,
    redeemed: redeemed,
    redeemedValue: redeemedValue,
    expired: expired,
    outstanding: alive.fold<int>(0, (sum, l) => sum + l.left) - owing,
    expiringNext: next,
    lastBill: lastBill,
  );
}

/// The standing as it was when [bill] was made: the bills up to and
/// including it, on its day — what its paper prints as the customer's total,
/// so a copy printed next month still says what the first one said.
LoyaltyStanding loyaltyStandingAt(
  LoyaltyRules rules,
  Iterable<LoyaltyBill> bills,
  LoyaltyBill bill,
) => loyaltyStanding(rules, [
  for (final b in bills)
    if (_byDay(b, bill) <= 0) b,
], today: bill.date);

int _byDay(LoyaltyBill a, LoyaltyBill b) {
  final byDate = a.date.compareTo(b.date);
  if (byDate != 0) return byDate;
  final byPosted = a.postedAtUtc.compareTo(b.postedAtUtc);
  return byPosted != 0 ? byPosted : a.docNo.compareTo(b.docNo);
}

final class _Lot {
  _Lot(this.left, this.expires);

  int left;

  /// The day it is gone, or null for never.
  final String? expires;
}

/// [date] (`YYYY-MM-DD`) [months] later, on the same day of the month or
/// the month's last where it has fewer days: 31 January and one month is
/// 28 or 29 February.
String addMonths(String date, int months) {
  final year = int.parse(date.substring(0, 4));
  final month = int.parse(date.substring(5, 7));
  final day = int.parse(date.substring(8, 10));
  final index = year * 12 + (month - 1) + months;
  final y = index ~/ 12;
  final m = index % 12 + 1;
  final last = DateTime.utc(y, m + 1, 0).day;
  final d = day > last ? last : day;
  return '${y.toString().padLeft(4, '0')}-'
      '${m.toString().padLeft(2, '0')}-'
      '${d.toString().padLeft(2, '0')}';
}
