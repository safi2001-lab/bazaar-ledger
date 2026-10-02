import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';
import 'report_table.dart';
import 'transaction_source.dart';

/// The transaction reports (M33): the sale and purchase reports, bill-wise
/// profit, every transaction of every kind, and where the money came from
/// and went. Pure builders, like every other report: each total is on the
/// table before the screen or an export sees it.

/// Every sale bill in [period]: what it came to, what has been paid on it,
/// what is still owed, how it was paid, and whether it is settled.
ReportTable saleReport(ReportPeriod period, List<BillRow> bills) =>
    _billRegister(
      id: 'sale_report',
      title: 'Sale report',
      period: period,
      bills: [
        for (final b in bills)
          if (b.docType == TransactionType.sale) b,
      ],
      totalLabel: 'Total sale',
      paidLabel: 'Received',
      balanceLabel: 'Balance',
      note: _receivedSince,
    );

const _saleAmountAndCost =
    'Sale amount is before tax and after every discount. Cost is what the '
    'goods cost when they left the shelf, as the bill recorded it.';

const _receivedSince =
    'Received is what has been paid against each bill, at the counter or '
    'since. A return against a bill comes off its balance; the returns '
    'themselves are in All Transactions.';

/// Every purchase bill in [period], the same way round: what each delivery
/// came to, what has been paid for it, and what is still owed.
ReportTable purchaseReport(ReportPeriod period, List<BillRow> bills) =>
    _billRegister(
      id: 'purchase_report',
      title: 'Purchase report',
      period: period,
      bills: [
        for (final b in bills)
          if (b.docType == TransactionType.purchase) b,
      ],
      totalLabel: 'Total purchase',
      paidLabel: 'Paid',
      balanceLabel: 'Unpaid',
      note: _paidSince,
    );

const _paidSince =
    'Paid is what has gone to the supplier against each bill, at the door '
    'or since. Goods sent back come off what is unpaid; the returns '
    'themselves are in All Transactions.';

ReportTable _billRegister({
  required String id,
  required String title,
  required ReportPeriod period,
  required List<BillRow> bills,
  required String totalLabel,
  required String paidLabel,
  required String balanceLabel,
  required String note,
}) {
  final total = Money.sum(bills.map((b) => b.total));
  final paid = Money.sum(bills.map((b) => b.paid));
  final balance = Money.sum(bills.map((b) => b.balance));
  return ReportTable(
    id: id,
    title: title,
    period: period,
    columns: [
      const ReportColumn('Date', CellKind.text),
      const ReportColumn('Bill', CellKind.text),
      const ReportColumn('Party', CellKind.text),
      const ReportColumn('Total', CellKind.money),
      ReportColumn(paidLabel, CellKind.money),
      ReportColumn(balanceLabel, CellKind.money),
      const ReportColumn('Paid by', CellKind.text),
      const ReportColumn('Status', CellKind.text),
    ],
    rows: [
      for (final b in bills)
        ReportRow(
          [
            b.date.value,
            b.docNo,
            b.party,
            b.total,
            b.paid,
            b.balance,
            b.modes.map(PaymentMode.label).join(', '),
            paymentStatusLabel(b.status),
          ],
          link: ReportLink.document(
            b.documentId,
            label: b.docNo,
            docType: b.docType,
          ),
        ),
      ReportRow([
        'Total',
        bills.length == 1 ? '1 bill' : '${bills.length} bills',
        null,
        total,
        paid,
        balance,
        null,
        null,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure(totalLabel, total),
      ReportFigure(paidLabel, paid),
      ReportFigure(balanceLabel, balance),
    ],
    notes: [note],
  );
}

/// What each sale bill in [period] made over what its goods cost, at the
/// cost they left the shelf at, as the bill itself recorded it (M33).
///
/// A return is a row of its own, with its sale and its cost taken back, so
/// the period's total is what the bills and returns between them earned and
/// agrees with the profit in Sales by item and Party-wise profit and loss.
ReportTable billWiseProfit(ReportPeriod period, List<BillRow> bills) {
  final rows = [
    for (final b in bills)
      if (b.docType == TransactionType.sale ||
          b.docType == TransactionType.saleReturn)
        b,
  ];
  Money signed(BillRow b, Money m) => b.isReturn ? -m : m;
  final sales = Money.sum([for (final b in rows) signed(b, b.taxable)]);
  final cost = Money.sum([for (final b in rows) signed(b, b.cost)]);
  final profit = sales - cost;
  final losing = rows.where((b) => !b.isReturn && b.profit.isNegative).length;
  return ReportTable(
    id: 'bill_wise_profit',
    title: 'Bill-wise profit',
    period: period,
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Bill', CellKind.text),
      ReportColumn('Party', CellKind.text),
      ReportColumn('Sale amount', CellKind.money),
      ReportColumn('Cost', CellKind.money, isCost: true),
      ReportColumn('Profit', CellKind.money, isCost: true),
      ReportColumn('Margin', CellKind.percent, isCost: true),
    ],
    rows: [
      for (final b in rows)
        ReportRow(
          [
            b.date.value,
            b.isReturn ? '${b.docNo} (return)' : b.docNo,
            b.party,
            signed(b, b.taxable),
            signed(b, b.cost),
            signed(b, b.profit),
            shareBp(b.profit, b.taxable),
          ],
          link: ReportLink.document(
            b.documentId,
            label: b.docNo,
            docType: b.docType,
          ),
        ),
      ReportRow([
        'Total',
        rows.length == 1 ? '1 bill' : '${rows.length} bills',
        null,
        sales,
        cost,
        profit,
        shareBp(profit, sales),
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Sales', sales),
      ReportFigure('Cost', cost),
      ReportFigure('Profit', profit),
    ],
    notes: [
      _saleAmountAndCost,
      if (losing > 0)
        losing == 1
            ? '1 bill sold below cost.'
            : '$losing bills sold below cost.',
    ],
  );
}

/// Every document and payment in [period], of every kind, in the order
/// they were recorded, then summed by kind (M33). A void is listed, so the
/// owner sees what was cancelled, and left out of every sum.
ReportTable allTransactions(ReportPeriod period, List<TransactionRow> rows) {
  final standing = rows.where((r) => !r.isVoid).toList();
  final voids = rows.length - standing.length;

  final byType = <String, List<TransactionRow>>{};
  for (final r in standing) {
    byType.putIfAbsent(r.type, () => []).add(r);
  }
  Money sum(Iterable<TransactionRow> rs, Money Function(TransactionRow) f) =>
      Money.sum(rs.map(f));
  Money totalOf(String type) =>
      sum(byType[type] ?? const <TransactionRow>[], (r) => r.total);

  final types = [
    for (final t in TransactionType.all)
      if (byType.containsKey(t)) t,
    for (final t in byType.keys)
      if (!TransactionType.all.contains(t)) t,
  ];

  return ReportTable(
    id: 'all_transactions',
    title: 'All transactions',
    period: period,
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Number', CellKind.text),
      ReportColumn('Type', CellKind.text),
      ReportColumn('Party', CellKind.text),
      ReportColumn('Total', CellKind.money),
      ReportColumn('Paid', CellKind.money),
      ReportColumn('Balance', CellKind.money),
      ReportColumn('Status', CellKind.text),
    ],
    rows: [
      for (final r in rows)
        ReportRow(
          [
            r.date.value,
            r.number,
            TransactionType.label(r.type),
            r.party,
            r.total,
            _settles(r.type) ? r.paid : null,
            _settles(r.type) ? r.balance : null,
            _status(r),
          ],
          link: r.isPayment
              ? null
              : ReportLink.document(r.id, label: r.number, docType: r.type),
        ),
      if (types.isNotEmpty) ReportRow.heading('By type', 8),
      for (final t in types)
        ReportRow([
          '',
          '${byType[t]!.length}',
          TransactionType.label(t),
          '',
          totalOf(t),
          _settles(t) ? sum(byType[t]!, (r) => r.paid) : null,
          _settles(t) ? sum(byType[t]!, (r) => r.balance) : null,
          '',
        ], style: RowStyle.subtotal),
      ReportRow([
        'Total',
        standing.length == 1
            ? '1 transaction'
            : '${standing.length} '
                  'transactions',
        null,
        null,
        null,
        null,
        null,
        voids == 0 ? null : '$voids void',
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('Transactions', standing.length),
      ReportFigure('Sales', totalOf(TransactionType.sale)),
      ReportFigure('Purchases', totalOf(TransactionType.purchase)),
    ],
    notes: [
      _byTypeNote,
      if (voids > 0)
        voids == 1
            ? '1 void is listed and counted nowhere.'
            : '$voids voids are listed and counted nowhere.',
    ],
  );
}

const _byTypeNote =
    'Totals by type leave out anything voided. A payment taken with a bill '
    'at the counter is part of that bill, not a line of its own.';

/// Whether a transaction of [type] is something paid against.
bool _settles(String type) => const {
  TransactionType.sale,
  TransactionType.saleReturn,
  TransactionType.purchase,
  TransactionType.purchaseReturn,
  TransactionType.expense,
  TransactionType.charge,
}.contains(type);

String _status(TransactionRow r) {
  if (r.isVoid) return 'Void';
  if (r.isPayment) {
    return switch (r.status) {
      'pending' => 'Cheque pending',
      'bounced' => 'Bounced',
      _ => 'Cleared',
    };
  }
  if (!_settles(r.type) ||
      r.type == TransactionType.saleReturn ||
      r.type == TransactionType.purchaseReturn) {
    return '';
  }
  if (!r.balance.isPositive) return paymentStatusLabel(PaymentStatus.paid);
  return paymentStatusLabel(
    r.paid.isPositive ? PaymentStatus.partial : PaymentStatus.unpaid,
  );
}

/// Where the money came from and where it went over [period], summed by
/// what moved it, for the drawer and for the bank and wallets (M33).
///
/// Not the Cash Book. The Cash Book is the drawer entry by entry, for
/// counting it; this is the period at a glance, every kind of money the
/// shop holds, so "we sold well, where is the money" has an answer in one
/// page: so much came in at the counter and on khatas, so much went on
/// deliveries, suppliers and expenses, and this is what is left.
ReportTable cashflow(
  ReportPeriod period,
  MoneyBalance opening,
  List<MoneyFlow> flows,
) {
  final inCash = <String, Money>{};
  final inBank = <String, Money>{};
  final outCash = <String, Money>{};
  final outBank = <String, Money>{};
  void add(Map<String, Money> into, String kind, Money m) {
    if (m.isZero) return;
    into[kind] = (into[kind] ?? Money.zero) + m;
  }

  for (final f in flows) {
    add(f.inCash ? inCash : inBank, f.kind, f.moneyIn);
    add(f.inCash ? outCash : outBank, f.kind, f.moneyOut);
  }

  List<String> kinds(Map<String, Money> a, Map<String, Money> b) {
    final present = {...a.keys, ...b.keys};
    return [
      for (final k in _flowOrder)
        if (present.contains(k)) k,
      ...present.where((k) => !_flowOrder.contains(k)).toList()..sort(),
    ];
  }

  final cashIn = Money.sum(inCash.values);
  final bankIn = Money.sum(inBank.values);
  final cashOut = Money.sum(outCash.values);
  final bankOut = Money.sum(outBank.values);
  final closingCash = opening.cash + cashIn - cashOut;
  final closingBank = opening.bank + bankIn - bankOut;

  ReportRow line(String label, Money cash, Money bank, {RowStyle? style}) =>
      ReportRow([
        label,
        cash,
        bank,
        cash + bank,
      ], style: style ?? RowStyle.line);

  return ReportTable(
    id: 'cash_flow',
    title: 'Cash flow',
    period: period,
    columns: const [
      ReportColumn('Details', CellKind.text),
      ReportColumn('Cash', CellKind.money),
      ReportColumn('Bank and wallets', CellKind.money),
      ReportColumn('Total', CellKind.money),
    ],
    rows: [
      line(
        'Opening balance',
        opening.cash,
        opening.bank,
        style: RowStyle.subtotal,
      ),
      ReportRow.heading('Money in', 4),
      for (final k in kinds(inCash, inBank))
        line(
          _flowLabel(k, moneyIn: true),
          inCash[k] ?? Money.zero,
          inBank[k] ?? Money.zero,
        ),
      line('Total money in', cashIn, bankIn, style: RowStyle.subtotal),
      ReportRow.heading('Money out', 4),
      for (final k in kinds(outCash, outBank))
        line(
          _flowLabel(k, moneyIn: false),
          outCash[k] ?? Money.zero,
          outBank[k] ?? Money.zero,
        ),
      line('Total money out', cashOut, bankOut, style: RowStyle.subtotal),
      line(
        'Net change',
        cashIn - cashOut,
        bankIn - bankOut,
        style: RowStyle.subtotal,
      ),
      line('Closing balance', closingCash, closingBank, style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Opening balance', opening.total),
      ReportFigure('Money in', cashIn + bankIn),
      ReportFigure('Money out', cashOut + bankOut),
      ReportFigure('Closing balance', closingCash + closingBank),
    ],
    notes: const [_flowNote],
  );
}

const _flowNote =
    'Cash is the drawer; bank and wallets are every bank account and mobile '
    'wallet. A cheque counts when it clears. Money moved between the drawer '
    'and the bank shows on both sides. The Cash Book lists the drawer entry '
    'by entry.';

const _flowOrder = [
  'opening',
  'sale',
  'payment',
  'other_income',
  'sale_return',
  'purchase',
  'purchase_return',
  'expense',
  'manual',
  'adjustment',
  'reversal',
];

String _flowLabel(String kind, {required bool moneyIn}) => switch (kind) {
  'sale' => 'Sales at the counter',
  'payment' => moneyIn ? 'Received on khatas' : 'Paid to parties',
  'other_income' => 'Charges and other income',
  'sale_return' => moneyIn ? 'Sale returns' : 'Refunds to customers',
  'purchase' => 'Paid for deliveries',
  'purchase_return' => moneyIn ? 'Refunds from suppliers' : 'Purchase returns',
  'expense' => 'Expenses',
  'opening' => 'Opening balances',
  'manual' => 'Journal vouchers',
  'adjustment' => 'Adjustments',
  'reversal' => 'Cancelled entries',
  _ => kind,
};
