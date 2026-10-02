import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'item_stock_source.dart';
import 'period.dart';
import 'report_table.dart';

/// The item and stock reports (M34): every one the market's apps have, and
/// the two a shop asks for that Vyapar does not answer, the stock that has
/// stopped selling and how long the shelf has been holding it.
///
/// Pure builders, like every other report: each total is on the table
/// before the screen or an export sees it, and the screen adds nothing up.
/// A row that is an item opens that item's stock history.

/// The defaults a stock report reads with until the shop chooses its own
/// (M34). Each is printed in the report's notes, so a list of what to
/// order never hides the arithmetic behind it.
abstract final class StockDefaults {
  /// Days of selling the low stock list averages over.
  static const lowStockDays = 30;

  /// Days of selling a reorder is meant to last: a fortnight, about the
  /// time between one wholesaler's visit and the next.
  static const coverDays = 15;

  /// Days of selling the fast, slow and dead stock looks back over. Three
  /// months: an item nobody has asked for in a season is dead stock.
  static const movementDays = 90;

  /// Bills in that time from which an item is fast-moving.
  static const fastAt = 10;

  /// Bills in that time below which an item is slow-moving.
  static const slowBelow = 3;
}

/// Items with no category, and khula maal, which has no item to have one.
const _uncategorised = 'No category';

String _categoryOf(String? category) {
  final c = category?.trim() ?? '';
  return c.isEmpty ? _uncategorised : c;
}

ReportLink _item(String id, String name, String unitCode) =>
    ReportLink.item(id, label: name, unitCode: unitCode);

String _count(int n, String one, String many) => n == 1 ? '1 $one' : '$n $many';

int _byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

Money _each(Rate rate) => rate.amountFor(Qty.one);

const _baseUnits =
    'Quantities are in each item\'s own base unit, and a total adds them as '
    'they are: kilos and pieces in one category add up to a count, not a '
    'weight.';

const _atBookValue =
    'Value is what the books carry the stock at: every delivery, sale, '
    'return, count and move as it went through Inventory. Cost is that '
    'value for one unit, or the item\'s average cost where none is on the '
    'shelf.';

String _belowNothing(int items) {
  final what = items == 1 ? '1 item shows' : '$items items show';
  return '$what less than nothing on the shelf, in red: more was sold than '
      'was recorded coming in.';
}

String _againstBooks(Money stock, Money books) => stock == books
    ? 'The stock value agrees with Inventory in the books.'
    : 'The stock value and Inventory in the books differ. Run the data '
          'health check in Settings.';

/// The stock summary (M34): every stocked item with what it sells for,
/// what it cost, how much is on the shelf and what the books carry it at,
/// at the close of [asOf].
///
/// [inBooks] is Inventory in the books on the same day, given when the
/// report is not narrowed: the whole shelf, valued as the books value it,
/// is that figure to the paisa, and the report says so.
ReportTable stockSummary(
  BusinessDate asOf,
  List<StockLine> lines, {
  Money? inBooks,
}) {
  final rows = lines.toList()..sort((a, b) => _byName(a.itemName, b.itemName));
  final qty = Qty.sum(rows.map((l) => l.qty));
  final value = Money.sum(rows.map((l) => l.value));
  final short = rows.where((l) => l.qty.isNegative).length;
  return ReportTable(
    id: 'stock_summary',
    title: 'Stock summary',
    period: ReportPeriod.day(asOf),
    columns: const [
      ReportColumn('Item', CellKind.text),
      ReportColumn('Category', CellKind.text),
      ReportColumn('Unit', CellKind.text),
      ReportColumn('Sale price', CellKind.money),
      ReportColumn('Cost', CellKind.money, isCost: true),
      ReportColumn('Stock', CellKind.qty),
      ReportColumn('Value', CellKind.money, isCost: true),
    ],
    rows: [
      for (final l in rows)
        ReportRow([
          l.itemName,
          _categoryOf(l.category),
          l.unitCode,
          _each(l.saleRate),
          _each(l.unitCost),
          l.qty,
          l.value,
        ], link: _item(l.itemId, l.itemName, l.unitCode)),
      ReportRow([
        'Total',
        _count(rows.length, 'item', 'items'),
        null,
        null,
        null,
        qty,
        value,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('Items', rows.length),
      ReportFigure('Stock value', value, isCost: true),
      if (inBooks != null)
        ReportFigure('Inventory in the books', inBooks, isCost: true),
    ],
    notes: [
      _atBookValue,
      if (inBooks != null) _againstBooks(value, inBooks),
      if (short > 0) _belowNothing(short),
      _baseUnits,
    ],
  );
}

/// The stock summary by item category (M34): how many items, how much and
/// what it is worth, a category at a time.
ReportTable stockSummaryByCategory(BusinessDate asOf, List<StockLine> lines) {
  final groups = <String, ({int items, Qty qty, Money value})>{};
  for (final l in lines) {
    final name = _categoryOf(l.category);
    final was = groups[name];
    groups[name] = (
      items: (was?.items ?? 0) + 1,
      qty: (was?.qty ?? Qty.zero) + l.qty,
      value: (was?.value ?? Money.zero) + l.value,
    );
  }
  final names = groups.keys.toList()..sort(_byName);
  final value = Money.sum(groups.values.map((g) => g.value));
  return ReportTable(
    id: 'stock_summary_by_category',
    title: 'Stock summary by item category',
    period: ReportPeriod.day(asOf),
    columns: const [
      ReportColumn('Category', CellKind.text),
      ReportColumn('Items', CellKind.count),
      ReportColumn('Stock', CellKind.qty),
      ReportColumn('Value', CellKind.money, isCost: true),
    ],
    rows: [
      for (final n in names)
        ReportRow([n, groups[n]!.items, groups[n]!.qty, groups[n]!.value]),
      ReportRow([
        'Total',
        groups.values.fold<int>(0, (n, g) => n + g.items),
        Qty.sum(groups.values.map((g) => g.qty)),
        value,
      ], style: RowStyle.total),
    ],
    summary: [ReportFigure('Stock value', value, isCost: true)],
    notes: const [_atBookValue, _baseUnits],
  );
}

/// The stock detail (M34): every item over [period], from what it opened
/// with, through everything that came in and went out, to what it closed
/// on, in quantity and in the value the books carry.
///
/// Opening plus what came in, less what went out, plus or minus what was
/// adjusted, is the closing, for every item. [openingInBooks] and
/// [closingInBooks] are Inventory in the books at either end, given when
/// the report is not narrowed: the opening and closing values add up to
/// them to the paisa, and the report says whether they do.
ReportTable stockDetail(
  ReportPeriod period,
  List<StockFlow> flows, {
  Money? openingInBooks,
  Money? closingInBooks,
}) {
  final rows = flows.toList()..sort((a, b) => _byName(a.itemName, b.itemName));
  final moved = rows.fold(StockMoves.none, (sum, f) => sum + f.moves);
  final openingQty = Qty.sum(rows.map((f) => f.openingQty));
  final openingValue = Money.sum(rows.map((f) => f.openingValue));
  final closingQty = openingQty + moved.net;
  final closingValue = Money.sum(
    rows.map((f) => f.openingValue + f.movedValue),
  );

  List<Object?> movements(StockMoves m) => [
    m.purchased,
    m.returnsIn,
    m.transfersIn,
    m.produced,
    m.sold,
    m.returnsOut,
    m.transfersOut,
    m.used,
    m.wasted,
    m.adjusted,
  ];

  return ReportTable(
    id: 'stock_detail',
    title: 'Stock detail',
    period: period,
    columns: const [
      ReportColumn('Item', CellKind.text),
      ReportColumn('Unit', CellKind.text),
      ReportColumn('Opening', CellKind.qty),
      ReportColumn('Opening value', CellKind.money, isCost: true),
      ReportColumn('Purchased', CellKind.qty),
      ReportColumn('Returns in', CellKind.qty),
      ReportColumn('Moved in', CellKind.qty),
      ReportColumn('Made', CellKind.qty),
      ReportColumn('Sold', CellKind.qty),
      ReportColumn('Returns out', CellKind.qty),
      ReportColumn('Moved out', CellKind.qty),
      ReportColumn('Used', CellKind.qty),
      ReportColumn('Wasted', CellKind.qty),
      ReportColumn('Adjusted', CellKind.qty),
      ReportColumn('Closing', CellKind.qty),
      ReportColumn('Closing value', CellKind.money, isCost: true),
    ],
    rows: [
      for (final f in rows)
        ReportRow([
          f.itemName,
          f.unitCode,
          f.openingQty,
          f.openingValue,
          ...movements(f.moves),
          f.openingQty + f.moves.net,
          f.openingValue + f.movedValue,
        ], link: _item(f.itemId, f.itemName, f.unitCode)),
      ReportRow([
        'Total',
        _count(rows.length, 'item', 'items'),
        openingQty,
        openingValue,
        ...movements(moved),
        closingQty,
        closingValue,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Opening value', openingValue, isCost: true),
      ReportFigure('Closing value', closingValue, isCost: true),
      if (closingInBooks != null)
        ReportFigure('Inventory in the books', closingInBooks, isCost: true),
    ],
    notes: [
      _openingPlusInLessOut,
      _adjustedIs,
      if (openingInBooks != null && closingInBooks != null)
        openingValue == openingInBooks && closingValue == closingInBooks
            ? 'The opening and closing values agree with Inventory in the '
                  'books on both days.'
            : 'The values and Inventory in the books differ. Run the data '
                  'health check in Settings.',
      _baseUnits,
    ],
  );
}

const _openingPlusInLessOut =
    'Opening, plus what came in, less what went out, plus or minus what was '
    'adjusted, is the closing. Moved in and out are goods taken between the '
    'shop floor, godowns and vans; made and used are production runs.';

const _adjustedIs =
    'Adjusted is stock counted in or out by hand, opening stock entered in '
    'the period, and the goods of a cancelled bill going out and coming '
    'back. Sold is bills and challans that stand.';

/// One item's stock day by day over [period] (M34): what it opened each day
/// with, what came and went, and what it closed on. Only the days it moved
/// are listed; the rest would only repeat the day before.
ReportTable itemDetail(ReportPeriod period, ItemHistory? history) {
  const columns = [
    ReportColumn('Date', CellKind.text),
    ReportColumn('Opening', CellKind.qty),
    ReportColumn('Purchased', CellKind.qty),
    ReportColumn('Sold', CellKind.qty),
    ReportColumn('Returns in', CellKind.qty),
    ReportColumn('Returns out', CellKind.qty),
    ReportColumn('Production', CellKind.qty),
    ReportColumn('Moved', CellKind.qty),
    ReportColumn('Adjusted', CellKind.qty),
    ReportColumn('Closing', CellKind.qty),
  ];
  if (history == null) {
    return ReportTable(
      id: 'item_detail',
      title: 'Item detail',
      period: period,
      columns: columns,
      rows: const [],
      notes: const [_chooseAnItem],
    );
  }
  final days = history.days.toList()
    ..sort((a, b) => a.date.value.compareTo(b.date.value));

  List<Object?> movements(StockMoves m) => [
    m.purchased,
    m.sold,
    m.returnsIn,
    m.returnsOut,
    m.produced - m.used,
    m.transfersIn - m.transfersOut,
    m.adjusted - m.wasted,
  ];

  var running = history.openingQty;
  final rows = <ReportRow>[
    for (final d in days)
      () {
        final opening = running;
        running = running + d.moves.net;
        return ReportRow([
          d.date.value,
          opening,
          ...movements(d.moves),
          running,
        ]);
      }(),
  ];
  final all = days.fold(StockMoves.none, (sum, d) => sum + d.moves);
  return ReportTable(
    id: 'item_detail',
    title: 'Item detail: ${history.itemName}',
    period: period,
    columns: columns,
    rows: [
      ...rows,
      ReportRow([
        'Total',
        history.openingQty,
        ...movements(all),
        history.openingQty + all.net,
      ], style: RowStyle.total),
    ],
    notes: [
      'Quantities are in ${history.unitCode}; only the days it moved show.',
      _productionMovedAdjusted,
    ],
  );
}

const _productionMovedAdjusted =
    'Production is what was made less what was used; moved is what came in '
    'from other places less what went out to them; adjusted includes stock '
    'written off.';

const _chooseAnItem = 'Choose an item to see its stock day by day.';

/// Item-wise profit and loss (M34): what each item sold for over [period],
/// net of returns, against what the goods cost as each bill recorded it,
/// most profitable first. Its total is the period's bill-wise profit.
ReportTable itemProfitAndLoss(ReportPeriod period, List<ItemTrade> trades) {
  final rows =
      trades
          .where(
            (t) =>
                !t.netSales.isZero || !t.netCost.isZero || !t.netQtySold.isZero,
          )
          .toList()
        ..sort((a, b) {
          final byProfit = b.profit.compareTo(a.profit);
          return byProfit != 0 ? byProfit : _byName(a.itemName, b.itemName);
        });
  final sales = Money.sum(rows.map((t) => t.netSales));
  final cost = Money.sum(rows.map((t) => t.netCost));
  final profit = sales - cost;
  final losing = rows.where((t) => t.profit.isNegative).length;
  final loose = rows.any((t) => t.isLoose);
  return ReportTable(
    id: 'item_profit_and_loss',
    title: 'Item-wise profit and loss',
    period: period,
    columns: const [
      ReportColumn('Item', CellKind.text),
      ReportColumn('Category', CellKind.text),
      ReportColumn('Qty sold', CellKind.qty),
      ReportColumn('Unit', CellKind.text),
      ReportColumn('Sales', CellKind.money),
      ReportColumn('Cost', CellKind.money, isCost: true),
      ReportColumn('Profit', CellKind.money, isCost: true),
      ReportColumn('Margin', CellKind.percent, isCost: true),
    ],
    rows: [
      for (final t in rows)
        ReportRow(
          [
            t.itemName,
            _categoryOf(t.category),
            t.isLoose ? null : t.netQtySold,
            t.unitCode,
            t.netSales,
            t.isLoose ? null : t.netCost,
            t.profit,
            t.isLoose ? null : shareBp(t.profit, t.netSales),
          ],
          link: t.itemId == null
              ? null
              : _item(t.itemId!, t.itemName, t.unitCode),
        ),
      ReportRow([
        'Total',
        _count(rows.length, 'item', 'items'),
        null,
        null,
        sales,
        cost,
        profit,
        shareBp(profit, sales),
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Sales', sales),
      ReportFigure('Cost', cost, isCost: true),
      ReportFigure('Profit', profit, isCost: true),
    ],
    notes: [
      _salesNetOfReturns,
      if (losing > 0)
        losing == 1
            ? '1 item sold below cost.'
            : '$losing items sold below cost.',
      if (loose) _looseHasNoCost,
    ],
  );
}

const _looseHasNoCost =
    '${ItemTrade.looseLines} is goods sold by the rupee with no item behind '
    'them: no cost was recorded, so the books count all of it as profit, '
    'and so do the totals here.';

const _salesNetOfReturns =
    'Sales are before tax and after every discount, less returns. Cost is '
    'what the goods cost when they left the shelf, as each bill recorded '
    'it, less what came back.';

/// Item category-wise profit and loss (M34): the same, a category at a
/// time.
ReportTable categoryProfitAndLoss(ReportPeriod period, List<ItemTrade> trades) {
  final groups = <String, ({int items, Money sales, Money cost})>{};
  var loose = false;
  for (final t in trades) {
    if (t.netSales.isZero && t.netCost.isZero && t.netQtySold.isZero) {
      continue;
    }
    loose = loose || t.isLoose;
    final name = _categoryOf(t.category);
    final was = groups[name];
    groups[name] = (
      items: (was?.items ?? 0) + (t.isLoose ? 0 : 1),
      sales: (was?.sales ?? Money.zero) + t.netSales,
      cost: (was?.cost ?? Money.zero) + t.netCost,
    );
  }
  Money profitOf(String n) => groups[n]!.sales - groups[n]!.cost;
  final names = groups.keys.toList()
    ..sort((a, b) {
      final byProfit = profitOf(b).compareTo(profitOf(a));
      return byProfit != 0 ? byProfit : _byName(a, b);
    });
  final sales = Money.sum(groups.values.map((g) => g.sales));
  final cost = Money.sum(groups.values.map((g) => g.cost));
  final profit = sales - cost;
  return ReportTable(
    id: 'category_profit_and_loss',
    title: 'Item category-wise profit and loss',
    period: period,
    columns: const [
      ReportColumn('Category', CellKind.text),
      ReportColumn('Items', CellKind.count),
      ReportColumn('Sales', CellKind.money),
      ReportColumn('Cost', CellKind.money, isCost: true),
      ReportColumn('Profit', CellKind.money, isCost: true),
      ReportColumn('Margin', CellKind.percent, isCost: true),
    ],
    rows: [
      for (final n in names)
        ReportRow([
          n,
          groups[n]!.items,
          groups[n]!.sales,
          groups[n]!.cost,
          profitOf(n),
          shareBp(profitOf(n), groups[n]!.sales),
        ]),
      ReportRow([
        'Total',
        groups.values.fold<int>(0, (n, g) => n + g.items),
        sales,
        cost,
        profit,
        shareBp(profit, sales),
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Sales', sales),
      ReportFigure('Cost', cost, isCost: true),
      ReportFigure('Profit', profit, isCost: true),
    ],
    notes: [
      _salesNetOfReturns,
      if (loose) '$_looseHasNoCost It is under $_uncategorised.',
    ],
  );
}

/// Sale and purchase by item category (M34): how much of each category was
/// sold and bought over [period], and for how much, net of returns either
/// way.
ReportTable salePurchaseByCategory(
  ReportPeriod period,
  List<ItemTrade> trades,
) {
  final groups =
      <String, ({Qty sold, Money sales, Qty bought, Money purchases})>{};
  for (final t in trades) {
    final name = _categoryOf(t.category);
    final was = groups[name];
    // Khula maal has no unit to count it in; its money is counted, under
    // no category, and its quantity is not.
    groups[name] = (
      sold: (was?.sold ?? Qty.zero) + (t.isLoose ? Qty.zero : t.netQtySold),
      sales: (was?.sales ?? Money.zero) + t.netSales,
      bought: (was?.bought ?? Qty.zero) + t.netQtyBought,
      purchases: (was?.purchases ?? Money.zero) + t.netPurchases,
    );
  }
  groups.removeWhere(
    (_, g) =>
        g.sold.isZero &&
        g.sales.isZero &&
        g.bought.isZero &&
        g.purchases.isZero,
  );
  final names = groups.keys.toList()
    ..sort((a, b) {
      final bySales = groups[b]!.sales.compareTo(groups[a]!.sales);
      return bySales != 0 ? bySales : _byName(a, b);
    });
  final sales = Money.sum(groups.values.map((g) => g.sales));
  final purchases = Money.sum(groups.values.map((g) => g.purchases));
  return ReportTable(
    id: 'sale_purchase_by_category',
    title: 'Sale and purchase by item category',
    period: period,
    columns: const [
      ReportColumn('Category', CellKind.text),
      ReportColumn('Sold qty', CellKind.qty),
      ReportColumn('Sale amount', CellKind.money),
      ReportColumn('Bought qty', CellKind.qty),
      ReportColumn('Purchase amount', CellKind.money),
    ],
    rows: [
      for (final n in names)
        ReportRow([
          n,
          groups[n]!.sold,
          groups[n]!.sales,
          groups[n]!.bought,
          groups[n]!.purchases,
        ]),
      ReportRow([
        'Total',
        Qty.sum(groups.values.map((g) => g.sold)),
        sales,
        Qty.sum(groups.values.map((g) => g.bought)),
        purchases,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Sale amount', sales),
      ReportFigure('Purchase amount', purchases),
    ],
    notes: const [_amountsNet, _baseUnits],
  );
}

const _amountsNet =
    'Amounts are before tax and after every discount, less returns either '
    'way.';

/// What one item did with each party over [period] (M34): who bought it
/// and who supplied it, net of returns, the biggest buyer first. Empty,
/// and asking for one, until an item is chosen.
ReportTable itemByParty(
  ReportPeriod period,
  List<ItemPartyTrade> parties, {
  String? itemName,
}) {
  const columns = [
    ReportColumn('Party', CellKind.text),
    ReportColumn('Sold qty', CellKind.qty),
    ReportColumn('Sale amount', CellKind.money),
    ReportColumn('Bought qty', CellKind.qty),
    ReportColumn('Purchase amount', CellKind.money),
  ];
  if (itemName == null) {
    return ReportTable(
      id: 'item_by_party',
      title: 'Item report by party',
      period: period,
      columns: columns,
      rows: const [],
      notes: const ['Choose an item to see who bought and supplied it.'],
    );
  }
  final rows =
      parties
          .where(
            (p) =>
                !p.qtySold.isZero ||
                !p.saleAmount.isZero ||
                !p.qtyBought.isZero ||
                !p.purchaseAmount.isZero,
          )
          .toList()
        ..sort((a, b) {
          final bySales = b.saleAmount.compareTo(a.saleAmount);
          if (bySales != 0) return bySales;
          final byPurchases = b.purchaseAmount.compareTo(a.purchaseAmount);
          return byPurchases != 0 ? byPurchases : _byName(a.name, b.name);
        });
  final sold = Qty.sum(rows.map((p) => p.qtySold));
  final sales = Money.sum(rows.map((p) => p.saleAmount));
  final bought = Qty.sum(rows.map((p) => p.qtyBought));
  final purchases = Money.sum(rows.map((p) => p.purchaseAmount));
  return ReportTable(
    id: 'item_by_party',
    title: 'Item report by party: $itemName',
    period: period,
    columns: columns,
    rows: [
      for (final p in rows)
        ReportRow(
          [p.name, p.qtySold, p.saleAmount, p.qtyBought, p.purchaseAmount],
          link: p.partyId == null
              ? null
              : ReportLink.party(p.partyId!, label: p.name),
        ),
      ReportRow([
        'Total',
        sold,
        sales,
        bought,
        purchases,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Sale amount', sales),
      ReportFigure('Purchase amount', purchases),
    ],
    notes: const [_amountsNet],
  );
}

/// The item-wise discount (M34): what came off each item's price over
/// [period], line discounts and each line's share of a discount on the
/// whole bill, as the bill itself apportioned it. The biggest giveaway
/// first; an item only ever sold at its price is left out.
ReportTable itemDiscount(ReportPeriod period, List<ItemTrade> trades) {
  final rows = trades.where((t) => !t.discount.isZero).toList()
    ..sort((a, b) {
      final byDiscount = b.discount.compareTo(a.discount);
      return byDiscount != 0 ? byDiscount : _byName(a.itemName, b.itemName);
    });
  final gross = Money.sum(rows.map((t) => t.salesGross));
  final discount = Money.sum(rows.map((t) => t.discount));
  return ReportTable(
    id: 'item_discount',
    title: 'Item-wise discount',
    period: period,
    columns: const [
      ReportColumn('Item', CellKind.text),
      ReportColumn('Qty sold', CellKind.qty),
      ReportColumn('Unit', CellKind.text),
      ReportColumn('Before discount', CellKind.money),
      ReportColumn('Discount', CellKind.money),
      ReportColumn('Discount %', CellKind.percent),
      ReportColumn('After discount', CellKind.money),
    ],
    rows: [
      for (final t in rows)
        ReportRow(
          [
            t.itemName,
            t.isLoose ? null : t.qtySold,
            t.unitCode,
            t.salesGross,
            t.discount,
            shareBp(t.discount, t.salesGross),
            t.salesGross - t.discount,
          ],
          link: t.itemId == null
              ? null
              : _item(t.itemId!, t.itemName, t.unitCode),
        ),
      ReportRow([
        'Total',
        null,
        _count(rows.length, 'item', 'items'),
        gross,
        discount,
        shareBp(discount, gross),
        gross - discount,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Discount given', discount),
      ReportFigure('Before discount', gross),
    ],
    notes: const [_discountIs],
  );
}

const _discountIs =
    'Discount is each line\'s own and its share of a discount on the whole '
    'bill, the way the bill split it, which is the Discount Given account. '
    'Before discount is the lines at their rate. Items sold only at their '
    'price are left out.';

/// The low stock summary (M34): every item at or below the floor the shop
/// set for it, the worst first, with who last supplied it and how much to
/// order.
///
/// The order is the average day's selling over [salesDays], times
/// [coverDays], less what is on the shelf, and never less than what puts
/// the shelf back up to its floor, in whole units rounded up.
ReportTable lowStockSummary(
  BusinessDate asOf,
  List<LowStockLine> lines, {
  int salesDays = StockDefaults.lowStockDays,
  int coverDays = StockDefaults.coverDays,
}) {
  int worst(LowStockLine l) => l.minStock.isPositive
      ? divideRounded(
          l.stock.inThousandths * 1000,
          l.minStock.inThousandths,
          RoundingMode.truncate,
        )
      : 0;
  final rows = lines.toList()
    ..sort((a, b) {
      final byWorst = worst(a).compareTo(worst(b));
      return byWorst != 0 ? byWorst : _byName(a.itemName, b.itemName);
    });
  final out = rows.where((l) => !l.stock.isPositive).length;
  return ReportTable(
    id: 'low_stock',
    title: 'Low stock summary',
    period: ReportPeriod.day(asOf),
    columns: [
      const ReportColumn('Item', CellKind.text),
      const ReportColumn('Unit', CellKind.text),
      const ReportColumn('Minimum', CellKind.qty),
      const ReportColumn('Stock', CellKind.qty),
      const ReportColumn('Short by', CellKind.qty),
      ReportColumn('Sold in $salesDays days', CellKind.qty),
      const ReportColumn('Last supplier', CellKind.text),
      const ReportColumn('Order', CellKind.qty),
    ],
    rows: [
      for (final l in rows)
        ReportRow([
          l.itemName,
          l.unitCode,
          l.minStock,
          l.stock,
          l.minStock - l.stock,
          l.sold,
          l.lastSupplier ?? '',
          reorderQty(l, salesDays: salesDays, coverDays: coverDays),
        ], link: _item(l.itemId, l.itemName, l.unitCode)),
      ReportRow([
        'Total',
        _count(rows.length, 'item', 'items'),
        null,
        null,
        null,
        null,
        null,
        null,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('Items to order', rows.length),
      ReportFigure.count('Out of stock', out),
    ],
    notes: [
      _orderIs(salesDays, coverDays),
      'Only items given a minimum are listed.',
    ],
  );
}

String _orderIs(int salesDays, int coverDays) =>
    'Order is the average day\'s selling over the last $salesDays days, '
    'times $coverDays days, less what is on the shelf, and never less than '
    'what brings it back up to its minimum; in whole units, rounded up.';

/// How much of [line] to order (M34): enough for [coverDays] of the
/// selling it saw over [salesDays], less what is on the shelf, and at
/// least enough to bring the shelf back to its floor, in whole units
/// rounded up. Nothing when the shelf already holds enough.
Qty reorderQty(
  LowStockLine line, {
  required int salesDays,
  required int coverDays,
}) {
  final sold = line.sold.isNegative ? 0 : line.sold.inThousandths;
  final forCover = salesDays <= 0
      ? 0
      : divideRounded(sold * coverDays, salesDays, RoundingMode.ceilAbs);
  final stock = line.stock.inThousandths;
  final want = [
    forCover - stock,
    line.minStock.inThousandths - stock,
  ].reduce((a, b) => a > b ? a : b);
  if (want <= 0) return Qty.zero;
  return Qty.raw(divideRounded(want, 1000, RoundingMode.ceilAbs) * 1000);
}

/// The item batch report (M34): every batch on the shelf, with its expiry,
/// how long it has left, its printed price, how much is left and what it
/// cost, item by item and soonest to expire first.
ReportTable batchReport(BusinessDate asOf, List<BatchLine> batches) {
  final rows = batches.toList()
    ..sort((a, b) {
      final byItem = _byName(a.itemName, b.itemName);
      if (byItem != 0) return byItem;
      final ae = a.expiry?.value ?? '9999-12-31';
      final be = b.expiry?.value ?? '9999-12-31';
      final byExpiry = ae.compareTo(be);
      return byExpiry != 0 ? byExpiry : a.lotNo.compareTo(b.lotNo);
    });
  final expired = rows
      .where((b) => b.expiry != null && _daysTo(asOf, b.expiry!) < 0)
      .length;
  final value = Money.sum(rows.map((b) => b.value));
  return ReportTable(
    id: 'item_batches',
    title: 'Item batch report',
    period: ReportPeriod.day(asOf),
    columns: const [
      ReportColumn('Item', CellKind.text),
      ReportColumn('Batch', CellKind.text),
      ReportColumn('Expiry', CellKind.text),
      ReportColumn('Days left', CellKind.count),
      ReportColumn('MRP', CellKind.money),
      ReportColumn('Stock', CellKind.qty),
      ReportColumn('Value', CellKind.money, isCost: true),
    ],
    rows: [
      for (final b in rows)
        ReportRow([
          b.itemName,
          b.lotNo,
          b.expiry?.value ?? '',
          b.expiry == null ? null : _daysTo(asOf, b.expiry!),
          b.mrp,
          b.qty,
          b.value,
        ], link: _item(b.itemId, b.itemName, b.unitCode)),
      ReportRow([
        'Total',
        _count(rows.length, 'batch', 'batches'),
        null,
        null,
        null,
        null,
        value,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('Batches', rows.length),
      ReportFigure.count('Past their date', expired),
      ReportFigure('Value', value, isCost: true),
    ],
    notes: const [_batchValueIs],
  );
}

const _batchValueIs =
    'Value is what the books carry what is left of each batch at. Days left '
    'below nothing is a batch past its date, which the counter will not '
    'sell.';

/// Whole days from [from] to [to], both business dates: minus when [to] is
/// earlier. Calendar arithmetic on the shop's own dates, never an instant.
int _daysTo(BusinessDate from, BusinessDate to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// The item serial and IMEI report (M34): every numbered piece the shop
/// has had, whether it is here, who it came from and when, and who it went
/// to, when and on which bill.
ReportTable serialReport(BusinessDate asOf, List<SerialLine> serials) {
  final rows = serials.toList()
    ..sort((a, b) {
      final byItem = _byName(a.itemName, b.itemName);
      return byItem != 0 ? byItem : a.serial.compareTo(b.serial);
    });
  final statuses = [for (final s in rows) serialStatus(s)];
  return ReportTable(
    id: 'item_serials',
    title: 'Item serial and IMEI report',
    period: ReportPeriod.day(asOf),
    columns: const [
      ReportColumn('Serial or IMEI', CellKind.text),
      ReportColumn('Item', CellKind.text),
      ReportColumn('Status', CellKind.text),
      ReportColumn('Bought from', CellKind.text),
      ReportColumn('Came in', CellKind.text),
      ReportColumn('Sold to', CellKind.text),
      ReportColumn('Sold on', CellKind.text),
      ReportColumn('Bill', CellKind.text),
    ],
    rows: [
      for (var i = 0; i < rows.length; i++)
        ReportRow(
          [
            rows[i].serial,
            rows[i].itemName,
            statuses[i],
            rows[i].supplier ?? '',
            rows[i].boughtOn?.value ?? '',
            rows[i].saleNo == null ? '' : rows[i].customer ?? 'Walk-in',
            rows[i].soldOn?.value ?? '',
            rows[i].saleNo ?? '',
          ],
          link: rows[i].saleId == null
              ? null
              : ReportLink.document(
                  rows[i].saleId!,
                  label: rows[i].saleNo ?? '',
                  docType: rows[i].saleType,
                ),
        ),
      ReportRow([
        'Total',
        _count(rows.length, 'piece', 'pieces'),
        null,
        null,
        null,
        null,
        null,
        null,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count(
        'In stock',
        rows.where((s) => s.onHand.isPositive).length,
      ),
      ReportFigure.count(
        'Sold',
        statuses.where((s) => s == SerialStatus.sold).length,
      ),
    ],
    notes: const [_serialStatuses],
  );
}

const _serialStatuses =
    'Back from customer is a piece sold and brought back, on the shelf '
    'again. Sent back went to the supplier; written off was counted out or '
    'wasted.';

/// Where a numbered piece stands, as the serial report writes it (M34).
abstract final class SerialStatus {
  static const inStock = 'In stock';
  static const backFromCustomer = 'Back from customer';
  static const sold = 'Sold';
  static const sentBack = 'Sent back';
  static const writtenOff = 'Written off';
}

/// [line]'s standing: on the shelf, back from a customer, sold, sent back
/// to the supplier, or written off.
String serialStatus(SerialLine line) {
  if (line.onHand.isPositive) {
    final back =
        line.returnedOn != null &&
        (line.soldOn == null ||
            line.returnedOn!.value.compareTo(line.soldOn!.value) >= 0);
    return back ? SerialStatus.backFromCustomer : SerialStatus.inStock;
  }
  return switch (line.lastOut) {
    'sale' => SerialStatus.sold,
    'purchase_return' => SerialStatus.sentBack,
    _ => SerialStatus.writtenOff,
  };
}

/// The stock transfer report (M34): every move of goods between the shop
/// floor, the godowns and the vans over [period], oldest first.
ReportTable stockTransferReport(
  ReportPeriod period,
  List<StockTransferLine> moves,
) {
  final rows = moves.toList()
    ..sort((a, b) => a.date.value.compareTo(b.date.value));
  final value = Money.sum(rows.map((m) => m.value));
  return ReportTable(
    id: 'stock_transfers',
    title: 'Stock transfer report',
    period: period,
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Item', CellKind.text),
      ReportColumn('Qty', CellKind.qty),
      ReportColumn('Unit', CellKind.text),
      ReportColumn('From', CellKind.text),
      ReportColumn('To', CellKind.text),
      ReportColumn('Value', CellKind.money, isCost: true),
    ],
    rows: [
      for (final m in rows)
        ReportRow([
          m.date.value,
          m.itemName,
          m.qty,
          m.unitCode,
          placeLabel(m.from),
          placeLabel(m.to),
          m.value,
        ], link: _item(m.itemId, m.itemName, m.unitCode)),
      ReportRow([
        'Total',
        _count(rows.length, 'move', 'moves'),
        null,
        null,
        null,
        null,
        value,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('Moves', rows.length),
      ReportFigure('Value moved', value, isCost: true),
    ],
    notes: const [_movingChangesNothing],
  );
}

const _movingChangesNothing =
    'Goods move at the item\'s average cost, and moving them changes nothing '
    'in the books: the shop owns the same stock wherever it is.';

/// The production register (M34): every production run over [period], what
/// it made, what it used, and what that cost.
ReportTable productionRegister(ReportPeriod period, List<ProductionRun> runs) {
  final rows = runs.toList()
    ..sort((a, b) {
      final byDate = a.date.value.compareTo(b.date.value);
      return byDate != 0 ? byDate : a.runNo.compareTo(b.runNo);
    });
  final components = Money.sum(rows.map((r) => r.componentsCost));
  final overhead = Money.sum(rows.map((r) => r.overhead));
  return ReportTable(
    id: 'production_register',
    title: 'Production register',
    period: period,
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Run', CellKind.text),
      ReportColumn('Made', CellKind.text),
      ReportColumn('Qty', CellKind.qty),
      ReportColumn('Unit', CellKind.text),
      ReportColumn('Used', CellKind.text),
      ReportColumn('Components', CellKind.money, isCost: true),
      ReportColumn('Work and overheads', CellKind.money, isCost: true),
      ReportColumn('Total cost', CellKind.money, isCost: true),
    ],
    rows: [
      for (final r in rows)
        ReportRow([
          r.date.value,
          r.runNo,
          r.itemName,
          r.qty,
          r.unitCode,
          [
            for (final c in r.components)
              '${c.itemName} ${c.qty.display} ${c.unitCode}',
          ].join(', '),
          r.componentsCost,
          r.overhead,
          r.totalCost,
        ], link: _item(r.itemId, r.itemName, r.unitCode)),
      ReportRow([
        'Total',
        _count(rows.length, 'run', 'runs'),
        null,
        null,
        null,
        null,
        components,
        overhead,
        components + overhead,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('Runs', rows.length),
      ReportFigure(
        'Cost of what was made',
        components + overhead,
        isCost: true,
      ),
    ],
    notes: const [_componentsAndWork],
  );
}

const _componentsAndWork =
    'Components are what the ingredients cost as they left the shelf; work '
    'and overheads are what the recipe adds on top, carried in the stock of '
    'what was made.';

/// How an item has been selling, in bands (M34).
enum MovementBand {
  fast('Fast'),
  medium('Medium'),
  slow('Slow'),
  dead('Not sold');

  const MovementBand(this.label);

  final String label;
}

/// Which band [bills] puts an item in: fast from [fastAt] bills, slow
/// under [slowBelow], dead at none, and medium between.
MovementBand bandFor(int bills, {required int fastAt, required int slowBelow}) {
  if (bills <= 0) return MovementBand.dead;
  if (bills >= fastAt) return MovementBand.fast;
  if (bills < slowBelow) return MovementBand.slow;
  return MovementBand.medium;
}

/// Fast, slow and dead stock (M34): every item on the shelf or sold lately,
/// banded by how many bills it was on over the last [salesDays], with when
/// it last sold and the money tied up in it. Marg's fast and slow-moving
/// list, which Vyapar does not have: what to reorder without thinking, and
/// what to put on offer before it spoils the shelf.
ReportTable fastSlowStock(
  BusinessDate asOf,
  List<ItemSelling> items, {
  int salesDays = StockDefaults.movementDays,
  int fastAt = StockDefaults.fastAt,
  int slowBelow = StockDefaults.slowBelow,
}) {
  MovementBand band(ItemSelling i) =>
      bandFor(i.bills, fastAt: fastAt, slowBelow: slowBelow);
  final rows = items.toList()
    ..sort((a, b) {
      final byBand = band(a).index.compareTo(band(b).index);
      if (byBand != 0) return byBand;
      final byBills = b.bills.compareTo(a.bills);
      return byBills != 0 ? byBills : _byName(a.itemName, b.itemName);
    });
  Money valueOf(MovementBand m) => Money.sum([
    for (final i in rows)
      if (band(i) == m) i.value,
  ]);
  final value = Money.sum(rows.map((i) => i.value));
  final dead = rows.where((i) => band(i) == MovementBand.dead).length;
  return ReportTable(
    id: 'fast_slow_stock',
    title: 'Fast, slow and dead stock',
    period: ReportPeriod(asOf.addDays(1 - salesDays), asOf),
    columns: const [
      ReportColumn('Item', CellKind.text),
      ReportColumn('Category', CellKind.text),
      ReportColumn('Moving', CellKind.text),
      ReportColumn('Bills', CellKind.count),
      ReportColumn('Qty sold', CellKind.qty),
      ReportColumn('Last sold', CellKind.text),
      ReportColumn('Stock', CellKind.qty),
      ReportColumn('Value', CellKind.money, isCost: true),
    ],
    rows: [
      for (final i in rows)
        ReportRow([
          i.itemName,
          _categoryOf(i.category),
          band(i).label,
          i.bills,
          i.qtySold,
          i.lastSold?.value ?? 'Never',
          i.stock,
          i.value,
        ], link: _item(i.itemId, i.itemName, i.unitCode)),
      ReportRow([
        'Total',
        _count(rows.length, 'item', 'items'),
        null,
        rows.fold<int>(0, (n, i) => n + i.bills),
        null,
        null,
        null,
        value,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('Not sold', dead),
      for (final m in MovementBand.values)
        ReportFigure('${m.label}: value', valueOf(m), isCost: true),
    ],
    notes: [
      _bandsAre(salesDays, fastAt, slowBelow),
      'Value is what the books carry the stock at: the money tied up in it.',
    ],
  );
}

String _bandsAre(int salesDays, int fastAt, int slowBelow) =>
    'Over the last $salesDays days: fast is on $fastAt bills or more, slow '
    'on fewer than $slowBelow, not sold on none, and medium between. Last '
    'sold is the last bill it was ever on.';

/// The age bands of the stock ageing, as its columns read.
const ageBands = ['0-45 days', '46-90 days', '91-180 days', 'Over 180 days'];

/// Stock ageing (M34): what is on the shelf at the close of [asOf], split
/// by how long ago it came in, at the value the books carry it.
///
/// First in, first out: the oldest goods are taken to have gone first, so
/// what is still on the shelf is matched to the latest receipts (a
/// delivery, opening stock, a customer's return, a production run, a count
/// that found more), newest first, until the quantity on hand is covered.
/// Anything the receipts on record do not cover is counted as the oldest.
/// Each band's value is the item's value shared out by quantity.
ReportTable stockAgeing(BusinessDate asOf, List<ItemAgeing> items) {
  final rows = items.where((i) => i.onHand.isPositive).toList()
    ..sort((a, b) => _byName(a.itemName, b.itemName));
  List<Qty> spread(ItemAgeing i) {
    final b = [
      for (var k = 0; k < ageBands.length; k++)
        k < i.buckets.length ? i.buckets[k] : Qty.zero,
    ];
    final rest = i.onHand - Qty.sum(b);
    if (rest.isPositive) b[ageBands.length - 1] += rest;
    return b;
  }

  final values = [
    for (final i in rows)
      i.value.allocate([
        for (final q in spread(i)) q.isNegative ? 0 : q.inThousandths,
      ]),
  ];
  final totals = [
    for (var k = 0; k < ageBands.length; k++)
      Money.sum([for (final v in values) v[k]]),
  ];
  final value = Money.sum(rows.map((i) => i.value));
  return ReportTable(
    id: 'stock_ageing',
    title: 'Stock ageing',
    period: ReportPeriod.day(asOf),
    columns: [
      const ReportColumn('Item', CellKind.text),
      const ReportColumn('Category', CellKind.text),
      const ReportColumn('Stock', CellKind.qty),
      for (final band in ageBands)
        ReportColumn(band, CellKind.money, isCost: true),
      const ReportColumn('Value', CellKind.money, isCost: true),
    ],
    rows: [
      for (var r = 0; r < rows.length; r++)
        ReportRow([
          rows[r].itemName,
          _categoryOf(rows[r].category),
          rows[r].onHand,
          ...values[r],
          rows[r].value,
        ], link: _item(rows[r].itemId, rows[r].itemName, rows[r].unitCode)),
      ReportRow([
        'Total',
        _count(rows.length, 'item', 'items'),
        null,
        ...totals,
        value,
      ], style: RowStyle.total),
    ],
    summary: [
      for (var k = 0; k < ageBands.length; k++)
        ReportFigure(ageBands[k], totals[k], isCost: true),
    ],
    notes: const [
      _agedFirstInFirstOut,
      'Each band is the item\'s value at cost, shared out by quantity.',
    ],
  );
}

const _agedFirstInFirstOut =
    'Aged first in, first out: what is on the shelf is taken to be the '
    'latest goods to come in, a delivery, opening stock, a return, a '
    'production run or a count that found more, newest first. What the '
    'records do not reach back to is counted as over 180 days.';
