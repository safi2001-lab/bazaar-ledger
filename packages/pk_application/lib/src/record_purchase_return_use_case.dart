import 'package:pk_domain/pk_domain.dart';

/// Sending goods back to a supplier.
///
/// The same five steps as every other use case. The delivery, what earlier
/// returns took off it, and what the shelf holds are all read inside the
/// transaction: the limit on what can go back is only a limit if it is
/// checked against now.
final class RecordPurchaseReturnUseCase {
  const RecordPurchaseReturnUseCase({
    required this.writer,
    this.builder = const PurchaseReturnBuilder(),
  });

  final PurchaseReturnWriter writer;
  final PurchaseReturnBuilder builder;

  Future<RecordedPurchaseReturn> call(
    ActorContext actor,
    PurchaseReturnDraft draft,
  ) {
    return writer.inTransaction(actor, (write) async {
      final delivery = await write.deliveryFor(draft.originalDocumentId);
      if (delivery == null) {
        throw const ReturnRefused(
          'There is no posted delivery with that number to return against.',
        );
      }

      String? refundLedgerAccountId;
      if (draft.refundNow.isPositive) {
        final accountId = draft.paymentAccountId;
        if (accountId == null) {
          throw const ReturnRefused(
            'Money is coming back and no account was named for it.',
          );
        }
        refundLedgerAccountId = await write.ledgerAccountFor(accountId);
        if (refundLedgerAccountId == null) {
          throw const ReturnRefused(
            'That payment method is not linked to an account, so money '
            'coming back through it would land nowhere.',
          );
        }
      }

      final posting = builder.build(
        actor: actor,
        draft: draft,
        boughtLines: delivery.lines,
        originalDocNo: delivery.docNo,
        partyId: delivery.partyId,
        originalOutstanding: delivery.outstanding,
        positions: await write.costPositionsFor({
          for (final l in delivery.lines) l.itemId,
        }),
        returnNumber: await write.nextNumber('purchase_return'),
        journalNumber: await write.nextNumber('journal_entry'),
        refundLedgerAccountId: refundLedgerAccountId,
      );

      return write.apply(posting);
    });
  }
}
