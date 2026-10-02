import 'package:pk_money/pk_money.dart';

/// A quantity as the shop says it out loud (M56).
///
/// "1.500 kg" is how a scale prints; "dedh kilo", one kilo and five hundred
/// grams, is how a shopkeeper reads it back. Users of every billing app in
/// this market complain about the same thing — decimals of a kilo nobody
/// can picture ("0.4756") — so a weight in kilos with grams in it is shown
/// as kilos and grams:
///
/// ```text
/// 1.5 kg    →  1 kg 500 g
/// 0.75 kg   →  750 g
/// 2 kg      →  2 kg
/// -0.25 kg  →  -250 g
/// ```
///
/// Kilos only, because that is where it is exact and unambiguous: stock is
/// held in thousandths of the item's unit, and a thousandth of a kilo is a
/// whole gram, so the split never rounds. Everything else — pieces, litres,
/// maunds — reads as the number and its unit, as before. A full two-unit
/// display ("2 ctn + 5 pcs", "1 mann 5 kg") is M45's; this is the one case
/// the counter and the stock list needed now.
///
/// For screens only. The printed bill keeps "1.5 kg x 300.00", where the
/// customer can check the multiplication.
String quantityWords(Qty qty, String unitCode) {
  if (unitCode != 'kg' || qty.isWhole) return '${qty.display} $unitCode';
  final sign = qty.isNegative ? '-' : '';
  final grams = qty.abs.inThousandths;
  final kilos = grams ~/ 1000;
  final rest = grams % 1000;
  return kilos == 0 ? '$sign$rest g' : '$sign$kilos kg $rest g';
}
