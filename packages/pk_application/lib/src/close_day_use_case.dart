import 'package:pk_domain/pk_domain.dart';

/// Closes the day against the drawer: what was counted, beside what the
/// books said, with any difference put through the books as it is found.
final class CloseDayUseCase {
  const CloseDayUseCase({
    required this.writer,
    this.builder = const DayCloseBuilder(),
  });

  final DayCloseWriter writer;
  final DayCloseBuilder builder;

  Future<DayClosePosting> call(
    ActorContext actor, {
    required Money counted,
    String? note,
  }) => writer.inTransaction(actor, (write) async {
    // Read inside the transaction, so a sale rung on the second till while
    // the drawer was being counted cannot slip between the two figures.
    final expected = await write.cashInBooks();
    final posting = builder.build(
      actor: actor,
      expected: expected,
      counted: counted,
      note: note,
      journalNumber: expected == counted
          ? null
          : await write.nextNumber('journal_entry'),
    );
    await write.apply(posting);
    return posting;
  });
}
