import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../expenses/shop_money_providers.dart';
import 'other_income_screen.dart';
import 'other_income_sheet.dart';

/// The shop's other income, newest first (M47).
final otherIncomesProvider = FutureProvider.autoDispose<List<OtherIncomeRow>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.shopMoney.otherIncomes();
});

/// This month's other income, by head.
final incomeThisMonthProvider = FutureProvider.autoDispose<Map<String, Money>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const {};
  return services.shopMoney.incomeThisMonth();
});

/// Money that came in without a sale: rent from the room upstairs,
/// commission, the bank's profit, the kabari's money for the empties.
///
/// Its own list, beside the expenses it mirrors, with this month's total
/// by head at the top: the question an owner asks of it is "how much did
/// the sub-let bring in this year", never one entry.
class OtherIncomeListScreen extends ConsumerWidget {
  const OtherIncomeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final rows = ref.watch(otherIncomesProvider);
    final month = ref.watch(incomeThisMonthProvider).valueOrNull ?? const {};
    final heads = ref.watch(incomeHeadsProvider).valueOrNull ?? const [];
    final total = Money.sum(month.values);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.incomeTitle)),
      body: SafeArea(
        child: rows.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 4),
          ),
          error: (error, _) =>
              BlError(title: s.commonSomethingWentWrong, message: '$error'),
          data: (list) => ListView(
            padding: const EdgeInsets.fromLTRB(
              BlTokens.space4,
              BlTokens.space3,
              BlTokens.space4,
              BlTokens.space10 * 2,
            ),
            children: [
              if (total.isPositive) ...[
                BlCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.incomeThisMonth,
                              style: TextStyle(fontSize: 13, color: t.inkMuted),
                            ),
                          ),
                          BlMoney(total, size: 18),
                        ],
                      ),
                      for (final MapEntry(:key, :value) in month.entries)
                        BlAmountRow(
                          label: incomeKeyName(s, key, heads),
                          child: BlMoney(value, size: 14),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: BlTokens.space3),
              ],
              if (list.isEmpty)
                BlEmpty(
                  icon: Icons.savings_outlined,
                  title: s.incomeEmpty,
                  message: s.incomeEmptyHint,
                )
              else
                for (final row in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: BlTokens.space2),
                    child: BlCard(
                      onTap: () =>
                          showOtherIncomeSheet(context, documentId: row.id),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  incomeKeyName(s, row.headKey, heads),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: t.ink,
                                  ),
                                ),
                                if (row.fromName != null || row.note.isNotEmpty)
                                  Text(
                                    [
                                      ?row.fromName,
                                      if (row.note.isNotEmpty) row.note,
                                    ].join(' · '),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: t.inkMuted,
                                    ),
                                  ),
                                Text(
                                  '${row.dateLocal} · ${row.docNo}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: t.inkFaint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: BlTokens.space2),
                          BlMoney(row.amount, size: 16),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const OtherIncomeScreen()),
        ),
        icon: const Icon(Icons.add),
        label: Text(s.incomeNew),
      ),
    );
  }
}
