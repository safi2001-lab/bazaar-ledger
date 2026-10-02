import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'order_form_screen.dart';
import 'order_providers.dart';
import 'order_screen.dart';

/// Purchase orders, or sale orders, newest first (M41), each saying where
/// it stands: open, part of it in or out, all of it, late, or cancelled.
class OrderListScreen extends ConsumerWidget {
  const OrderListScreen({super.key, required this.kind});

  final OrderKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final buying = kind == OrderKind.purchase;
    final today = BusinessDate.now(ref.watch(appServicesProvider).clock);
    final orders = ref.watch(orderListProvider(kind));

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(buying ? s.ordersPurchase : s.ordersSale)),
      body: SafeArea(
        child: orders.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(BlTokens.space4),
            child: BlSkeletonList(rows: 4),
          ),
          error: (error, _) => BlError(
            title: s.commonSomethingWentWrong,
            message: '$error',
            retryLabel: s.actionRetry,
            onRetry: () => ref.invalidate(orderListProvider(kind)),
          ),
          data: (rows) => rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(BlTokens.space4),
                  child: BlEmpty(
                    icon: buying
                        ? Icons.assignment_outlined
                        : Icons.shopping_bag_outlined,
                    title: buying
                        ? s.orderListEmptyPurchase
                        : s.orderListEmptySale,
                    message: buying
                        ? s.orderListEmptyPurchaseHint
                        : s.orderListEmptySaleHint,
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
                    child: _OrderTile(row: rows[i], today: today),
                  ),
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => OrderFormScreen(kind: kind)),
        ),
        icon: const Icon(Icons.add),
        label: Text(buying ? s.orderNewPurchase : s.orderNewSale),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.row, required this.today});

  final OrderRow row;
  final BusinessDate today;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final (label, tone) = orderStatusChip(s, row, today);
    return BlCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => OrderScreen(orderId: row.id)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.partyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                Text(
                  [
                    row.docNo,
                    row.date.value,
                    if (row.dueDate != null) s.orderDue(row.dueDate!.value),
                  ].join(' · '),
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
                const SizedBox(height: BlTokens.space1),
                Wrap(
                  spacing: BlTokens.space2,
                  runSpacing: BlTokens.space1,
                  children: [
                    BlChip(label, tone: tone),
                    if (row.advance.isPositive)
                      BlChip(
                        s.orderAdvance(row.advance.amountOnly),
                        tone: BlChipTone.good,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: BlTokens.space2),
          BlMoney(row.total, size: 16),
        ],
      ),
    );
  }
}
