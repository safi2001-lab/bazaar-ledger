import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/counting.dart';
import '../../app/providers.dart';
import '../../design/components.dart';
import '../../l10n/app_strings.dart';
import 'cart.dart';

// Two-unit quantities at the counter (M45): a line shown as "2 ctn + 5
// pcs", and "2 ctn 5" typed into its quantity box made into exactly 53
// pieces at the piece price. Its own file, so the counter's screen and the
// cart change by a few marked lines each.

/// [line]'s quantity in its item's own unit — what leaves the shelf — or
/// null when the conversions have not loaded or do not reach it.
Qty? lineBase(CartLine line, UnitConverter? units) {
  if (!line.isConverted) return line.qty;
  if (units == null) return null;
  try {
    return units.convert(
      line.qty,
      fromUnitId: line.sellingUnitId,
      toUnitId: line.item.unitId,
      itemId: line.item.id,
    );
  } on UnitConversionException {
    return null;
  }
}

/// How much one of the unit [line] is sold in holds in the item's own unit:
/// one piece, or the 24 of a carton.
Qty? lineUnitSize(CartLine line, UnitConverter? units) =>
    lineBase(line.copyWith(qty: Qty.one), units);

/// How [line] is counted: its item's packs and the unit it is being sold
/// in, the shop's dozen or mann included. [forEntry] also understands every
/// other unit that converts into the item exactly, for the quantity box.
CountingLadder lineCounting(
  CountingBook book,
  CartLine line, {
  bool forEntry = false,
}) {
  final item = line.item;
  final itemId = line.isLoose ? null : item.id;
  final baseUnitId = item.unitId.isEmpty ? null : item.unitId;
  // M54: a line moved to pieces from the dozen it was rung in still counts
  // in that dozen on the screen.
  final countedIn = line.isConverted
      ? line.sellingUnitId
      : line.countedInUnitId;
  return forEntry
      ? book.entryLadder(
          itemId: itemId,
          baseUnitCode: item.unitCode,
          baseUnitId: baseUnitId,
          baseDecimals: item.unitDecimals,
          countedInUnitId: countedIn,
        )
      : book.ladder(
          itemId: itemId,
          baseUnitCode: item.unitCode,
          baseUnitId: baseUnitId,
          baseDecimals: item.unitDecimals,
          countedInUnitId: countedIn,
        );
}

/// A line's quantity on the counter, as the shop counts it.
///
/// "2 ctn + 5 pcs" for fifty-three pieces of a carton-of-24 item, "2 ctn"
/// for two cartons, "2 maund" for two maunds of atta. It used to print the
/// figure beside the item's own unit whatever the line was sold in, so two
/// cartons read "2 pcs" on the very screen the cashier checks the bill on.
class CountedLineQty extends ConsumerWidget {
  const CountedLineQty({super.key, required this.line, this.size = 15});

  final CartLine line;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = lineBase(line, ref.watch(unitConverterProvider).valueOrNull);
    if (base == null) {
      return BlQty(
        line.qty,
        unit: line.sellingUnitCode.isEmpty ? null : line.sellingUnitCode,
        size: size,
      );
    }
    return BlQty(
      base,
      size: size,
      counting: lineCounting(ref.watch(countingBookProvider), line),
    );
  }
}

/// What the line editor's quantity box does to a line (M45): nothing, a
/// new quantity in the line's own unit, the whole line remade, or a reason
/// it cannot.
final class CountedEdit {
  const CountedEdit._({this.qty, this.line, this.problem});

  /// For [CartNotifier.setQty]: in the unit the line is already sold in.
  final Qty? qty;

  /// For [CartNotifier.setCounted]: the line in its item's own unit, its
  /// price carried there exactly.
  final CartLine? line;

  /// Said under the box, and the editor stays open.
  final String? problem;
}

/// Reads [typed] for [line] with [counting].
///
/// A figure alone is in the line's own unit, as it always was. A count —
/// "2 ctn 5" — is in the item's own unit, 53 pieces, and the line follows
/// it: where the count is a whole number of the unit the line is sold in it
/// stays in that unit ("3 ctn" on a carton line is three cartons), and
/// otherwise it moves to the item's own unit with the price carried there
/// exactly, Rs 960 a carton becoming Rs 40 a piece. Never 2.208 cartons: a
/// decimal of a pack on a bill is the thing this milestone exists to end.
///
/// A price that does not come out even per piece — Rs 1,000 for 24 — is
/// refused in words rather than rounded, as every unit change is (M1).
CountedEdit countedEdit(
  AppStrings s,
  String typed,
  CartLine line,
  CountingLadder counting,
  UnitConverter? units, {
  Rate? rate,
}) {
  if (typed.trim().isEmpty) return const CountedEdit._();
  final read = counting.read(typed);
  if (read == null) return CountedEdit._(problem: s.qtyNotUnderstood);
  if (read.bare) {
    // The keypad used to refuse a third decimal, or any decimal of a piece;
    // the box takes letters now, so it is refused here instead.
    if (read.qty.inThousandths % _smallest(line.item.unitDecimals) != 0) {
      return CountedEdit._(problem: s.qtyNotWhole(line.sellingUnitCode));
    }
    return CountedEdit._(qty: read.qty);
  }
  final base = read.qty;
  if (!base.isPositive) return const CountedEdit._(qty: Qty.zero);
  if (!line.isConverted || line.lotIds.isNotEmpty) {
    return CountedEdit._(qty: base);
  }
  if (units == null) return CountedEdit._(problem: s.qtyNotUnderstood);
  try {
    final inUnit = units.convert(
      base,
      fromUnitId: line.item.unitId,
      toUnitId: line.sellingUnitId,
      itemId: line.item.id,
    );
    if (inUnit.isWhole) return CountedEdit._(qty: inUnit);
  } on UnitConversionException {
    // Not a whole number of the line's unit; to the item's own, below.
  }
  final price = rate ?? line.rate;
  try {
    return CountedEdit._(
      line: line.copyWith(
        qty: base,
        rate: units.convertRate(
          price,
          fromUnitId: line.sellingUnitId,
          toUnitId: line.item.unitId,
          itemId: line.item.id,
        ),
        unitId: line.item.unitId,
        unitCode: line.item.unitCode,
        // M54: and still counted in the unit it was rung in, "3 doz + 4
        // pcs", rather than read out as forty pieces.
        countedInUnitId: line.sellingUnitId,
      ),
    );
  } on UnitConversionException {
    return CountedEdit._(
      problem: s.qtyPriceNotEven(
        price.amountOnly,
        line.sellingUnitCode,
        line.item.unitCode,
      ),
    );
  }
}

/// The smallest step [decimals] allows, in thousandths.
int _smallest(int decimals) => switch (decimals) {
  <= 0 => 1000,
  1 => 100,
  2 => 10,
  _ => 1,
};
