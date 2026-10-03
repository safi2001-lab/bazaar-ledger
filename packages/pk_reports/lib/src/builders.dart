import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'item_stock_source.dart';
import 'party_builders.dart';
import 'period.dart';
import 'report_source.dart';
import 'report_table.dart';
import 'transaction_source.dart';

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
///
/// With [stock] (M33) the cost of sales is laid out the way every trading
/// account in the market is, and the way Vyapar shows it: opening stock,
/// plus purchases, less purchase returns, less closing stock. The books
/// here cost each sale as it happens, so the figure that line arrives at is
/// still the Cost of Goods Sold account to the paisa; what moved the shelf
/// for any other reason (a count, a write-off, a challan, a production run,
/// stock brought in as an opening) is shown on its own line so the sum can
/// be followed on paper.
ReportTable profitAndLoss(
  ReportPeriod period,
  List<AccountMovement> movements, {
  StockFigures? stock,
}) {
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

  // The trading account's lines, when the stock figures were read.
  final goodsSold = Money.sum([
    for (final a in direct)
      if (a.systemKey == 'cogs') a.net,
  ]);
  final otherwise = stock == null
      ? Money.zero
      : goodsSold -
            (stock.opening +
                stock.purchases -
                stock.purchaseReturns -
                stock.closing);

  const width = 2;
  final rows = <ReportRow>[
    ReportRow.heading('Sales', width),
    for (final a in revenue) ReportRow([a.name, earned(a)]),
    ReportRow(['Net sales', netSales], style: RowStyle.subtotal),
    ReportRow.heading('Cost of sales', width),
    if (stock == null)
      for (final a in direct) ReportRow([a.name, a.net])
    else ...[
      ReportRow(['Opening stock', stock.opening]),
      ReportRow(['Purchases', stock.purchases]),
      if (!stock.purchaseReturns.isZero)
        ReportRow(['Purchase returns', -stock.purchaseReturns]),
      if (!otherwise.isZero) ReportRow([_stockOtherwise, otherwise]),
      ReportRow(['Closing stock', -stock.closing]),
      ReportRow(['Cost of goods sold', goodsSold], style: RowStyle.subtotal),
      for (final a in direct)
        if (a.systemKey != 'cogs') ReportRow([a.name, a.net]),
    ],
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
      if (stock != null) _stockAtCost,
    ],
  );
}

const _stockOtherwise = 'Stock in or out otherwise';

// Goods taken home (M47) leave the shelf at cost against the owner's
// drawings, not through the cost of goods sold, so they are among what moved
// the shelf otherwise (M58).
const _stockAtCost =
    'Opening and closing stock are the Inventory account at cost. Stock in '
    'or out otherwise is stock counted in or written off, taken home by the '
    'owner (ghar le gaye, at cost), sent on a challan, used or made in '
    'production, or brought in as an opening.';

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
///
/// Since M33 laid out as a shop's roznamcha is: each transaction with who it
/// was with, the number on its paper, what it came to, and the money that
/// came in or went out with it. The day's money in and money out are summed
/// at the foot, and their difference is what the drawer, the bank and the
/// wallets gained between them.
ReportTable dayBook(ReportPeriod period, List<DayBookEntry> entries) {
  final moneyIn = Money.sum(entries.map((e) => e.moneyIn));
  final moneyOut = Money.sum(entries.map((e) => e.moneyOut));
  return ReportTable(
    id: 'day_book',
    title: 'Day Book',
    period: period,
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Number', CellKind.text),
      ReportColumn('Type', CellKind.text),
      ReportColumn('Party', CellKind.text),
      ReportColumn('Details', CellKind.text),
      ReportColumn('Total', CellKind.money),
      ReportColumn('Money in', CellKind.money),
      ReportColumn('Money out', CellKind.money),
    ],
    rows: [
      for (final e in entries)
        ReportRow(
          [
            e.date.value,
            e.reference ?? e.entryNo,
            _dayBookType(e),
            e.party ?? '',
            e.narration,
            e.amount,
            e.moneyIn.isZero ? null : e.moneyIn,
            e.moneyOut.isZero ? null : e.moneyOut,
          ],
          link: e.documentId == null
              ? null
              : ReportLink.document(
                  e.documentId!,
                  label: e.reference ?? e.entryNo,
                  docType: e.docType,
                ),
        ),
      ReportRow([
        null,
        null,
        null,
        null,
        entries.length == 1 ? '1 entry' : '${entries.length} entries',
        null,
        moneyIn,
        moneyOut,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Money in', moneyIn),
      ReportFigure('Money out', moneyOut),
      ReportFigure('Net', moneyIn - moneyOut),
    ],
    notes: const [_moneyInAndOut],
  );
}

const _moneyInAndOut =
    'Money in and out is cash in the drawer, the bank and mobile wallets. A '
    'cheque is counted when it clears, and a bill left on udhaar moves no '
    'money until it is paid.';

/// What a day book line was (M58): a write-off or a settlement discount
/// (M44) is posted as a payment and known by the words its entry begins
/// with, the same words M31's cancel finds it by; anything else by its kind.
String _dayBookType(DayBookEntry e) {
  if (e.sourceType == 'payment') {
    for (final k in AllowanceKind.values) {
      if (e.narration.startsWith('${k.narration} ${k.prefix}-')) {
        return k.narration;
      }
    }
  }
  return _sourceLabel(e.sourceType);
}

String _sourceLabel(String sourceType) => switch (sourceType) {
  'sale' => 'Sale',
  'sale_return' => 'Sale return',
  'purchase' => 'Purchase',
  'purchase_return' => 'Purchase return',
  'payment' => 'Payment',
  'expense' => 'Expense',
  // An `other_income` entry the day book still reads as one has a party
  // behind it: a charge on their khata (M25). The shop's own income has its
  // own kind since M58.
  'other_income' => 'Charge',
  TransactionType.otherIncome => 'Other income',
  TransactionType.ownerDrawings => "Owner's drawings (ghar)",
  'loan' => 'Loan',
  'opening' => 'Opening',
  'adjustment' => 'Adjustment',
  'reversal' => 'Reversal',
  'manual' => 'Journal voucher',
  'year_close' => 'Year closed',
  _ => sourceType,
};

/// What each item sold for in [period], net of returns, best sellers first.
///
/// Since M58 khula maal (M37), the lines with no item behind them, is one
/// row of its own, as M34's item reports have it: sold by the rupee, with
/// no quantity to count and no cost on record, so its sale is all profit in
/// the books and here. Without it the total came to less than the bills.
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
  final loose = items.any((s) => s.isLoose);
  return ReportTable(
    id: 'sales_by_item',
    title: 'Sales by item',
    period: period,
    columns: const [
      ReportColumn('Item', CellKind.text),
      ReportColumn('Qty', CellKind.qty),
      ReportColumn('Unit', CellKind.text),
      ReportColumn('Sales', CellKind.money),
      ReportColumn('Cost', CellKind.money, isCost: true),
      ReportColumn('Profit', CellKind.money, isCost: true),
      ReportColumn('Margin', CellKind.percent, isCost: true),
    ],
    rows: [
      for (final s in items)
        ReportRow(
          [
            s.itemName,
            s.isLoose ? null : s.netQty,
            s.isLoose ? '' : s.unitCode,
            s.netSales,
            s.isLoose ? null : s.netCost,
            s.profit,
            s.isLoose ? null : shareBp(s.profit, s.netSales),
          ],
          link: s.itemId == null
              ? null
              : ReportLink.item(
                  s.itemId!,
                  label: s.itemName,
                  unitCode: s.unitCode,
                ),
        ),
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
    notes: [_salesAreNet, if (loose) _looseIsAllProfit],
  );
}

const _looseIsAllProfit =
    '${ItemTrade.looseLines} is goods sold by the rupee with no item behind '
    'them: no cost was recorded, so the books count all of it as profit, '
    'and so does this report.';

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
ReportTable receivablesByAge(
  BusinessDate asOf,
  List<PartyReceivable> parties,
) => _byAge(
  id: 'receivables',
  title: 'Udhaar by age',
  who: 'Customer',
  asOf: asOf,
  parties: parties,
);

/// What the shop owes its suppliers, and for how long.
///
/// The same page as udhaar by age, the other way round: deliveries and
/// expenses left on account, aged from their dates.
ReportTable payablesByAge(BusinessDate asOf, List<PartyReceivable> parties) =>
    _byAge(
      id: 'payables',
      title: 'Owed to suppliers',
      who: 'Supplier',
      asOf: asOf,
      parties: parties,
    );

ReportTable _byAge({
  required String id,
  required String title,
  required String who,
  required BusinessDate asOf,
  required List<PartyReceivable> parties,
}) {
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
    id: id,
    title: title,
    period: ReportPeriod.day(asOf),
    columns: [
      ReportColumn(who, CellKind.text),
      const ReportColumn('Opening', CellKind.money),
      const ReportColumn('0-30 days', CellKind.money),
      const ReportColumn('31-60 days', CellKind.money),
      const ReportColumn('61-90 days', CellKind.money),
      const ReportColumn('Over 90 days', CellKind.money),
      const ReportColumn('Advance', CellKind.money),
      const ReportColumn('Owed', CellKind.money),
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
      'Aged from the date of each bill still open.',
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

/// The trial balance on [asOf]: every account's balance on the side it
/// falls, and the two sides summed. They agree, because every entry the
/// app writes is proved to balance before it commits; the report says so,
/// or says by how much they do not.
ReportTable trialBalance(BusinessDate asOf, List<AccountMovement> accounts) {
  final rows = _byCode(accounts.where((a) => !a.net.isZero));
  final debits = Money.sum([
    for (final a in rows)
      if (a.net.isPositive) a.net,
  ]);
  final credits = Money.sum([
    for (final a in rows)
      if (a.net.isNegative) -a.net,
  ]);
  return ReportTable(
    id: 'trial_balance',
    title: 'Trial Balance',
    period: ReportPeriod.day(asOf),
    columns: const [
      ReportColumn('Code', CellKind.text),
      ReportColumn('Account', CellKind.text),
      ReportColumn('Debit', CellKind.money),
      ReportColumn('Credit', CellKind.money),
    ],
    rows: [
      for (final a in rows)
        ReportRow([
          a.code,
          a.name,
          a.net.isPositive ? a.net : null,
          a.net.isNegative ? -a.net : null,
        ]),
      ReportRow(['', 'Total', debits, credits], style: RowStyle.total),
    ],
    notes: [
      if (debits == credits)
        'Debits and credits agree.'
      else
        _sidesDiffer('Debits and credits', debits - credits),
    ],
  );
}

/// The balance sheet on [asOf]: what the shop has, what it owes, and what
/// is the owner's, with the profit earned so far shown as its own line
/// until a year is closed into the owner's capital.
ReportTable balanceSheet(BusinessDate asOf, List<AccountMovement> accounts) {
  final assets = _byCode(
    accounts.where((a) => a.type == 'asset' && !a.net.isZero),
  );
  final liabilities = _byCode(
    accounts.where((a) => a.type == 'liability' && !a.net.isZero),
  );
  final equity = _byCode(
    accounts.where((a) => a.type == 'equity' && !a.net.isZero),
  );
  final profit =
      Money.sum([
        for (final a in accounts)
          if (a.type == 'income') -a.net,
      ]) -
      Money.sum([
        for (final a in accounts)
          if (a.type == 'expense') a.net,
      ]);

  final totalAssets = Money.sum(assets.map((a) => a.net));
  final totalLiabilities = Money.sum(liabilities.map((a) => -a.net));
  final totalEquity = Money.sum(equity.map((a) => -a.net)) + profit;
  final gap = totalAssets - totalLiabilities - totalEquity;

  const width = 2;
  return ReportTable(
    id: 'balance_sheet',
    title: 'Balance Sheet',
    period: ReportPeriod.day(asOf),
    columns: const [
      ReportColumn('Account', CellKind.text),
      ReportColumn('Amount', CellKind.money),
    ],
    rows: [
      ReportRow.heading('Assets', width),
      for (final a in assets) ReportRow([a.name, a.net]),
      ReportRow(['Total assets', totalAssets], style: RowStyle.subtotal),
      ReportRow.heading('Liabilities', width),
      for (final a in liabilities) ReportRow([a.name, -a.net]),
      ReportRow([
        'Total liabilities',
        totalLiabilities,
      ], style: RowStyle.subtotal),
      ReportRow.heading("Owner's equity", width),
      for (final a in equity) ReportRow([a.name, -a.net]),
      ReportRow(['Profit to date', profit]),
      ReportRow(['Total equity', totalEquity], style: RowStyle.subtotal),
      ReportRow([
        'Total liabilities and equity',
        totalLiabilities + totalEquity,
      ], style: RowStyle.total),
    ],
    notes: [
      if (gap.isZero)
        "What the shop has equals what it owes plus what is the owner's."
      else
        _sidesDiffer('The two sides', gap),
      _profitToDate,
    ],
  );
}

const _profitToDate =
    'Profit to date is every sale less every cost since the books began, '
    "until a year is closed into the owner's capital.";

String _sidesDiffer(String what, Money by) =>
    '$what differ by Rs ${by.abs.amountOnly}. Run the data health check in '
    'Settings.';

/// Batches past their date, and those coming up to it within [withinDays],
/// soonest first: what to pull off the shelf, and what to sell first or
/// send back to the supplier while it can still be sold.
ReportTable expiryReport(
  BusinessDate asOf,
  List<LotOnHand> batches, {
  int withinDays = 90,
}) {
  final today = DateTime.utc(asOf.year, asOf.month, asOf.day);
  int daysLeft(BusinessDate d) =>
      DateTime.utc(d.year, d.month, d.day).difference(today).inDays;
  final due = [
    for (final b in batches)
      if (b.expiry != null && daysLeft(b.expiry!) <= withinDays) b,
  ]..sort((a, b) => a.expiry!.value.compareTo(b.expiry!.value));
  final expired = due.where((b) => daysLeft(b.expiry!) < 0).toList();
  final value = Money.sum([for (final b in due) b.cost.amountFor(b.qty)]);
  final expiredValue = Money.sum([
    for (final b in expired) b.cost.amountFor(b.qty),
  ]);
  return ReportTable(
    id: 'expiry',
    title: 'Expiry',
    period: ReportPeriod.day(asOf),
    columns: const [
      ReportColumn('Item', CellKind.text),
      ReportColumn('Batch', CellKind.text),
      ReportColumn('Expiry', CellKind.text),
      ReportColumn('Days left', CellKind.count),
      ReportColumn('Qty', CellKind.qty),
      ReportColumn('Value', CellKind.money),
    ],
    rows: [
      for (final b in due)
        ReportRow([
          b.itemName,
          b.lotNo,
          b.expiry!.value,
          daysLeft(b.expiry!),
          b.qty,
          b.cost.amountFor(b.qty),
        ]),
      ReportRow([
        'Total',
        null,
        null,
        null,
        null,
        value,
      ], style: RowStyle.total),
    ],
    notes: [
      if (expired.isNotEmpty) _pastDate(expired.length, expiredValue),
      'Batches expiring within $withinDays days, valued at what they cost.',
    ],
  );
}

String _pastDate(int batches, Money value) {
  final what = batches == 1 ? '1 batch is' : '$batches batches are';
  return '$what past its date, worth Rs ${value.amountOnly} at cost. The '
      'counter will not sell them.';
}

/// The sales tax a registered shop charged and gave back in [period], by
/// rate, and what is owed over for it: the figures the monthly return asks
/// for, computed here and typed in by the shop or its accountant. Nothing is
/// sent anywhere.
///
/// A shop whose services the province taxes (M59) owes two authorities, and
/// the summary keeps them apart (M61): FBR's rows and "Total owed to FBR"
/// first, exactly as before, then a section of the province's own — "PRA
/// 16%", "PRA 8% (card)", what returns gave back of each, and "Owed to PRA"
/// — which is the figure the province's own return is filed from. The two
/// are never added together: a shop cannot pay PRA's tax to FBR.
ReportTable salesTaxSummary(ReportPeriod period, List<TaxLine> lines) {
  bool provincial(TaxLine l) => l.kind == 'provincial_st';
  final charged = [
    for (final l in lines)
      if (!l.isReturn && !provincial(l)) l,
  ]..sort((a, b) => a.code.compareTo(b.code));
  final returned = [
    for (final l in lines)
      if (l.isReturn && !provincial(l)) l,
  ];
  Money sum(Iterable<TaxLine> ls, String kind) => Money.sum([
    for (final l in ls)
      if (l.kind == kind) l.amount,
  ]);
  final st = sum(charged, 'sales_tax') - sum(returned, 'sales_tax');
  final ft = sum(charged, 'further_tax') - sum(returned, 'further_tax');

  // M61: the province's own section, authority by authority, the higher
  // rate first, and what came back under each after what was charged.
  final services = [
    for (final l in lines)
      if (provincial(l)) l,
  ];
  final authorities = {
    for (final l in services) serviceTaxAuthorityOf(l.code),
  }.toList()..sort();
  int byRate(TaxLine a, TaxLine b) {
    final r = b.rateBp.compareTo(a.rateBp);
    return r != 0 ? r : a.code.compareTo(b.code);
  }

  final owed = <String, Money>{};
  final provincialRows = <ReportRow>[];
  for (final who in authorities) {
    final mine = [
      for (final l in services)
        if (serviceTaxAuthorityOf(l.code) == who) l,
    ];
    final out = [
      for (final l in mine)
        if (!l.isReturn) l,
    ]..sort(byRate);
    final back = [
      for (final l in mine)
        if (l.isReturn) l,
    ]..sort(byRate);
    owed[who] =
        Money.sum([for (final l in out) l.amount]) -
        Money.sum([for (final l in back) l.amount]);
    provincialRows.addAll([
      for (final l in out)
        ReportRow([
          serviceTaxLabel(l.code, l.rateBp),
          l.rateBp,
          l.base,
          l.amount,
        ]),
      for (final l in back)
        ReportRow([
          '${serviceTaxLabel(l.code, l.rateBp)} given back on returns',
          l.rateBp,
          -l.base,
          -l.amount,
        ]),
      ReportRow([
        'Owed to $who',
        null,
        null,
        owed[who],
      ], style: RowStyle.subtotal),
    ]);
  }

  return ReportTable(
    id: 'sales_tax',
    title: 'Sales tax',
    period: period,
    columns: const [
      ReportColumn('Tax', CellKind.text),
      ReportColumn('Rate', CellKind.percent),
      ReportColumn('Value of supplies', CellKind.money),
      ReportColumn('Tax', CellKind.money),
    ],
    rows: [
      for (final l in charged)
        ReportRow([_taxName(l.code), l.rateBp, l.base, l.amount]),
      for (final l in returned)
        ReportRow([_taxName(l.code), null, -l.base, -l.amount]),
      ReportRow([
        'Sales tax owed (FBR)',
        null,
        null,
        st,
      ], style: RowStyle.subtotal),
      ReportRow([
        'Further tax owed (FBR)',
        null,
        null,
        ft,
      ], style: RowStyle.subtotal),
      ReportRow([
        'Total owed to FBR',
        null,
        null,
        st + ft,
      ], style: RowStyle.total),
      if (provincialRows.isNotEmpty) ...[
        ReportRow.heading('Provincial tax on services', 4),
        ...provincialRows,
      ],
    ],
    summary: [
      if (owed.isNotEmpty) ...[
        ReportFigure('Owed to FBR', st + ft),
        for (final who in authorities) ReportFigure('Owed to $who', owed[who]!),
      ],
    ],
    notes: [
      _noInputTax,
      if (owed.isNotEmpty) _owedToProvince(authorities),
      _neverSent,
    ],
  );
}

String _owedToProvince(List<String> authorities) {
  final who = authorities.join(' and ');
  return 'The tax on services is owed to $who, not FBR, and is filed on '
      '$who\'s own portal: it is never in the sales tax or the total owed '
      'to FBR. A service given back is taken off at the rate it was charged.';
}

const _noInputTax =
    'Input tax on purchases is not kept by this app yet: take it from the '
    'suppliers\' invoices when filing.';

const _neverSent =
    'Computed on this phone and never sent anywhere. File the return on IRIS.';

String _taxName(String code) => switch (code) {
  'ST_STD_18' => 'Sales tax 18%',
  'ST_3RD_18' => 'Sales tax, Third Schedule',
  'FURTHER_4' => 'Further tax 4%',
  'ST_RETURN' => 'Sales tax given back on returns',
  'FURTHER_RETURN' => 'Further tax given back on returns',
  _ => code,
};

/// The Tajir Dost fixed tax: one per cent of each month's turnover, for a
/// retailer in the scheme (SRO 1166(I)/2026), with the withholding already
/// paid on the shop's electricity bill left to be taken off.
ReportTable tajirDost(ReportPeriod period, Map<String, Money> turnover) {
  final months = turnover.keys.toList()..sort();
  final total = Money.sum(turnover.values);
  return ReportTable(
    id: 'tajir_dost',
    title: 'Tajir Dost 1%',
    period: period,
    columns: const [
      ReportColumn('Month', CellKind.text),
      ReportColumn('Turnover', CellKind.money),
      ReportColumn('Tax at 1%', CellKind.money),
    ],
    rows: [
      for (final m in months)
        ReportRow([m, turnover[m], turnover[m]!.percentBp(tajirDostBp)]),
      ReportRow([
        'Total',
        total,
        Money.sum([
          for (final m in months) turnover[m]!.percentBp(tajirDostBp),
        ]),
      ], style: RowStyle.total),
    ],
    notes: const [_lessUtilityWht, _neverSent],
  );
}

/// The Tajir Dost rate, in basis points.
const tajirDostBp = 100;

const _lessUtilityWht =
    'Take off the withholding tax already paid with the electricity bill for '
    'each month; what is left is what is paid.';

/// Every purchase bill in a period, and what went back: the register a
/// registered shop's accountant files input tax from (M24).
ReportTable purchaseRegister(
  ReportPeriod period,
  List<PurchaseRegisterLine> lines,
) {
  Money signed(PurchaseRegisterLine l, Money m) => l.isReturn ? -m : m;
  final taxable = Money.sum([for (final l in lines) signed(l, l.taxable)]);
  final tax = Money.sum([for (final l in lines) signed(l, l.tax)]);
  final total = Money.sum([for (final l in lines) signed(l, l.total)]);
  final owed = Money.sum([for (final l in lines) l.owed]);
  return ReportTable(
    id: 'purchase_register',
    title: 'Purchase register',
    period: period,
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Bill', CellKind.text),
      ReportColumn('Supplier', CellKind.text),
      ReportColumn('Their bill no', CellKind.text),
      ReportColumn('NTN', CellKind.text),
      ReportColumn('Value', CellKind.money),
      ReportColumn('Sales tax', CellKind.money),
      ReportColumn('Total', CellKind.money),
      ReportColumn('Unpaid', CellKind.money),
    ],
    rows: [
      for (final l in lines)
        ReportRow([
          l.date.value,
          l.isReturn ? '${l.docNo} (return)' : l.docNo,
          l.supplier,
          l.supplierBillNo ?? '',
          l.supplierNtn ?? '',
          signed(l, l.taxable),
          signed(l, l.tax),
          signed(l, l.total),
          l.owed,
        ]),
      ReportRow([
        'Total',
        '${lines.length}',
        '',
        '',
        '',
        taxable,
        tax,
        total,
        owed,
      ], style: RowStyle.total),
    ],
    notes: const [_returnsNote],
  );
}

/// One party's account over a period, as a statement to hand them (M24):
/// what they owed when it began, every bill, payment and charge in it with
/// the balance after each, and what they owe at the end.
///
/// [entries] is the party's whole ledger, oldest first, as the khata reads
/// it; the opening is the balance after the last entry before the period.
/// [owedToUs] is false for a supplier's statement, where the figures are
/// what the shop owes them.
ReportTable partyStatement({
  required String partyName,
  required ReportPeriod period,
  required List<LedgerEntry> entries,
  bool owedToUs = true,
}) {
  // The section the party reports share (M33): the same opening, the same
  // lines and the same closing, so the PDF the khata sends and the party
  // statement in the reports cannot tell a customer two different things.
  final section = statementSection(
    period: period,
    entries: entries,
    owedToUs: owedToUs,
  );
  final closing = section.closing;
  return ReportTable(
    id: 'statement',
    title: 'Statement of account: $partyName',
    period: period,
    columns: [
      const ReportColumn('Date', CellKind.text),
      const ReportColumn('Details', CellKind.text),
      const ReportColumn('Reference', CellKind.text),
      ReportColumn(owedToUs ? 'Debit' : 'Credit', CellKind.money),
      ReportColumn(owedToUs ? 'Credit' : 'Debit', CellKind.money),
      const ReportColumn('Balance', CellKind.money),
    ],
    rows: section.rows,
    notes: [
      if (closing.isNegative)
        owedToUs
            ? 'A minus balance is an advance: we owe it back.'
            : 'A minus balance is an advance we have paid them.',
    ],
  );
}

const _returnsNote =
    'Returns to suppliers are shown as minus amounts and taken off the '
    'totals.';
