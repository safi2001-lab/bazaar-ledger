import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../sales/receipt_screen.dart';
import 'mobile_providers.dart';

/// How a plan stands, in the shopkeeper's words.
String qistStandingWords(AppStrings s, QistStanding standing) =>
    switch (standing) {
      QistStanding.running => s.mobileQistRunning,
      QistStanding.overdue => s.mobileQistOverdue,
      QistStanding.paidOff => s.mobileQistPaidOff,
      QistStanding.closed => s.mobileQistClosed,
      QistStanding.cancelled => s.mobileQistCancelled,
    };

BlChipTone qistTone(QistStanding standing) => switch (standing) {
  QistStanding.overdue => BlChipTone.bad,
  QistStanding.paidOff => BlChipTone.good,
  QistStanding.running => BlChipTone.neutral,
  QistStanding.closed || QistStanding.cancelled => BlChipTone.warn,
};

/// One phone sold on qist (M50): the bill, the money, the guarantor, and
/// every instalment with what has been paid off it — oldest first, as the
/// receipts pay them — and what is late.
///
/// Money is taken on the customer's khata, as any udhaar is: a receipt there
/// pays the oldest instalment first without knowing there is a plan. From
/// here the plan can be closed early, when the customer means to settle:
/// whatever is left is then due at once.
class QistPlanScreen extends ConsumerWidget {
  const QistPlanScreen({super.key, required this.planId});

  final String planId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final plan = ref.watch(qistPlanProvider(planId));
    final mobile = ref.watch(appServicesProvider).mobile;
    final today = mobile.today;
    return Scaffold(
      appBar: AppBar(title: Text(s.mobileQistPlanTitle)),
      body: plan.when(
        loading: () => const BlSkeletonList(rows: 4),
        error: (e, _) => BlError(
          title: s.commonSomethingWentWrong,
          message: '$e',
          onRetry: () => ref.invalidate(qistPlanProvider(planId)),
        ),
        data: (plan) {
          if (plan == null) return BlEmpty(title: s.mobileQistGone);
          final standing = plan.standingOn(today);
          final guarantor = plan.guarantor;
          return ListView(
            padding: const EdgeInsets.all(BlTokens.space4),
            children: [
              BlCard(
                onTap: () => unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReceiptScreen(
                        documentId: plan.documentId,
                        docNo: plan.docNo,
                      ),
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      plan.partyName,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                    Text(
                      '${plan.docNo} · '
                      '${shortDate(plan.soldOn.value, thisYear: today.year)}',
                      style: TextStyle(fontSize: 13, color: t.inkMuted),
                    ),
                    for (final g in plan.goods)
                      Text(g, style: TextStyle(fontSize: 13, color: t.ink)),
                    const SizedBox(height: BlTokens.space2),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: BlChip(
                        qistStandingWords(s, standing),
                        tone: qistTone(standing),
                      ),
                    ),
                    const SizedBox(height: BlTokens.space2),
                    BlAmountRow(
                      label: s.mobileQistBillTotal,
                      child: BlMoney(plan.billTotal),
                    ),
                    if (plan.markup.isPositive)
                      BlAmountRow(
                        label: s.mobileQistMarkupIncluded,
                        child: BlMoney(plan.markup),
                      ),
                    BlAmountRow(
                      label: s.mobileQistDownNow,
                      child: BlMoney(plan.downPayment),
                    ),
                    BlAmountRow(
                      label: s.mobileQistOnQist,
                      child: BlMoney(plan.financed),
                    ),
                    BlAmountRow(
                      label: s.mobileQistPaid,
                      child: BlMoney(plan.paid),
                    ),
                    BlAmountRow(
                      label: s.mobileQistLeft,
                      child: BlMoney(plan.left),
                    ),
                    if (plan.overdueOn(today).isPositive)
                      BlAmountRow(
                        label: s.mobileQistOverdueAmount,
                        child: BlMoney(plan.overdueOn(today), colour: t.danger),
                      ),
                  ],
                ),
              ),
              if (guarantor != null) ...[
                const SizedBox(height: BlTokens.space3),
                BlCard(
                  child: SelectableText(
                    [
                      s.mobileQistGuarantorIs(guarantor.name),
                      if (guarantor.cnic case final c? when c.isNotEmpty)
                        'CNIC ${cnicDisplay(c)}',
                      ?guarantor.phone,
                    ].join('\n'),
                    style: TextStyle(fontSize: 13, color: t.ink),
                  ),
                ),
              ],
              if (plan.closedOn case final closed?) ...[
                const SizedBox(height: BlTokens.space3),
                Text(
                  [
                    s.mobileQistClosedOn(
                      shortDate(closed.value, thisYear: today.year),
                    ),
                    ?plan.closeNote,
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: t.warning),
                ),
              ],
              const SizedBox(height: BlTokens.space4),
              BlSectionHeader(s.mobileQistSchedule),
              const SizedBox(height: BlTokens.space2),
              for (final row in plan.standings)
                _InstalmentRow(
                  standing: row,
                  today: today,
                  cancelled: plan.billCancelled,
                ),
              const SizedBox(height: BlTokens.space3),
              Text(
                s.mobileQistHowPaid,
                style: TextStyle(fontSize: 12, color: t.inkMuted),
              ),
              if (standing == QistStanding.running ||
                  standing == QistStanding.overdue) ...[
                if (mobile.canCloseQist) ...[
                  const SizedBox(height: BlTokens.space4),
                  BlButton(
                    label: s.mobileQistCloseEarly,
                    icon: Icons.event_available_outlined,
                    kind: BlButtonKind.secondary,
                    onPressed: () => unawaited(_close(context, ref, plan)),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _close(
    BuildContext context,
    WidgetRef ref,
    QistPlan plan,
  ) async {
    final s = AppStrings.of(context);
    final note = TextEditingController();
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.mobileQistCloseEarly),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.mobileQistCloseConfirm(plan.left.amountOnly)),
            const SizedBox(height: BlTokens.space3),
            BlField(controller: note, label: s.mobileQistCloseNote),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.mobileQistCloseEarly),
          ),
        ],
      ),
    );
    final why = note.text;
    note.dispose();
    if (!(yes ?? false) || !context.mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(appServicesProvider)
          .mobile
          .closeQistEarly(plan.id, note: why);
      container.bumpRefresh();
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class _InstalmentRow extends StatelessWidget {
  const _InstalmentRow({
    required this.standing,
    required this.today,
    required this.cancelled,
  });

  final InstalmentStanding standing;
  final BusinessDate today;
  final bool cancelled;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final i = standing.instalment;
    final late = standing.daysLateOn(today);
    final (String words, Color colour) = cancelled
        ? (s.mobileQistCancelled, t.inkMuted)
        : standing.isPaid
        ? (s.mobileQistInstalmentPaid, t.money)
        : standing.isOverdueOn(today)
        ? (s.mobileQistInstalmentLate(late, standing.left.amountOnly), t.danger)
        : standing.isDueTodayOn(today)
        ? (s.mobileQistInstalmentToday(standing.left.amountOnly), t.warning)
        : standing.isPartPaid
        ? (s.mobileQistInstalmentPart(standing.left.amountOnly), t.ink)
        : (s.mobileQistInstalmentDue, t.inkMuted);
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text('${i.seq}.', style: TextStyle(color: t.inkMuted)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  printedDate(standing.dueOn),
                  style: TextStyle(fontSize: 14, color: t.ink),
                ),
                Text(words, style: TextStyle(fontSize: 12, color: colour)),
              ],
            ),
          ),
          BlMoney(i.amount, size: 14),
        ],
      ),
    );
  }
}
