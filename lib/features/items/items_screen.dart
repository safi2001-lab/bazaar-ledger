import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/paged.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../manufacturing/recipes_screen.dart';
import '../subscription/plans_screen.dart';
import 'item_editor.dart';

/// Reset when the screen goes, because the search box is reset with it.
///
/// This was a plain global `StateProvider`, so the filter outlived the screen
/// while the `TextEditingController` — which lives on the State — came back
/// empty. Type "Sugar", go back, come in again, and the catalogue appears to
/// have shrunk to one row with nothing in the search box to explain why. On
/// the counter it was worse: the cart is only drawn when the query is empty,
/// so a shopkeeper returning to a half-built bill saw a stale search result
/// and no bill at all.
final itemsQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// Everything on the shelves.
class ItemsScreen extends ConsumerStatefulWidget {
  const ItemsScreen({super.key});

  @override
  ConsumerState<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends ConsumerState<ItemsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) ref.read(itemsQueryProvider.notifier).state = value.trim();
    });
  }

  Future<void> _openEditor([ItemSummary? item]) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ItemEditorScreen(item: item)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final query = ref.watch(itemsQueryProvider);
    final items = ref.watch(pagedItemsProvider(query));

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(s.itemsTitle),
        actions: [
          // What the shop makes from what it has (M17).
          BlIconButton(
            icon: Icons.blender_outlined,
            label: s.recipesTitle,
            onPressed: () => openWithPlan(
              context,
              ref,
              PlanFeature.manufacturing,
              () => const RecipesScreen(),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                BlTokens.space4,
                BlTokens.space3,
                BlTokens.space4,
                BlTokens.space2,
              ),
              child: BlField(
                controller: _search,
                label: s.actionSearch,
                hint: s.posSearchHint,
                onChanged: _onChanged,
                prefix: const Icon(Icons.search, size: 20),
              ),
            ),
            // What the shelves are worth, above the list of what is on them.
            // Its own card rather than another nav tile: a shopkeeper looking
            // at stock is already here, and a number one tap further away is a
            // number nobody looks at.
            const _StockSummaryCard(),
            Expanded(
              child: items.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(BlTokens.space4),
                  child: BlSkeletonList(),
                ),
                error: (error, _) => Center(
                  child: BlError(
                    title: s.commonSomethingWentWrong,
                    message: '$error',
                    retryLabel: s.actionRetry,
                    onRetry: () => ref.invalidate(pagedItemsProvider(query)),
                  ),
                ),
                data: (page) {
                  final rows = page.items;
                  if (rows.isEmpty) {
                    return Center(
                      child: BlEmpty(
                        title: query.isEmpty ? s.itemsEmpty : s.emptyNoResults,
                        message: query.isEmpty
                            ? s.itemsEmptyHint
                            : s.emptyNoResultsHint,
                        icon: Icons.inventory_2_outlined,
                        action: BlButton(
                          label: s.itemsAdd,
                          icon: Icons.add,
                          onPressed: () => _openEditor(),
                        ),
                      ),
                    );
                  }
                  // Asks for the next page at eighty per cent, so it has
                  // usually arrived by the time the shopkeeper's thumb gets
                  // there. Without this the list stopped at forty items on a
                  // catalogue of twenty thousand.
                  return NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      final at = n.metrics;
                      if (at.pixels >= at.maxScrollExtent * 0.8) {
                        ref.read(pagedItemsProvider(query).notifier).more();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        BlTokens.space4,
                        0,
                        BlTokens.space4,
                        BlTokens.space10 * 2,
                      ),
                      itemCount: rows.length,
                      itemExtent: blRowExtent(context, 72),
                      itemBuilder: (context, i) => _ItemRow(
                        key: ValueKey(rows[i].id),
                        item: rows[i],
                        onTap: () => _openEditor(rows[i]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: Text(s.itemsAdd),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({super.key, required this.item, required this.onTap});

  final ItemSummary item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;

    return RepaintBoundary(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: BlTokens.space2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.tracksStock
                                // "1 kg 500 g in stock" (M56).
                                ? s.itemStockLeft(
                                    quantityWords(
                                      item.stockOnHand,
                                      item.unitCode,
                                    ),
                                  )
                                : item.unitCode,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: t.inkMuted),
                          ),
                        ),
                        if (item.isLowOnStock) ...[
                          const SizedBox(width: BlTokens.space2),
                          BlChip(s.itemLowStock, tone: BlChipTone.warn),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: BlTokens.space3),
              Text(
                item.saleRate.amountOnly,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                  fontFeatures: BlTokens.tabular,
                ),
              ),
              Icon(Icons.chevron_right, color: t.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// The shop's stock in one line, above the item list.
///
/// Deliberately five numbers and no table. The table IS the list underneath.
/// What a shopkeeper wants at a glance before locking up is what is tied up in
/// stock, what is about to run out, and what has already gone — and each of
/// those is a different action, so each gets its own chip rather than being
/// folded into one "needs attention" count.
class _StockSummaryCard extends ConsumerWidget {
  const _StockSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final summary = ref.watch(stockSummaryProvider);

    // No card at all while it loads, and none for a shop with nothing in it.
    // A skeleton above a list that already has its own skeleton is two
    // loading states arguing, and an empty valuation on an empty shop is a
    // zero nobody needs to read.
    final data = summary.valueOrNull;
    if (data == null || data.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BlTokens.space4,
        0,
        BlTokens.space4,
        BlTokens.space3,
      ),
      child: BlCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.stockSummaryValue,
                        style: TextStyle(fontSize: 12, color: t.inkMuted),
                      ),
                      const SizedBox(height: 2),
                      // At cost. Valuing the shelf at retail counts profit the
                      // shop has not made, which is the commonest way a small
                      // business talks itself into believing it is richer than
                      // it is.
                      BlMoney(data.stockValue, size: 20),
                    ],
                  ),
                ),
                Text(
                  s.stockSummaryItems('${data.trackedItems}'),
                  style: TextStyle(fontSize: 12, color: t.inkMuted),
                ),
              ],
            ),
            if (data.lowCount > 0 ||
                data.outCount > 0 ||
                data.negativeCount > 0) ...[
              const SizedBox(height: BlTokens.space3),
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space2,
                children: [
                  if (data.lowCount > 0)
                    BlChip(
                      s.stockSummaryLow('${data.lowCount}'),
                      tone: BlChipTone.warn,
                      icon: Icons.trending_down,
                    ),
                  if (data.outCount > 0)
                    BlChip(
                      s.stockSummaryOut('${data.outCount}'),
                      tone: BlChipTone.bad,
                      icon: Icons.remove_shopping_cart_outlined,
                    ),
                  // Impossible on a shelf and entirely possible in a ledger:
                  // it means the shop sold something it never recorded
                  // receiving. Shown rather than clamped, because it is an
                  // error a person has to fix and hiding it makes the
                  // valuation above quietly wrong.
                  if (data.negativeCount > 0)
                    BlChip(
                      s.stockSummaryNegative('${data.negativeCount}'),
                      tone: BlChipTone.bad,
                      icon: Icons.priority_high,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
