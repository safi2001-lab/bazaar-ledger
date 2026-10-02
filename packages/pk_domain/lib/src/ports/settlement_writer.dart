/// Letting udhaar go: the write side of M44.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../receivables/allowance.dart';
import '../sales/sale_posting_builder.dart';
import 'payment_writer.dart';

/// One transaction in which a receipt and the discount that settles it, or
/// a write-off on its own, are written — or nothing is.
abstract interface class SettlementWriter {
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(SettlementWriteContext write) body,
  );
}

/// What the settlement use case reads and writes inside its transaction.
abstract interface class SettlementWriteContext {
  ActorContext get actor;

  /// The payment handle on this same transaction: the receipt is taken,
  /// and the allowance written, by exactly the code that writes receipts.
  PaymentWriteContext get payments;

  Future<AllocatedNumber> nextNumber(String docType);

  /// What [partyId] owes now, read inside the transaction with the one
  /// expression the khata uses (opening balance and open bills, less what
  /// the shop holds for them) — after any receipt this transaction took.
  Future<Money> owedBy(String partyId);

  /// The expense account [kind] is posted to, and the hidden payment
  /// account its rows are written under, each added the first time a shop
  /// needs it.
  Future<({String paymentAccountId, String ledgerAccountId})> allowanceAccount(
    AllowanceKind kind,
  );
}

/// One write-off or settlement discount, as the bad-debts list shows it.
final class AllowanceRow {
  const AllowanceRow({
    required this.paymentId,
    required this.paymentNo,
    required this.kind,
    required this.partyId,
    required this.partyName,
    required this.dateLocal,
    required this.amount,
    required this.reason,
    required this.byName,
    required this.cancelled,
  });

  final String paymentId;
  final String paymentNo;
  final AllowanceKind kind;
  final String partyId;
  final String partyName;
  final String dateLocal;
  final Money amount;
  final String reason;

  /// Who let it go.
  final String byName;

  /// Cancelled since (M31): the udhaar is owed again.
  final bool cancelled;
}
