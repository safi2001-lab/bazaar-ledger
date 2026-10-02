import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';

/// What the khata, the chase list and the home screen read about when
/// udhaar falls due (M38). Each watches the refresh tick, so a payment taken
/// anywhere moves every due date and promise on screen with it.

/// One customer's open bills, each with its due date.
final billsDueProvider = FutureProvider.autoDispose
    .family<List<BillDue>, String>((ref, partyId) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return const [];
      return services.udhaar.queries.billsDue(
        firm.id,
        partyId,
        asOfDateLocal: services.udhaar.today,
      );
    });

/// The shop's open bills, bucketed by how late they are.
final dueAgingProvider = FutureProvider.autoDispose<DueAging>((ref) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const DueAging({});
  return services.udhaar.queries.dueAging(
    firm.id,
    asOfDateLocal: services.udhaar.today,
  );
});

/// Every customer who owes, most late first.
final duePartiesProvider = FutureProvider.autoDispose<List<DueParty>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.udhaar.queries.dueParties(
    firm.id,
    asOfDateLocal: services.udhaar.today,
  );
});

/// One customer's promises, newest first.
final promisesProvider = FutureProvider.autoDispose
    .family<List<PaymentPromise>, String>((ref, partyId) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return const [];
      return services.udhaar.queries.promisesOf(firm.id, partyId);
    });

/// The home screen's card: due today, overdue, promised today.
final udhaarTodayProvider = FutureProvider.autoDispose<UdhaarToday>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return UdhaarToday.quiet;
  return services.udhaar.queries.udhaarToday(
    firm.id,
    asOfDateLocal: services.udhaar.today,
  );
});

/// A customer's own credit days, or null when they have none of their own.
final creditDaysProvider = FutureProvider.autoDispose.family<int?, String>((
  ref,
  partyId,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return null;
  return (await services.queries.partyDraft(firm.id, partyId))?.creditDays;
});

/// One customer's reminder language and opt-out (M39).
final reminderPrefsProvider = FutureProvider.autoDispose
    .family<ReminderPrefs, String>((ref, partyId) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).udhaar.reminderPrefs(partyId);
    });

/// The reminders sent to one customer, newest first (M39).
final remindersSentProvider = FutureProvider.autoDispose
    .family<List<ReminderSent>, String>((ref, partyId) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).udhaar.remindersSent(partyId);
    });
