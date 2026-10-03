import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';

/// Whether the shop says it is a mobile shop in its details (M50): the
/// phone search, used phones bought over the counter and qist are shown.
final isMobileShopProvider = Provider<bool>(
  (ref) => ref.watch(firmProvider).valueOrNull?.isMobileShop ?? false,
);

/// Phones whose IMEI 1 or 2 holds the digits typed, those in the shop first.
final phoneSearchProvider = FutureProvider.autoDispose
    .family<List<PhoneUnit>, String>((ref, digits) async {
      ref.watch(refreshTickProvider);
      if (imeiDigits(digits).length < 3) return const [];
      return ref.watch(appServicesProvider).mobile.findPhones(digits);
    });

/// One phone's whole story.
final phoneStoryProvider = FutureProvider.autoDispose
    .family<PhoneStory?, String>((ref, lotId) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).mobile.story(lotId);
    });

/// Every qist plan, or one customer's (by their id), newest first.
final qistPlansProvider = FutureProvider.autoDispose
    .family<List<QistPlan>, String?>((ref, partyId) async {
      ref.watch(refreshTickProvider);
      await ref.watch(firmProvider.future);
      return ref.watch(appServicesProvider).mobile.plans(partyId: partyId);
    });

/// One qist plan.
final qistPlanProvider = FutureProvider.autoDispose.family<QistPlan?, String>((
  ref,
  planId,
) async {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).mobile.plan(planId);
});
