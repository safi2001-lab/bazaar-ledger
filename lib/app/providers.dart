import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'preferences.dart';

/// Overridden in `main` once the database is open. Reading it before that is a
/// programming error, not a runtime condition, so it throws rather than
/// returning a half-built object.
final appServicesProvider = Provider<AppServices>(
  (ref) => throw StateError('AppServices was read before bootstrap finished'),
);

/// The language and theme read off disk before the first frame.
///
/// Overridden in `main` alongside [appServicesProvider]. Loading them as an
/// async provider instead would flash English at a shopkeeper who chose Roman
/// Urdu, and white at one who chose dark.
final initialPreferencesProvider = Provider<AppPreferences>(
  (ref) => AppPreferences.defaults(),
);

final preferencesProvider =
    NotifierProvider<PreferencesNotifier, AppPreferences>(
  PreferencesNotifier.new,
);

class PreferencesNotifier extends Notifier<AppPreferences> {
  @override
  AppPreferences build() => ref.watch(initialPreferencesProvider);

  Future<void> setLocale(Locale locale) async {
    state = AppPreferences(locale: locale, themeMode: state.themeMode);
    await state.save();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = AppPreferences(locale: state.locale, themeMode: mode);
    await state.save();
  }
}

/// The shop, or null when this device has not been set up.
///
/// Everything downstream keys off this: there is no login, no account and no
/// server, so "is there a firm row" is the whole of the app's session state.
final firmProvider = FutureProvider<FirmProfile?>((ref) async {
  // Watches the tick like every other read. `updateFirm` is the only writer
  // of this row, and without this a shopkeeper who corrects their shop name,
  // NTN or IBAN in Settings sees no change on screen — or on the receipt —
  // until they restart the app, and reasonably concludes it did not save.
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  return services.queries.currentFirm();
});

/// Bumped after every write so the lists and the day totals refresh.
///
/// A deliberate choice over streaming every query: on an Android Go handset a
/// stream per list is a stream per rebuild, and the counter is the one screen
/// that must never stutter.
final refreshTickProvider = StateProvider<int>((ref) => 0);

extension RefreshTick on WidgetRef {
  void bumpRefresh() =>
      read(refreshTickProvider.notifier).update((n) => n + 1);
}

final todayTotalsProvider = FutureProvider<DayTotals>((ref) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return DayTotals.empty;
  final today = BusinessDate.now(services.clock).value;
  return services.queries.dayTotals(firm.id, today);
});

final recentSalesProvider = FutureProvider<List<SaleListRow>>((ref) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.recentSales(firm.id, limit: 60);
});

final paymentAccountsProvider =
    FutureProvider<List<PaymentAccountSummary>>((ref) async {
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.paymentAccounts(firm.id);
});

final unitsProvider = FutureProvider<
    List<({String id, String code, String name, int decimals})>>((ref) async {
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.units(firm.id);
});

/// Item search, keyed by the query the counter typed.
///
/// Auto-disposed, and that matters more here than anywhere else. A family
/// without it keeps one provider instance per distinct key for the life of
/// the app, so every keystroke at the counter permanently retains a provider
/// and the item list it fetched — unbounded growth on the one screen that
/// must never stutter, on the handset least able to afford it.
final itemSearchProvider =
    FutureProvider.autoDispose.family<List<ItemSummary>, String>(
        (ref, query) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.searchItems(firm.id, query: query);
});

final partySearchProvider =
    FutureProvider.autoDispose.family<List<PartySummary>, String>(
        (ref, query) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.searchParties(firm.id, query: query);
});

final receiptProvider =
    FutureProvider.autoDispose.family<ReceiptData?, String>(
        (ref, documentId) async {
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return null;
  return services.queries.receiptFor(firm.id, documentId);
});

/// The integrity check, on demand only.
///
/// Deliberately does NOT watch the refresh tick. It runs `PRAGMA quick_check`
/// over every page of the file plus a full foreign-key sweep; re-running that
/// after every write while the Settings screen happens to be open would turn
/// a diagnostic into a background job on a phone that cannot spare one. The
/// screen has an explicit "check now" button, and that is the trigger.
final dataHealthProvider =
    FutureProvider.autoDispose<DatabaseHealth>((ref) async {
  return ref.watch(appServicesProvider).checkHealth();
});
