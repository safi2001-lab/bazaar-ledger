import 'package:pk_money/pk_money.dart';

import '../cheques/cheque_lifecycle.dart';
import '../identity/actor_context.dart';
import '../sales/sale_posting_builder.dart';

/// The persistence boundary for a cheque's life after it is taken.
abstract interface class ChequeWriter {
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(ChequeWriteContext write) body,
  );
}

/// The handle a cheque step is written through.
abstract interface class ChequeWriteContext {
  ActorContext get actor;

  Future<AllocatedNumber> nextNumber(String docType);

  /// The cheque, if it is still in hand — pending, deposited or not. Null
  /// once it has cleared or bounced, which is what stops it being cleared
  /// twice by two tills.
  Future<ChequeInHand?> chequeInHand(String paymentId);

  /// A cheque the shop wrote, if the bank has not yet paid or returned it.
  Future<IssuedCheque?> issuedCheque(String paymentId);

  /// The bills this cheque paid, as recorded when it was taken.
  Future<List<ChequeAllocation>> allocationsOf(String paymentId);

  /// What each of these bills is paid and owes now.
  Future<Map<String, ({Money paid, Money balance})>> billsNow(
    Iterable<String> documentIds,
  );

  Future<String?> ledgerAccountFor(String paymentAccountId);

  Future<void> apply(ChequeStepPosting posting);
}
