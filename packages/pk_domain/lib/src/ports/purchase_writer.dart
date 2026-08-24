import 'package:pk_money/pk_money.dart';

import '../costing/moving_average.dart';
import '../costing/purchase_posting.dart';
import '../identity/actor_context.dart';
import '../sales/sale_posting_builder.dart';

/// What a posted purchase left behind.
final class PostedPurchase {
  const PostedPurchase({
    required this.documentId,
    required this.docNo,
    required this.total,
    required this.paid,
    required this.balance,
    required this.journalEntryId,
    required this.newAverages,
  });

  final String documentId;
  final String docNo;
  final Money total;
  final Money paid;
  final Money balance;
  final String journalEntryId;

  /// Each item's cost per base unit after this delivery. Returned rather than
  /// left to be read back, because "the average moved" is the whole claim of
  /// this milestone and a caller should be able to see that it did.
  final Map<String, Rate> newAverages;
}

/// The persistence boundary for buying.
abstract interface class PurchaseWriter {
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(PurchaseWriteContext write) body,
  );
}

/// The handle a purchase is written through.
abstract interface class PurchaseWriteContext {
  ActorContext get actor;

  Future<AllocatedNumber> nextNumber(String docType);

  /// Each item's costing as it stands right now.
  ///
  /// Read inside the transaction, because a second till selling the same item
  /// between the bill being typed and being saved changes the balance the new
  /// average is weighted against.
  Future<Map<String, CostPosition>> costPositionsFor(Iterable<String> itemIds);

  /// The account in the chart a payment account posts to.
  Future<String?> ledgerAccountFor(String paymentAccountId);

  /// Writes the document, its lines, the stock movements, the new averages,
  /// the journal entry and its lines, the audit row and the outbox entries.
  Future<PostedPurchase> apply(PurchasePosting posting);
}
