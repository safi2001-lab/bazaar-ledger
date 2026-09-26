import 'package:pk_domain/pk_domain.dart';

/// Posts a journal voucher the accountant wrote by hand.
final class PostJournalVoucherUseCase {
  const PostJournalVoucherUseCase({
    required this.writer,
    this.builder = const JournalVoucherBuilder(),
  });

  final JournalWriter writer;
  final JournalVoucherBuilder builder;

  /// Returns the entry's number.
  Future<String> call(
    ActorContext actor, {
    required String narration,
    required List<VoucherLine> lines,
  }) => writer.inTransaction(actor, (write) async {
    final entry = builder.build(
      actor: actor,
      narration: narration,
      lines: lines,
      number: await write.nextNumber('journal_entry'),
    );
    await write.apply(entry);
    return entry.entryNo;
  });
}
