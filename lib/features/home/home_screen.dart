import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../cheques/cheques_screen.dart';
import '../expenses/expenses_screen.dart';
import '../items/items_screen.dart';
import '../items/low_stock_screen.dart';
import '../parties/parties_screen.dart';
import '../pos/pos_screen.dart';
import '../purchases/purchases_screen.dart';
import '../sales/sales_screen.dart';
import '../settings/settings_screen.dart';

/// The day, at a glance, and the way to everything else.
///
/// The shopkeeper cannot leave the counter, so the four numbers that decide
/// whether the day went well are legible from arm's length: what was sold,
/// how many bills, what actually came in, and what went out on udhaar. New
/// Bill is the largest target on the screen because it is the reason the app
/// is open.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final firm = ref.watch(firmProvider).valueOrNull;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(firm?.name ?? s.appName),
        actions: [
          BlIconButton(
            icon: Icons.settings_outlined,
            label: s.homeSettings,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.bumpRefresh(),
          child: ListView(
            padding: const EdgeInsets.all(BlTokens.space4),
            children: [
              const _DayCard(),
              const SizedBox(height: BlTokens.space5),
              BlSectionHeader(s.homeTitle),
              const SizedBox(height: BlTokens.space3),
              _NavGrid(
                tiles: [
                  _NavTile(
                    label: s.homeNewBill,
                    icon: Icons.point_of_sale_outlined,
                    accent: true,
                    onTap: () => _open(context, const PosScreen()),
                  ),
                  _NavTile(
                    label: s.homeItems,
                    icon: Icons.inventory_2_outlined,
                    onTap: () => _open(context, const ItemsScreen()),
                  ),
                  _NavTile(
                    label: s.homeSales,
                    icon: Icons.receipt_long_outlined,
                    onTap: () => _open(context, const SalesScreen()),
                  ),
                  _NavTile(
                    label: s.homeCustomers,
                    icon: Icons.people_alt_outlined,
                    onTap: () => _open(context, const PartiesScreen()),
                  ),
                  // Where every margin figure in this app becomes true. Until
                  // this tile existed, avg_cost_milli_paisa was written once
                  // when an item was created and never moved again.
                  _NavTile(
                    label: s.homePurchases,
                    icon: Icons.local_shipping_outlined,
                    onTap: () => _open(context, const PurchasesScreen()),
                  ),
                  // Rent, bijli and wages. The heads have sat in the chart
                  // since M0 with nothing posting to them, so every margin
                  // this app showed was profit before the shop paid its rent.
                  _NavTile(
                    label: s.homeExpenses,
                    icon: Icons.receipt_outlined,
                    onTap: () => _open(context, const ExpensesScreen()),
                  ),
                  // The cheque drawer. In wholesale most of what is owed
                  // arrives as post-dated cheques, and one banked late goes
                  // stale while one that bounces unnoticed reads as paid.
                  _NavTile(
                    label: s.homeCheques,
                    icon: Icons.description_outlined,
                    onTap: () => _open(context, const ChequesScreen()),
                  ),
                  // What to buy on the way in tomorrow. The query behind this
                  // has been written, tested and fast since M1, and until now
                  // there was no way to reach it.
                  _NavTile(
                    label: s.stockLowTitle,
                    icon: Icons.production_quantity_limits_outlined,
                    onTap: () => _open(context, const LowStockScreen()),
                  ),
                ],
              ),
              const SizedBox(height: BlTokens.space5),
              const _RecentSales(),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context, const PosScreen()),
        icon: const Icon(Icons.add),
        label: Text(s.homeNewBill),
      ),
    );
  }

  static void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _DayCard extends ConsumerWidget {
  const _DayCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final totals = ref.watch(todayTotalsProvider);

    return BlCard(
      accent: true,
      child: totals.when(
        loading: () => const SizedBox(
          height: 116,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        error: (error, _) => SizedBox(
          height: 116,
          child: Center(
            child: Text(
              s.commonSomethingWentWrong,
              style: TextStyle(color: t.danger),
            ),
          ),
        ),
        data: (day) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Both flexible. At 200% the label and the bill-count chip
                // together are wider than a 360dp screen, and the chip — which
                // in the zero-sales state reads "Koi bill nahi", the first
                // thing every morning — was cut off at the edge.
                Flexible(
                  child: Text(
                    s.homeTodaySales,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: t.inkMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: BlTokens.space2),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: BlChip(s.homeBillCount(day.billCount)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: BlTokens.space2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: BlMoney(
                day.sales,
                size: 38,
                weight: FontWeight.w700,
                withSymbol: true,
                semanticPrefix: s.homeTodaySales,
              ),
            ),
            const SizedBox(height: BlTokens.space4),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: s.homeReceived,
                    amount: day.received,
                    icon: Icons.south_west,
                    colour: t.money,
                  ),
                ),
                Container(width: 1, height: 34, color: t.line),
                Expanded(
                  child: _MiniStat(
                    label: s.homeOnUdhaar,
                    amount: day.onUdhaar,
                    icon: Icons.schedule,
                    colour: t.warning,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.amount,
    required this.icon,
    required this.colour,
  });

  final String label;
  final Money amount;
  final IconData icon;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BlTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: colour),
              const SizedBox(width: BlTokens.space1),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: BlTokens.space1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: BlMoney(amount, size: 18, semanticPrefix: label),
          ),
        ],
      ),
    );
  }
}

class _NavGrid extends StatelessWidget {
  const _NavGrid({required this.tiles});

  final List<_NavTile> tiles;

  @override
  Widget build(BuildContext context) {
    // Two columns on a phone, four on a tablet on the counter. Never a fixed
    // width: a 720x1600 Android Go screen and a 10-inch landscape tablet are
    // both first-class here.
    final columns = context.isWide ? 4 : 2;

    // A height, not an aspect ratio. An aspect ratio ties the tile's height to
    // the screen's width, so turning the system font up made the label taller
    // while the tile stayed exactly the same size — and the second line was
    // clipped on the four largest targets on the home screen, for precisely
    // the users who turned the font up because they could not read it.
    final scaler = MediaQuery.textScalerOf(context);
    final labelHeight = scaler.scale(14) * 2 * 1.45;
    final extent = BlTokens.space3 * 2 + 28 + BlTokens.space2 + labelHeight;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: BlTokens.space3,
        crossAxisSpacing: BlTokens.space3,
        mainAxisExtent: extent,
      ),
      itemCount: tiles.length,
      itemBuilder: (context, i) => tiles[i],
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.label,
    required this.icon,
    required this.onTap,
    this.accent = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: accent ? t.accent : t.surface,
        borderRadius: BorderRadius.circular(BlTokens.radiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(BlTokens.radiusLg),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BlTokens.radiusLg),
              border: Border.all(color: accent ? t.accent : t.line),
            ),
            padding: const EdgeInsets.all(BlTokens.space3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 28, color: accent ? t.accentInk : t.ink),
                const SizedBox(height: BlTokens.space2),
                // Flexible as well as a measured tile height. The height is
                // computed from the text scaler and is close, but "close" on a
                // layout is a stripe of yellow and black at some font size
                // nobody tested; giving the label room to shrink means the
                // worst case is an ellipsis rather than an overflow.
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: accent ? t.accentInk : t.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentSales extends ConsumerWidget {
  const _RecentSales();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final sales = ref.watch(recentSalesProvider);

    return sales.when(
      loading: () => const BlSkeletonList(rows: 3),
      error: (error, _) => BlError(
        title: s.commonSomethingWentWrong,
        message: '$error',
        retryLabel: s.actionRetry,
        onRetry: () => ref.invalidate(recentSalesProvider),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return BlEmpty(
            title: s.homeNoSalesToday,
            message: s.salesEmptyHint,
            icon: Icons.receipt_long_outlined,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BlSectionHeader(s.salesTitle),
            const SizedBox(height: BlTokens.space2),
            for (final row in rows.take(5)) SaleRowTile(row: row),
          ],
        );
      },
    );
  }
}
