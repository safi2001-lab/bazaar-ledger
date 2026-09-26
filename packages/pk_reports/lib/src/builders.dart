import 'package:pk_domain/pk_domain.dart';

import 'period.dart';
import 'report_source.dart';
import 'report_table.dart';

/// The contra accounts under expenses. They carry credit balances that
/// reduce the cost of goods, and are not money the shop spent.
const _cogsIsNotAnExpense =
    'The cost of goods sold is not an expense here; it is in Profit and '
    'Loss, against the sales it earned.';

const _cashOnly =
    'Cash only. A cheque is not cash until it clears into an account, and '
    'money into the bank or a wallet is in their own books.';

const _salesAreNet =
    'Sales are before tax and after every discount, less returns. Cost is '
    'what the goods cost when they left the shelf.';

String _belowZero(int items) {
  final what = items == 1 ? '1 item shows' : '$items items show';
  return '$what less than nothing on the shelf: more was sold than was '
      'recorded coming in.';
}

const _notSpending = {'cogs', 'purchase_returns', 'discount_received'};

List<AccountMovement> _byCode(Iterable<AccountMovement> accounts) =>
    accounts.toList()..sort((a, b) => a.code.compareTo(b.code));

/// Profit and loss for [period], from what was posted to each account.
///
/// Read off the ledger rather than off the bills, so a void, a return, a
/// debit note and an expense all land where the double entry put them, and
/// the figure here cannot disagree with the books.
ReportTable profitAndLoss(
  ReportPeriod period,
  List<AccountMovement> movements,
) {
  final revenue = _byCode(
    movements.where((a) => a.type == 'income' && a.systemKey != 'other_income'),
  );
  final otherIncome = _byCode(
    movements.where((a) => a.type == 'income' && a.systemKey == 'other_income'),
  );
  final direct = _byCode(
    movements.where((a) => a.type == 'expense' && a.isDirect),
  );
  final indirect = _byCode(
    movements.where((a) => a.type == 'expense' && !a.isDirect),
  );

  // Income shown as the positive it is, so a discount given reads as the
  // negative it is against sales.
  Money earned(AccountMovement a) => -a.net;

  final netSales = Money.sum(revenue.map(earned));
  final costOfSales = Money.sum(direct.map((a) => a.net));
  final gross = netSales - costOfSales;
  final other = Money.sum(otherIncome.map(earned));
  final expenses = Money.sum(indirect.map((a) => a.net));
  final net = gross + other - expenses;

  const width = 2;
  final rows = <ReportRow>[
    ReportRow.heading('Sales', width),
    for (final a in revenue) ReportRow([a.name, earned(a)]),
    ReportRow(['Net sales', netSales], style: RowStyle.subtotal),
    ReportRow.heading('Cost of sales', width),
    for (final a in direct) ReportRow([a.name, a.net]),
    ReportRow(['Total cost of sales', costOfSales], style: RowStyle.subtotal),
    ReportRow(['Gross profit', gross], style: RowStyle.subtotal),
    if (otherIncome.isNotEmpty) ...[
      ReportRow.heading('Other income', width),
      for (final a in otherIncome) ReportRow([a.name, earned(a)]),
      ReportRow(['Total other income', other], style: RowStyle.subtotal),
    ],
    ReportRow.heading('Expenses', width),
    for (final a in indirect) ReportRow([a.name, a.net]),
    ReportRow(['Total expenses', expenses], style: RowStyle.subtotal),
    ReportRow([
      net.isNegative ? 'Net loss' : 'Net profit',
      net,
    ], style: RowStyle.total),
  ];

  return ReportTable(
    id: 'profit_and_loss',
    title: 'Profit and Loss',
    period: period,
    columns: const [
      ReportColumn('Account', CellKind.text),
      ReportColumn('Amount', CellKind.money),
    ],
    rows: rows,
    notes: [
      if (netSales.isPositive)
        'Gross margin ${formatBp(shareBp(gross, netSales))} of net sales.',
      'Cost of sales is what the goods sold cost when they left the shelf.',
    ],
  );
}

/// What the shop spent in [period], by head, largest first.
ReportTable expensesByHead(
  ReportPeriod period,
  List<AccountMovement> movements,
) {
  final heads =
      movements
          .where(
            (a) =>
                a.type == 'expense' &&
                !_notSpending.contains(a.systemKey) &&
                !a.net.isZero,
          )
          .toList()
        ..sort((a, b) {
          final byAmount = b.net.compareTo(a.net);
          return byAmount != 0 ? byAmount : a.code.compareTo(b.code);
        });
  final total = Money.sum(heads.map((a) => a.net));
  return ReportTable(
    id: 'expenses',
    title: 'Expenses by head',
    period: period,
    columns: const [
      ReportColumn('Head', CellKind.text),
      ReportColumn('Amount', CellKind.money),
      ReportColumn('Share', CellKind.percent),
    ],
    rows: [
      for (final a in heads) ReportRow([a.name, a.net, shareBp(a.net, total)]),
      ReportRow([
        'Total',
        total,
        total.isZero ? 0 : 10000,
      ], style: RowStyle.total),
    ],
    notes: const [_cogsIsNotAnExpense],
  );
}

/// The cash book: the drawer's opening balance, every rupee in and out, and
/// what should be in it at the end.
ReportTable cashBook(
  ReportPeriod period,
  Money opening,
  List<CashMovement> movements,
) {
  var running = opening;
  final rows = <ReportRow>[
    ReportRow([
      period.from.value,
      null,
      'Opening balance',
      null,
      null,
      opening,
    ], style: RowStyle.subtotal),
    for (final m in movements)
      () {
        running = running + m.moneyIn - m.moneyOut;
        return ReportRow([
          m.date.value,
          m.entryNo,
          m.narration,
          m.moneyIn.isZero ? null : m.moneyIn,
          m.moneyOut.isZero ? null : m.moneyOut,
          running,
        ]);
      }(),
    ReportRow([
      period.to.value,
      null,
      'Closing balance',
      Money.sum(movements.map((m) => m.moneyIn)),
      Money.sum(movements.map((m) => m.moneyOut)),
      running,
    ], style: RowStyle.total),
  ];
  return ReportTable(
    id: 'cash_book',
    title: 'Cash Book',
    period: period,
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Entry', CellKind.text),
      ReportColumn('Details', CellKind.text),
      ReportColumn('In', CellKind.money),
      ReportColumn('Out', CellKind.money),
      ReportColumn('Balance', CellKind.money),
    ],
    rows: rows,
    notes: const [_cashOnly],
  );
}

/// Every entry in the books in [period], in the order it was recorded.
ReportTable dayBook(ReportPeriod period, List<DayBookEntry> entries) {
  final total = Money.sum(entries.map((e) => e.amount));
  return ReportTable(
    id: 'day_book',
    title: 'Day Book',
    period: period,
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Entry', CellKind.text),
      ReportColumn('Type', CellKind.text),
      ReportColumn('Details', CellKind.text),
      ReportColumn('Amount', CellKind.money),
    ],
    rows: [
      for (final e in entries)
        ReportRow([
          e.date.value,
          e.entryNo,
          _sourceLabel(e.sourceType),
          e.narration,
          e.amount,
        ]),
      ReportRow([
        null,
        null,
        null,
        entries.length == 1 ? '1 entry' : '${entries.length} entries',
        total,
      ], style: RowStyle.total),
    ],
  );
}

String _sourceLabel(String sourceType) => switch (sourceType) {
  'sale' => 'Sale',
  'sale_return' => 'Sale return',
  'purchase' => 'Purchase',
  'purchase_return' => 'Purchase return',
  'payment' => 'Payment',
  'expense' => 'Expense',
  'other_income' => 'Charge',
  'opening' => 'Opening',
  'adjustment' => 'Adjustment',
  'reversal' => 'Reversal',
  _ => sourceType,
};

/// What each item sold for in [period], net of returns, best sellers first.
ReportTable salesByItem(ReportPeriod period, List<ItemSales> sales) {
  final items =
      sales.where((s) => !s.netQty.isZero || !s.netSales.isZero).toList()
        ..sort((a, b) {
          final bySales = b.netSales.compareTo(a.netSales);
          return bySales != 0 ? bySales : a.itemName.compareTo(b.itemName);
        });
  final totalSales = Money.sum(items.map((s) => s.netSales));
  final totalCost = Money.sum(items.map((s) => s.netCost));
  final totalProfit = totalSales - totalCost;
  return ReportTable(
    id: 'sales_by_item',
    title: 'Sales by item',
    period: period,
    columns: const [
      ReportColumn('Item', CellKind.text),
      ReportColumn('Qty', CellKind.qty),
      ReportColumn('Unit', CellKind.text),
      ReportColumn('Sales', CellKind.money),
      ReportColumn('Cost', CellKind.money),
      ReportColumn('Profit', CellKind.money),
      ReportColumn('Margin', CellKind.percent),
    ],
    rows: [
      for (final s in items)
        ReportRow([
          s.itemName,
          s.netQty,
          s.unitCode,
          s.netSales,
          s.netCost,
          s.profit,
          shareBp(s.profit, s.netSales),
        ]),
      ReportRow([
        'Total',
        null,
        null,
        totalSales,
        totalCost,
        totalProfit,
        shareBp(totalProfit, totalSales),
      ], style: RowStyle.total),
    ],
    notes: const [_salesAreNet],
  );
}

/// What is on the shelf now and what it cost, beside what the books say.
ReportTable stockValue(
  BusinessDate asOf,
  List<StockPosition> positions,
  Money inBooks,
) {
  final items = positions.where((p) => !p.qty.isZero).toList()
    ..sort((a, b) => a.itemName.compareTo(b.itemName));
  final total = Money.sum(items.map((p) => p.value));
  final short = items.where((p) => p.qty.isNegative).length;
  final gap = total - inBooks;
  return ReportTable(
    id: 'stock_value',
    title: 'Stock value',
    period: ReportPeriod.day(asOf),
    columns: const [
      ReportColumn('Item', CellKind.text),
      ReportColumn('Qty', CellKind.qty),
      ReportColumn('Unit', CellKind.text),
      ReportColumn('Average cost', CellKind.money),
      ReportColumn('Value', CellKind.money),
    ],
    rows: [
      for (final p in items)
        ReportRow([
          p.itemName,
          p.qty,
          p.unitCode,
          p.averageCost.amountFor(Qty.one),
          p.value,
        ]),
      ReportRow(['Total', null, null, null, total], style: RowStyle.total),
    ],
    notes: [
      'Inventory in the books: Rs ${inBooks.amountOnly}.',
      if (!gap.isZero) _shelfAndBooksDiffer(gap),
      if (short > 0) _belowZero(short),
    ],
  );
}

String _shelfAndBooksDiffer(Money gap) =>
    'The shelf at average cost and the books differ by '
    'Rs ${gap.abs.amountOnly}: the average moves as goods arrive, and the '
    'books keep what each movement cost at the time.';

/// Each day's selling in [period], and the period's total.
ReportTable salesByDay(ReportPeriod period, List<DaySales> days) {
  final sorted = days.toList()
    ..sort((a, b) => a.date.value.compareTo(b.date.value));
  Money sum(Money Function(DaySales d) f) => Money.sum(sorted.map(f));
  return ReportTable(
    id: 'sales_by_day',
    title: 'Sales by day',
    period: period,
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Bills', CellKind.count),
      ReportColumn('Sales', CellKind.money),
      ReportColumn('Returns', CellKind.money),
      ReportColumn('Received', CellKind.money),
      ReportColumn('On udhaar', CellKind.money),
    ],
    rows: [
      for (final d in sorted)
        ReportRow([
          d.date.value,
          d.bills,
          d.sales,
          d.returns,
          d.received,
          d.onUdhaar,
        ]),
      ReportRow([
        'Total',
        sorted.fold<int>(0, (n, d) => n + d.bills),
        sum((d) => d.sales),
        sum((d) => d.returns),
        sum((d) => d.received),
        sum((d) => d.onUdhaar),
      ], style: RowStyle.total),
    ],
    notes: const [_receivedAtTheCounter],
  );
}

const _receivedAtTheCounter =
    "Received is what was paid at the counter on the day's bills. Money "
    'collected later against udhaar is in the Cash Book on the day it came.';

/// Who owes the shop, and for how long, oldest money on the right.
ReportTable receivablesByAge(BusinessDate asOf, List<PartyReceivable> parties) {
  final owing = parties.where((p) => !p.owed.isZero).toList()
    ..sort((a, b) {
      final byOld = b.over90.compareTo(a.over90);
      if (byOld != 0) return byOld;
      final byOwed = b.owed.compareTo(a.owed);
      return byOwed != 0 ? byOwed : a.name.compareTo(b.name);
    });
  Money sum(Money Function(PartyReceivable p) f) => Money.sum(owing.map(f));
  final anyOpening = owing.any((p) => !p.opening.isZero);
  final anyAdvance = owing.any((p) => !p.advance.isZero);
  return ReportTable(
    id: 'receivables',
    title: 'Udhaar by age',
    period: ReportPeriod.day(asOf),
    columns: const [
      ReportColumn('Customer', CellKind.text),
      ReportColumn('Opening', CellKind.money),
      ReportColumn('0-30 days', CellKind.money),
      ReportColumn('31-60 days', CellKind.money),
      ReportColumn('61-90 days', CellKind.money),
      ReportColumn('Over 90 days', CellKind.money),
      ReportColumn('Advance', CellKind.money),
      ReportColumn('Owed', CellKind.money),
    ],
    rows: [
      for (final p in owing)
        ReportRow([
          p.name,
          p.opening,
          p.upTo30,
          p.upTo60,
          p.upTo90,
          p.over90,
          -p.advance,
          p.owed,
        ]),
      ReportRow([
        'Total',
        sum((p) => p.opening),
        sum((p) => p.upTo30),
        sum((p) => p.upTo60),
        sum((p) => p.upTo90),
        sum((p) => p.over90),
        -sum((p) => p.advance),
        sum((p) => p.owed),
      ], style: RowStyle.total),
    ],
    notes: [
      'Aged from the date of each bill or charge still open.',
      if (anyOpening) _openingHasNoDate,
      if (anyAdvance) _advanceComesOff,
    ],
  );
}

const _openingHasNoDate =
    'Opening is the balance brought forward when the khata was started, '
    'which has no date to age from.';

const _advanceComesOff =
    'Advance is money the shop is holding for the customer, and comes off '
    'what they owe.';
