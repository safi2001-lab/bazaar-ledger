import '../identity/actor_context.dart';
import '../sales/sale_posting_builder.dart';
import '../shop_money/other_income.dart';
import 'correction_writer.dart';
import 'void_writer.dart';

/// The persistence boundary for the shop's other income (M47).
///
/// One transaction, with the void handle M31 cancels a charge or an expense
/// through opened on it, so an edit — the old entry cancelled and the
/// corrected one written — commits as one act or not at all.
abstract interface class OtherIncomeWriter {
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(OtherIncomeWriteContext write) body,
  );
}

/// The handle other income is written and put right through.
abstract interface class OtherIncomeWriteContext {
  ActorContext get actor;

  Future<AllocatedNumber> nextNumber(String docType);

  /// The chart account behind the cash drawer, bank or wallet
  /// [paymentAccountId], or null when it is not one money can come into
  /// (the cheque drawer, or an account that is not this shop's).
  Future<String?> moneyAccountFor(String paymentAccountId);

  /// The head [headKey] as the books name it, or null when the shop keeps
  /// no such head.
  Future<String?> incomeHeadName(String headKey);

  /// Writes the document, its entry with every line tagged, and an audit
  /// row.
  Future<RecordedOtherIncome> apply(OtherIncomePosting posting);

  /// True when [documentId] is the shop's other income, false when it is a
  /// charge on a khata (an `other_income` document with a party), and null
  /// when it is neither.
  Future<bool?> isShopIncome(String documentId);

  /// M31's void handle, on this same transaction.
  VoidWriteContext get documents;

  /// Writes the row that ties a cancelled entry to its replacement.
  void recordCorrection(CorrectionRecord record);
}
