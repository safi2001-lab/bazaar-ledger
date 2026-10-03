/// ABC classification (M67): which few items the shop's money rides on.
///
/// Zoho Inventory sorts a shop's items into three classes by what they
/// bring in: A, the few that make most of it; B, the next; C, the long tail
/// that sits on the shelf for the sake of the customer who asks once a
/// season. A kiryana store with three thousand lines finds that two hundred
/// of them are four fifths of its sales, and those two hundred are the ones
/// never to run out of, the ones to haggle hardest with the distributor
/// over, and the ones to count first.
///
/// Items are ranked by what they sold for over the period (net of returns,
/// before tax, after every discount, as Item-wise profit reads them), or by
/// what they made over their cost for a role that may see costs. Walking
/// down the ranking, an item belongs to class A while the share of the
/// whole before it is under the A line (80% unless the shop moves it), to B
/// while under the B line (95%), and to C after; so the item that carries
/// the running share across a line is still in the class it started in,
/// and the top seller is always A. An item that sold nothing, or made a
/// loss on a ranking by profit, is C.
///
/// The classes add up: every item is in exactly one, and their sales are
/// the Item-wise profit's sales to the paisa, khula maal (M37) included as
/// a row of its own.
library;

import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'item_stock_source.dart';
import 'period.dart';
import 'report_table.dart';

/// The three classes.
enum AbcClass { a, b, c }

extension AbcClassName on AbcClass {
  /// "A", "B" or "C", as the report writes it.
  String get letter => name.toUpperCase();
}

/// Which class each of [values] falls in, walking down them largest first:
/// A while the share of the positive whole before it is under [aAt] per
/// cent, B while under [bAt], C after, and C for anything not above
/// nothing. Parallel to [values].
List<AbcClass> abcClasses(List<Money> values, {int aAt = 80, int bAt = 95}) {
  final order = [for (var i = 0; i < values.length; i++) i]
    ..sort((x, y) => values[y].compareTo(values[x]));
  final whole = Money.sum([
    for (final v in values)
      if (v.isPositive) v,
  ]);
  final classes = List<AbcClass>.filled(values.length, AbcClass.c);
  var before = Money.zero;
  for (final i in order) {
    final v = values[i];
    if (!v.isPositive) continue;
    final share = shareBp(before, whole);
    classes[i] = share < aAt * 100
        ? AbcClass.a
        : share < bAt * 100
        ? AbcClass.b
        : AbcClass.c;
    before += v;
  }
  return classes;
}

const _noCategory = 'No category';

String _category(String? c) {
  final t = c?.trim() ?? '';
  return t.isEmpty ? _noCategory : t;
}

/// The ABC classification of the items sold in [period] (M67), from the
/// same rows Item-wise profit reads.
ReportTable abcClassification(
  ReportPeriod period,
  List<ItemTrade> trades, {
  AbcBasis basis = AbcBasis.sales,
  int aAt = AbcDefaults.a,
  int bAt = AbcDefaults.b,
}) {
  final byProfit = basis == AbcBasis.margin;
  final sold =
      trades.where((t) => !t.netQtySold.isZero || !t.netSales.isZero).toList()
        ..sort((x, y) {
          final a = byProfit ? x.profit : x.netSales;
          final b = byProfit ? y.profit : y.netSales;
          final c = b.compareTo(a);
          return c != 0
              ? c
              : x.itemName.toLowerCase().compareTo(y.itemName.toLowerCase());
        });
  Money valueOf(ItemTrade t) => byProfit ? t.profit : t.netSales;
  final values = [for (final t in sold) valueOf(t)];
  final classes = abcClasses(values, aAt: aAt, bAt: bAt);
  final whole = Money.sum([
    for (final v in values)
      if (v.isPositive) v,
  ]);
  final totalSales = Money.sum(sold.map((t) => t.netSales));
  final totalProfit = Money.sum(sold.map((t) => t.profit));

  var running = Money.zero;
  final rows = <ReportRow>[];
  for (var i = 0; i < sold.length; i++) {
    final t = sold[i];
    final v = values[i];
    if (v.isPositive) running += v;
    rows.add(
      ReportRow(
        [
          i + 1,
          t.itemName,
          t.isLoose ? _noCategory : _category(t.category),
          classes[i].letter,
          t.isLoose ? null : t.netQtySold,
          t.isLoose ? '' : t.unitCode,
          t.netSales,
          t.profit,
          v.isPositive ? shareBp(v, whole) : 0,
          shareBp(running, whole),
        ],
        link: t.itemId == null
            ? null
            : ReportLink.item(
                t.itemId!,
                label: t.itemName,
                unitCode: t.unitCode,
              ),
      ),
    );
  }

  ({int items, Money sales, Money value}) of(AbcClass k) {
    var items = 0;
    var sales = Money.zero;
    var value = Money.zero;
    for (var i = 0; i < sold.length; i++) {
      if (classes[i] != k) continue;
      items++;
      sales += sold[i].netSales;
      value += values[i];
    }
    return (items: items, sales: sales, value: value);
  }

  final perClass = {for (final k in AbcClass.values) k: of(k)};
  final what = byProfit ? 'profit' : 'sales';
  return ReportTable(
    id: 'abc_classification',
    title: 'ABC classification',
    period: period,
    columns: [
      const ReportColumn('Rank', CellKind.count),
      const ReportColumn('Item', CellKind.text),
      const ReportColumn('Category', CellKind.text),
      const ReportColumn('Class', CellKind.text),
      const ReportColumn('Qty', CellKind.qty),
      const ReportColumn('Unit', CellKind.text),
      const ReportColumn('Sales', CellKind.money),
      const ReportColumn('Profit', CellKind.money, isCost: true),
      // A share of the profit is a figure about cost.
      ReportColumn('Share', CellKind.percent, isCost: byProfit),
      ReportColumn('Running share', CellKind.percent, isCost: byProfit),
    ],
    rows: [
      ...rows,
      ReportRow([
        sold.length,
        'Total',
        null,
        null,
        null,
        null,
        totalSales,
        totalProfit,
        whole.isZero ? 0 : 10000,
        null,
      ], style: RowStyle.total),
    ],
    summary: [
      for (final k in AbcClass.values) ...[
        ReportFigure.count('Class ${k.letter} items', perClass[k]!.items),
        if (byProfit)
          ReportFigure(
            'Class ${k.letter} profit',
            perClass[k]!.value,
            isCost: true,
          )
        else
          ReportFigure('Class ${k.letter} sales', perClass[k]!.sales),
      ],
    ],
    notes: [
      for (final k in AbcClass.values)
        _classNote(
          k,
          perClass[k]!.items,
          sold.length,
          perClass[k]!.value,
          what,
          whole,
        ),
      _rankedBy(what, aAt, bAt),
      _salesAreItemProfits,
      if (sold.any((t) => t.isLoose)) _looseIsOneItem,
      if (byProfit && sold.any((t) => !t.profit.isPositive)) _lossIsC,
    ],
  );
}

String _classNote(
  AbcClass k,
  int items,
  int of,
  Money value,
  String what,
  Money whole,
) {
  return 'Class ${k.letter}: $items of $of items '
      '(${formatBp(_itemShare(items, of))}), Rs ${value.amountOnly} of '
      '$what (${formatBp(shareBp(value, whole))}).';
}

String _rankedBy(String what, int aAt, int bAt) =>
    'Ranked by $what over the period: class A until the items above reach '
    '$aAt% of it, class B until $bAt%, class C after. An item that carries '
    'the share across a line stays in the class it started in.';

const _salesAreItemProfits =
    'Sales are before tax, after every discount, less returns, as Item-wise '
    "profit reads them; its total is that report's.";

const _looseIsOneItem =
    '${ItemTrade.looseLines} is ranked as one item: it has no item, no '
    'category and no cost of its own.';

const _lossIsC = 'An item that made nothing or a loss is in class C.';

int _itemShare(int items, int of) =>
    of == 0 ? 0 : divideRounded(items * 10000, of, RoundingMode.halfUp);
