import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'expense_entry_sheet.dart';
import 'expense_screen.dart';

/// Rent, bijli and wages, newest first.
///
/// The answer to "did I already put this month's rent in?", which a
/// shopkeeper asks before entering it a second time. Without a list the only
/// way to check was the Trial Balance, and nobody at a counter reads one.
final recentExpensesProvider = FutureProvider.autoDispose<List<ExpenseRow>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.recentExpenses(firm.id);
});

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final expenses = ref.watch(recentExpensesProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.expensesTitle)),
      body: SafeArea(
        child: expenses.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 4),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(BlTokens.space4),
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
              retryLabel: s.actionRetry,
              onRetry: () => ref.invalidate(recentExpensesProvider),
            ),
          ),
          data: (rows) => rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(BlTokens.space4),
                  child: BlEmpty(
                    icon: Icons.receipt_outlined,
                    title: s.expensesEmpty,
                    message: s.expensesEmptyHint,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    BlTokens.space4,
                    BlTokens.space3,
                    BlTokens.space4,
                    BlTokens.space10 * 2,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: BlTokens.space2),
                    child: _ExpenseTile(row: rows[i]),
                  ),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const ExpenseScreen())),
        icon: const Icon(Icons.add),
        label: Text(s.expenseNew),
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.row});

  final ExpenseRow row;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    return BlCard(
      // Opens it whole, to correct or cancel (M31). A saved expense used to
      // be a line that did nothing when tapped.
      onTap: () => showExpenseEntrySheet(context, documentId: row.id),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expenseHeadLabel(s, row.head),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                Text(
                  row.note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: t.inkMuted),
                ),
                Text(
                  '${row.dateLocal} · ${row.docNo}',
                  style: TextStyle(fontSize: 12, color: t.inkFaint),
                ),
                if (row.owed.isPositive && row.partyName != null) ...[
                  const SizedBox(height: BlTokens.space1),
                  BlChip(
                    s.expenseOwedTo(row.partyName!),
                    tone: BlChipTone.warn,
                    icon: Icons.schedule,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: BlTokens.space2),
          BlMoney(row.amount, size: 16),
        ],
      ),
    );
  }
}
