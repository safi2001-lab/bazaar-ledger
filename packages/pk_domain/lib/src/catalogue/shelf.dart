import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../sales/sale_draft.dart';
import 'quantity_words.dart';

/// What happens when a sale would take an item below nothing (M53).
///
/// The complaint this answers is a Pakistani shopkeeper's, in Vyapar's
/// reviews: seven hundred kilos sold against six hundred in stock, and not a
/// word said. A stock figure that can go negative in silence is a stock
/// figure nobody trusts, and the shop goes back to counting the sacks.
///
/// Three answers, as BUSY gives them, because shops differ:
///
///  * [allow] sells on. A shop that rings goods before the delivery is keyed
///    in, or a service with stock it never counts, wants no question.
///  * [warn] asks the cashier first — "only 600 kg on the shelf; sell
///    anyway?" — and sells if they say so. The figure goes negative knowingly.
///  * [block] refuses, in words. The owner changes the item's rule or puts
///    the stock right; nobody at the counter can talk past it.
///
/// Every shop has a setting of its own, and every item may say otherwise.
/// A new shop asks ([warn]): never silently, which is the whole point, and
/// never stopping a sale the shopkeeper means to make.
enum NegativeStock {
  allow,
  warn,
  block;

  /// As the item's column and the shop's setting hold it.
  String get code => name;

  /// [code] read back; null for nothing or anything this build does not
  /// know, which falls through to the shop's setting.
  static NegativeStock? fromCode(String? code) {
    for (final rule in values) {
      if (rule.code == code) return rule;
    }
    return null;
  }

  /// What a shop that never chose says.
  static const shopDefault = NegativeStock.warn;
}

/// The settings key the shop's own rule is kept under.
const negativeStockSettingKey = 'stock.negative';

/// One item's shelf, as the moment of sale sees it.
final class ShelfState {
  const ShelfState({
    required this.itemId,
    required this.itemName,
    required this.unitCode,
    required this.onHand,
    required this.rule,
    this.tracksStock = true,
  });

  final String itemId;
  final String itemName;

  /// The item's base unit, which [onHand] is counted in.
  final String unitCode;

  /// What is at the place the goods leave from: the shop floor, or the van a
  /// rider is selling from (M18). Not the godown — goods in the godown are
  /// not on the shelf until they are moved (M11).
  final Qty onHand;

  /// The rule that applies: the item's own, or the shop's.
  final NegativeStock rule;

  /// An item that carries no stock is never short.
  final bool tracksStock;
}

/// Reads [ShelfState]s at the moment of sale.
///
/// A port of its own rather than one more method on the sale and challan
/// writers, because the question is the same for both and for the counter
/// screen, and an answer read in two places by two queries is two answers.
/// Called inside the sale's own transaction, so the figure it reads is the
/// figure the sale will move.
abstract interface class ShelfReader {
  /// The shelf for each of [itemIds] at [locationCode]. An id that names no
  /// item in the firm is left out.
  Future<Map<String, ShelfState>> shelfFor(
    ActorContext actor,
    Iterable<String> itemIds, {
    required String locationCode,
  });
}

/// One item a bill wants more of than the shelf holds.
final class ShelfShort {
  const ShelfShort({required this.shelf, required this.wanted});

  final ShelfState shelf;

  /// What the bill takes, all its lines of the item together, in the base
  /// unit.
  final Qty wanted;

  String get itemId => shelf.itemId;
  NegativeStock get rule => shelf.rule;

  /// How far below nothing the sale would leave it.
  Qty get shortBy => wanted - shelf.onHand;

  /// "600 kg", "1 kg 500 g", "12 pcs": the shelf as the shop says it.
  String get onHandWords => quantityWords(shelf.onHand, shelf.unitCode);
  String get wantedWords => quantityWords(wanted, shelf.unitCode);
}

/// What each item on [lines] takes off the shelf, in its base unit.
///
/// Every line of one item counted together: a bill with a carton and six
/// loose pieces of the same biscuit takes thirty pieces, not twenty-four and
/// then six. Loose lines (M37) and items that carry no stock take nothing.
Map<String, Qty> shelfWanted(Iterable<SaleLineDraft> lines) {
  final wanted = <String, Qty>{};
  for (final line in lines) {
    final itemId = line.itemId;
    if (itemId == null || !line.tracksStock || !line.baseQty.isPositive) {
      continue;
    }
    wanted[itemId] = (wanted[itemId] ?? Qty.zero) + line.baseQty;
  }
  return wanted;
}

/// The items [wanted] would take below nothing, under any rule but
/// [NegativeStock.allow].
///
/// Pure, so the counter's question and the service's refusal are the same
/// arithmetic: the screen asks with it and the sale path refuses with it.
List<ShelfShort> shelfShortfalls(
  Map<String, Qty> wanted,
  Map<String, ShelfState> shelf,
) => [
  for (final MapEntry(key: itemId, value: qty) in wanted.entries)
    if (shelf[itemId] case final state?
        when state.tracksStock &&
            state.rule != NegativeStock.allow &&
            qty > state.onHand)
      ShelfShort(shelf: state, wanted: qty),
];

/// Refuses a sale or a challan that would take an item the shop has set to
/// [NegativeStock.block] below nothing.
///
/// The service's answer, beneath every screen: a counter that missed the
/// question — a bill restored after the app was killed, a stock figure that
/// moved while the bill was being rung — still cannot sell into thin air.
/// Nothing is written: it is thrown inside the sale's transaction, so no
/// bill, no number and no stock row survives it.
final class ShelfRefused implements Exception {
  const ShelfRefused(this.short);

  /// Every blocked item the bill is short of, not only the first.
  final List<ShelfShort> short;

  @override
  String toString() => short.map(_words).join('\n');

  static String _words(ShelfShort s) =>
      'Only ${s.onHandWords} of ${s.shelf.itemName} is in stock, and the '
      'bill takes ${s.wantedWords}. It is set not to sell below nothing: put '
      "the stock right, or change the item's rule.";
}

/// Throws [ShelfRefused] when [lines] would take a blocked item below
/// nothing at [locationCode]; does nothing otherwise.
///
/// Only [NegativeStock.block] is refused here. A [NegativeStock.warn] item
/// is the counter's question to ask, at the moment the line goes on and
/// again before the bill is saved; the cashier's yes is not something the
/// books can check after the fact, so the service lets it through and the
/// shelf reads below nothing, where the item list shows it.
Future<void> refuseBlockedShortfalls(
  ShelfReader reader,
  ActorContext actor,
  Iterable<SaleLineDraft> lines, {
  required String locationCode,
}) async {
  final wanted = shelfWanted(lines);
  if (wanted.isEmpty) return;
  final shelf = await reader.shelfFor(
    actor,
    wanted.keys,
    locationCode: locationCode,
  );
  final blocked = [
    for (final s in shelfShortfalls(wanted, shelf))
      if (s.rule == NegativeStock.block) s,
  ];
  if (blocked.isNotEmpty) throw ShelfRefused(blocked);
}
