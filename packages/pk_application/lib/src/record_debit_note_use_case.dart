import 'package:pk_domain/pk_domain.dart';

/// Puts a charge on a customer's khata: owed like a bill, and not a sale.
final class RecordDebitNoteUseCase {
  const RecordDebitNoteUseCase({
    required this.writer,
    this.builder = const DebitNoteBuilder(),
  });

  final DebitNoteWriter writer;
  final DebitNoteBuilder builder;

  /// Returns the note's id and number.
  Future<({String id, String docNo})> call(
    ActorContext actor,
    DebitNoteDraft draft,
  ) => writer.inTransaction(actor, (write) async {
    final number = await write.nextNumber('other_income');
    final posting = builder.build(
      actor: actor,
      draft: draft,
      number: number,
      journalNumber: await write.nextNumber('journal_entry'),
    );
    return (id: await write.apply(posting), docNo: number.formatted);
  });
}
