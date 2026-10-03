/// The profit on a bill while it is being made (M66): "Munafa Rs 1,240
/// (12.5%)", and a line sold below what it cost said in red.
///
/// Marg puts the bill's gross profit on Ctrl+F7 and lets the owner hide it
/// from a user; Vyapar's "Show profit while making sale invoice" is a
/// premium setting. Here it is a figure for whoever may see costs (M9's
/// `seeCosts`), worked out by the books' own rule: what the goods sell for
/// before tax — the bill's own discounts, line and bill, already off — less
/// what they cost at the weighted average, which is exactly the cost the
/// sale will post (`SaleCalculator`, `CalculatedSale.grossProfit`). A free
/// line (M43) sells for nothing and still costs what it cost, so a 10+1
/// shows what the scheme really gave away; a loose line (M37) has no item
/// and so no cost, as the books have it.
///
/// Pure: the screen hands it the counter's own preview and the costs it may
/// read.
library;

import 'package:pk_money/pk_money.dart';

import '../sales/sale_calculator.dart';

/// One item's share of a bill: what it sells for and what it costs.
final class LineMargin {
  const LineMargin({
    required this.key,
    required this.name,
    required this.sale,
    required this.cost,
  });

  /// The item's id, or a loose line's name.
  final String key;
  final String name;

  /// What it sells for before tax, after every discount.
  final Money sale;

  /// What it costs, at the average, free goods of it included.
  final Money cost;

  Money get profit => sale - cost;

  /// Profit on what it sells for, in basis points; 0 on nothing sold.
  int get marginBp => marginOf(profit, sale);

  /// Sold for less than it cost: "Qeemat se kam".
  bool get belowCost => profit.isNegative;
}

/// A whole bill's margin.
final class BillMargin {
  const BillMargin({required this.lines});

  /// By item, in the order the bill first rings each.
  final List<LineMargin> lines;

  Money get sale => Money.sum([for (final l in lines) l.sale]);
  Money get cost => Money.sum([for (final l in lines) l.cost]);
  Money get profit => sale - cost;
  int get marginBp => marginOf(profit, sale);

  /// Whether any line sells below what it cost.
  bool get anyBelowCost => lines.any((l) => l.belowCost);

  /// [key]'s share, or null when it is not on the bill.
  LineMargin? forKey(String key) {
    for (final l in lines) {
      if (l.key == key) return l;
    }
    return null;
  }

  /// [sale] as the counter previews it, at [costs] per each item's own
  /// unit (the items' averages). An item whose cost is not known is costed
  /// at nothing, as the books would post it.
  static BillMargin fromSale(CalculatedSale sale, Map<String, Rate> costs) {
    final order = <String>[];
    final names = <String, String>{};
    final sold = <String, Money>{};
    final cost = <String, Money>{};
    for (final line in sale.lines) {
      final draft = line.draft;
      final key = draft.itemId ?? draft.itemName;
      if (!sold.containsKey(key)) {
        order.add(key);
        names[key] = draft.itemName;
        sold[key] = Money.zero;
        cost[key] = Money.zero;
      }
      sold[key] = sold[key]! + line.taxable;
      final unit = draft.itemId == null ? null : costs[draft.itemId];
      if (unit != null) {
        cost[key] =
            cost[key]! +
            unit.amountFor(draft.baseQty, mode: RoundingMode.halfUp);
      }
    }
    return BillMargin(
      lines: [
        for (final k in order)
          LineMargin(key: k, name: names[k]!, sale: sold[k]!, cost: cost[k]!),
      ],
    );
  }
}

/// [profit] as a share of [sale], in basis points, half away from nought.
int marginOf(Money profit, Money sale) {
  if (!sale.isPositive) return 0;
  final p = profit.inPaisa * 10000;
  final half = sale.inPaisa ~/ 2;
  return p >= 0 ? (p + half) ~/ sale.inPaisa : -((-p + half) ~/ sale.inPaisa);
}

/// "12.5%", "-3%": a margin as a shopkeeper reads it, to one place.
String marginLabel(int bp) {
  final negative = bp < 0;
  final tenths = ((negative ? -bp : bp) + 5) ~/ 10;
  final whole = tenths ~/ 10;
  final part = tenths % 10;
  final text = part == 0 ? '$whole%' : '$whole.$part%';
  return negative ? '-$text' : text;
}
