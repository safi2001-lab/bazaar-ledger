import 'package:pk_domain/pk_domain.dart';

import 'pay_supplier_use_case.dart';
import 'record_debit_note_use_case.dart';
import 'record_expense_use_case.dart';
import 'record_receipt_use_case.dart';

/// Putting right what a shopkeeper keyed in (M31).
///
/// Shopkeepers testing the app said it plainly: an entry in a customer's
/// khata could not be changed once it was added. A receipt typed as
/// Rs 5,000 when Rs 500 came in, a supplier paid from the wrong account, a
/// month's rent entered twice — each stayed wrong, and the khata with it.
///
/// Everything here keeps the rule the books were built on: nothing written
/// is rewritten. To *cancel* is to write the mirror of the entry, dated
/// today, and mark it void. To *edit* is to cancel and record the corrected
/// entry, in one transaction, presented to the shopkeeper as one action. A
/// failure anywhere leaves the original standing exactly as it was.
///
/// ## What is never here
///
/// A sale bill. The customer has the paper in their hand, and a bill that
/// changes after it is printed is the thing that makes a customer stop
/// trusting a shop. It is returned or cancelled from the bill itself, under
/// its own permission, and every cancellation of a document below refuses a
/// bill by name rather than relying on no screen ever offering one.
///
/// Each method is the same five steps as every use case in this package:
/// one transaction, numbers from pure builders, rows described as a value,
/// the balance proved before the write, and what was written handed back.
final class CorrectEntriesUseCase {
  const CorrectEntriesUseCase({
    required this.writer,
    this.payments = const PaymentVoidBuilder(),
    this.documents = const VoidBuilder(),
    this.openings = const OpeningCorrectionBuilder(),
  });

  final CorrectionWriter writer;
  final PaymentVoidBuilder payments;
  final VoidBuilder documents;
  final OpeningCorrectionBuilder openings;

  // -------------------------------------------------------------------------
  // Payments, taken and made
  // -------------------------------------------------------------------------

  /// Cancels a receipt or a payment to a supplier: its entry mirrored, the
  /// bills it settled owed again, the payment marked void.
  Future<VoidedPayment> cancelPayment(
    ActorContext actor, {
    required String paymentId,
    required String reason,
  }) => writer.inTransaction(
    actor,
    (write) => _cancelPayment(write, actor, paymentId, reason),
  );

  /// Replaces a receipt with [draft]: the old one cancelled, the new one
  /// taken against the customer's bills as they stand once the old one's
  /// money is off them.
  Future<CorrectedEntry> editReceipt(
    ActorContext actor, {
    required String paymentId,
    required ReceiptDraft draft,
    required String reason,
  }) => writer.inTransaction(actor, (write) async {
    final old = await _cancelPayment(
      write,
      actor,
      paymentId,
      reason,
      direction: 'in',
      partyId: draft.partyId,
    );
    final fresh = await RecordReceiptUseCase.recordOn(
      write.payments,
      actor,
      draft,
    );
    return _linkPayments(write, old, fresh, reason);
  });

  /// Replaces a payment to a supplier with [draft], the same way.
  ///
  /// The old payment is cancelled first, so what the shop owes is read back
  /// at its full height before the new amount is checked against it — a
  /// payment cannot be edited upwards past what is owed, and the check has
  /// to see the money the old one is about to give back.
  Future<CorrectedEntry> editSupplierPayment(
    ActorContext actor, {
    required String paymentId,
    required SupplierPaymentDraft draft,
    required String reason,
  }) => writer.inTransaction(actor, (write) async {
    final old = await _cancelPayment(
      write,
      actor,
      paymentId,
      reason,
      direction: 'out',
      partyId: draft.partyId,
    );
    final fresh = await PaySupplierUseCase.payOn(write.payments, actor, draft);
    return _linkPayments(write, old, fresh, reason);
  });

  Future<VoidedPayment> _cancelPayment(
    CorrectionWriteContext write,
    ActorContext actor,
    String paymentId,
    String reason, {
    String? direction,
    String? partyId,
  }) async {
    final snapshot = await write.paymentSnapshot(paymentId);
    if (snapshot == null) {
      throw const VoidRefused(
        'There is no payment with that number to cancel.',
      );
    }
    if (direction != null && snapshot.direction != direction) {
      // A receipt edited into a payment out is not a correction of either.
      throw VoidRefused(
        '${snapshot.paymentNo} is a ${snapshot.isReceipt ? 'receipt' : 'payment'}, '
        'and is corrected as one.',
      );
    }
    if (partyId != null && snapshot.partyId != partyId) {
      // Moving money from one khata to another is two corrections a
      // shopkeeper should see as two: this one cancelled, the right one
      // taken on the right khata.
      throw VoidRefused(
        '${snapshot.paymentNo} is corrected on the same khata. If it was '
        'entered against the wrong name, cancel it here and enter it again '
        'on the right one.',
      );
    }
    final posting = payments.build(
      actor: actor,
      payment: snapshot,
      reason: reason,
      journalNumber: await write.nextNumber('journal_entry'),
    );
    return write.applyPaymentVoid(posting);
  }

  CorrectedEntry _linkPayments(
    CorrectionWriteContext write,
    VoidedPayment old,
    RecordedReceipt fresh,
    String reason,
  ) {
    write.recordCorrection(
      CorrectionRecord(
        action: 'PAYMENT_EDITED',
        entityTable: 'payments',
        replacedId: old.paymentId,
        replacedNo: old.paymentNo,
        replacementId: fresh.paymentId,
        replacementNo: fresh.paymentNo,
        before: old.amount,
        after: fresh.amount,
        reason: reason.trim(),
      ),
    );
    return CorrectedEntry(
      cancelledId: old.paymentId,
      cancelledNo: old.paymentNo,
      id: fresh.paymentId,
      no: fresh.paymentNo,
      amount: fresh.amount,
    );
  }

  // -------------------------------------------------------------------------
  // Charges on a khata
  // -------------------------------------------------------------------------

  /// Takes a charge back off a khata (M25), now under this permission
  /// rather than the one that cancels bills.
  Future<VoidedDocument> cancelCharge(
    ActorContext actor, {
    required String documentId,
    required String reason,
  }) => writer.inTransaction(actor, (write) async {
    final (voided, _) = await _cancelDocument(
      write,
      actor,
      documentId,
      reason,
      docType: 'other_income',
    );
    return voided;
  });

  /// Replaces a charge with [draft].
  Future<CorrectedEntry> editCharge(
    ActorContext actor, {
    required String documentId,
    required DebitNoteDraft draft,
    required String reason,
  }) => writer.inTransaction(actor, (write) async {
    final (old, was) = await _cancelDocument(
      write,
      actor,
      documentId,
      reason,
      docType: 'other_income',
    );
    final fresh = await RecordDebitNoteUseCase.recordOn(
      write.charges,
      actor,
      draft,
    );
    return _linkDocuments(
      write,
      action: 'CHARGE_EDITED',
      old: old,
      was: was,
      freshId: fresh.id,
      freshNo: fresh.docNo,
      now: draft.amount,
      reason: reason,
    );
  });

  // -------------------------------------------------------------------------
  // Expenses
  // -------------------------------------------------------------------------

  /// Cancels an expense: its entry mirrored, its document marked void.
  Future<VoidedDocument> cancelExpense(
    ActorContext actor, {
    required String documentId,
    required String reason,
  }) => writer.inTransaction(actor, (write) async {
    final (voided, _) = await _cancelDocument(
      write,
      actor,
      documentId,
      reason,
      docType: 'expense',
    );
    return voided;
  });

  /// Replaces an expense with [draft].
  Future<CorrectedEntry> editExpense(
    ActorContext actor, {
    required String documentId,
    required ExpenseDraft draft,
    required String reason,
  }) => writer.inTransaction(actor, (write) async {
    final (old, was) = await _cancelDocument(
      write,
      actor,
      documentId,
      reason,
      docType: 'expense',
    );
    final fresh = await RecordExpenseUseCase.recordOn(
      write.expenses,
      actor,
      draft,
    );
    return _linkDocuments(
      write,
      action: 'EXPENSE_EDITED',
      old: old,
      was: was,
      freshId: fresh.documentId,
      freshNo: fresh.docNo,
      now: fresh.amount,
      reason: reason,
    );
  });

  Future<(VoidedDocument, Money)> _cancelDocument(
    CorrectionWriteContext write,
    ActorContext actor,
    String documentId,
    String reason, {
    required String docType,
  }) async {
    final snapshot = await write.documents.snapshotOf(documentId);
    if (snapshot == null) {
      throw const VoidRefused('There is nothing standing with that number.');
    }
    if (snapshot.docType != docType) {
      // Above all, never a sale bill: this permission puts right what was
      // keyed in, and a bill is cancelled from the bill.
      throw VoidRefused(
        '${snapshot.docNo} is not '
        '${docType == 'expense' ? 'an expense' : 'a charge'}. A bill is '
        'returned or cancelled from the bill itself.',
      );
    }
    final posting = documents.build(
      actor: actor,
      documentId: snapshot.documentId,
      docNo: snapshot.docNo,
      reason: reason,
      originalEntry: snapshot.entry,
      originalEntryId: snapshot.entryId,
      originalMovements: snapshot.movements,
      journalNumber: await write.nextNumber('journal_entry'),
      allocatedPayments: snapshot.allocatedPayments,
    );
    return (await write.documents.apply(posting), snapshot.total);
  }

  CorrectedEntry _linkDocuments(
    CorrectionWriteContext write, {
    required String action,
    required VoidedDocument old,
    required Money was,
    required String freshId,
    required String freshNo,
    required Money now,
    required String reason,
  }) {
    write.recordCorrection(
      CorrectionRecord(
        action: action,
        entityTable: 'documents',
        replacedId: old.documentId,
        replacedNo: old.docNo,
        replacementId: freshId,
        replacementNo: freshNo,
        before: was,
        after: now,
        reason: reason.trim(),
      ),
    );
    return CorrectedEntry(
      cancelledId: old.documentId,
      cancelledNo: old.docNo,
      id: freshId,
      no: freshNo,
      amount: now,
    );
  }

  // -------------------------------------------------------------------------
  // Opening balances
  // -------------------------------------------------------------------------

  /// Sets the opening balance a party started with to [opening]: the old
  /// opening entry mirrored, the new one posted, the party's column moved to
  /// match.
  Future<void> correctOpening(
    ActorContext actor, {
    required String partyId,
    required Money opening,
    required String reason,
  }) => writer.inTransaction(actor, (write) async {
    final snapshot = await write.openingOf(partyId);
    if (snapshot == null) {
      throw const VoidRefused('That customer is not in this shop.');
    }
    final posting = openings.build(
      actor: actor,
      snapshot: snapshot,
      opening: opening,
      reason: reason,
      journalNumbers: [
        for (final _ in snapshot.entries)
          await write.nextNumber('journal_entry'),
      ],
    );
    await write.applyOpeningCorrection(posting);
  });
}
