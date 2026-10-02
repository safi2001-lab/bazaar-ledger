import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../l10n/app_strings.dart';
import 'expense_screen.dart' show expenseHeadLabel;

/// What the expense book, the heads and the monthly bills read (M47).
///
/// Each waits for the shop, and reads nothing for a role that may not keep
/// the expense book, rather than throwing on a screen that role never opens.

final expenseHeadsProvider = FutureProvider.autoDispose<List<ExpenseHead>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null || !services.can(Permission.expenses)) return const [];
  return services.shopMoney.expenseHeads();
});

final incomeHeadsProvider = FutureProvider.autoDispose<List<IncomeHead>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null || !services.can(Permission.expenses)) return const [];
  return services.shopMoney.incomeHeads();
});

final dueBillsProvider = FutureProvider.autoDispose<List<DueBill>>((ref) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null || !services.can(Permission.expenses)) return const [];
  return services.shopMoney.billsDueNow();
});

final monthlyBillsProvider = FutureProvider.autoDispose<List<MonthlyBill>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null || !services.can(Permission.expenses)) return const [];
  return services.shopMoney.monthlyBills();
});

final monthSplitProvider = FutureProvider.autoDispose<MonthSplit?>((ref) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null || !services.can(Permission.expenses)) return null;
  return services.shopMoney.thisMonth();
});

/// Whose money one expense was, its head and the bill it paid.
final expenseFactsProvider = FutureProvider.autoDispose
    .family<ExpenseFacts?, String>((ref, documentId) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return null;
      return services.shopMoney.expenseFacts(documentId);
    });

/// A head as the screen names it: a shipped head in the shopkeeper's
/// language until the shop renames it, then the shop's own name.
String expenseHeadName(AppStrings s, ExpenseHead head) =>
    head.isShipped && !head.isRenamed
    ? expenseHeadLabel(s, head.systemKey!)
    : head.name;

/// What an expense is called in the list and on its page.
String expenseTitle(
  AppStrings s, {
  required bool forHome,
  required String? systemKey,
  required String headName,
}) {
  if (forHome) return s.expenseForHome;
  if (systemKey != null &&
      expenseHeads.contains(systemKey) &&
      headName == shippedAccountName(systemKey)) {
    return expenseHeadLabel(s, systemKey);
  }
  return headName;
}

/// A shipped head of other income, in the shopkeeper's language.
String shippedIncomeLabel(AppStrings s, String key) => switch (key) {
  'rent_received' => s.incomeHeadRent,
  'commission' => s.incomeHeadCommission,
  'interest' => s.incomeHeadInterest,
  'scrap' => s.incomeHeadScrap,
  'refund' => s.incomeHeadRefund,
  'other' => s.incomeHeadOther,
  _ => key,
};

/// A head of other income as the screen names it.
String incomeHeadName(AppStrings s, IncomeHead head) =>
    head.name ?? shippedIncomeLabel(s, head.key);

/// The head [key] as the screen names it, from the shop's [heads].
String incomeKeyName(AppStrings s, String key, List<IncomeHead> heads) {
  for (final h in heads) {
    if (h.key == key) return incomeHeadName(s, h);
  }
  return shippedIncomeLabel(s, key);
}
