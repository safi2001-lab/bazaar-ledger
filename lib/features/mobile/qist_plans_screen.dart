import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'mobile_providers.dart';
import 'qist_plan_screen.dart';

/// Every phone sold on qist (M50), the late ones first to the eye: who,
/// which phone, how many instalments are paid, what is late, and when the
/// next falls due. Narrowed to the running, the late or the paid off.
class QistPlansScreen extends ConsumerStatefulWidget {
  const QistPlansScreen({super.key});

  @override
  ConsumerState<QistPlansScreen> createState() => _QistPlansScreenState();
}

enum _Show { open, overdue, paidOff, all }

class _QistPlansScreenState extends ConsumerState<QistPlansScreen> {
  _Show _show = _Show.open;

  bool _wanted(QistPlan p, BusinessDate today) {
    final standing = p.standingOn(today);
    return switch (_show) {
      _Show.all => true,
      _Show.overdue => standing == QistStanding.overdue,
      _Show.paidOff => standing == QistStanding.paidOff,
      _Show.open =>
        standing == QistStanding.running ||
            standing == QistStanding.overdue ||
            standing == QistStanding.closed,
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final today = ref.watch(appServicesProvider).mobile.today;
    final plans = ref.watch(qistPlansProvider(null));
    return Scaffold(
      appBar: AppBar(title: Text(s.mobileQistPlansTitle)),
      body: ListView(
        padding: const EdgeInsets.all(BlTokens.space4),
        children: [
          Wrap(
            spacing: BlTokens.space2,
            children: [
              for (final (show, label) in [
                (_Show.open, s.mobileQistShowOpen),
                (_Show.overdue, s.mobileQistOverdue),
                (_Show.paidOff, s.mobileQistPaidOff),
                (_Show.all, s.mobileQistShowAll),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _show == show,
                  onSelected: (_) => setState(() => _show = show),
                ),
            ],
          ),
          const SizedBox(height: BlTokens.space3),
          plans.when(
            loading: () => const BlSkeletonList(rows: 3),
            error: (e, _) => BlError(
              title: s.commonSomethingWentWrong,
              message: '$e',
              onRetry: () => ref.invalidate(qistPlansProvider(null)),
            ),
            data: (all) {
              final shown = [
                for (final p in all)
                  if (_wanted(p, today)) p,
              ];
              if (shown.isEmpty) {
                return BlEmpty(
                  title: s.mobileQistNone,
                  message: s.mobileQistNoneHint,
                  icon: Icons.calendar_month_outlined,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in shown) QistPlanTile(plan: p, today: today),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One plan in a list.
class QistPlanTile extends StatelessWidget {
  const QistPlanTile({
    super.key,
    required this.plan,
    required this.today,
    this.showCustomer = true,
  });

  final QistPlan plan;
  final BusinessDate today;
  final bool showCustomer;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final standing = plan.standingOn(today);
    final next = plan.nextOpen;
    final overdue = plan.overdueOn(today);
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: BlCard(
        onTap: () => unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => QistPlanScreen(planId: plan.id),
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    showCustomer ? plan.partyName : plan.docNo,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                ),
                BlChip(
                  qistStandingWords(s, standing),
                  tone: qistTone(standing),
                ),
              ],
            ),
            if (plan.goods.isNotEmpty)
              Text(
                plan.goods.join(', '),
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
            const SizedBox(height: BlTokens.space1),
            Text(
              [
                s.mobileQistPaidOf(plan.paidCount, plan.count),
                s.mobileQistLeftAmount(plan.left.amountOnly),
                if (overdue.isPositive)
                  s.mobileQistOverdueShort(overdue.amountOnly),
                if (next != null &&
                    !plan.billCancelled &&
                    standing != QistStanding.paidOff)
                  s.mobileQistNext(
                    shortDate(next.dueOn.value, thisYear: today.year),
                  ),
              ].join(' · '),
              style: TextStyle(
                fontSize: 13,
                color: overdue.isPositive ? t.danger : t.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A customer's phones on qist, on their khata (M50). Nothing at all for a
/// customer with none.
class QistPlansCard extends ConsumerWidget {
  const QistPlansCard({super.key, required this.partyId});

  final String partyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans =
        ref.watch(qistPlansProvider(partyId)).valueOrNull ?? const <QistPlan>[];
    if (plans.isEmpty) return const SizedBox.shrink();
    final s = AppStrings.of(context);
    final today = ref.watch(appServicesProvider).mobile.today;
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BlSectionHeader(s.mobileQistPlansTitle),
          const SizedBox(height: BlTokens.space2),
          for (final p in plans)
            QistPlanTile(plan: p, today: today, showCustomer: false),
        ],
      ),
    );
  }
}
