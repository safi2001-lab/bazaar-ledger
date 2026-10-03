/// Who may take more on udhaar, and who has had enough (M68).
///
/// A wholesaler does not run a khata on one number. Marg ERP's credit
/// control, which the research found every wholesale counter in Lahore's
/// markets has heard of, holds a customer to three things at once: how much
/// they may owe, how many bills they may leave open, and how old the oldest
/// unpaid bill may be. Zoho adds the choice of a warning or a refusal for
/// each, and a limit raised for a season that falls back by itself.
///
/// Five rules, each read off the books as they stand:
///
///  * **Amount** -- the credit limit the party form has carried since M3.
///    Over it, the counter says so (a warning) or refuses the udhaar (a
///    block). A **temporary limit** ("Rs 50,000 till Friday") stands in for
///    it until its day has passed, and then lapses by itself: nothing has
///    to be remembered or undone.
///  * **Open bills** -- "no more than three bills on udhaar".
///  * **Days** -- "nothing older than thirty days unpaid". Measured from
///    the bill's own date, as a shopkeeper counts it, not from its due date.
///  * **A bounced cheque** (M6) still owed: udhaar, or another cheque, which
///    is only credit with a date on it, is asked about or refused until the
///    customer has made it good.
///
/// Each rule a customer has no word on takes the shop's own (Settings), and
/// a shop that sets nothing behaves as it did before M68: a warning over the
/// limit and a warning after a bounce, no limit on bills or days.
///
/// A block refuses udhaar only. Cash, a card or a wallet are never refused:
/// the money is in the drawer. The owner may let one bill past a block with
/// their PIN and a reason, and the books keep who and why.
library;

import 'dart:convert';

import 'package:pk_money/pk_money.dart';

import '../receivables/aging.dart' show daysBetween;
import '../time/clock.dart';

/// The settings key the shop's own rules are kept under, as JSON.
const creditDefaultsSetting = 'credit.defaults';

/// The settings key prefix a customer's own rules are kept under:
/// `credit.party.<partyId>`, one row per customer, so two counters setting
/// two customers' rules the same evening each keep theirs.
const partyCreditKeyPrefix = 'credit.party.';

/// The audit code for the shop's rules changed.
const creditDefaultsSetAction = 'CREDIT_DEFAULTS_SET';

/// The audit code for one customer's rules changed.
const partyCreditSetAction = 'CREDIT_RULES_SET';

/// The audit code left when a bill went past a rule set to warn: the
/// cashier saw it and gave the udhaar anyway. Not a refusal, so no PIN; the
/// owner reads it in the activity log.
const creditWarningPassedAction = 'CREDIT_WARNING_PASSED';

/// The audit code left when the owner let one bill past a rule set to block.
const creditOverrideAction = 'CREDIT_RULE_OVERRIDDEN';

/// What a rule does when it bites.
enum CreditMode {
  /// Nothing; the rule is not kept.
  off,

  /// The counter says so, and the cashier may go on.
  warn,

  /// Udhaar is refused unless the owner lets this one bill past.
  block;

  /// [code] as stored, or null when it is not one this app knows.
  static CreditMode? parse(Object? code) {
    for (final m in values) {
      if (m.name == code) return m;
    }
    return null;
  }
}

/// The rules of the shop, for every customer who has none of their own.
final class CreditDefaults {
  const CreditDefaults({
    this.limitMode = CreditMode.warn,
    this.maxOpenBills,
    this.billsMode = CreditMode.warn,
    this.maxDays,
    this.daysMode = CreditMode.warn,
    this.bounceMode = CreditMode.warn,
  });

  /// What a shop that never opened these settings gets: the limit and a
  /// bounce each a warning, as the counter has said since M3 and M6.
  static const standard = CreditDefaults();

  /// What going over a customer's credit limit does.
  final CreditMode limitMode;

  /// The most bills a customer may leave owing, or null for no such rule.
  final int? maxOpenBills;
  final CreditMode billsMode;

  /// The oldest a bill may be and still be owed, in days, or null.
  final int? maxDays;
  final CreditMode daysMode;

  /// What a bounced cheque still owed does.
  final CreditMode bounceMode;

  String toJson() => jsonEncode({
    'limit': limitMode.name,
    'bills': ?maxOpenBills,
    'billsMode': billsMode.name,
    'days': ?maxDays,
    'daysMode': daysMode.name,
    'bounce': bounceMode.name,
  });

  /// Read back from [text]; anything missing or unreadable is the standard.
  static CreditDefaults fromJson(String? text) {
    final map = _map(text);
    if (map == null) return standard;
    return CreditDefaults(
      limitMode: CreditMode.parse(map['limit']) ?? standard.limitMode,
      maxOpenBills: _count(map['bills']),
      billsMode: CreditMode.parse(map['billsMode']) ?? CreditMode.warn,
      maxDays: _count(map['days']),
      daysMode: CreditMode.parse(map['daysMode']) ?? CreditMode.warn,
      bounceMode: CreditMode.parse(map['bounce']) ?? standard.bounceMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CreditDefaults && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

/// One customer's own rules. Every field left null takes the shop's.
///
/// The amount itself is not here: it is the credit limit on the party row,
/// where it has been since M3, and the form that sets it is the one the
/// shopkeeper already knows.
final class PartyCreditRules {
  const PartyCreditRules({
    this.limitMode,
    this.maxOpenBills,
    this.billsMode,
    this.maxDays,
    this.daysMode,
    this.bounceMode,
    this.tempLimit,
    this.tempUntil,
    this.noBillsRule = false,
    this.noDaysRule = false,
  });

  /// Nothing of their own: the shop's rules throughout.
  static const none = PartyCreditRules();

  final CreditMode? limitMode;
  final int? maxOpenBills;
  final CreditMode? billsMode;
  final int? maxDays;
  final CreditMode? daysMode;
  final CreditMode? bounceMode;

  /// A limit raised (or lowered) for a while, and the last day it stands.
  /// Both or neither.
  final Money? tempLimit;
  final BusinessDate? tempUntil;

  /// This customer is held to no count of bills, whatever the shop's rule.
  final bool noBillsRule;

  /// This customer is held to no age of bills, whatever the shop's rule.
  final bool noDaysRule;

  bool get isNone => toJson() == none.toJson();

  /// The temporary limit, while its day has not passed.
  Money? tempLimitOn(BusinessDate today) {
    final until = tempUntil;
    final limit = tempLimit;
    if (until == null || limit == null) return null;
    return today.value.compareTo(until.value) <= 0 ? limit : null;
  }

  /// Whether a temporary limit was set and its day has gone by.
  bool tempLapsedOn(BusinessDate today) =>
      tempUntil != null &&
      tempLimit != null &&
      today.value.compareTo(tempUntil!.value) > 0;

  String toJson() => jsonEncode({
    'limit': ?limitMode?.name,
    'bills': ?maxOpenBills,
    'billsMode': ?billsMode?.name,
    'days': ?maxDays,
    'daysMode': ?daysMode?.name,
    'bounce': ?bounceMode?.name,
    'temp': ?tempLimit?.inPaisa,
    'tempUntil': ?tempUntil?.value,
    if (noBillsRule) 'noBills': true,
    if (noDaysRule) 'noDays': true,
  });

  static PartyCreditRules fromJson(String? text) {
    final map = _map(text);
    if (map == null) return none;
    final temp = map['temp'];
    final until = map['tempUntil'];
    final untilDate = until is String ? BusinessDate.tryParse(until) : null;
    final hasTemp = temp is int && untilDate != null;
    return PartyCreditRules(
      limitMode: CreditMode.parse(map['limit']),
      maxOpenBills: _count(map['bills']),
      billsMode: CreditMode.parse(map['billsMode']),
      maxDays: _count(map['days']),
      daysMode: CreditMode.parse(map['daysMode']),
      bounceMode: CreditMode.parse(map['bounce']),
      tempLimit: hasTemp ? Money.paisa(temp) : null,
      tempUntil: hasTemp ? untilDate : null,
      noBillsRule: map['noBills'] == true,
      noDaysRule: map['noDays'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PartyCreditRules && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

/// The rules that bind one customer today: theirs over the shop's, and a
/// temporary limit over the permanent one while it stands.
final class CreditPolicy {
  const CreditPolicy({
    this.limit,
    this.limitIsTemporary = false,
    this.tempUntil,
    this.limitMode = CreditMode.warn,
    this.maxOpenBills,
    this.billsMode = CreditMode.warn,
    this.maxDays,
    this.daysMode = CreditMode.warn,
    this.bounceMode = CreditMode.warn,
  });

  factory CreditPolicy.of({
    required Money? partyLimit,
    required PartyCreditRules own,
    required CreditDefaults shop,
    required BusinessDate today,
  }) {
    final temp = own.tempLimitOn(today);
    return CreditPolicy(
      limit: temp ?? partyLimit,
      limitIsTemporary: temp != null,
      tempUntil: temp == null ? null : own.tempUntil,
      limitMode: own.limitMode ?? shop.limitMode,
      maxOpenBills: own.noBillsRule
          ? null
          : own.maxOpenBills ?? shop.maxOpenBills,
      billsMode: own.billsMode ?? shop.billsMode,
      maxDays: own.noDaysRule ? null : own.maxDays ?? shop.maxDays,
      daysMode: own.daysMode ?? shop.daysMode,
      bounceMode: own.bounceMode ?? shop.bounceMode,
    );
  }

  /// The amount they may owe, or null for no limit.
  final Money? limit;

  /// Whether [limit] is a temporary one, standing until [tempUntil].
  final bool limitIsTemporary;
  final BusinessDate? tempUntil;
  final CreditMode limitMode;
  final int? maxOpenBills;
  final CreditMode billsMode;
  final int? maxDays;
  final CreditMode daysMode;
  final CreditMode bounceMode;
}

/// What the books say about one customer, as far as credit is concerned.
final class CreditStanding {
  const CreditStanding({
    required this.balance,
    this.openBills = 0,
    this.oldestOpenBill,
    this.bouncedCheques = 0,
  });

  /// What they owe overall, after what the shop is holding for them (the
  /// khata's own figure, `PartySummary.balance`).
  final Money balance;

  /// Their sale bills with something still owed on them.
  final int openBills;

  /// The date of the oldest of those, or null when none is owed.
  final BusinessDate? oldestOpenBill;

  /// Cheques of theirs the bank sent back, ever.
  final int bouncedCheques;

  /// A cheque bounced and they still owe: M6's `hasUnsettledBounce`.
  bool get unsettledBounce => bouncedCheques > 0 && balance.isPositive;

  /// The same customer with one more bill leaving [owed] on the khata.
  CreditStanding withBill(Money owed, BusinessDate today) => CreditStanding(
    balance: balance + owed,
    openBills: owed.isPositive ? openBills + 1 : openBills,
    oldestOpenBill: oldestOpenBill ?? (owed.isPositive ? today : null),
    bouncedCheques: bouncedCheques,
  );
}

/// Which rule.
enum CreditRule { limit, bills, days, bounce }

/// One rule a bill would break, and the figures that show it.
final class CreditBreach {
  const CreditBreach.limit({
    required this.mode,
    required Money this.limit,
    required Money this.after,
    this.temporary = false,
    this.tempUntil,
  }) : rule = CreditRule.limit,
       count = null,
       most = null,
       bounced = null,
       owed = null;

  const CreditBreach.bills({
    required this.mode,
    required int this.count,
    required int this.most,
  }) : rule = CreditRule.bills,
       limit = null,
       after = null,
       temporary = false,
       tempUntil = null,
       bounced = null,
       owed = null;

  const CreditBreach.days({
    required this.mode,
    required int this.count,
    required int this.most,
  }) : rule = CreditRule.days,
       limit = null,
       after = null,
       temporary = false,
       tempUntil = null,
       bounced = null,
       owed = null;

  const CreditBreach.bounce({
    required this.mode,
    required int this.bounced,
    required Money this.owed,
  }) : rule = CreditRule.bounce,
       limit = null,
       after = null,
       temporary = false,
       tempUntil = null,
       count = null,
       most = null;

  final CreditRule rule;

  /// [CreditMode.warn] or [CreditMode.block]; never off.
  final CreditMode mode;

  /// The limit, and where this bill would take what they owe.
  final Money? limit;
  final Money? after;

  /// Whether [limit] is a temporary one, and the last day it stands.
  final bool temporary;
  final BusinessDate? tempUntil;

  /// Open bills with this one, or the age in days of the oldest owed.
  final int? count;

  /// The most bills, or the most days, the rule allows.
  final int? most;

  /// Cheques bounced, and what is still owed.
  final int? bounced;
  final Money? owed;

  bool get blocks => mode == CreditMode.block;

  /// The rule in English, for the activity log and a refusal with no
  /// screen to say it in the shop's language.
  String get words => switch (rule) {
    CreditRule.limit =>
      'over the ${temporary ? 'temporary ' : ''}credit limit of Rs '
          '${limit!.amountOnly} (would owe Rs ${after!.amountOnly})',
    CreditRule.bills => '$count bills on udhaar, at most $most',
    CreditRule.days => 'a bill $count days old unpaid, at most $most days',
    CreditRule.bounce =>
      '$bounced cheque(s) bounced and Rs ${owed!.amountOnly} still owed',
  };
}

/// Every rule a bill would break, warnings and blocks together.
final class CreditVerdict {
  const CreditVerdict(this.breaches);

  static const clear = CreditVerdict([]);

  final List<CreditBreach> breaches;

  bool get isClear => breaches.isEmpty;

  /// Whether any rule refuses the udhaar outright.
  bool get blocks => breaches.any((b) => b.blocks);

  List<CreditBreach> get blocking => [
    for (final b in breaches)
      if (b.blocks) b,
  ];

  CreditBreach? of(CreditRule rule) =>
      breaches.where((b) => b.rule == rule).firstOrNull;

  /// The rules in English, `; ` apart.
  String words([Iterable<CreditBreach>? which]) =>
      (which ?? breaches).map((b) => b.words).join('; ');
}

/// Judges one bill against [policy].
///
/// [before] is the customer as the books stood before this bill; [after]
/// is the same customer with it. At the counter [after] is
/// `before.withBill(...)`; at the service, beneath the screen, it is read
/// back off the books inside the bill's own transaction, so the figure a
/// second till has just changed is the figure judged.
///
/// [givesCredit] is whether the bill leaves anything owed after whatever
/// the shop was already holding for it; [byCheque] whether it is paid by a
/// cheque. Only a bounced cheque speaks to a cheque; the other rules are
/// about udhaar, and a bill that leaves nothing owed answers to none of
/// them.
CreditVerdict judgeCredit({
  required CreditPolicy policy,
  required CreditStanding before,
  required CreditStanding after,
  required BusinessDate today,
  required bool givesCredit,
  bool byCheque = false,
}) {
  final out = <CreditBreach>[];
  if (givesCredit) {
    final limit = policy.limit;
    if (policy.limitMode != CreditMode.off &&
        limit != null &&
        after.balance > limit) {
      out.add(
        CreditBreach.limit(
          mode: policy.limitMode,
          limit: limit,
          after: after.balance,
          temporary: policy.limitIsTemporary,
          tempUntil: policy.tempUntil,
        ),
      );
    }
    final most = policy.maxOpenBills;
    if (policy.billsMode != CreditMode.off &&
        most != null &&
        after.openBills > most) {
      out.add(
        CreditBreach.bills(
          mode: policy.billsMode,
          count: after.openBills,
          most: most,
        ),
      );
    }
    final days = policy.maxDays;
    final oldest = before.oldestOpenBill;
    if (policy.daysMode != CreditMode.off && days != null && oldest != null) {
      final age = daysBetween(oldest.value, today.value);
      if (age > days) {
        out.add(
          CreditBreach.days(mode: policy.daysMode, count: age, most: days),
        );
      }
    }
  }
  if ((givesCredit || byCheque) &&
      policy.bounceMode != CreditMode.off &&
      before.unsettledBounce) {
    out.add(
      CreditBreach.bounce(
        mode: policy.bounceMode,
        bounced: before.bouncedCheques,
        owed: before.balance,
      ),
    );
  }
  return CreditVerdict(out);
}

Map<String, Object?>? _map(String? text) {
  if (text == null || text.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

int? _count(Object? value) => value is int && value >= 0 ? value : null;
