import 'package:pk_domain/pk_domain.dart';

/// A cheque in hand moving on: to the bank, cleared, or bounced.
///
/// Each step reads the cheque inside its own transaction and refuses one that
/// is no longer in hand. Two tills clearing the same cheque, or clearing one
/// that bounced a minute ago on the other, is exactly the case that read is
/// for.
final class MoveChequeUseCase {
  const MoveChequeUseCase({
    required this.writer,
    this.lifecycle = const ChequeLifecycle(),
  });

  final ChequeWriter writer;
  final ChequeLifecycle lifecycle;

  Future<void> deposit(ActorContext actor, String paymentId) =>
      writer.inTransaction(actor, (write) async {
        final cheque = await _inHand(write, paymentId);
        await write.apply(lifecycle.deposit(actor: actor, cheque: cheque));
      });

  /// [bankAccountId] is the payment account the money lands in.
  Future<void> clear(
    ActorContext actor,
    String paymentId, {
    required String bankAccountId,
  }) => writer.inTransaction(actor, (write) async {
    final cheque = await _inHand(write, paymentId);
    final ledger = await write.ledgerAccountFor(bankAccountId);
    if (ledger == null) {
      throw const ChequeRefused(
        'That account is not linked to the books, so the money would land '
        'nowhere.',
      );
    }
    await write.apply(
      lifecycle.clear(
        actor: actor,
        cheque: cheque,
        bankLedgerAccountId: ledger,
        journalNumber: await write.nextNumber('journal_entry'),
      ),
    );
  });

  Future<void> bounce(
    ActorContext actor,
    String paymentId, {
    String reason = '',
  }) => writer.inTransaction(actor, (write) async {
    final cheque = await _inHand(write, paymentId);
    final allocations = await write.allocationsOf(paymentId);
    await write.apply(
      lifecycle.bounce(
        actor: actor,
        cheque: cheque,
        allocations: allocations,
        bills: await write.billsNow([
          for (final a in allocations) a.documentId,
        ]),
        journalNumber: await write.nextNumber('journal_entry'),
        reason: reason,
      ),
    );
  });

  /// The supplier presented a cheque the shop wrote, and the bank paid it.
  Future<void> clearIssued(ActorContext actor, String paymentId) =>
      writer.inTransaction(actor, (write) async {
        final cheque = await _issued(write, paymentId);
        await write.apply(
          lifecycle.clearIssued(
            actor: actor,
            cheque: cheque,
            journalNumber: await write.nextNumber('journal_entry'),
          ),
        );
      });

  /// The bank would not pay a cheque the shop wrote.
  Future<void> bounceIssued(
    ActorContext actor,
    String paymentId, {
    String reason = '',
  }) => writer.inTransaction(actor, (write) async {
    final cheque = await _issued(write, paymentId);
    final allocations = await write.allocationsOf(paymentId);
    await write.apply(
      lifecycle.bounceIssued(
        actor: actor,
        cheque: cheque,
        allocations: allocations,
        bills: await write.billsNow([
          for (final a in allocations) a.documentId,
        ]),
        journalNumber: await write.nextNumber('journal_entry'),
        reason: reason,
      ),
    );
  });

  static Future<IssuedCheque> _issued(
    ChequeWriteContext write,
    String paymentId,
  ) async {
    final cheque = await write.issuedCheque(paymentId);
    if (cheque == null) {
      throw const ChequeRefused(
        'That cheque is no longer outstanding. The bank has already paid or '
        'returned it.',
      );
    }
    return cheque;
  }

  static Future<ChequeInHand> _inHand(
    ChequeWriteContext write,
    String paymentId,
  ) async {
    final cheque = await write.chequeInHand(paymentId);
    if (cheque == null) {
      throw const ChequeRefused(
        'That cheque is no longer in hand. It has already cleared or bounced.',
      );
    }
    return cheque;
  }
}
