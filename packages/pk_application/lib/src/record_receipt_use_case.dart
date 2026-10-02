import 'package:pk_domain/pk_domain.dart';

/// Taking money against udhaar.
///
/// The same five steps as [PostSaleUseCase], in the same order, because every
/// use case in this product copies that shape:
///
///  1. everything happens inside one transaction;
///  2. the numbers come from a pure function that needs no database;
///  3. the rows are described as a value before any of them is written;
///  4. the entry is proved to balance before the write is attempted;
///  5. the caller receives what was actually written, or an exception.
///
/// The open bills are read *inside* the transaction rather than passed in. A
/// balance read before the transaction opened is a balance a second till may
/// already have changed, and allocating against a stale figure is how a shop
/// ends up with a payment applied to a bill somebody else settled a minute
/// earlier.
final class RecordReceiptUseCase {
  const RecordReceiptUseCase({
    required this.writer,
    this.builder = const ReceiptBuilder(),
  });

  final PaymentWriter writer;
  final ReceiptBuilder builder;

  Future<RecordedReceipt> call(ActorContext actor, ReceiptDraft draft) =>
      writer.inTransaction(
        actor,
        (write) => recordOn(write, actor, draft, builder: builder),
      );

  /// The same steps, on a transaction somebody else opened.
  ///
  /// An edit (M31) cancels a receipt and takes its replacement in one
  /// commit, and the replacement has to be taken exactly as any other
  /// receipt is — the same allocation against the same freshly read bills —
  /// or an edited receipt would be a second, slightly different kind of
  /// receipt. So the body lives here once and both callers run it.
  static Future<RecordedReceipt> recordOn(
    PaymentWriteContext write,
    ActorContext actor,
    ReceiptDraft draft, {
    ReceiptBuilder builder = const ReceiptBuilder(),
  }) async {
    final ledgerAccountId = await write.ledgerAccountFor(
      draft.paymentAccountId,
    );
    if (ledgerAccountId == null) {
      // Named, because the alternative is a foreign key error naming a
      // column. A payment account with no account behind it is a setup
      // problem the shopkeeper can fix; a constraint name is not.
      throw StateError(
        'The payment method "${draft.paymentAccountId}" is not linked to '
        'an account, so money taken through it would land nowhere.',
      );
    }

    final openBills = await write.openBillsFor(draft.partyId);

    final posting = builder.build(
      actor: actor,
      draft: draft,
      openBills: openBills,
      paymentNumber: await write.nextNumber('payment_in'),
      journalNumber: await write.nextNumber('journal_entry'),
      ledgerAccountId: ledgerAccountId,
    );

    return write.apply(posting);
  }
}
