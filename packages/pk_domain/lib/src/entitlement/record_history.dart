/// One record's story: who made it, who printed it, who changed it, who
/// cancelled it and why (M42).
///
/// Vyapar sells this as "View History" on its premium plan; Tally's Edit Log
/// and Zoho's version compare are its accountants' answer. A Pakistani shop
/// wants it for a plainer reason: the bill the customer is waving at the
/// counter says Rs 4,200 and the books say Rs 3,800, and the owner needs to
/// know which hand made the difference, when, and what it said at the time.
///
/// Read from what the books already keep. Every write since M0 has left an
/// audit row inside its own transaction; a print leaves its print job; a
/// return its link; a payment its allocation. Nothing here is written for
/// the history's sake, so nothing can be missing from it that happened.
library;

import 'package:pk_money/pk_money.dart';

/// Which record a history is asked of.
final class RecordRef {
  const RecordRef(this.table, this.id);

  /// A bill, a return, a charge, an expense — anything in `documents`.
  const RecordRef.document(this.id) : table = 'documents';

  /// A payment taken or made, a settlement discount, a write-off.
  const RecordRef.payment(this.id) : table = 'payments';

  /// A customer or supplier.
  const RecordRef.party(this.id) : table = 'parties';

  /// An item on the shelf.
  const RecordRef.item(this.id) : table = 'items';

  final String table;
  final String id;

  /// Whether a history can be read for [table] at all.
  static bool supports(String table) =>
      const {'documents', 'payments', 'parties', 'items'}.contains(table);

  @override
  bool operator ==(Object other) =>
      other is RecordRef && other.table == table && other.id == id;

  @override
  int get hashCode => Object.hash(table, id);
}

/// M54: how a paper left the phone from its send sheet (M30), as its
/// history says it: "Shared on WhatsApp · Asif · 3 Oct".
///
/// Written as an audit row on the paper the moment it leaves, so the owner
/// asking "did the customer ever get this bill?" reads who sent it, how and
/// when. Kept apart from a print: a share is never the second paper copy
/// that M30's DUPLICATE mark is about.
enum SharedVia {
  whatsapp,
  pdf,
  picture;

  /// The audit row's action code: `SHARED_WHATSAPP`, `SHARED_PDF`,
  /// `SHARED_PICTURE`.
  String get action => '$sharedActionPrefix${name.toUpperCase()}';

  /// What the audit row says, in the log's English.
  String get words => switch (this) {
    SharedVia.whatsapp => 'Shared on WhatsApp',
    SharedVia.pdf => 'Shared as a PDF',
    SharedVia.picture => 'Shared as a picture',
  };

  /// The way [action] names, or null for any other code.
  static SharedVia? ofAction(String action) {
    for (final v in values) {
      if (v.action == action) return v;
    }
    return null;
  }
}

/// Every [SharedVia] action starts with this.
const sharedActionPrefix = 'SHARED_';

/// What kind of thing happened, so a screen can mark it.
enum HistoryKind {
  /// Made: a bill posted, a customer added.
  created,

  /// Printed, or a print tried and failed.
  printed,

  /// Something about it changed: a field edited, a status moved.
  changed,

  /// Cancelled, hidden, written off.
  cancelled,

  /// Goods came back against it.
  returned,

  /// Money went against it.
  paid,

  /// Replaced by a corrected entry, or the correction of another.
  corrected,

  /// Let into closed books, or a PIN given for it.
  approved,

  /// Anything else the log kept.
  other,
}

/// One field, as it was and as it became. Raw values as the books keep
/// them; a screen turns `sale_rate_milli_paisa` into rupees and a name.
final class FieldChange {
  const FieldChange(this.field, this.before, this.after);

  final String field;
  final Object? before;
  final Object? after;
}

/// One line of a record's history.
final class HistoryEvent {
  const HistoryEvent({
    required this.atUtcMillis,
    required this.kind,
    required this.actionCode,
    required this.who,
    this.device,
    this.summary,
    this.amount,
    this.reason,
    this.changes = const [],
    this.linked,
    this.linkedLabel,
  });

  final int atUtcMillis;
  final HistoryKind kind;

  /// The audit code, or `PRINTED` / `PRINT_FAILED` for a print job.
  final String actionCode;

  /// Who did it, by name.
  final String who;

  /// Which phone or till it was done on.
  final String? device;

  /// The line the log wrote at the time, in English.
  final String? summary;
  final Money? amount;

  /// Why, where the act carried a reason: a cancel, a correction, an
  /// override of closed books.
  final String? reason;

  /// Field by field, where the log kept the before and the after.
  final List<FieldChange> changes;

  /// The other record this event ties to: the return, the receipt, the
  /// corrected entry, the bill a payment went against.
  final RecordRef? linked;

  /// That record's number, as the shop knows it.
  final String? linkedLabel;
}

/// An entry that reached this phone from a counter after the books for its
/// date had been closed here.
///
/// Accepted rather than refused. It was made on a till that had not yet
/// heard of the closing — offline, or not synced since — and refusing it
/// would leave the counter and the master disagreeing about money that
/// really moved. It is shown to the owner instead, who decides whether the
/// closed figures need a second look.
final class LateArrival {
  const LateArrival({
    required this.record,
    required this.number,
    required this.dateLocal,
    required this.arrivedAtUtcMillis,
    required this.device,
    this.amount,
  });

  final RecordRef record;
  final String number;
  final String dateLocal;
  final int arrivedAtUtcMillis;
  final String device;
  final Money? amount;
}

/// Where histories are read from.
abstract interface class RecordHistoryReads {
  /// Everything that happened to [record] and the records tied to it,
  /// oldest first.
  Future<List<HistoryEvent>> historyOf(String firmId, RecordRef record);

  /// Entries from other devices dated inside closed books that arrived
  /// after those books were closed, newest first.
  Future<List<LateArrival>> lateArrivals(String firmId);

  /// The business date of the last day close, or null when none was made.
  Future<String?> lastDayClosed(String firmId);
}
