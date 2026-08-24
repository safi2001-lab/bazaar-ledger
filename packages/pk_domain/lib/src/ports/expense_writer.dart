import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../receivables/expense_builder.dart';
import '../sales/sale_posting_builder.dart';

/// What a recorded expense left behind.
final class RecordedExpense {
  const RecordedExpense({
    required this.documentId,
    required this.docNo,
    required this.amount,
    required this.head,
    required this.journalEntryId,
  });

  final String documentId;
  final String docNo;
  final Money amount;
  final String head;
  final String journalEntryId;
}

/// The persistence boundary for money going out that is not stock.
abstract interface class ExpenseWriter {
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(ExpenseWriteContext write) body,
  );
}

/// The handle an expense is written through.
abstract interface class ExpenseWriteContext {
  ActorContext get actor;

  Future<AllocatedNumber> nextNumber(String docType);

  Future<String?> ledgerAccountFor(String paymentAccountId);

  Future<RecordedExpense> apply(ExpensePosting posting);
}
