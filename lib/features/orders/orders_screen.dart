import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'order_list_screen.dart';
import 'order_providers.dart';
import 'reorder_screen.dart';
import 'shortage_screen.dart';

/// Orders, in one place (M41): what the shop has asked suppliers for, what
/// customers have asked the shop for, what the counter was asked for and
/// did not have, and what to order now.
///
/// Each shows only to whoever may use it: purchase orders and what to
/// order to whoever buys, sale orders to whoever sells, the shortage list
/// to both.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final services = ref.watch(appServicesProvider);
    final buying = services.orders.canHandle(OrderKind.purchase);
    final selling = services.orders.canHandle(OrderKind.sale);

    int standing(OrderKind kind) =>
        (ref.watch(orderListProvider(kind)).valueOrNull ?? const [])
            .where((o) => o.status.isStanding)
            .length;
    final asked = ref.watch(shortageProvider).valueOrNull?.length ?? 0;

    void open(Widget screen) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.ordersTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            if (buying)
              _Entry(
                icon: Icons.assignment_outlined,
                title: s.ordersPurchase,
                hint: s.ordersPurchaseHint,
                count: standing(OrderKind.purchase),
                onTap: () =>
                    open(const OrderListScreen(kind: OrderKind.purchase)),
              ),
            if (selling)
              _Entry(
                icon: Icons.shopping_bag_outlined,
                title: s.ordersSale,
                hint: s.ordersSaleHint,
                count: standing(OrderKind.sale),
                onTap: () => open(const OrderListScreen(kind: OrderKind.sale)),
              ),
            if (services.orders.canNoteShortage)
              _Entry(
                icon: Icons.star_border,
                title: s.ordersShortage,
                hint: s.ordersShortageHint,
                count: asked,
                onTap: () => open(const ShortageScreen()),
              ),
            if (buying)
              _Entry(
                icon: Icons.playlist_add_check,
                title: s.ordersReorder,
                hint: s.ordersReorderHint,
                onTap: () => open(const ReorderScreen()),
              ),
          ],
        ),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.title,
    required this.hint,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String title;
  final String hint;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: BlCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 24, color: t.accent),
            const SizedBox(width: BlTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: t.ink,
                    ),
                  ),
                  Text(hint, style: TextStyle(fontSize: 13, color: t.inkMuted)),
                ],
              ),
            ),
            if (count case final n? when n > 0)
              BlChip(s.ordersOpenCount(n), tone: BlChipTone.warn),
            Icon(Icons.chevron_right, size: 20, color: t.inkFaint),
          ],
        ),
      ),
    );
  }
}
