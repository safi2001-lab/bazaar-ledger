import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';

/// The bills one party still owes on, oldest first.
///
/// The same rows, in the same order, that the writer reads inside its own
/// transaction. That is deliberate: what the shopkeeper is shown before they
/// tap Save has to be what actually happens, and a second ordering would make
/// the preview a guess.
final openBillsProvider = FutureProvider.autoDispose
    .family<List<OpenBill>, String>((ref, partyId) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return const [];
      return services.queries.openBillsFor(firm.id, partyId);
    });

/// One customer, live.
///
/// The khata screen was handed a `PartySummary` by the list that drew it, and
/// a payment taken on the khata changes it. Re-read rather than trusted, and
/// by id rather than by filtering an unfiltered search — a wholesaler has
/// thousands of customers and loading all of them to show one is the shape of
/// bug this project keeps finding in its own lists.
final partyProvider = FutureProvider.autoDispose.family<PartySummary?, String>((
  ref,
  partyId,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return null;
  return services.queries.partyById(firm.id, partyId);
});
