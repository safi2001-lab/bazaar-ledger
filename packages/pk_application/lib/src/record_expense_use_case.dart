import 'package:pk_domain/pk_domain.dart';

/// Writing down rent, bijli, or the boy who carries sacks.
///
/// The same shape as every other use case here, and the shortest of them —
/// an expense has no lines, no stock and no tax. What it does have is a head
/// and a note, and both are required for the same reason: an expense report
/// nobody can read is one nobody uses.
final class RecordExpenseUseCase {
  const RecordExpenseUseCase({
    required this.writer,
    this.builder = const ExpenseBuilder(),
  });

  final ExpenseWriter writer;
  final ExpenseBuilder builder;

  Future<RecordedExpense> call(ActorContext actor, ExpenseDraft draft) {
    return writer.inTransaction(actor, (write) async {
      String? ledgerAccountId;
      final accountId = draft.paymentAccountId;
      if (accountId != null) {
        ledgerAccountId = await write.ledgerAccountFor(accountId);
        if (ledgerAccountId == null) {
          throw const ExpenseRefused(
            'That payment method is not linked to an account, so money paid '
            'through it would come from nowhere.',
          );
        }
      }

      return write.apply(
        builder.build(
          actor: actor,
          draft: draft,
          expenseNumber: await write.nextNumber('expense'),
          journalNumber: await write.nextNumber('journal_entry'),
          ledgerAccountId: ledgerAccountId,
        ),
      );
    });
  }
}
