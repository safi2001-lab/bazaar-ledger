import 'package:pk_money/pk_money.dart';

import '../corrections/opening_correction.dart';
import '../corrections/payment_void.dart';
import '../identity/actor_context.dart';
import '../sales/sale_posting_builder.dart';
import 'debit_note_writer.dart';
import 'expense_writer.dart';
import 'payment_writer.dart';
import 'void_writer.dart';

/// The persistence boundary for putting an entry right (M31).
///
/// One transaction, with every handle a correction needs on it. An edit is a
/// cancellation and a fresh entry, and the two have to commit together: an
/// edit that cancelled the old receipt and then failed to write the new one
/// would leave the customer owing money they paid, and one that wrote the
/// new one first would count the money twice until somebody noticed.
abstract interface class CorrectionWriter {
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(CorrectionWriteContext write) body,
  );
}

/// The handle a correction is written through.
abstract interface class CorrectionWriteContext {
  ActorContext get actor;

  Future<AllocatedNumber> nextNumber(String docType);

  /// The ordinary handles, on this same transaction, so the replacement for
  /// a cancelled entry is written by exactly the code that wrote the first
  /// one — the same allocation, the same checks, the same rows.
  VoidWriteContext get documents;
  PaymentWriteContext get payments;
  ExpenseWriteContext get expenses;
  DebitNoteWriteContext get charges;

  /// The payment as written, or null when there is no such payment.
  Future<PostedPaymentSnapshot?> paymentSnapshot(String paymentId);

  /// Appends the reversing entry, reopens the bills, releases the
  /// allocations and marks the payment void.
  Future<VoidedPayment> applyPaymentVoid(PaymentVoidPosting posting);

  /// The party's opening balance and the entries that put it on the books,
  /// or null when there is no such party.
  Future<OpeningSnapshot?> openingOf(String partyId);

  /// Reverses the old opening entries, posts the new opening and sets the
  /// party's column to match.
  Future<void> applyOpeningCorrection(OpeningCorrectionPosting posting);

  /// Writes the row that ties a cancelled entry to the one that replaced it.
  void recordCorrection(CorrectionRecord record);
}

/// What an edit left behind: the entry cancelled, and the one now standing
/// in its place.
final class CorrectedEntry {
  const CorrectedEntry({
    required this.cancelledId,
    required this.cancelledNo,
    required this.id,
    required this.no,
    required this.amount,
  });

  final String cancelledId;
  final String cancelledNo;

  /// The replacement — a new payment, charge or expense with its own number.
  /// The old number is never reused: the customer may be holding paper that
  /// carries it.
  final String id;
  final String no;
  final Money amount;
}

/// One entry replaced by another, as the activity log keeps it.
///
/// The cancellation and the new entry each write their own audit row. This
/// is the third, and the only one that says the two are one act: without it
/// the log reads "receipt cancelled" and, a line later, "receipt taken", and
/// nobody can say the second was the first put right.
final class CorrectionRecord {
  const CorrectionRecord({
    required this.action,
    required this.entityTable,
    required this.replacedId,
    required this.replacedNo,
    required this.replacementId,
    required this.replacementNo,
    required this.before,
    required this.after,
    required this.reason,
  });

  /// `PAYMENT_EDITED`, `EXPENSE_EDITED` or `CHARGE_EDITED`.
  final String action;
  final String entityTable;
  final String replacedId;
  final String replacedNo;
  final String replacementId;
  final String replacementNo;
  final Money before;
  final Money after;
  final String reason;

  String get summary =>
      '$replacedNo (${before.amountOnly}) corrected to $replacementNo '
      '(${after.amountOnly}): $reason';
}
