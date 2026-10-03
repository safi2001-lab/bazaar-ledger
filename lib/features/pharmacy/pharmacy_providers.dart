import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';

/// The shop's standing as a chemist (M49): a pharmacy or not, and its
/// discount off the printed price.
///
/// Kept, not disposed: the counter reads it synchronously as each line goes
/// on, to give an item with a printed price the shop's "10% off", and a
/// figure that is loading at that moment is a line rung at the wrong price.
final pharmacyRulesProvider = FutureProvider<PharmacyRules>((ref) async {
  ref.watch(refreshTickProvider);
  // Follows the shop that is open, as everything else does.
  await ref.watch(firmProvider.future);
  return ref.watch(appServicesProvider).pharmacy.rules();
});

/// The items with [itemId]'s salt and strength, the ones on the shelf first.
final substitutesProvider = FutureProvider.autoDispose
    .family<List<ItemSummary>, String>((ref, itemId) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).pharmacy.substitutes(itemId);
    });

/// The batches expiring within [days], or held, under their suppliers.
final nearExpiryProvider = FutureProvider.autoDispose
    .family<List<SupplierExpiries>, int>((ref, days) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).pharmacy.nearExpiry(days: days);
    });
