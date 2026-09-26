import 'package:pk_domain/pk_domain.dart';

/// Paying a supplier against what the shop owes them.
///
/// The receipt use case turned around, and deliberately the same five steps:
/// one transaction, a pure builder, the rows as a value, the balance proved
/// before the write, and what was written handed back.
///
/// What is owed is read *inside* the transaction. A payable read before it
/// opened is one a second till may already have paid down, and paying a
/// supplier against a delivery somebody else settled a minute ago is how a
/// shop ends up paying the same bill twice.
final class PaySupplierUseCase {
  const PaySupplierUseCase({
    required this.writer,
    this.builder = const SupplierPaymentBuilder(),
  });

  final PaymentWriter writer;
  final SupplierPaymentBuilder builder;

  Future<RecordedReceipt> call(ActorContext actor, SupplierPaymentDraft draft) {
    return writer.inTransaction(actor, (write) async {
      final ledgerAccountId = await write.ledgerAccountFor(
        draft.paymentAccountId,
      );
      if (ledgerAccountId == null) {
        throw const SupplierPaymentRefused(
          'That payment method is not linked to an account, so money paid '
          'through it would come from nowhere.',
        );
      }

      final posting = builder.build(
        actor: actor,
        draft: draft,
        openBills: await write.openPayablesFor(draft.partyId),
        paymentNumber: await write.nextNumber('payment_out'),
        journalNumber: await write.nextNumber('journal_entry'),
        ledgerAccountId: ledgerAccountId,
      );

      return write.apply(posting);
    });
  }
}
