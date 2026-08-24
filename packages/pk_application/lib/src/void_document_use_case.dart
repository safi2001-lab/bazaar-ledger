import 'package:pk_domain/pk_domain.dart';

/// Undoing a posted document.
///
/// The same five steps as every other use case here. The one difference is
/// that the arithmetic starts from what was WRITTEN rather than from a draft:
/// prices, costs and tax rules all move, and the entry that exists is the
/// only thing worth undoing.
final class VoidDocumentUseCase {
  const VoidDocumentUseCase({
    required this.writer,
    this.builder = const VoidBuilder(),
  });

  final VoidWriter writer;
  final VoidBuilder builder;

  Future<VoidedDocument> call(
    ActorContext actor, {
    required String documentId,
    required String reason,
  }) {
    return writer.inTransaction(actor, (write) async {
      final snapshot = await write.snapshotOf(documentId);
      if (snapshot == null) {
        // Named, because the alternatives are all things a shopkeeper can
        // act on: it was already voided, it is still a draft, or they are
        // looking at a bill from another shop's backup.
        throw const VoidRefused(
          'There is no posted bill with that number to undo.',
        );
      }

      final posting = builder.build(
        actor: actor,
        documentId: snapshot.documentId,
        docNo: snapshot.docNo,
        reason: reason,
        originalEntry: snapshot.entry,
        originalEntryId: snapshot.entryId,
        originalMovements: snapshot.movements,
        journalNumber: await write.nextNumber('journal_entry'),
        allocatedPayments: snapshot.allocatedPayments,
      );

      return write.apply(posting);
    });
  }
}
