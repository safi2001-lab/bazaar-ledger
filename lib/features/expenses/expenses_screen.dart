import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../income/other_income_list_screen.dart';
import 'expense_entry_sheet.dart';
import 'expense_screen.dart';
import 'heads_screen.dart';
import 'monthly_bills_screen.dart';
import 'shop_money_providers.dart';

/// Rent, bijli and wages, newest first.
///
/// The answer to "did I already put this month's rent in?", which a
/// shopkeeper asks before entering it a second time. Without a list the only
/// way to check was the Trial Balance, and nobody at a counter reads one.
///
/// Since M47 it is read through the expense book, which names a head the
/// shop added itself and marks the home's spending, and it opens on what
/// is due: each monthly bill whose day has come and which is not yet paid,
/// with Pay now, and this month's spending, the shop's and the home's apart.
final recentExpensesProvider = FutureProvider.autoDispose<List<ExpenseBookRow>>(
  (ref) async {
    ref.watch(refreshTickProvider);
    final services = ref.watch(appServicesProvider);
    final firm = await ref.watch(firmProvider.future);
    if (firm == null) return const [];
    return services.shopMoney.expenseBook();
  },
);

class ExpensesScreen extends ConsumerWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final expenses = ref.watch(recentExpensesProvider);
    final due = ref.watch(dueBillsProvider).valueOrNull ?? const <DueBill>[];
    final split = ref.watch(monthSplitProvider).valueOrNull;

    void open(Widget screen) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));

    final header = <Widget>[
      for (final bill in due)
        Padding(
          padding: const EdgeInsets.only(bottom: BlTokens.space2),
          child: _DueBillCard(due: bill),
        ),
      if (split != null && (split.shop.isPositive || split.home.isPositive))
        Padding(
          padding: const EdgeInsets.only(bottom: BlTokens.space3),
          child: _MonthSplit(split: split),
        ),
    ];

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(s.expensesTitle),
        actions: [
          // Money that came in without a sale (M47), beside the money that
          // went out without a purchase.
          BlIconButton(
            icon: Icons.savings_outlined,
            label: s.incomeTitle,
            onPressed: () => open(const OtherIncomeListScreen()),
          ),
          BlIconButton(
            icon: Icons.event_repeat_outlined,
            label: s.billsTitle,
            onPressed: () => open(const MonthlyBillsScreen()),
          ),
          if (services.can(Permission.journal))
            BlIconButton(
              icon: Icons.category_outlined,
              label: s.headsTitle,
              onPressed: () => open(const HeadsScreen()),
            ),
        ],
      ),
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
          data: (rows) => ListView(
            padding: const EdgeInsets.fromLTRB(
              BlTokens.space4,
              BlTokens.space3,
              BlTokens.space4,
              BlTokens.space10 * 2,
            ),
            children: [
              ...header,
              if (rows.isEmpty)
                BlEmpty(
                  icon: Icons.receipt_outlined,
                  title: s.expensesEmpty,
                  message: s.expensesEmptyHint,
                )
              else
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: BlTokens.space2),
                    child: _ExpenseTile(row: row),
                  ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => open(const ExpenseScreen()),
        icon: const Icon(Icons.add),
        label: Text(s.expenseNew),
      ),
    );
  }
}

/// One monthly bill whose day has come: what it is, what it usually comes
/// to, Pay now, and Not this month. Nothing is paid until the shopkeeper
/// says so, on the expense screen this opens.
class _DueBillCard extends ConsumerWidget {
  const _DueBillCard({required this.due});

  final DueBill due;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final bill = due.bill;

    Future<void> skip() async {
      final messenger = ScaffoldMessenger.of(context);
      final container = ProviderScope.containerOf(context, listen: false);
      await ref.read(appServicesProvider).shopMoney.skipThisMonth(bill);
      container.bumpRefresh();
      messenger.showSnackBar(SnackBar(content: Text(s.billSkipped)));
    }

    return BlCard(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                bill.forHome ? Icons.home_outlined : Icons.event_repeat,
                size: 20,
                color: t.warning,
              ),
              const SizedBox(width: BlTokens.space2),
              Expanded(
                child: Text(
                  s.billDue(bill.note),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
              ),
              const SizedBox(width: BlTokens.space2),
              BlMoney(bill.amount, size: 16),
            ],
          ),
          Text(
            s.billDueOn(due.dueOn.value),
            style: TextStyle(fontSize: 12, color: t.inkMuted),
          ),
          const SizedBox(height: BlTokens.space2),
          Wrap(
            spacing: BlTokens.space2,
            runSpacing: BlTokens.space2,
            children: [
              BlButton(
                label: s.billPayNow,
                icon: Icons.payments_outlined,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ExpenseScreen(bill: bill),
                  ),
                ),
              ),
              BlButton(
                label: s.billSkip,
                kind: BlButtonKind.ghost,
                onPressed: () => unawaited(skip()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// This month's spending, the shop's and the home's side by side: the
/// split the owner asked for, and the reason the home's has its own book.
class _MonthSplit extends StatelessWidget {
  const _MonthSplit({required this.split});

  final MonthSplit split;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    Widget half(String label, Money amount, IconData icon) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: t.inkMuted),
              const SizedBox(width: BlTokens.space1),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
              ),
            ],
          ),
          BlMoney(amount, size: 16),
        ],
      ),
    );
    return BlCard(
      child: Row(
        children: [
          half(s.expenseMonthShop, split.shop, Icons.storefront),
          const SizedBox(width: BlTokens.space3),
          half(s.expenseMonthHome, split.home, Icons.home_outlined),
        ],
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.row});

  final ExpenseBookRow row;

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
                  expenseTitle(
                    s,
                    forHome: row.forHome,
                    systemKey: row.headSystemKey,
                    headName: row.headName,
                  ),
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
