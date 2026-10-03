import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/counting.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

// Two-unit quantities on a delivery (M45): a supplier's bill for "10 ctn 5
// pcs" typed as it is written, and every line on the delivery said back in
// cartons. Its own file, so the delivery screens change by a few marked
// lines each.

/// What the delivery picker's quantity box holds: the quantity as billed,
/// the same in the item's own unit, and the pack it is billed in (null for
/// the item's own unit).
typedef PurchaseCount = ({Qty qty, Qty base, ItemPack? pack});

/// Reads [typed] for a delivery line whose pack chip says [pack].
///
/// A figure alone is in the chosen pack, as it always was: "10" with the
/// carton chip on is ten cartons. A count — "10 ctn 5" — is in the item's
/// own unit, 245 pieces, and is billed by the carton only where it is a
/// whole number of them; otherwise by the piece, so the bill never says
/// 10.208 cartons. Null when it cannot be read exactly.
PurchaseCount? purchaseCount(
  String typed,
  CountingLadder counting,
  ItemPack? pack,
) {
  final read = counting.read(typed);
  if (read == null) return null;
  if (read.bare) {
    if (pack == null) return (qty: read.qty, base: read.qty, pack: null);
    try {
      return (qty: read.qty, base: pack.inBase(read.qty), pack: pack);
    } on UnitConversionException {
      return null;
    }
  }
  final base = read.qty;
  if (pack != null && base.inThousandths % pack.size.inThousandths == 0) {
    final packs = base.inThousandths ~/ pack.size.inThousandths;
    return (qty: Qty.units(packs), base: base, pack: pack);
  }
  return (qty: base, base: base, pack: null);
}

/// A delivery line said back in the item's packs, under its figure: "Yani
/// 10 ctn + 5 pcs (245 pcs)". Nothing where the figure already says it.
class PurchaseLineCount extends ConsumerWidget {
  const PurchaseLineCount({super.key, required this.line});

  final PurchaseLineDraft line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = ref.watch(countingBookProvider);
    // The item's own unit: where its packs count into, or the line's unit
    // where the line is in it (its figure and the shelf's are the same).
    final base =
        book.baseCodeOf(line.itemId) ??
        (line.qty == line.baseQty ? line.unitCode : null);
    if (base == null) return const SizedBox.shrink();
    final packs = book.packsOf(line.itemId, baseUnitCode: base);
    final said = paperQuantity(
      qty: line.qty,
      unitCode: line.unitCode,
      baseQty: line.baseQty,
      baseCode: base,
      packs: packs,
    );
    if (said == null) return const SizedBox.shrink();
    final ladder = lineLadder(
      qty: line.qty,
      unitCode: line.unitCode,
      baseQty: line.baseQty,
      baseCode: base,
      packs: packs,
    );
    return Text(
      AppStrings.of(context).qtyCountedAs(
        ladder.words(line.baseQty),
        '${line.baseQty.display} $base',
      ),
      style: TextStyle(fontSize: 13, color: context.bl.inkMuted),
    );
  }
}
