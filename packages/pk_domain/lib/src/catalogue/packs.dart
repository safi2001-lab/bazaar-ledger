import 'package:pk_money/pk_money.dart';

import 'unit_converter.dart';

/// One pack an item comes in, and how much of it the pack holds (M53).
///
/// A carton of biscuits is twenty-four packets, a dabba of matches twelve
/// boxes, a bori of atta fifty kilos. How many is a fact about the item —
/// the next carton on the shelf holds forty-eight sachets — so it is kept
/// on the item, as that item's own conversion from the pack to the unit its
/// stock is counted in, and never on the shop's units, where it would make
/// every carton the same size.
///
/// The pack is a way of counting, not a second stock: the shelf is still
/// counted in the base unit alone. A carton sold takes twenty-four pieces
/// off it, priced at twenty-four times the piece unless the line says
/// otherwise; a carton bought puts twenty-four on it at what the carton
/// cost. Both go through [UnitConverter], exactly or not at all.
final class ItemPack {
  const ItemPack({required this.unitId, required this.size, this.unitCode});

  /// The pack's unit: the shop's carton, dabba, bori.
  final String unitId;

  /// For the screen. The writer goes by [unitId].
  final String? unitCode;

  /// How much one pack holds, in the item's base unit: 24 pieces, 50 kg.
  final Qty size;

  /// [qty] of these packs in the item's base unit, exactly or not at all —
  /// the same arithmetic as the converter's, for a screen that has the pack
  /// in hand: a carton and a half of 24 is 36 pieces.
  Qty inBase(Qty qty) {
    final thousandths = qty.inThousandths * size.inThousandths;
    if (thousandths % 1000 != 0) {
      throw UnitConversionException(
        '${qty.display} ${unitCode ?? unitId} is not a whole number of the '
        "item's smallest unit.",
      );
    }
    return Qty.raw(thousandths ~/ 1000);
  }

  @override
  bool operator ==(Object other) =>
      other is ItemPack && other.unitId == unitId && other.size == size;

  @override
  int get hashCode => Object.hash(unitId, size);

  @override
  String toString() => '1 ${unitCode ?? unitId} = ${size.display}';
}

/// The shop's units an item may be packed in.
///
/// The packs M56 shipped with no size of their own (carton, dabba, packet,
/// strip) and the bori, which shipped with M53 for the same reason: flour
/// comes in 10, 40, 50 and 80 kg sacks and the shop decides which it means,
/// item by item. Not the dozen, the maund or the seer: those already have
/// one size for the whole shop, and a "dozen" of ten for one item would be a
/// lie on its bill.
const packUnitCodes = ['carton', 'dabba', 'packet', 'strip', 'bori'];

/// The packs [itemId] has, from the conversions the converter holds.
///
/// Only its own conversions into [baseUnitId]: each is a pack. A conversion
/// the whole shop shares is not one of this item's packs.
List<ItemPack> packsOf(
  UnitConverter units, {
  required String itemId,
  required String baseUnitId,
  Map<String, String> codes = const {},
}) => [
  for (final edge in units.ownEdgesOf(itemId))
    if (edge.toUnitId == baseUnitId)
      ItemPack(
        unitId: edge.fromUnitId,
        unitCode: codes[edge.fromUnitId],
        size: Qty.raw(edge.factorThousandths),
      ),
];

/// Why a list of packs cannot be kept, or null when it can.
///
/// Said in English for the log; the editor offers only what passes, so a
/// shopkeeper never reads these.
String? packProblem(
  List<ItemPack> packs, {
  required String baseUnitId,
  UnitConverter? shopUnits,
}) {
  final seen = <String>{};
  for (final pack in packs) {
    if (pack.unitId == baseUnitId) {
      return 'A pack cannot be the unit the item is counted in.';
    }
    if (!seen.add(pack.unitId)) {
      return 'One size per pack: ${pack.unitCode ?? pack.unitId} is there '
          'twice.';
    }
    if (!pack.size.isPositive) {
      return 'A pack has to hold something.';
    }
    // A unit the shop already converts for every item — the dozen, the
    // maund — has its size already. Giving one item a different one would
    // print "1 dozen" on a bill for ten.
    if (shopUnits != null &&
        shopUnits.canConvert(
          Qty.one,
          fromUnitId: pack.unitId,
          toUnitId: baseUnitId,
        )) {
      return '${pack.unitCode ?? pack.unitId} already has a size in this '
          'shop.';
    }
  }
  return null;
}
