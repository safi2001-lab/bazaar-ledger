import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'cashier_queue_screen.dart';
import 'control_providers.dart';
import 'stock_check_screen.dart';

/// The morning's two M68 lines on the home screen, beside the udhaar due
/// and the monthly bills: bills waiting at the cashier ("3 bill cashier ke
/// paas intezar mein"), and today's random count ("Aaj ki ginti: 4 cheezein
/// baqi"). Each opens its screen; nothing at all when there is nothing to
/// say, or for a role the line is not for.
///
/// With the shop's check set to daily, reading today's check is what picks
/// it: the first time the home screen is opened on a new day.
class ControlHomeLines extends ConsumerWidget {
  const ControlHomeLines({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final queue = ref.watch(heldQueueProvider).valueOrNull ?? const [];
    final check = ref.watch(stockCheckTodayProvider).valueOrNull;
    final toCount = check == null
        ? 0
        : check.lines.where((l) => !l.isCounted).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (queue.isNotEmpty)
          _Line(
            icon: Icons.point_of_sale_outlined,
            text: s.cashierHomeLine(queue.length),
            open: () => const CashierQueueScreen(),
          ),
        if (check != null && check.isOpen)
          _Line(
            icon: Icons.fact_check_outlined,
            text: toCount > 0
                ? s.stockCheckHomeLine(toCount)
                : s.stockCheckHomeWaiting,
            open: () => const StockCheckScreen(),
          ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, required this.open});

  final IconData icon;
  final String text;
  final Widget Function() open;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space3),
      child: InkWell(
        borderRadius: BorderRadius.circular(BlTokens.radiusMd),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => open())),
        child: Container(
          padding: const EdgeInsets.all(BlTokens.space3),
          decoration: BoxDecoration(
            color: t.warningSurface,
            borderRadius: BorderRadius.circular(BlTokens.radiusMd),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: t.warning),
              const SizedBox(width: BlTokens.space2),
              Expanded(
                child: Text(text, style: TextStyle(fontSize: 13, color: t.ink)),
              ),
              Icon(Icons.chevron_right, size: 18, color: t.warning),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whether the home screen offers the cashier's counter: cashier mode on,
/// and whoever is signed in takes money.
final cashierCounterShownProvider = Provider<bool>((ref) {
  final mode = ref.watch(cashierModeProvider).valueOrNull ?? CashierMode.off;
  final salesman = ref.watch(isSalesmanProvider).valueOrNull ?? false;
  return mode.on && !salesman;
});
