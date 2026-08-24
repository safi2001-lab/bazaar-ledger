import 'package:pk_domain/pk_domain.dart';

/// Entering a supplier's bill.
///
/// The same five steps as every other use case here: one transaction, pure
/// arithmetic, rows described as a value, the entry proved to balance, and a
/// return value that comes from the writer so a use case that wrote nothing
/// has nothing to return.
///
/// The costing positions are read INSIDE the transaction. A second till
/// selling the same item between the bill being typed and being saved changes
/// the balance the new average is weighted against, and an average computed
/// from a stale balance is wrong for every sale that follows it.
final class RecordPurchaseUseCase {
  const RecordPurchaseUseCase({
    required this.writer,
    this.builder = const PurchaseBuilder(),
  });

  final PurchaseWriter writer;
  final PurchaseBuilder builder;

  Future<PostedPurchase> call(ActorContext actor, PurchaseDraft draft) {
    return writer.inTransaction(actor, (write) async {
      String? ledgerAccountId;
      if (draft.paid.isPositive) {
        final accountId = draft.paymentAccountId;
        if (accountId == null) {
          throw StateError(
            'Money was paid at the door and no account was named for it.',
          );
        }
        ledgerAccountId = await write.ledgerAccountFor(accountId);
        if (ledgerAccountId == null) {
          throw StateError(
            'The payment method "$accountId" is not linked to an account, so '
            'money paid through it would come from nowhere.',
          );
        }
      }

      final positions = await write.costPositionsFor({
        for (final l in draft.lines) l.itemId,
      });

      final posting = builder.build(
        actor: actor,
        draft: draft,
        positions: positions,
        billNumber: await write.nextNumber('purchase_bill'),
        journalNumber: await write.nextNumber('journal_entry'),
        ledgerAccountId: ledgerAccountId,
      );

      return write.apply(posting);
    });
  }
}
