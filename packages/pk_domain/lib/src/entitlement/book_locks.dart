/// What the owner has closed, and the PIN that stands in front of undoing
/// anything (M42).
///
/// Two locks, both the owner's to set and both kept in `settings`, so they
/// travel to every counter with the rest of the books and bind there too:
///
/// * **The books closed up to a date.** Once the owner has counted the
///   drawer, handed the accountant the month and filed the return, the
///   figures for those days are what the shop told somebody. A bill keyed in
///   afterwards with last Tuesday's date, or last Tuesday's bill cancelled
///   today, changes a total that has already left the shop. Tally calls it a
///   period lock, Zoho a lock date, Marg a freeze. Anything dated on or
///   before the date is refused in words; the owner can still let one in,
///   with their PIN and a reason, and that act is itself kept.
///
/// * **Data Lock.** Khatabook's most-asked-for setting: a PIN before
///   anything is cancelled, written off, hidden or restored over. One phone
///   at the counter is used by the owner, the son and the boy who carries
///   sacks; the app being open as the owner must not mean anybody can
///   cancel the owner's bills.
///
/// Neither lock is a screen rule. Both are checked by the one write path
/// (`TxRunner`) as the rows are written, so a button somebody forgot to
/// hide, a deep link, an import or a counter on an older screen meets the
/// same refusal.
library;

import '../time/clock.dart';
import 'staff.dart';

/// The settings key the closing date is kept under, as `YYYY-MM-DD`.
const booksClosedThroughSetting = 'books.closed_through';

/// The settings key Data Lock is kept under, `1` when it is on.
const dataLockSetting = 'books.data_lock';

/// The audit code written when the owner closes the books up to a date, or
/// moves the date on. Its `after_json` carries `closed_through`, which is
/// how an entry that arrived from a counter afterwards is found.
const booksClosedAction = 'BOOKS_CLOSED';

/// The audit code written when the owner moves the date back, or clears it.
const booksReopenedAction = 'BOOKS_REOPENED';

/// The audit code written when the owner lets an entry into closed books.
const closedBooksOverrideAction = 'CLOSED_BOOKS_OVERRIDDEN';

/// The audit code written when a PIN was given for something Data Lock
/// guards, naming whose PIN it was.
const dataLockPinAction = 'DATA_LOCK_PIN_GIVEN';

/// The audit codes for turning Data Lock on and off.
const dataLockOnAction = 'DATA_LOCK_ON';
const dataLockOffAction = 'DATA_LOCK_OFF';

/// The audit codes that undo, take back or hide something already made.
///
/// Data Lock asks for a PIN before a transaction carrying any of these is
/// allowed to commit. Matched on the audit code rather than on the screen
/// that asked, because every one of these acts already leaves exactly one
/// of these rows inside its own transaction — the trail is the one thing
/// none of them can skip, which makes it the one place a check cannot be
/// walked round.
///
/// A return is not here: goods coming back today is a new event, dated
/// today, not an old one undone. Nor is a settlement discount, which is
/// given at the counter within the role's own ceiling (M44).
const undoingActions = <String>{
  // A bill, a challan, a charge or an expense cancelled.
  'DOCUMENT_VOIDED',
  // A payment taken back (M31), or a write-off taken back.
  'PAYMENT_VOIDED',
  // An entry replaced by a corrected one (M31).
  'PAYMENT_EDITED',
  'CHARGE_EDITED',
  'EXPENSE_EDITED',
  'OPENING_BALANCE_CORRECTED',
  // Udhaar given up on (M44).
  'BAD_DEBT_WRITTEN_OFF',
  // An item or a customer hidden.
  'ITEM_ARCHIVED',
  'PARTY_ARCHIVED',
  // Everything else that puts something in the recycle bin (M60): an
  // expense head or a head of income no longer offered, a member of staff
  // switched off, a van or a recipe put away, and a photograph taken off an
  // entry — the supplier's bill a counter boy would most like gone. Spelt
  // out rather than imported from the bin's own list, so this stays the one
  // place every guarded code can be read.
  'EXPENSE_HEAD_HIDDEN',
  'INCOME_HEAD_HIDDEN',
  'USER_DEACTIVATED',
  'VAN_HIDDEN',
  'RECIPE_HIDDEN',
  'ATTACHMENT_REMOVED',
  // A loan entry cancelled (M48).
  'LOAN_ENTRY_CANCELLED',
  // The locks themselves: reopening closed books, or turning the PIN off,
  // is the first thing anybody who meant harm would do.
  booksReopenedAction,
  dataLockOffAction,
};

/// The two locks as the books hold them now.
final class BookLocks {
  const BookLocks({this.closedThrough, this.dataLock = false});

  /// Nothing closed, no PIN asked.
  static const none = BookLocks();

  /// The last day whose books are closed, or null when none are.
  final BusinessDate? closedThrough;

  /// Whether a PIN is asked before anything is undone.
  final bool dataLock;

  /// Whether an entry dated [dateLocal] would land inside closed books.
  bool closes(String dateLocal) {
    final through = closedThrough;
    return through != null && dateLocal.compareTo(through.value) <= 0;
  }
}

/// Which lock is asking.
enum ApprovalKind {
  /// Something dated inside closed books. Only the owner may let it in,
  /// with their PIN and a reason.
  closedBooks,

  /// Something Data Lock guards: a cancel, a write-off, a hidden customer.
  dataLock,
}

/// A write the books would not make without somebody's PIN.
///
/// Thrown by the write path, inside the transaction, which then rolls back
/// whole. Its message is the refusal in words, for a screen that has no
/// way to ask for a PIN; the app's own screens ask, and try again.
final class ApprovalNeeded implements Exception {
  const ApprovalNeeded.closedBooks({
    required String this.closedThrough,
    required String this.dateLocal,
    required this.what,
    required this.actorUserId,
  }) : kind = ApprovalKind.closedBooks;

  const ApprovalNeeded.dataLock({required this.what, required this.actorUserId})
    : kind = ApprovalKind.dataLock,
      closedThrough = null,
      dateLocal = null;

  final ApprovalKind kind;

  /// The last closed day, for [ApprovalKind.closedBooks].
  final String? closedThrough;

  /// The date of the entry that would land inside them.
  final String? dateLocal;

  /// What was being done, in a few words: "a sale bill", "INV-0007
  /// cancelled: customer changed his mind".
  final String what;

  /// Who was doing it. Data Lock accepts their own PIN, or the owner's.
  final String actorUserId;

  @override
  String toString() => switch (kind) {
    ApprovalKind.closedBooks =>
      'The books are closed up to $closedThrough. $what, dated $dateLocal, '
          'falls inside them. Only the owner can let it in, with their PIN '
          'and a reason.',
    ApprovalKind.dataLock =>
      'Data Lock is on, so this needs a PIN first: $what. Nothing was '
          'changed.',
  };
}

/// Somebody's PIN, checked, standing behind one write.
///
/// Made only once the PIN has been verified against the stored hash. The
/// write path reads [kind] and [userName] into the audit row it leaves, so
/// the trail names who agreed as well as who did it.
final class Approval {
  const Approval({
    required this.kind,
    required this.userId,
    required this.userName,
    this.reason,
  });

  final ApprovalKind kind;
  final String userId;
  final String userName;

  /// Why, for [ApprovalKind.closedBooks]; never blank there.
  final String? reason;
}

/// Asks for, checks and returns an [Approval], or null when nobody gave one.
typedef Approver = Future<Approval?> Function(ApprovalNeeded needed);

/// What a screen is shown when a PIN is needed: what for, who may give it,
/// and why the last try failed.
final class ApprovalAsk {
  const ApprovalAsk({required this.needed, required this.people, this.problem});

  final ApprovalNeeded needed;

  /// Whose PIN is accepted: the owner, for closed books; for Data Lock the
  /// person signed in as well. Each says whether they have a PIN; in a shop
  /// where nobody has one, the owner's say-so and a reason are enough,
  /// because anybody at the phone already is the owner.
  final List<StaffMember> people;

  /// Why the last answer was refused, or null on the first ask. A reason
  /// rather than a sentence, so the prompt says it in the shop's language.
  final ApprovalProblem? problem;

  /// Whether a reason must be given.
  bool get needsReason => needed.kind == ApprovalKind.closedBooks;
}

/// Why an answer to an [ApprovalAsk] was refused.
enum ApprovalProblem {
  /// The PIN did not match.
  wrongPin,

  /// Five wrong PINs in a row: every PIN is refused for half a minute, as
  /// at sign-in.
  tooManyTries,

  /// Closed books were asked into without saying why.
  reasonNeeded,

  /// Somebody else in the shop has a PIN and the person chosen has none,
  /// so there is nothing to check that it is them.
  noPin,
}

/// What the person at the phone answered.
final class ApprovalAnswer {
  const ApprovalAnswer({required this.userId, this.pin = '', this.reason});

  final String userId;

  /// The digits as typed. Checked against the hash and dropped; never kept.
  final String pin;
  final String? reason;
}

/// Shows an [ApprovalAsk] and returns what was answered, or null when the
/// person backed out.
typedef ApprovalPrompt = Future<ApprovalAnswer?> Function(ApprovalAsk ask);
