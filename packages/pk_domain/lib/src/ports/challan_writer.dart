import 'package:pk_money/pk_money.dart';

import '../documents/delivery_challan.dart';
import '../identity/actor_context.dart';
import '../sales/sale_posting_builder.dart';
import '../tax/tax_charge.dart';

/// The persistence boundary for a delivery challan.
abstract interface class ChallanWriter {
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(ChallanWriteContext write) body,
  );
}

/// The handle a challan is written through.
abstract interface class ChallanWriteContext {
  ActorContext get actor;

  /// The same tax context a bill for this party would be priced under.
  Future<TaxContext> taxContextFor(String? partyId);

  Future<AllocatedNumber> nextNumber(String docType);

  /// Weighted-average cost per base unit for each item, as it stands now.
  Future<Map<String, Rate>> averageCostFor(Iterable<String> itemIds);

  /// Writes the challan, its lines, its stock movements and its entry.
  /// Returns its id.
  Future<String> apply(ChallanPosting posting);
}
