import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'chase_screen.dart';
import 'udhaar_providers.dart';

/// The morning's udhaar on the first screen: who falls due today, who is
/// already late, and who said today was the day (M38).
///
/// This is the reminder. There is no notification from the operating
/// system: that would mean a scheduling plugin, a permission to post
/// notifications, and an alarm that fires whether or not the shop is open.
/// The shopkeeper opens the app every morning to ring the first bill, and
/// this is on the screen they open it to — each line opens the chase list
/// already narrowed to the customers it counted. A quiet day shows nothing.
class UdhaarDueCard extends ConsumerWidget {
  const UdhaarDueCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final today = ref.watch(udhaarTodayProvider).valueOrNull;
    if (today == null || today.isQuiet) return const SizedBox.shrink();

    Widget line(String text, IconData icon, Color colour, ChaseView view) =>
        Padding(
          padding: const EdgeInsets.only(top: BlTokens.space3),
          child: BlCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChaseScreen(initialView: view),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: colour),
                const SizedBox(width: BlTokens.space3),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, color: t.inkMuted),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (today.promisedTodayCount > 0)
          line(
            s.homeUdhaarPromised(
              today.promisedTodayCount,
              today.promisedToday.amountOnly,
            ),
            Icons.handshake_outlined,
            t.money,
            ChaseView.promisedToday,
          ),
        if (today.dueTodayCount > 0)
          line(
            s.homeUdhaarDueToday(
              today.dueTodayCount,
              today.dueToday.amountOnly,
            ),
            Icons.event_outlined,
            t.warning,
            ChaseView.dueToday,
          ),
        if (today.overdueCount > 0)
          line(
            s.homeUdhaarOverdue(today.overdueCount, today.overdue.amountOnly),
            Icons.schedule,
            t.danger,
            ChaseView.overdue,
          ),
      ],
    );
  }
}
