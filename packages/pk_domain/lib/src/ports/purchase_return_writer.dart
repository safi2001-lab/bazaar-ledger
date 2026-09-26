import 'package:pk_money/pk_money.dart';

import '../corrections/purchase_return_builder.dart';
import '../costing/moving_average.dart';
import '../identity/actor_context.dart';
import '../sales/sale_posting_builder.dart';

/// A delivery goods can go back against, as it stands now.
final class ReturnableDelivery {
  const ReturnableDelivery({
    required this.documentId,
    required this.docNo,
    required this.partyId,
    required this.outstanding,
    required this.lines,
  });

  final String documentId;
  final String docNo;
  final String partyId;

  /// What the shop still owes on this delivery.
  final Money outstanding;
  final List<BoughtLine> lines;
}

/// What a return to a supplier left behind.
final class RecordedPurchaseReturn {
  const RecordedPurchaseReturn({
    required this.documentId,
    required this.docNo,
    required this.total,
    required this.refunded,
    required this.againstBill,
    required this.journalEntryId,
  });

  final String documentId;
  final String docNo;
  final Money total;
  final Money refunded;
  final Money againstBill;
  final String journalEntryId;
}

/// The persistence boundary for goods going back to a supplier.
abstract interface class PurchaseReturnWriter {
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(PurchaseReturnWriteContext write) body,
  );
}

/// The handle a return to a supplier is written through.
abstract interface class PurchaseReturnWriteContext {
  ActorContext get actor;

  Future<AllocatedNumber> nextNumber(String docType);

  /// The delivery, with what earlier returns already sent back — read inside
  /// the transaction, so two tills cannot send the same sack back twice.
  Future<ReturnableDelivery?> deliveryFor(String documentId);

  /// What the shelf holds of each item now, the same read a delivery makes.
  Future<Map<String, CostPosition>> costPositionsFor(Iterable<String> itemIds);

  Future<String?> ledgerAccountFor(String paymentAccountId);

  Future<RecordedPurchaseReturn> apply(PurchaseReturnPosting posting);
}
