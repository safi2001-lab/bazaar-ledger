/// The udhaar pack's reads and writes: due dates and promises (M38), and
/// reminders in each customer's language (M39).
///
/// Its own port rather than more methods on [AppQueries], so the khata's
/// chasing can grow without every other screen's reader growing with it,
/// and so a reports milestone can be handed exactly this to plug the
/// due-date ageing into its registry.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../receivables/allowance.dart';
import '../receivables/due_dates.dart';
import '../receivables/promise.dart';
import '../receivables/reminder_templates.dart';
import 'app_queries.dart';
import 'settlement_writer.dart';

/// A customer who owes, as the chase list needs them.
final class DueParty {
  const DueParty({
    required this.party,
    required this.openBills,
    required this.daysOverdue,
    required this.overdue,
    required this.dueToday,
    this.oldestDueLocal,
    this.promise,
    this.prefs = ReminderPrefs.standard,
    this.lastRemindedAt,
  });

  /// Who, and what they owe overall — the one balance the whole app uses,
  /// advances taken off.
  final PartySummary party;

  /// Bills still open. Zero for a customer whose only debt is an opening
  /// balance, listed here because they made a promise.
  final int openBills;

  /// The earliest due date among their open bills; null with none.
  final String? oldestDueLocal;

  /// How late that earliest one is: positive is overdue, zero due today,
  /// negative the days still to go.
  final int daysOverdue;

  /// Owed on bills already past their due date.
  final Money overdue;

  /// Owed on bills that fall due today.
  final Money dueToday;

  /// Their most recent promise, whatever became of it.
  final PaymentPromise? promise;

  /// The language their reminders go in, and whether they get any (M39).
  final ReminderPrefs prefs;

  /// When they were last sent a reminder, if ever (M39).
  final DateTime? lastRemindedAt;

  DueBucket get bucket => DueBucket.forDaysOverdue(daysOverdue);
  bool get isOverdue => overdue.isPositive;
  bool get hasDueToday => dueToday.isPositive;

  /// Their most recent promise if it is still to be watched for on [today].
  PaymentPromise? livePromiseOn(String today) {
    final p = promise;
    return p != null && p.standingOn(today).isLive ? p : null;
  }
}

/// The morning's udhaar, in three lines: what falls due today, what is
/// already late, and who said they would pay today.
final class UdhaarToday {
  const UdhaarToday({
    this.dueTodayCount = 0,
    this.dueToday = Money.zero,
    this.overdueCount = 0,
    this.overdue = Money.zero,
    this.promisedTodayCount = 0,
    this.promisedToday = Money.zero,
  });

  final int dueTodayCount;
  final Money dueToday;
  final int overdueCount;
  final Money overdue;
  final int promisedTodayCount;

  /// What those customers said they would bring; a promise with no amount
  /// counts what they owe.
  final Money promisedToday;

  bool get isQuiet =>
      dueTodayCount == 0 && overdueCount == 0 && promisedTodayCount == 0;

  static const UdhaarToday quiet = UdhaarToday();
}

/// One customer's reminder, ready to leave the phone (M39): their message,
/// written in their language from the shop's template, and the number
/// WhatsApp and the messages app can reach them on.
final class ReminderReady {
  const ReminderReady({
    required this.party,
    required this.message,
    required this.prefs,
    this.whatsappNumber,
  });

  final PartySummary party;
  final String message;
  final ReminderPrefs prefs;

  /// `923004471203`, or null when the khata has no Pakistani mobile.
  final String? whatsappNumber;
}

/// Why an udhaar write was refused, in words the counter can act on.
final class UdhaarRefused implements Exception {
  const UdhaarRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// What the khata, the chase list and the home screen read.
abstract interface class UdhaarQueries {
  /// One customer's open bills, oldest first, each with its due date.
  Future<List<BillDue>> billsDue(
    String firmId,
    String partyId, {
    required String asOfDateLocal,
  });

  /// Every open bill in the shop, bucketed by how late it is. The ageing a
  /// reports milestone can show beside the bill-age one.
  Future<DueAging> dueAging(String firmId, {required String asOfDateLocal});

  /// Every customer who owes, most overdue first, each with their latest
  /// promise. A customer in credit overall is never listed.
  Future<List<DueParty>> dueParties(
    String firmId, {
    required String asOfDateLocal,
  });

  /// One customer's promises, newest first, each knowing what has come in
  /// since it was made.
  Future<List<PaymentPromise>> promisesOf(String firmId, String partyId);

  /// The home screen's card.
  Future<UdhaarToday> udhaarToday(
    String firmId, {
    required String asOfDateLocal,
  });

  /// The owner's own words for [language], or null while the shop's
  /// defaults stand (M39).
  Future<String?> customReminderTemplate(
    String firmId,
    ReminderLanguage language,
  );

  /// One customer's reminder language and opt-out (M39).
  Future<ReminderPrefs> reminderPrefs(String firmId, String partyId);

  /// The reminders sent to one customer, newest first: who sent each, when,
  /// and how (M39).
  Future<List<ReminderSent>> remindersSent(
    String firmId,
    String partyId, {
    int limit = 20,
  });

  /// Every write-off (or settlement discount) in the shop, newest first,
  /// cancelled ones included and marked (M44): who, how much, why, and who
  /// let it go. The bad-debts list reads it, and a reports milestone can
  /// register it as the Bad Debts report, narrowed to a period.
  Future<List<AllowanceRow>> allowances(
    String firmId, {
    required AllowanceKind kind,
    String? fromDateLocal,
    String? toDateLocal,
  });
}

/// What the khata writes about chasing, through the one write path.
abstract interface class UdhaarStore {
  /// Records a promise to pay and returns its id.
  Future<String> recordPromise(ActorContext actor, PromiseDraft draft);

  /// Marks a promise withdrawn. It stays in the customer's history.
  Future<void> withdrawPromise(ActorContext actor, String promiseId);

  /// Keeps the owner's words for [language]. Empty text, or the shop's own
  /// default, puts the default back (M39).
  Future<void> saveReminderTemplate(
    ActorContext actor,
    ReminderLanguage language,
    String text,
  );

  /// Keeps one customer's reminder language and opt-out (M39).
  Future<void> setReminderPrefs(
    ActorContext actor,
    String partyId,
    ReminderPrefs prefs,
  );

  /// Writes a reminder into the khata's log: to whom, by which channel, in
  /// which language, for how much. Who and when are the actor (M39).
  Future<void> recordReminderSent(
    ActorContext actor,
    String partyId, {
    required ReminderChannel channel,
    required ReminderLanguage language,
    required Money amount,
  });
}
