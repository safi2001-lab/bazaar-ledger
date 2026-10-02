/// "Friday ko de dunga": a customer's promise to pay, kept on the khata
/// (M38).
///
/// CreditBook calls it the wasooli date and Zoho the expected payment date;
/// the shopkeeper calls it what the customer said at the counter, and until
/// now wrote it on the inside cover of the register or nowhere. The promise
/// is the thing the next conversation starts from — "aap ne Jumma kaha tha"
/// — so it lives on the khata, and the day it falls due it is on the first
/// screen of the morning.
///
/// ## Kept, broken, replaced: worked out, never typed
///
/// Nobody marks a promise kept. It is kept when the money came: receipts
/// from the day it was made to the day it was for, at least what was
/// promised (or anything, when no amount was named). It is broken when its
/// day has passed without that. It is replaced when the customer made a new
/// one before it fell due — "Jumma nahi, agle mahine ki pehli". Each of
/// these is read off the books and the calendar, so the record cannot be
/// left saying "pending" about a promise everyone knows was broken.
///
/// ## History is kept
///
/// A promise is never deleted. Withdrawing one (it was entered on the wrong
/// khata, or the shopkeeper misheard) marks it withdrawn and leaves it in
/// the list. A customer who has broken three promises is worth knowing
/// about before the fourth, and that is exactly what deleting would hide.
library;

import 'package:pk_money/pk_money.dart';

import '../time/clock.dart';

/// Where promises live in the shop's settings, one row per promise:
/// `promise.<partyId>.<promiseId>`.
///
/// One row each rather than one list per customer, so two counters taking
/// promises from the same customer on the same evening each write their
/// own row and neither is lost when the LAN sync merges them (M13) — a
/// list in one row would keep whichever counter wrote last.
const promiseKeyPrefix = 'promise.';

String promiseKey(String partyId, String promiseId) =>
    '$promiseKeyPrefix$partyId.$promiseId';

/// What the shopkeeper typed.
final class PromiseDraft {
  const PromiseDraft({
    required this.partyId,
    required this.promisedFor,
    this.amount,
    this.note,
  });

  final String partyId;

  /// The day they said, `YYYY-MM-DD`.
  final String promisedFor;

  /// How much they said, if they said. "Kuch de dunga" is a promise too.
  final Money? amount;

  /// Their words, or the shopkeeper's: "tankhwah par", "beta bhejega".
  final String? note;

  /// Why this cannot be recorded on [today], in words, or null when it can.
  String? problemOn(String today) {
    final day = BusinessDate.tryParse(promisedFor);
    if (day == null) return 'Pick the day they said they would pay.';
    // A promise is about a day still to come. One for yesterday is a
    // promise already broken, which is not something a customer makes.
    if (promisedFor.compareTo(today) < 0) {
      return 'A promise is for today or a day to come.';
    }
    final money = amount;
    if (money != null && !money.isPositive) {
      return 'An amount promised has to be more than nothing.';
    }
    return null;
  }

  Map<String, Object?> toJson({required String madeOn}) => {
    'party_id': partyId,
    'for': promisedFor,
    'amount_paisa': amount?.inPaisa,
    'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
    'made_on': madeOn,
  };
}

/// Where one promise stands.
enum PromiseStanding {
  /// Its day has not come.
  pending,

  /// Today is the day.
  dueToday,

  /// The money came, on or before the day.
  kept,

  /// The day passed without it.
  broken,

  /// The customer made a new promise before this one fell due.
  replaced,

  /// Taken off by the shop: entered wrongly, or misheard. Still listed.
  withdrawn;

  /// Still to be watched for: the one a khata and the home screen show.
  bool get isLive => this == pending || this == dueToday;
}

/// A promise as recorded, with what has come in since.
final class PaymentPromise {
  const PaymentPromise({
    required this.id,
    required this.partyId,
    required this.promisedFor,
    required this.madeOn,
    required this.madeBy,
    this.amount,
    this.note,
    this.withdrawnOn,
    this.paidSince = Money.zero,
    this.supersededOn,
    this.partyName = '',
  });

  /// Read back from its settings row. [id] is the row's key; [madeBy] the
  /// name of whoever recorded it; [paidSince] and [supersededOn] are
  /// worked out by the reader (see [PaymentPromise]).
  factory PaymentPromise.fromJson(
    String id,
    Map<String, Object?> json, {
    required String madeBy,
    Money paidSince = Money.zero,
    String? supersededOn,
    String partyName = '',
  }) {
    final paisa = json['amount_paisa'];
    return PaymentPromise(
      id: id,
      partyId: json['party_id'] as String? ?? '',
      promisedFor: json['for'] as String? ?? '',
      madeOn: json['made_on'] as String? ?? '',
      madeBy: madeBy,
      amount: paisa is int ? Money.paisa(paisa) : null,
      note: json['note'] as String?,
      withdrawnOn: json['withdrawn_on'] as String?,
      paidSince: paidSince,
      supersededOn: supersededOn,
      partyName: partyName,
    );
  }

  /// The settings row's key.
  final String id;
  final String partyId;
  final String partyName;
  final String promisedFor;
  final Money? amount;
  final String? note;

  /// The business day it was recorded, and by whom.
  final String madeOn;
  final String madeBy;

  /// The day the shop took it off, if it did.
  final String? withdrawnOn;

  /// Receipts from this customer dated from [madeOn] to [promisedFor]: the
  /// money that keeps the promise.
  final Money paidSince;

  /// The day the customer's next promise was made, if there is one.
  final String? supersededOn;

  bool get isWithdrawn => withdrawnOn != null;

  /// Where this promise stands on [today].
  PromiseStanding standingOn(String today) {
    if (isWithdrawn) return PromiseStanding.withdrawn;
    final promised = amount;
    final kept = promised == null
        ? paidSince.isPositive
        : paidSince >= promised;
    if (kept) return PromiseStanding.kept;
    // A new promise made before this one's day replaces it; one made after
    // the day had passed does not mend the one already broken.
    final next = supersededOn;
    if (next != null && next.compareTo(promisedFor) <= 0) {
      return PromiseStanding.replaced;
    }
    final order = today.compareTo(promisedFor);
    if (order < 0) return PromiseStanding.pending;
    if (order == 0) return PromiseStanding.dueToday;
    return PromiseStanding.broken;
  }
}

/// The days a shopkeeper is most often told, worked out from [today], so
/// the promise sheet offers them as one tap each.
///
/// Tomorrow; this coming Friday (Jumma — a week on, if today is Friday);
/// a week from today; and the first of next month, which is salary day for
/// the households whose khatas settle on it.
({String tomorrow, String friday, String nextWeek, String salaryDay})
promiseDays(String today) {
  final day = BusinessDate(today);
  final weekday = DateTime.utc(day.year, day.month, day.day).weekday;
  var toFriday = (DateTime.friday - weekday) % 7;
  if (toFriday == 0) toFriday = 7;
  final nextMonth = day.month == 12
      ? DateTime.utc(day.year + 1)
      : DateTime.utc(day.year, day.month + 1);
  return (
    tomorrow: day.addDays(1).value,
    friday: day.addDays(toFriday).value,
    nextWeek: day.addDays(7).value,
    salaryDay: BusinessDate.fromUtc(nextMonth, Duration.zero).value,
  );
}
