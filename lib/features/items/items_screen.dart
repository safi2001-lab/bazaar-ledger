import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/paged.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
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
      appBar: AppBar(title: Text(s.itemsTitle)),
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
                                ? s.itemInStock(
                                    item.stockOnHand.display,
                                    item.unitCode,
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
