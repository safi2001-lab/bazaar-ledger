import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';

/// The persistence boundary for a hand-written journal voucher.
abstract interface class JournalWriter {
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(JournalWriteContext write) body,
  );
}

/// The handle a voucher is written through.
abstract interface class JournalWriteContext {
  ActorContext get actor;

  Future<AllocatedNumber> nextNumber(String docType);

  /// Writes the entry and its audit row. Returns the entry's id.
  Future<String> apply(JournalEntryPosting entry);
}
