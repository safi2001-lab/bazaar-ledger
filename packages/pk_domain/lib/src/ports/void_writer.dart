import '../corrections/reversal.dart';
import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';

/// What voiding a document left behind.
final class VoidedDocument {
  const VoidedDocument({
    required this.documentId,
    required this.docNo,
    required this.reversingEntryId,
    required this.reason,
  });

  final String documentId;
  final String docNo;
  final String reversingEntryId;
  final String reason;
}

/// What a document looked like when it was posted.
///
/// Read back out of the database so the reversal is the exact mirror of what
/// was actually written, rather than of what a builder would produce from the
/// same draft today. Prices, costs and tax rules all move; the entry that
/// exists is the only thing worth undoing.
final class PostedDocumentSnapshot {
  const PostedDocumentSnapshot({
    required this.documentId,
    required this.docNo,
    required this.entryId,
    required this.entry,
    required this.movements,
    required this.allocatedPayments,
  });

  final String documentId;
  final String docNo;
  final String entryId;
  final JournalEntryPosting entry;
  final List<StockMovementPosting> movements;

  /// Receipt numbers already applied to this document.
  final List<String> allocatedPayments;
}

/// The persistence boundary for corrections.
abstract interface class VoidWriter {
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(VoidWriteContext write) body,
  );
}

/// The handle a correction is written through.
abstract interface class VoidWriteContext {
  ActorContext get actor;

  Future<AllocatedNumber> nextNumber(String docType);

  /// The document as posted, or null if there is no such posted document.
  ///
  /// Read inside the transaction, because a payment allocated against this
  /// bill between the shopkeeper tapping Void and the write beginning is
  /// exactly the case the refusal exists for.
  Future<PostedDocumentSnapshot?> snapshotOf(String documentId);

  /// Appends the reversing entry and stock rows, and marks the document void.
  Future<VoidedDocument> apply(VoidPosting posting);
}
