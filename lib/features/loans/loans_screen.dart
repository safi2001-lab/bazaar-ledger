import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../subscription/plans_screen.dart';
import 'loan_screen.dart';
import 'take_loan_screen.dart';

/// Every loan the shop has taken, with what is still owed on each (M48).
final loansProvider = FutureProvider.autoDispose<List<LoanView>>((ref) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.loans.list();
});

/// The loans: who lent what, and what is still owed on each, the ones
/// still being paid first. Reached from Accounts, by whoever may write the
/// books; taking a new one is part of the paid accounting set.
class LoansScreen extends ConsumerWidget {
  const LoansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.loansTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openWithPlan(
          context,
          ref,
          PlanFeature.accountingReports,
          () => const TakeLoanScreen(),
        ),
        icon: const Icon(Icons.add),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.loansNew),
            const SizedBox(width: BlTokens.space1),
            const PlanLock(PlanFeature.accountingReports),
          ],
        ),
      ),
      body: SafeArea(
        child: ref
            .watch(loansProvider)
            .when(
              loading: () => const Padding(
                padding: EdgeInsets.all(BlTokens.space4),
                child: BlSkeletonList(rows: 4),
              ),
              error: (error, _) =>
                  BlError(title: s.commonSomethingWentWrong, message: '$error'),
              data: (loans) {
                if (loans.isEmpty) {
                  return BlEmpty(
                    icon: Icons.account_balance_outlined,
                    title: s.loansEmpty,
                    message: s.loansEmptyHint,
                  );
                }
                // Still being paid first, then the paid off, then the ones
                // entered by mistake.
                int rank(LoanView l) => l.cancelled
                    ? 2
                    : l.owed.isPositive
                    ? 0
                    : 1;
                final sorted = [...loans]
                  ..sort((a, b) {
                    final byRank = rank(a).compareTo(rank(b));
                    return byRank != 0 ? byRank : a.code.compareTo(b.code);
                  });
                final owed = Money.sum([
                  for (final l in loans)
                    if (!l.cancelled) l.owed,
                ]);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    BlTokens.space4,
                    BlTokens.space4,
                    BlTokens.space4,
                    BlTokens.space10 * 2,
                  ),
                  children: [
                    BlCard(
                      accent: true,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.loansTotalOwed,
                              style: TextStyle(
                                fontSize: 15,
                                color: t.inkMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: BlMoney(
                                owed,
                                size: 24,
                                weight: FontWeight.w700,
                                withSymbol: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: BlTokens.space4),
                    for (final loan in sorted)
                      Padding(
                        padding: const EdgeInsets.only(bottom: BlTokens.space2),
                        child: _LoanCard(loan: loan),
                      ),
                  ],
                );
              },
            ),
      ),
    );
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({required this.loan});

  final LoanView loan;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final terms = loan.terms;
    final rate = terms?.rateBp;
    return BlCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => LoanScreen(loanId: loan.id)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loan.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: loan.cancelled ? t.inkMuted : t.ink,
                  ),
                ),
                if (terms != null)
                  Text(
                    [
                      s.loanTakenOn(terms.takenOn.value),
                      s.loanOf(terms.amount.amountOnly),
                      if (rate != null) s.loanRateShown(formatBp(rate)),
                    ].join(' · '),
                    style: TextStyle(fontSize: 13, color: t.inkMuted),
                  ),
                if (loan.cancelled) ...[
                  const SizedBox(height: BlTokens.space1),
                  BlChip(s.loanCancelled, tone: BlChipTone.bad),
                ],
              ],
            ),
          ),
          const SizedBox(width: BlTokens.space2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              BlMoney(loan.owed, size: 16),
              Text(
                s.loanOwed,
                style: TextStyle(fontSize: 12, color: t.inkMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
