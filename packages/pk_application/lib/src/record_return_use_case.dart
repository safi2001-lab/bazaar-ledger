import 'package:pk_domain/pk_domain.dart';

/// Taking goods back.
///
/// The same shape as every other use case here. The one thing worth saying is
/// that the bill is read INSIDE the transaction, including what earlier
/// returns already took: two tills returning the same tin at the same moment
/// is exactly the case the limit exists for, and a limit checked against a
/// figure read a minute ago is not a limit.
final class RecordReturnUseCase {
  const RecordReturnUseCase({
    required this.writer,
    this.builder = const ReturnBuilder(),
  });

  final ReturnWriter writer;
  final ReturnBuilder builder;

  Future<RecordedReturn> call(ActorContext actor, ReturnDraft draft) {
    return writer.inTransaction(actor, (write) async {
      final bill = await write.billFor(draft.originalDocumentId);
      if (bill == null) {
        throw const ReturnRefused(
          'There is no posted bill with that number to return against.',
        );
      }

      String? refundLedgerAccountId;
      if (draft.refundNow.isPositive) {
        final accountId = draft.paymentAccountId;
        if (accountId == null) {
          throw const ReturnRefused(
            'Money is being handed back and no account was named for it.',
          );
        }
        refundLedgerAccountId = await write.ledgerAccountFor(accountId);
        if (refundLedgerAccountId == null) {
          throw const ReturnRefused(
            'That payment method is not linked to an account, so a refund '
            'through it would come from nowhere.',
          );
        }
      }

      final posting = builder.build(
        actor: actor,
        draft: draft,
        soldLines: bill.lines,
        originalDocNo: bill.docNo,
        partyId: bill.partyId,
        originalOutstanding: bill.outstanding,
        returnNumber: await write.nextNumber('sale_return'),
        journalNumber: await write.nextNumber('journal_entry'),
        refundLedgerAccountId: refundLedgerAccountId,
      );

      return write.apply(posting);
    });
  }
}
