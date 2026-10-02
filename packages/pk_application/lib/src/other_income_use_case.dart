import 'package:pk_domain/pk_domain.dart';

/// The shop's other income, written and put right (M47).
///
/// Recording is the same five steps as every use case here. Putting one
/// right is M31's path, extended to this kind of entry rather than copied:
/// a cancellation is the void builder's mirror of the entry, dated today,
/// written through the same void handle a charge or an expense is cancelled
/// through; an edit is that cancellation and the corrected entry in one
/// transaction, tied together in the activity log the way M31 ties an
/// edited expense to the one it replaced.
///
/// It never cancels a charge. A charge is an `other_income` document too
/// (M25), and the two are told apart by the party a charge carries; one
/// handed here is refused and pointed at the khata it is on.
final class OtherIncomeUseCase {
  const OtherIncomeUseCase({
    required this.writer,
    this.builder = const OtherIncomeBuilder(),
    this.voids = const VoidBuilder(),
  });

  final OtherIncomeWriter writer;
  final OtherIncomeBuilder builder;
  final VoidBuilder voids;

  /// Records [draft].
  Future<RecordedOtherIncome> record(
    ActorContext actor,
    OtherIncomeDraft draft,
  ) => writer.inTransaction(
    actor,
    (write) => recordOn(write, actor, draft, builder: builder),
  );

  /// The same steps, on a transaction somebody else opened.
  static Future<RecordedOtherIncome> recordOn(
    OtherIncomeWriteContext write,
    ActorContext actor,
    OtherIncomeDraft draft, {
    OtherIncomeBuilder builder = const OtherIncomeBuilder(),
  }) async {
    final ledger = await write.moneyAccountFor(draft.paymentAccountId);
    if (ledger == null) {
      throw const OtherIncomeRefused(
        'Pick the cash or the bank it came into. A cheque is recorded in the '
        'cheque drawer until it clears.',
      );
    }
    final headName = await write.incomeHeadName(draft.headKey);
    if (headName == null) {
      throw OtherIncomeRefused(
        '"${draft.headKey}" is not a head of income this shop keeps.',
      );
    }
    return write.apply(
      builder.build(
        actor: actor,
        draft: draft,
        number: await write.nextNumber('other_income'),
        journalNumber: await write.nextNumber('journal_entry'),
        ledgerAccountId: ledger,
        headName: headName,
      ),
    );
  }

  /// Cancels an entry: its entry mirrored, dated today, and the document
  /// marked void with [reason].
  Future<VoidedDocument> cancel(
    ActorContext actor, {
    required String documentId,
    required String reason,
  }) => writer.inTransaction(
    actor,
    (write) async => (await _cancel(write, actor, documentId, reason)).$1,
  );

  /// Replaces an entry with [draft]: the old one cancelled and the corrected
  /// one written, as one act.
  Future<CorrectedEntry> edit(
    ActorContext actor, {
    required String documentId,
    required OtherIncomeDraft draft,
    required String reason,
  }) => writer.inTransaction(actor, (write) async {
    final (old, was) = await _cancel(write, actor, documentId, reason);
    final fresh = await recordOn(write, actor, draft, builder: builder);
    write.recordCorrection(
      CorrectionRecord(
        action: 'OTHER_INCOME_EDITED',
        entityTable: 'documents',
        replacedId: old.documentId,
        replacedNo: old.docNo,
        replacementId: fresh.documentId,
        replacementNo: fresh.docNo,
        before: was,
        after: fresh.amount,
        reason: reason.trim(),
      ),
    );
    return CorrectedEntry(
      cancelledId: old.documentId,
      cancelledNo: old.docNo,
      id: fresh.documentId,
      no: fresh.docNo,
      amount: fresh.amount,
    );
  });

  Future<(VoidedDocument, Money)> _cancel(
    OtherIncomeWriteContext write,
    ActorContext actor,
    String documentId,
    String reason,
  ) async {
    final shop = await write.isShopIncome(documentId);
    if (shop == false) {
      throw const VoidRefused(
        'That is a charge on a customer\'s khata, not the shop\'s own income. '
        'Open it from their khata to take it back.',
      );
    }
    final snapshot = shop == null
        ? null
        : await write.documents.snapshotOf(documentId);
    if (snapshot == null) {
      throw const VoidRefused('There is nothing standing with that number.');
    }
    final posting = voids.build(
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
}
