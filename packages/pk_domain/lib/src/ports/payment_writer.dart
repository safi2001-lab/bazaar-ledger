import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../receivables/fifo_allocator.dart';
import '../receivables/receipt_posting.dart';
import '../sales/sale_posting_builder.dart';

/// What a recorded receipt left behind.
final class RecordedReceipt {
  const RecordedReceipt({
    required this.paymentId,
    required this.paymentNo,
    required this.amount,
    required this.applied,
    required this.unapplied,
    required this.journalEntryId,
    required this.settledDocumentIds,
  });

  final String paymentId;
  final String paymentNo;
  final Money amount;

  /// What landed on bills, and what the customer is now in credit for.
  final Money applied;
  final Money unapplied;

  final String journalEntryId;

  /// The bills this payment cleared or reduced, oldest first — the answer to
  /// the question every shopkeeper is asked and could not previously give.
  final List<String> settledDocumentIds;
}

/// The persistence boundary for taking money.
///
/// Shaped exactly like [SaleWriter] and for the same reasons: the use case
/// above it never sees SQL, a companion or a transaction object, and `lib/`
/// can depend on the application layer without being able to reach a
/// database at all.
abstract interface class PaymentWriter {
  /// Runs [body] atomically. Everything it wrote commits together or not at
  /// all.
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(PaymentWriteContext write) body,
  );
}

/// The handle a receipt is written through.
abstract interface class PaymentWriteContext {
  ActorContext get actor;

  /// Allocates the next number in a series for this device and fiscal year.
  ///
  /// Inside the transaction, so a receipt that rolls back does not burn a
  /// number. A gap in a receipt series is the first thing an auditor asks
  /// about, and the shopkeeper has to be able to answer.
  Future<AllocatedNumber> nextNumber(String docType);

  /// Every bill this party still owes on, oldest first.
  ///
  /// Read inside the transaction rather than passed in, because a balance
  /// read before the transaction opened is a balance another till may have
  /// changed — and the whole point of allocating is that it is against what
  /// is actually outstanding now.
  ///
  /// Sale invoices only. A party can be a customer and a supplier at once,
  /// and a list that also held their purchase bills would let a customer's
  /// payment settle a debt the SHOP owes — money in, applied to money out.
  Future<List<OpenBill>> openBillsFor(String partyId);

  /// Everything the shop still owes this party, oldest first: purchase bills
  /// and unpaid expenses. The payable side of [openBillsFor], and read inside
  /// the transaction for the same reason.
  Future<List<OpenBill>> openPayablesFor(String partyId);

  /// The account in the chart that a payment account posts to.
  Future<String?> ledgerAccountFor(String paymentAccountId);

  /// Writes the payment, its allocations, the bills it settled, the journal
  /// entry and its lines, the audit row and the outbox entries.
  Future<RecordedReceipt> apply(ReceiptPosting posting);
}
