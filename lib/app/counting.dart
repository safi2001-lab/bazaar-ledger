import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'providers.dart';

/// Every item's packs, ready to count a quantity in (M45).
///
/// Built from the conversions and units the counter already holds — no
/// query of its own — and rebuilt when either changes, so a carton given to
/// an item in the editor is how the stock list counts it the moment the
/// editor closes. Until they load, every quantity reads as its figure, with
/// kilos as kilos and grams, which is how they read before M45.
final countingBookProvider = Provider<CountingBook>((ref) {
  final units = ref.watch(unitConverterProvider).valueOrNull;
  if (units == null) return CountingBook.none;
  final codes = ref.watch(unitsProvider).valueOrNull ?? const [];
  return CountingBook(units, codes: {for (final u in codes) u.id: u.code});
});

/// How [item]'s stock is shown in a list: in its own packs. "2 ctn + 5
/// pcs", "1 bori + 12 kg", or the figure as before for an item with none.
CountingLadder countingOf(WidgetRef ref, ItemSummary item) => ref
    .watch(countingBookProvider)
    .ladder(
      itemId: item.id,
      baseUnitId: item.unitId,
      baseUnitCode: item.unitCode,
      baseDecimals: item.unitDecimals,
    );

/// The same for an item known only by its id and unit, as a stock report
/// row or an item's history knows it.
CountingLadder countingOfItem(WidgetRef ref, String itemId, String unitCode) =>
    ref
        .watch(countingBookProvider)
        .ladder(itemId: itemId, baseUnitCode: unitCode);
