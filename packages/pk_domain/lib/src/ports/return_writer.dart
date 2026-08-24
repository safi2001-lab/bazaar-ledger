import 'package:pk_money/pk_money.dart';

import '../corrections/return_builder.dart';
import '../identity/actor_context.dart';
import '../sales/sale_posting_builder.dart';

/// What a recorded return left behind.
final class RecordedReturn {
  const RecordedReturn({
    required this.documentId,
    required this.docNo,
    required this.total,
    required this.refunded,
    required this.againstBill,
    required this.onAccount,
    required this.journalEntryId,
  });

  final String documentId;
  final String docNo;
  final Money total;
  final Money refunded;
  final Money againstBill;
  final Money onAccount;
  final String journalEntryId;
}

/// A bill, as far as a return needs to know it.
final class ReturnableBill {
  const ReturnableBill({
    required this.documentId,
    required this.docNo,
    required this.partyId,
    required this.outstanding,
    required this.lines,
  });

  final String documentId;
  final String docNo;
  final String? partyId;

  /// What is still owed on it, which decides how much of a credit it can
  /// absorb before the rest becomes money the shop is holding.
  final Money outstanding;

  /// Each line as sold, with what earlier returns already took back.
  final List<SoldLine> lines;
}

/// The persistence boundary for returns.
abstract interface class ReturnWriter {
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(ReturnWriteContext write) body,
  );
}

/// The handle a return is written through.
abstract interface class ReturnWriteContext {
  ActorContext get actor;

  Future<AllocatedNumber> nextNumber(String docType);

  /// The bill being returned against, or null if there is no such posted
  /// bill.
  ///
  /// Read inside the transaction, so what earlier returns took is counted as
  /// of now. Two shopkeepers on two tills returning the same tin is exactly
  /// the case the limit exists for.
  Future<ReturnableBill?> billFor(String documentId);

  Future<String?> ledgerAccountFor(String paymentAccountId);

  /// Writes the return, its lines, the stock coming back, the journal entry,
  /// the link to the original and the audit row.
  Future<RecordedReturn> apply(ReturnPosting posting);
}
