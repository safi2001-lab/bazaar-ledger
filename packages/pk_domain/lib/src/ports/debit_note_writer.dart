import '../documents/debit_note.dart';
import '../identity/actor_context.dart';
import '../sales/sale_posting_builder.dart';

/// The persistence boundary for a debit note.
abstract interface class DebitNoteWriter {
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(DebitNoteWriteContext write) body,
  );
}

/// The handle a debit note is written through.
abstract interface class DebitNoteWriteContext {
  ActorContext get actor;

  Future<AllocatedNumber> nextNumber(String docType);

  /// Writes the note and its entry. Returns its id.
  Future<String> apply(DebitNotePosting posting);
}
