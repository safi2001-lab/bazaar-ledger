import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'report_screen.dart';

/// Today's figures, read off today's Z report (M35) by the same engine and
/// the same builder: the sale, what came in, the udhaar given, what was
/// spent, and the gross profit for a role that may see what goods cost.
final todayFiguresProvider = FutureProvider.autoDispose<List<ReportFigure>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  final today = BusinessDate.now(services.clock);
  final z = await services.reports.run(
    ReportKind.dailySummary,
    firmId: firm.id,
    period: ReportPeriod.day(today),
    today: today,
  );
  return z.summary;
});

/// The strip at the top of the Reports hub (M46): how today is going, at a
/// glance, before the shopkeeper picks a report. A tap opens the night's Z
/// report the figures come from.
///
/// Nothing here is summed. The figures are the Z report's own headline
/// tiles, so the strip and the report cannot disagree; the gross profit is
/// simply not among them for a cashier, because the builder leaves it off
/// for a role that may not see costs.
class TodayStrip extends ConsumerWidget {
  const TodayStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final figures = ref.watch(todayFiguresProvider).valueOrNull;
    if (figures == null || figures.isEmpty) return const SizedBox.shrink();
    final named = [
      for (final f in figures)
        if (_name(s, f.label) case final name? when f.amount != null)
          (name: name, amount: f.amount!),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space3),
      child: Semantics(
        button: true,
        label: s.reportTodayOpen,
        child: BlCard(
          padding: const EdgeInsets.all(BlTokens.space3),
          onTap: () => unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const ReportScreen(kind: ReportKind.dailySummary),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.today_outlined, size: 18, color: t.inkMuted),
                  const SizedBox(width: BlTokens.space2),
                  Expanded(
                    child: Text(
                      s.reportTodayTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.ink,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: t.inkMuted),
                ],
              ),
              const SizedBox(height: BlTokens.space2),
              Wrap(
                spacing: BlTokens.space4,
                runSpacing: BlTokens.space2,
                children: [
                  for (final f in named)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          f.name,
                          style: TextStyle(fontSize: 12, color: t.inkMuted),
                        ),
                        BlMoney(f.amount, size: 16, withSymbol: true),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A Z report figure's name in the shop's language, or null for one the
  /// strip does not show.
  static String? _name(AppStrings s, String label) => switch (label) {
    DayFigureLabel.netSales => s.reportTodaySale,
    DayFigureLabel.collected => s.reportTodayReceived,
    DayFigureLabel.udhaarGiven => s.reportTodayUdhaar,
    DayFigureLabel.expenses => s.reportTodayExpenses,
    DayFigureLabel.grossProfit => s.reportTodayProfit,
    _ => null,
  };
}
