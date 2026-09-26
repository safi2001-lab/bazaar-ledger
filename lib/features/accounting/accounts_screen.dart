import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'journal_voucher_screen.dart';

/// The chart of accounts, with every balance.
final chartProvider = FutureProvider.autoDispose<List<ChartAccount>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.chartOfAccounts(firm.id);
});

/// Every account the shop keeps, grouped as a balance sheet and a profit
/// and loss group them, each with what is in it now; tap one for every
/// entry that moved it.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.accountsTitle)),
      floatingActionButton: services.can(Permission.journal)
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const JournalVoucherScreen(),
                ),
              ),
              icon: const Icon(Icons.edit_note),
              label: Text(s.accountsWriteVoucher),
            )
          : null,
      body: SafeArea(
        child: ref
            .watch(chartProvider)
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(BlTokens.space4),
                child: BlSkeletonList(rows: 8),
              ),
              error: (error, _) =>
                  BlError(title: s.commonSomethingWentWrong, message: '$error'),
              data: (accounts) => ListView(
                padding: const EdgeInsets.fromLTRB(
                  BlTokens.space4,
                  BlTokens.space4,
                  BlTokens.space4,
                  BlTokens.space10 * 2,
                ),
                children: [
                  for (final (type, title) in [
                    ('asset', s.accountTypeAsset),
                    ('liability', s.accountTypeLiability),
                    ('equity', s.accountTypeEquity),
                    ('income', s.accountTypeIncome),
                    ('expense', s.accountTypeExpense),
                  ]) ...[
                    BlSectionHeader(title),
                    const SizedBox(height: BlTokens.space2),
                    for (final a in accounts.where((a) => a.type == type))
                      Padding(
                        padding: const EdgeInsets.only(bottom: BlTokens.space1),
                        child: BlCard(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => AccountLedgerScreen(account: a),
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 48,
                                child: Text(
                                  a.code,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: t.inkMuted,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  a.name,
                                  style: TextStyle(fontSize: 15, color: t.ink),
                                ),
                              ),
                              BlMoney(a.onItsSide, size: 15),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: BlTokens.space4),
                  ],
                ],
              ),
            ),
      ),
    );
  }
}

final _ledgerProvider = FutureProvider.autoDispose
    .family<List<AccountLedgerLine>, String>((ref, accountId) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return const [];
      return services.queries.accountLedger(firm.id, accountId);
    });

/// Every entry that moved one account, newest at the top, with the balance
/// after each.
class AccountLedgerScreen extends ConsumerWidget {
  const AccountLedgerScreen({required this.account, super.key});

  final ChartAccount account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final debitSide = account.type == 'asset' || account.type == 'expense';

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text('${account.code} ${account.name}')),
      body: SafeArea(
        child: ref
            .watch(_ledgerProvider(account.id))
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(BlTokens.space4),
                child: BlSkeletonList(rows: 6),
              ),
              error: (error, _) =>
                  BlError(title: s.commonSomethingWentWrong, message: '$error'),
              data: (lines) => lines.isEmpty
                  ? BlEmpty(
                      icon: Icons.menu_book_outlined,
                      title: s.accountLedgerEmpty,
                    )
                  : ListView(
                      padding: const EdgeInsets.all(BlTokens.space4),
                      children: [
                        for (final l in lines.reversed)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: BlTokens.space2,
                            ),
                            child: BlCard(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          l.narration,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: t.ink,
                                          ),
                                        ),
                                        Text(
                                          '${l.entryNo} · ${l.date.value}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: t.inkMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      BlMoney(
                                        debitSide
                                            ? l.debit - l.credit
                                            : l.credit - l.debit,
                                        size: 15,
                                        showSign: true,
                                      ),
                                      BlMoney(
                                        debitSide
                                            ? l.balanceAfter
                                            : -l.balanceAfter,
                                        size: 12,
                                        colour: t.inkMuted,
                                        weight: FontWeight.w400,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
      ),
    );
  }
}
