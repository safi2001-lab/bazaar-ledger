import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'providers.dart';

/// One page of a keyset-paginated list, and whether there is another.
///
/// The read layer has taken `afterId` since M1 and nothing ever passed it.
/// `searchItems` and `recentSales` were both called unpaged, and the sales
/// list carried a hard `limit: 60` — so a shop with 20,000 items and three
/// years of bills had a catalogue it could search and a list it could not
/// scroll past the first screen of. The keyset machinery was real, measured
/// against a 20,000-SKU fixture, and unreachable.
final class Page<T> {
  const Page({
    required this.items,
    required this.hasMore,
    this.loadingMore = false,
  });

  const Page.empty() : items = const [], hasMore = false, loadingMore = false;

  final List<T> items;

  /// Whether the last read filled its page. A short page means the end.
  final bool hasMore;

  /// A page is on its way. Kept separate from the outer AsyncValue so the
  /// list stays on screen while the next page loads — replacing it with a
  /// spinner is how a shopkeeper loses their scroll position mid-search.
  final bool loadingMore;

  Page<T> copyWith({List<T>? items, bool? hasMore, bool? loadingMore}) => Page(
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// The item list, paged.
final pagedItemsProvider = AsyncNotifierProvider.autoDispose
    .family<PagedItems, Page<ItemSummary>, String>(PagedItems.new);

final class PagedItems
    extends AutoDisposeFamilyAsyncNotifier<Page<ItemSummary>, String> {
  static const _pageSize = 40;

  @override
  Future<Page<ItemSummary>> build(String query) async {
    ref.watch(refreshTickProvider);
    final rows = await _read();
    return Page(items: rows, hasMore: rows.length == _pageSize);
  }

  Future<List<ItemSummary>> _read({String? afterId}) async {
    final services = ref.read(appServicesProvider);
    final firm = await ref.read(firmProvider.future);
    if (firm == null) return const [];
    return services.queries.searchItems(
      firm.id,
      query: arg,
      afterId: afterId,
      limit: _pageSize,
    );
  }

  /// Asks for the next page. Safe to call repeatedly while one is in flight.
  Future<void> more() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    if (current.items.isEmpty) return;

    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await _read(afterId: current.items.last.id);
      state = AsyncData(
        Page(
          items: [...current.items, ...next],
          hasMore: next.length == _pageSize,
        ),
      );
    } on Object catch (error, stack) {
      // The page already on screen is still good. Losing it because the next
      // one failed would be a worse answer than showing what we have.
      state = AsyncData(current.copyWith(loadingMore: false));
      ref.read(pageErrorProvider.notifier).state = (error, stack);
    }
  }
}

/// The sales list, paged, narrowed to one [SaleFilter] (M30).
///
/// Keyed on the filter, so each search is its own list with its own cursor:
/// the next page of "Rashid, this month" is read with that filter, never by
/// filtering the next forty of everything.
final pagedSalesProvider = AsyncNotifierProvider.autoDispose
    .family<PagedSales, Page<SaleListRow>, SaleFilter>(PagedSales.new);

final class PagedSales
    extends AutoDisposeFamilyAsyncNotifier<Page<SaleListRow>, SaleFilter> {
  static const _pageSize = 40;

  @override
  Future<Page<SaleListRow>> build(SaleFilter filter) async {
    ref.watch(refreshTickProvider);
    final rows = await _read();
    return Page(items: rows, hasMore: rows.length == _pageSize);
  }

  Future<List<SaleListRow>> _read({String? afterId}) async {
    final services = ref.read(appServicesProvider);
    final firm = await ref.read(firmProvider.future);
    if (firm == null) return const [];
    return services.queries.recentSales(
      firm.id,
      afterId: afterId,
      limit: _pageSize,
      filter: arg,
    );
  }

  Future<void> more() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    if (current.items.isEmpty) return;

    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await _read(afterId: current.items.last.id);
      state = AsyncData(
        Page(
          items: [...current.items, ...next],
          hasMore: next.length == _pageSize,
        ),
      );
    } on Object catch (error, stack) {
      state = AsyncData(current.copyWith(loadingMore: false));
      ref.read(pageErrorProvider.notifier).state = (error, stack);
    }
  }
}

/// The last failure while loading a further page.
///
/// Held separately because it must not blank the list. A shopkeeper scrolling
/// a catalogue whose next page failed still has the page they were reading.
final pageErrorProvider = StateProvider<(Object, StackTrace)?>((ref) => null);

/// What is about to run out, worst first.
///
/// The query has existed and been tested since M1, the four Roman-Urdu strings
/// have been in both ARBs since M1, and until now nothing referenced either.
final lowStockProvider = FutureProvider.autoDispose<List<ItemSummary>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return const [];
  return services.queries.lowStockItems(firm.id);
});

/// What the shelves are worth, and how much of the shop is not on them.
///
/// One indexed aggregation rather than a fetch-and-sum: the largest cluster of
/// crash reports against the nearest competitor is reports on catalogues of a
/// few thousand items, and the cause is always adding rows up in Dart.
final stockSummaryProvider = FutureProvider.autoDispose<StockSummary>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return StockSummary.empty;
  return services.queries.stockSummary(firm.id);
});
