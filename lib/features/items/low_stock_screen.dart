import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/paged.dart';
import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../orders/reorder_screen.dart';
import 'item_editor.dart';
import 'shelf_rule.dart';

/// What is about to run out, worst first.
///
/// Everything behind this screen was built in M1 and reachable from nowhere:
/// `lowStockItems` was written, tested twice and measured against a
/// 20,000-SKU fixture, and the four Roman-Urdu strings sat in both ARBs. A
/// commit called it done. Nothing in `lib/features/` referenced any of it, so
/// a shopkeeper could not see a single item that was running low.
///
/// Ordered by how far below the floor each item is rather than by name,
/// because the question this answers is "what do I buy on the way in
/// tomorrow", and that is a question about urgency.
class LowStockScreen extends ConsumerWidget {
  const LowStockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final items = ref.watch(lowStockProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(s.stockLowTitle),
        actions: [
          // From what is running low to a purchase order per supplier, in
          // one tap (M41).
          if (ref.watch(appServicesProvider).can(Permission.purchases))
            BlIconButton(
              icon: Icons.playlist_add_check,
              label: s.ordersReorder,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ReorderScreen()),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: items.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 6),
          ),
          error: (error, _) => Center(
            child: BlError(
              title: s.commonSomethingWentWrong,
              message: '$error',
              retryLabel: s.actionRetry,
              onRetry: () => ref.invalidate(lowStockProvider),
            ),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              // Not an empty state in the usual sense — nothing is wrong, and
              // the shopkeeper should be told so plainly rather than shown a
              // prompt to go and add something.
              return Center(
                child: BlEmpty(
                  icon: Icons.check_circle_outline,
                  title: s.stockLowNone,
                ),
              );
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    BlTokens.space4,
                    BlTokens.space3,
                    BlTokens.space4,
                    0,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      s.stockLowSubtitle,
                      style: TextStyle(fontSize: 13, color: t.inkMuted),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(BlTokens.space4),
                    itemCount: rows.length,
                    itemBuilder: (context, i) => _LowStockRow(item: rows[i]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LowStockRow extends StatelessWidget {
  const _LowStockRow({required this.item});

  final ItemSummary item;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final onHand = item.stockOnHand;
    // Out of stock reads differently from nearly out, and a shopkeeper
    // scanning this list needs the difference at a glance rather than by
    // reading the numbers.
    final colour = onHand.isPositive ? t.warning : t.danger;

    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: BlCard(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => ItemEditorScreen(item: item)),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: BlTokens.space4,
          vertical: BlTokens.space3,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // An item sold below nothing is on this list whether or
                  // not it has a floor (M53), and says so instead.
                  if (item.isBelowNothing)
                    const BelowNothingChip()
                  else
                    Text(
                      s.stockLowFloor(
                        quantityWords(item.minStock, item.unitCode),
                      ),
                      style: TextStyle(fontSize: 12, color: t.inkMuted),
                    ),
                ],
              ),
            ),
            const SizedBox(width: BlTokens.space3),
            // The figure a shopkeeper is actually here for, in the tone that
            // says how bad it is: nothing left reads differently from
            // half a sack left.
            BlQty(onHand, unit: item.unitCode, colour: colour),
          ],
        ),
      ),
    );
  }
}
