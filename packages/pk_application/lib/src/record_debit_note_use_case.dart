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
  ) => writer.inTransaction(
    actor,
    (write) => recordOn(write, actor, draft, builder: builder),
  );

  /// The same steps, on a transaction somebody else opened: an edit (M31)
  /// takes a charge back and puts the corrected one on in one commit.
  static Future<({String id, String docNo})> recordOn(
    DebitNoteWriteContext write,
    ActorContext actor,
    DebitNoteDraft draft, {
    DebitNoteBuilder builder = const DebitNoteBuilder(),
  }) async {
    final number = await write.nextNumber('other_income');
    final posting = builder.build(
      actor: actor,
      draft: draft,
      number: number,
      journalNumber: await write.nextNumber('journal_entry'),
    );
    return (id: await write.apply(posting), docNo: number.formatted);
  }
}
