import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'expenses_screen.dart';

/// The monthly bills due, as Home reads them: the same read as the Expenses
/// screen's (`dueBillsProvider`), held apart so the screen reads its own
/// afresh whenever it is opened rather than the copy Home is keeping.
final _dueOnHomeProvider = FutureProvider.autoDispose<List<DueBill>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null || !services.can(Permission.expenses)) return const [];
  return services.shopMoney.billsDueNow();
});

/// One line on the home screen for the monthly bills whose day has come
/// (M54, over M47's): "Mahana bill: 2 baqi, Rs 49,000.00 — Bijli, Kiraya".
///
/// M47 kept its reminders on the Expenses screen while another milestone
/// was building the home screen's due card, and said so. The morning's
/// other news is on the home screen — udhaar due (M38), repeating bills
/// (M63), FBR bills late (M59) — and the rent is the same kind of news, so
/// it sits beside them: one line, the count, what they come to and the
/// first few by name, opening the Expenses screen where each has its Pay
/// now. Nothing at all when nothing is due, or for a role that does not
/// keep the expense book (the provider reads nothing for it). Nothing is
/// ever paid from here: a bill is paid as M47 pays it, by the shopkeeper.
class MonthlyBillsDueLine extends ConsumerWidget {
  const MonthlyBillsDueLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(_dueOnHomeProvider).valueOrNull ?? const <DueBill>[];
    if (due.isEmpty) return const SizedBox.shrink();
    final s = AppStrings.of(context);
    final t = context.bl;
    final total = Money.sum([for (final d in due) d.bill.amount]);
    final names = [for (final d in due.take(3)) d.bill.note].join(', ');
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space3),
      child: InkWell(
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const ExpensesScreen())),
        child: Container(
          padding: const EdgeInsets.all(BlTokens.space3),
          decoration: BoxDecoration(
            color: t.warningSurface,
            borderRadius: BorderRadius.circular(BlTokens.radiusMd),
          ),
          child: Row(
            children: [
              Icon(Icons.receipt_long_outlined, size: 18, color: t.warning),
              const SizedBox(width: BlTokens.space2),
              Expanded(
                child: Text(
                  s.homeMonthlyBillsDue(due.length, total.amountOnly, names),
                  style: TextStyle(fontSize: 13, color: t.ink),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: t.warning),
            ],
          ),
        ),
      ),
    );
  }
}
