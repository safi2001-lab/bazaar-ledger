import '../documents/quotation.dart';
import '../identity/actor_context.dart';
import '../sales/sale_posting_builder.dart';
import '../tax/tax_charge.dart';

/// The persistence boundary for a quotation.
abstract interface class QuotationWriter {
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(QuotationWriteContext write) body,
  );
}

/// The handle a quotation is written through.
abstract interface class QuotationWriteContext {
  ActorContext get actor;

  /// The same tax context a bill for this party would be priced under.
  Future<TaxContext> taxContextFor(String? partyId);

  Future<AllocatedNumber> nextNumber(String docType);

  /// Writes the quotation and its lines, and nothing else. Returns its id.
  Future<String> apply(QuotationPosting posting);
}
