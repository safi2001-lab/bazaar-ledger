import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../accounting/accounts_screen.dart';
import '../cheques/cheques_screen.dart';
import '../day_close/day_close_screen.dart';
import '../documents/quotations_screen.dart';
import '../expenses/expenses_screen.dart';
import '../items/items_screen.dart';
import '../items/low_stock_screen.dart';
import '../khata/udhaar_due_card.dart';
import '../orders/orders_screen.dart';
import '../parties/parties_screen.dart';
import '../pos/pos_screen.dart';
import '../purchases/purchases_screen.dart';
import '../reports/reports_screen.dart';
import '../sales/sales_screen.dart';
import '../settings/settings_screen.dart';
import '../subscription/plans_screen.dart';
import '../tax/fbr_offline_line.dart'; // M59
import '../vans/vans_screen.dart';

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
    final services = ref.watch(appServicesProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(firm?.name ?? s.appName),
        actions: [
          // Only where somebody could sign back in: with no PIN anywhere in
          // the shop, a lock would open straight back onto the owner.
          if (services.currentUser?.hasPin ?? false)
            BlIconButton(
              icon: Icons.lock_outline,
              label: s.homeLock,
              onPressed: () async {
                final container = ProviderScope.containerOf(
                  context,
                  listen: false,
                );
                await services.lock();
                container.bumpRefresh();
              },
            ),
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
              const _ChequesDue(),
              // Udhaar due today, late, and promised for today (M38).
              const UdhaarDueCard(),
              const FbrOverdueLine(), // M59: FBR bills late under Rule 150XC
              const SizedBox(height: BlTokens.space5),
              BlSectionHeader(s.homeTitle),
              const SizedBox(height: BlTokens.space3),
              _NavGrid(
                tiles: [
                  if (services.can(Permission.sell))
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
                  if (services.can(Permission.purchases))
                    _NavTile(
                      label: s.homePurchases,
                      icon: Icons.local_shipping_outlined,
                      onTap: () => _open(context, const PurchasesScreen()),
                    ),
                  // Rent, bijli and wages. The heads have sat in the chart
                  // since M0 with nothing posting to them, so every margin
                  // this app showed was profit before the shop paid its rent.
                  if (services.can(Permission.expenses))
                    _NavTile(
                      label: s.homeExpenses,
                      icon: Icons.receipt_outlined,
                      onTap: () => _open(context, const ExpensesScreen()),
                    ),
                  // Prices given on the phone, and billed when the buyer
                  // rings back.
                  if (services.can(Permission.sell))
                    _NavTile(
                      label: s.homeQuotations,
                      icon: Icons.request_quote_outlined,
                      onTap: () => _open(context, const QuotationsScreen()),
                    ),
                  // Purchase orders, customers' orders, the shortage list and
                  // what to order (M41).
                  if (services.can(Permission.purchases) ||
                      services.can(Permission.sell))
                    _NavTile(
                      label: s.homeOrders,
                      icon: Icons.assignment_outlined,
                      onTap: () => _open(context, const OrdersScreen()),
                    ),
                  // Goods sent ahead of the bill, and the bill made from them
                  // when it is settled.
                  if (services.can(Permission.sell))
                    _NavTile(
                      label: s.homeChallans,
                      icon: Icons.assignment_turned_in_outlined,
                      onTap: () => _open(
                        context,
                        const QuotationsScreen(challans: true),
                      ),
                    ),
                  // The cheque drawer. In wholesale most of what is owed
                  // arrives as post-dated cheques, and one banked late goes
                  // stale while one that bounces unnoticed reads as paid.
                  if (services.can(Permission.cheques))
                    _NavTile(
                      label: s.homeCheques,
                      icon: Icons.description_outlined,
                      onTap: () => _open(context, const ChequesScreen()),
                    ),
                  // Did the shop make money this month, and where did it go.
                  if (services.can(Permission.reports))
                    _NavTile(
                      label: s.homeReports,
                      icon: Icons.bar_chart_outlined,
                      onTap: () => _open(context, const ReportsScreen()),
                    ),
                  // The books themselves: every account, its entries, and
                  // the vouchers an accountant writes by hand.
                  if (services.can(Permission.reports))
                    _NavTile(
                      label: s.homeAccounts,
                      icon: Icons.account_tree_outlined,
                      onTap: () => _open(context, const AccountsScreen()),
                    ),
                  // The evening count of the golak against the books.
                  if (services.can(Permission.closeDay))
                    _NavTile(
                      label: s.homeDayClose,
                      icon: Icons.lock_clock_outlined,
                      onTap: () => _open(context, const DayCloseScreen()),
                    ),
                  // Delivery vans: loading, and the rider's cash (M18).
                  if (services.can(Permission.closeDay))
                    _NavTile(
                      label: s.vansTitle,
                      icon: Icons.local_shipping_outlined,
                      onTap: () => openWithPlan(
                        context,
                        ref,
                        PlanFeature.vans,
                        () => const VansScreen(),
                      ),
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
      floatingActionButton: services.can(Permission.sell)
          ? FloatingActionButton.extended(
              onPressed: () => _open(context, const PosScreen()),
              icon: const Icon(Icons.add),
              label: Text(s.homeNewBill),
            )
          : null,
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

/// How many cheques in the drawer can go to the bank today and have not.
///
/// Its own provider rather than the drawer's list, so the drawer still reads
/// afresh each time it is opened instead of inheriting the home screen's copy.
final _chequesDueProvider =
    FutureProvider.autoDispose<({int toBank, Money ours})>((ref) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return (toBank: 0, ours: Money.zero);
      final today = BusinessDate.now(services.clock);
      final inHand = await services.queries.chequesInHand(firm.id);
      final issued = await services.queries.chequesIssued(firm.id);
      return (
        toBank: inHand.where((c) => !c.deposited && c.isDueBy(today)).length,
        // The shop's own cheques a supplier can present within the next few
        // days, and what the bank needs to hold for them.
        ours: Money.sum([
          for (final c in issued)
            if (c.isDueBy(today.addDays(_oursWarningDays))) c.amount,
        ]),
      );
    });

/// How far ahead the shop is warned about its own cheques: long enough to
/// move money into the account, short enough not to cry wolf.
const _oursWarningDays = 3;

/// Cheques whose day has come, said on the first screen of the morning.
///
/// A post-dated cheque is only good for six months from its date, and one
/// that sits in the drawer past its day is one the customer has had longer
/// to empty the account behind. So the shop is told when one is due rather
/// than having to go and look.
class _ChequesDue extends ConsumerWidget {
  const _ChequesDue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final due = ref.watch(_chequesDueProvider).valueOrNull;
    if (due == null) return const SizedBox.shrink();

    Widget line(String text, Color colour) => Padding(
      padding: const EdgeInsets.only(top: BlTokens.space3),
      child: BlCard(
        onTap: () => HomeScreen._open(context, const ChequesScreen()),
        child: Row(
          children: [
            Icon(Icons.notifications_active_outlined, color: colour),
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
        if (due.toBank > 0) line(s.homeChequesDue(due.toBank), t.warning),
        if (due.ours.isPositive)
          line(
            s.homeChequesIssuedDue(due.ours.amountOnly, '$_oursWarningDays'),
            t.danger,
          ),
      ],
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
