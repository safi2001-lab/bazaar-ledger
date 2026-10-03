import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../l10n/app_strings.dart';

/// What the screens read of M68: the shop's credit rules and a customer's,
/// days that lock themselves, the random stock check and cashier mode.
///
/// Each is read again whenever the books move (the refresh tick), so a rule
/// changed on another counter, or a held bill arriving from the salesman's
/// phone, shows on the next refresh.

final creditDefaultsProvider = FutureProvider<CreditDefaults>((ref) async {
  ref.watch(refreshTickProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return CreditDefaults.standard;
  return ref.watch(appServicesProvider).credit.defaults();
});

/// One customer's own rules, and where they stand.
final partyCreditProvider = FutureProvider.autoDispose
    .family<({PartyCreditRules own, CreditStanding standing}), String>((
      ref,
      partyId,
    ) async {
      ref.watch(refreshTickProvider);
      final credit = ref.watch(appServicesProvider).credit;
      return (
        own: await credit.rulesOf(partyId),
        standing: await credit.standingOf(partyId),
      );
    });

final autoLockProvider = FutureProvider<AutoLock>((ref) async {
  ref.watch(refreshTickProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return AutoLock.off;
  return ref.watch(appServicesProvider).autoLock.rule();
});

final cashierModeProvider = FutureProvider<CashierMode>((ref) async {
  ref.watch(refreshTickProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return CashierMode.off;
  return ref.watch(appServicesProvider).cashier.mode();
});

/// Whether whoever is signed in makes bills for the cashier.
final isSalesmanProvider = FutureProvider<bool>((ref) async {
  final mode = await ref.watch(cashierModeProvider.future);
  final services = ref.watch(appServicesProvider);
  return mode.isSalesman(services.currentUser?.id ?? services.identity?.userId);
});

/// The bills waiting at the cashier, oldest first; none outside cashier
/// mode, or for whoever may not take money.
final heldQueueProvider = FutureProvider<List<HeldBill>>((ref) async {
  final mode = await ref.watch(cashierModeProvider.future);
  final services = ref.watch(appServicesProvider);
  if (!mode.on || !services.can(Permission.takePayments)) return const [];
  return services.cashier.queue();
});

final stockCheckRuleProvider = FutureProvider<StockCheckRule>((ref) async {
  ref.watch(refreshTickProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return StockCheckRule.standard;
  return ref.watch(appServicesProvider).stockChecks.rule();
});

/// Today's check still to finish (picked now if the rule is daily), or
/// null.
final stockCheckTodayProvider = FutureProvider<StockCheck?>((ref) async {
  ref.watch(refreshTickProvider);
  final firm = await ref.watch(firmProvider.future);
  final services = ref.watch(appServicesProvider);
  if (firm == null || !services.stockChecks.mayCount) return null;
  return services.stockChecks.today();
});

final stockCheckHistoryProvider = FutureProvider<List<StockCheck>>((ref) async {
  ref.watch(refreshTickProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return ref.watch(appServicesProvider).stockChecks.history();
});

/// [mode] in the shop's words.
String creditModeName(AppStrings s, CreditMode mode) => switch (mode) {
  CreditMode.off => s.creditModeOff,
  CreditMode.warn => s.creditModeWarn,
  CreditMode.block => s.creditModeBlock,
};

/// The title of the rule [breach] breaks.
String creditRuleTitle(AppStrings s, CreditRule rule) => switch (rule) {
  CreditRule.limit => s.creditLimitRule,
  CreditRule.bills => s.creditBillsRule,
  CreditRule.days => s.creditDaysRule,
  CreditRule.bounce => s.tenderChequeBounced,
};

/// What [breach] found, in the shop's words.
String creditBreachText(AppStrings s, CreditBreach breach) =>
    switch (breach.rule) {
      CreditRule.limit when breach.temporary => s.creditTempLimitLine(
        breach.limit!.amountOnly,
        shortDate(breach.tempUntil!.value),
        breach.after!.amountOnly,
      ),
      CreditRule.limit => s.tenderOverLimitDetail(
        breach.limit!.amountOnly,
        breach.after!.amountOnly,
      ),
      CreditRule.bills => s.creditBillsLine(breach.count!, breach.most!),
      CreditRule.days => s.creditDaysLine(breach.count!, breach.most!),
      CreditRule.bounce => s.tenderChequeBouncedDetail(
        breach.bounced!,
        breach.owed!.amountOnly,
      ),
    };

/// A check's standing in the shop's words.
String stockCheckStatusText(AppStrings s, StockCheckStatus status) =>
    switch (status) {
      StockCheckStatus.open => s.stockCheckStatusOpen,
      StockCheckStatus.counted => s.stockCheckStatusCounted,
      StockCheckStatus.posted => s.stockCheckStatusPosted,
      StockCheckStatus.dropped => s.stockCheckStatusDropped,
    };
