import 'package:pk_domain/pk_domain.dart';

import 'record_receipt_use_case.dart';

/// What settling with a discount wrote: the money taken, and what was let
/// go to settle (M44).
final class SettledKhata {
  const SettledKhata({required this.receipt, this.discount});

  final RecordedReceipt receipt;

  /// Null when nothing was let go.
  final RecordedReceipt? discount;
}

/// "Baqi chhor do": settling a khata with a discount, and writing a bad
/// debt off (M44).
///
/// The same five steps as every use case here: one transaction, numbers
/// from pure builders, the rows described as a value, the balance proved
/// before the write, and what was written handed back.
///
/// A settlement discount is taken *after* the money, in the same
/// transaction: the receipt lands on the oldest bills exactly as any
/// receipt would, and only what is left is let go — so the discount is
/// never more than what the money did not cover, and a customer who hands
/// over more than they owe is given credit, not a discount.
///
/// Who may do which is not decided here but at the service boundary, where
/// the signed-in role is known (`settlementDiscountAllowed`, `mayWriteOff`).
final class SettleKhataUseCase {
  const SettleKhataUseCase({
    required this.writer,
    this.allowances = const AllowanceBuilder(),
  });

  final SettlementWriter writer;
  final AllowanceBuilder allowances;

  /// Takes [receipt] and lets [discount] go off what is still owed after it.
  Future<SettledKhata> settleWithDiscount(
    ActorContext actor, {
    required ReceiptDraft receipt,
    required Money discount,
    String reason = '',
  }) => writer.inTransaction(actor, (write) async {
    final taken = await RecordReceiptUseCase.recordOn(
      write.payments,
      actor,
      receipt,
    );
    if (!discount.isPositive) return SettledKhata(receipt: taken);
    final let = await _allow(
      write,
      actor,
      AllowanceDraft(
        partyId: receipt.partyId,
        kind: AllowanceKind.settlementDiscount,
        amount: discount,
        reason: reason,
      ),
    );
    return SettledKhata(receipt: taken, discount: let);
  });

  /// Writes [draft] off as a bad debt (or lets it go as a discount with no
  /// money taken).
  Future<RecordedReceipt> letGo(ActorContext actor, AllowanceDraft draft) =>
      writer.inTransaction(actor, (write) => _allow(write, actor, draft));

  Future<RecordedReceipt> _allow(
    SettlementWriteContext write,
    ActorContext actor,
    AllowanceDraft draft,
  ) async {
    final account = await write.allowanceAccount(draft.kind);
    final posting = allowances.build(
      actor: actor,
      draft: draft,
      openBills: await write.payments.openBillsFor(draft.partyId),
      owed: await write.owedBy(draft.partyId),
      paymentNumber: await write.nextNumber(draft.kind.docType),
      journalNumber: await write.nextNumber('journal_entry'),
      ledgerAccountId: account.ledgerAccountId,
      paymentAccountId: account.paymentAccountId,
    );
    return write.payments.apply(posting);
  }
}
