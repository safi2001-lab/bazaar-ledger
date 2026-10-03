/// Ratio analysis (M67): the handful of figures an accountant works out
/// first from a shop's books, and the owner asks about second.
///
/// Tally puts them on one screen — gross and net profit as a share of
/// sales, how fast the stock turns, how long customers take to pay — and
/// every Pakistani accountant who has kept a shop's books in Tally reaches
/// for it. Here each ratio sits beside the same ratio for the period
/// before, with which way it moved and whether that is better or worse,
/// and with the two figures it was worked out from, so a shopkeeper who
/// does not trust a percentage can check the division himself.
///
/// Nothing here is a figure of its own. Every input is read off the
/// finished Profit and Loss (`profitAndLoss`, with its trading account) of
/// the period and the finished Balance Sheet (`balanceSheet`) on its last
/// day, the same builders over the same reads the engine gives those two
/// reports, so a ratio cannot disagree with the statements it divides; a
/// test holds each input to the line it came from. The one exception is
/// cash, which is the Cash flow's closing money (`moneyBefore` the next
/// day): the drawer, the banks and the wallets, and not a cheque until it
/// clears.
///
/// Ratios are whole numbers, as every figure in pk_reports is: shares in
/// basis points, days in days, and "times" in hundredths. Nothing here is
/// a float.
library;

import 'package:pk_domain/pk_domain.dart';

import 'builders.dart';
import 'period.dart';
import 'report_source.dart';
import 'report_table.dart';
import 'transaction_source.dart';

/// The statements' figures a ratio is worked out from, for one period.
final class RatioFigures {
  const RatioFigures({
    required this.period,
    required this.days,
    required this.netSales,
    required this.grossProfit,
    required this.netProfit,
    required this.costOfGoodsSold,
    required this.expenses,
    required this.purchases,
    required this.openingStock,
    required this.closingStock,
    required this.receivables,
    required this.payables,
    required this.currentAssets,
    required this.currentLiabilities,
    required this.cash,
  });

  /// [profitAndLoss] and [balanceSheet] read line by line, as finished:
  /// the Profit and Loss of [period] built with its stock figures, and the
  /// Balance Sheet on [period]'s last day from [balances], the same rows it
  /// was built from. [days] is how many days of the period have passed.
  factory RatioFigures.fromBooks({
    required ReportPeriod period,
    required int days,
    required ReportTable profitAndLoss,
    required ReportTable balanceSheet,
    required List<AccountMovement> balances,
    required MoneyBalance money,
  }) {
    Money line(ReportTable t, String label) {
      for (final r in t.rows) {
        if (r.cells.first == label && r.cells[1] is Money) {
          return r.cells[1]! as Money;
        }
      }
      return Money.zero;
    }

    Money account(String key) => Money.sum([
      for (final a in balances)
        if (a.systemKey == key) a.net,
    ]);

    final net = profitAndLoss.totals.firstOrNull?.cells[1];
    return RatioFigures(
      period: period,
      days: days,
      netSales: line(profitAndLoss, 'Net sales'),
      grossProfit: line(profitAndLoss, 'Gross profit'),
      netProfit: net is Money ? net : Money.zero,
      costOfGoodsSold: line(profitAndLoss, 'Cost of goods sold'),
      expenses: line(profitAndLoss, 'Total expenses'),
      // The trading account's purchases, less what went back (a minus line
      // of its own).
      purchases:
          line(profitAndLoss, 'Purchases') +
          line(profitAndLoss, 'Purchase returns'),
      openingStock: line(profitAndLoss, 'Opening stock'),
      // The trading account takes the closing stock off, so it reads minus.
      closingStock: -line(profitAndLoss, 'Closing stock'),
      // The Balance Sheet's own lines for the two khatas, which it draws
      // from these same balances, an account's net on its side.
      receivables: account('accounts_receivable'),
      payables: -account('accounts_payable'),
      currentAssets:
          line(balanceSheet, 'Total assets') - account('fixed_assets'),
      currentLiabilities: line(balanceSheet, 'Total liabilities'),
      cash: money.total,
    );
  }

  final ReportPeriod period;

  /// Days of the period the figures cover.
  final int days;
  final Money netSales;
  final Money grossProfit;

  /// Net profit, minus for a loss.
  final Money netProfit;
  final Money costOfGoodsSold;

  /// The period's expenses, below the gross profit line.
  final Money expenses;

  /// Deliveries at cost, less what went back to suppliers.
  final Money purchases;
  final Money openingStock;
  final Money closingStock;

  /// Udhaar on the last day.
  final Money receivables;

  /// Owed to suppliers on the last day.
  final Money payables;

  /// Every asset but fixed assets: money, udhaar, cheques, stock.
  final Money currentAssets;

  /// Everything the shop owes.
  final Money currentLiabilities;

  /// The drawer, banks and wallets on the last day.
  final Money cash;

  /// The stock carried on an average day: opening and closing, halved.
  Money get averageStock =>
      Money.paisa(_divide((openingStock + closingStock).inPaisa, 2) ?? 0);

  /// What a month of the period's expenses comes to: thirty days of them.
  Money get monthsExpenses =>
      Money.paisa(_divide(expenses.inPaisa * 30, days) ?? 0);
}

/// The ratios, in the order the report lists them.
enum RatioKind {
  /// Gross profit as a share of net sales, in basis points.
  grossMargin,

  /// Net profit as a share of net sales, in basis points.
  netMargin,

  /// The cost of goods sold over the average stock, in hundredths of a
  /// time: how many times the shelf was sold through.
  stockTurnover,

  /// The days the average stock would last at the period's selling.
  daysOfStock,

  /// The days of sales the udhaar on the last day stands for.
  debtorsDays,

  /// The days of purchases owed to suppliers on the last day.
  creditorsDays,

  /// What the shop has against what it owes, in hundredths: 185 is 1.85
  /// to 1.
  currentRatio,

  /// The months of expenses the cash would pay, in hundredths of a month.
  cashCover;

  /// Whether a higher figure is the better one; null where neither is.
  /// Taking longer to pay suppliers keeps money in the drawer and strains
  /// the supplier, so creditors' days is left to the shopkeeper.
  bool? get higherIsBetter => switch (this) {
    grossMargin || netMargin || stockTurnover || currentRatio => true,
    cashCover => true,
    daysOfStock || debtorsDays => false,
    creditorsDays => null,
  };

  /// The ratio's name as the report writes it.
  String get title => switch (this) {
    grossMargin => 'Gross profit %',
    netMargin => 'Net profit %',
    stockTurnover => 'Stock turnover',
    daysOfStock => 'Days of stock',
    debtorsDays => "Debtors' days",
    creditorsDays => "Creditors' days",
    currentRatio => 'Current ratio',
    cashCover => "Cash against a month's expenses",
  };
}

/// [kind] worked out from [f], in its own unit; null when there is nothing
/// to divide by (no sales, no stock, no expenses).
int? ratioOf(RatioKind kind, RatioFigures f) {
  final stock = (f.openingStock + f.closingStock).inPaisa;
  return switch (kind) {
    RatioKind.grossMargin =>
      f.netSales.isPositive ? shareBp(f.grossProfit, f.netSales) : null,
    RatioKind.netMargin =>
      f.netSales.isPositive ? shareBp(f.netProfit, f.netSales) : null,
    // The cost of goods sold over the average stock: twice the cost over
    // the opening and closing added together.
    RatioKind.stockTurnover =>
      stock > 0 ? _divide(f.costOfGoodsSold.inPaisa * 200, stock) : null,
    RatioKind.daysOfStock =>
      f.costOfGoodsSold.isPositive && stock >= 0
          ? _divide(stock * f.days, f.costOfGoodsSold.inPaisa * 2)
          : null,
    RatioKind.debtorsDays =>
      f.netSales.isPositive
          ? _divide(f.receivables.inPaisa * f.days, f.netSales.inPaisa)
          : null,
    RatioKind.creditorsDays =>
      f.purchases.isPositive
          ? _divide(f.payables.inPaisa * f.days, f.purchases.inPaisa)
          : null,
    RatioKind.currentRatio =>
      f.currentLiabilities.isPositive
          ? _divide(f.currentAssets.inPaisa * 100, f.currentLiabilities.inPaisa)
          : null,
    // The cash over a month of expenses: the cash times the days over
    // thirty days of expenses.
    RatioKind.cashCover =>
      f.expenses.isPositive
          ? _divide(f.cash.inPaisa * 100 * f.days, f.expenses.inPaisa * 30)
          : null,
  };
}

/// [numerator] over [denominator], rounded half up; null over nothing.
int? _divide(int numerator, int denominator) => denominator <= 0
    ? null
    : divideRounded(numerator, denominator, RoundingMode.halfUp);

/// A figure in hundredths as `4.20`.
String _hundredths(int v) {
  final sign = v < 0 ? '-' : '';
  final abs = v.abs();
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}

String _days(int n) => n == 1 || n == -1 ? '$n day' : '$n days';

/// [value] of [kind] as the report writes it, or a dash for none.
String ratioText(RatioKind kind, int? value) {
  if (value == null) return '-';
  return switch (kind) {
    RatioKind.grossMargin || RatioKind.netMargin => formatBp(value),
    RatioKind.stockTurnover => '${_hundredths(value)} times',
    RatioKind.daysOfStock ||
    RatioKind.debtorsDays ||
    RatioKind.creditorsDays => _days(value),
    RatioKind.currentRatio => '${_hundredths(value)} : 1',
    RatioKind.cashCover => '${_hundredths(value)} months',
  };
}

/// How [now] differs from [before], in [kind]'s own terms: `+2.10 points`
/// for a share, `-5 days`, `+0.40 times`.
String ratioChangeText(RatioKind kind, int now, int before) {
  final d = now - before;
  final sign = d > 0 ? '+' : '';
  return switch (kind) {
    RatioKind.grossMargin ||
    RatioKind.netMargin => '$sign${_hundredths(d)} points',
    RatioKind.stockTurnover => '$sign${_hundredths(d)} times',
    RatioKind.daysOfStock ||
    RatioKind.debtorsDays ||
    RatioKind.creditorsDays => '$sign${_days(d)}',
    RatioKind.currentRatio => '$sign${_hundredths(d)}',
    RatioKind.cashCover => '$sign${_hundredths(d)} months',
  };
}

/// Better, worse or the same, for a ratio whose better direction is
/// known; empty where it is not, or there is nothing to compare.
String _reading(RatioKind kind, int? now, int? before) {
  final up = kind.higherIsBetter;
  if (up == null || now == null || before == null) return '';
  if (now == before) return 'Same';
  return (now > before) == up ? 'Better' : 'Worse';
}

String _rs(Money m) => 'Rs ${m.amountOnly}';

/// What [kind] was worked out from, in words with the figures.
String _workedOut(RatioKind kind, RatioFigures f) => switch (kind) {
  RatioKind.grossMargin =>
    'Gross profit ${_rs(f.grossProfit)} of net sales ${_rs(f.netSales)}',
  RatioKind.netMargin =>
    'Net profit ${_rs(f.netProfit)} of net sales ${_rs(f.netSales)}',
  RatioKind.stockTurnover =>
    'Cost of goods sold ${_rs(f.costOfGoodsSold)} over average stock '
        '${_rs(f.averageStock)}',
  RatioKind.daysOfStock =>
    'Average stock ${_rs(f.averageStock)} at ${f.days} days of cost of '
        'goods sold ${_rs(f.costOfGoodsSold)}',
  RatioKind.debtorsDays =>
    'Udhaar ${_rs(f.receivables)} against ${f.days} days of net sales '
        '${_rs(f.netSales)}',
  RatioKind.creditorsDays =>
    'Owed to suppliers ${_rs(f.payables)} against ${f.days} days of '
        'purchases ${_rs(f.purchases)}',
  RatioKind.currentRatio =>
    'Money, udhaar, cheques and stock ${_rs(f.currentAssets)} against '
        'everything owed ${_rs(f.currentLiabilities)}',
  RatioKind.cashCover =>
    'Drawer, banks and wallets ${_rs(f.cash)} against '
        '${_rs(f.monthsExpenses)} of expenses a month',
};

/// What a tap on a ratio opens: the report its figures came from, and for
/// debtors' days Tally's drill-down, how each customer pays.
ReportLink _source(RatioKind kind) => switch (kind) {
  RatioKind.grossMargin || RatioKind.netMargin => const ReportLink.report(
    'profitAndLoss',
    label: 'Profit and Loss',
  ),
  RatioKind.stockTurnover || RatioKind.daysOfStock => const ReportLink.report(
    'stockDetail',
    label: 'Stock detail',
  ),
  RatioKind.debtorsDays => const ReportLink.report(
    'paymentPerformance',
    label: 'How customers pay',
  ),
  RatioKind.creditorsDays => const ReportLink.report(
    'payables',
    label: 'Owed to suppliers',
  ),
  RatioKind.currentRatio => const ReportLink.report(
    'balanceSheet',
    label: 'Balance Sheet',
  ),
  RatioKind.cashCover => const ReportLink.report(
    'cashflow',
    label: 'Cash flow',
  ),
};

/// The ratio analysis for [now]'s period, each ratio beside [before]'s.
ReportTable ratioAnalysis(RatioFigures now, RatioFigures before) {
  return ReportTable(
    id: 'ratio_analysis',
    title: 'Ratio analysis',
    period: now.period,
    columns: const [
      ReportColumn('Ratio', CellKind.text),
      ReportColumn('This period', CellKind.text),
      ReportColumn('Period before', CellKind.text),
      ReportColumn('Change', CellKind.text),
      ReportColumn('Reading', CellKind.text),
      ReportColumn('Worked out from', CellKind.text),
    ],
    rows: [
      for (final kind in RatioKind.values)
        () {
          final a = ratioOf(kind, now);
          final b = ratioOf(kind, before);
          return ReportRow([
            kind.title,
            ratioText(kind, a),
            ratioText(kind, b),
            a == null || b == null ? '' : ratioChangeText(kind, a, b),
            _reading(kind, a, b),
            _workedOut(kind, now),
          ], link: _source(kind));
        }(),
    ],
    summary: [
      ReportFigure('Net sales', now.netSales),
      ReportFigure('Gross profit', now.grossProfit, isCost: true),
      ReportFigure(
        now.netProfit.isNegative ? 'Net loss' : 'Net profit',
        now.netProfit,
        isCost: true,
      ),
    ],
    notes: [
      _readOff(before.period),
      _averageStock(now.days),
      _debtorsCarryTax,
      _currentRatio,
      _cashIs,
    ],
  );
}

String _readOff(ReportPeriod before) =>
    'Each ratio is read off the Profit and Loss of the period and the '
    'Balance Sheet on its last day (or today, for a period not yet over); '
    'the period before is ${before.label}.';

String _averageStock(int days) =>
    "Average stock is the trading account's opening and closing stock, "
    'halved. Days are the $days days of the period that have passed.';

const _debtorsCarryTax =
    "Debtors' days set the udhaar, which carries tax, against net sales, "
    'which do not: a shop that charges sales tax reads a little long.';

const _currentRatio =
    'The current ratio counts every asset but fixed assets against '
    'everything the shop owes, a loan in full though it may be repaid over '
    'years.';

const _cashIs =
    'Cash is the drawer, the banks and the wallets on the last day, as the '
    "Cash flow closes; a month's expenses are the period's spread over "
    'thirty days. A dash is a ratio with nothing to divide by.';

/// The days of [period] that have passed by [today], both ends counted:
/// all of a period that is over, and up to today of one that is not.
int daysPassed(ReportPeriod period, BusinessDate today) {
  final end = period.to.value.compareTo(today.value) <= 0 ? period.to : today;
  if (end.value.compareTo(period.from.value) < 0) return 0;
  return DateTime.utc(end.year, end.month, end.day)
          .difference(
            DateTime.utc(period.from.year, period.from.month, period.from.day),
          )
          .inDays +
      1;
}

/// Reads and builds the ratio analysis for [period] and the period before
/// (M67), each from its own Profit and Loss and Balance Sheet.
Future<ReportTable> buildRatioReport(
  ReportSource source, {
  required String firmId,
  required ReportPeriod period,
  required BusinessDate today,
}) async {
  Future<RatioFigures> figuresFor(ReportPeriod p) async {
    // The Balance Sheet on the period's last day, or today's for a period
    // still running: the books hold nothing dated after today.
    final end = p.to.value.compareTo(today.value) <= 0 ? p.to : today;
    final balances = await source.accountBalances(firmId, end);
    return RatioFigures.fromBooks(
      period: p,
      days: daysPassed(p, today),
      profitAndLoss: profitAndLoss(
        p,
        await source.accountMovements(firmId, p),
        stock: await source.stockFigures(firmId, p),
      ),
      balanceSheet: balanceSheet(end, balances),
      balances: balances,
      money: await source.moneyBefore(firmId, end.addDays(1)),
    );
  }

  return ratioAnalysis(
    await figuresFor(period),
    await figuresFor(period.previous),
  );
}
