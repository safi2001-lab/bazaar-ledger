import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';
import 'report_table.dart';
import 'staff_source.dart';

/// The staff and time reports (M35): who sold what, on which counter, how
/// it was paid, at what hour, the night's Z report, and what was changed
/// after it was made. None of the market's apps has them; a shop with hired
/// hands asks for every one.

/// Sales by whoever rang them up, or by the counter they were rung on,
/// over [period], the biggest first.
ReportTable salesByStaff(
  ReportPeriod period,
  List<StaffSales> staff, {
  required StaffGrouping by,
}) {
  final rows =
      staff.where((s) => s.bills > 0 || s.returns > 0 || s.voids > 0).toList()
        ..sort((a, b) {
          final bySales = b.sales.compareTo(a.sales);
          return bySales != 0 ? bySales : a.name.compareTo(b.name);
        });
  int count(int Function(StaffSales s) f) =>
      rows.fold<int>(0, (n, s) => n + f(s));
  Money sum(Money Function(StaffSales s) f) => Money.sum(rows.map(f));
  final bills = count((s) => s.bills);
  final sales = sum((s) => s.sales);
  final returned = sum((s) => s.returnsValue);
  final byUser = by == StaffGrouping.user;
  return ReportTable(
    id: byUser ? 'sales_by_cashier' : 'sales_by_counter',
    title: byUser ? 'Sales by cashier' : 'Sales by counter',
    period: period,
    columns: [
      ReportColumn(byUser ? 'Cashier' : 'Counter', CellKind.text),
      ReportColumn(byUser ? 'Role' : 'Letter', CellKind.text),
      const ReportColumn('Bills', CellKind.count),
      const ReportColumn('Sales', CellKind.money),
      const ReportColumn('Average bill', CellKind.money),
      const ReportColumn('Discount', CellKind.money),
      const ReportColumn('Returns', CellKind.count),
      const ReportColumn('Returned', CellKind.money),
      const ReportColumn('Voids', CellKind.count),
      const ReportColumn('Voided', CellKind.money),
      const ReportColumn('Net sales', CellKind.money),
    ],
    rows: [
      for (final s in rows)
        ReportRow([
          s.name,
          s.detail ?? '',
          s.bills,
          s.sales,
          averageOf(s.sales, s.bills),
          s.discount,
          s.returns,
          s.returnsValue,
          s.voids,
          s.voidsValue,
          s.sales - s.returnsValue,
        ]),
      ReportRow([
        'Total',
        null,
        bills,
        sales,
        averageOf(sales, bills),
        sum((s) => s.discount),
        count((s) => s.returns),
        returned,
        count((s) => s.voids),
        sum((s) => s.voidsValue),
        sales - returned,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Sales', sales),
      ReportFigure('Discount', sum((s) => s.discount)),
      ReportFigure.count('Voids', count((s) => s.voids)),
    ],
    notes: [byUser ? _byCashierNote : _byCounterNote, _standingNote],
  );
}

/// [total] over [count], to the paisa, a half going up; nothing over none.
Money averageOf(Money total, int count) {
  if (count <= 0) return Money.zero;
  final p = total.inPaisa;
  final q = p ~/ count;
  final r = p.remainder(count).abs() * 2;
  return Money.paisa(r >= count ? q + (p < 0 ? -1 : 1) : q);
}

/// How the period's sales were paid, and what came in on khatas, one line
/// per mode (M35).
///
/// Every tender is its own line. A bill paid Rs 500 in cash, Rs 300 by
/// JazzCash and the rest on udhaar is in all three, each for its own part,
/// so the Sales paid column adds up to the period's sales to the paisa:
/// the split tender is the one thing the market's best-known app is most
/// complained about getting wrong.
ReportTable paymentModeSummary(
  ReportPeriod period,
  List<TenderTotal> tenders,
  UdhaarGiven udhaar,
) {
  final byMode = {for (final t in tenders) t.mode: t};
  final modes = [
    for (final m in PaymentMode.all)
      if (byMode.containsKey(m)) m,
    for (final m in byMode.keys)
      if (!PaymentMode.all.contains(m)) m,
  ];
  final counter = Money.sum(tenders.map((t) => t.counter));
  final khata = Money.sum(tenders.map((t) => t.khata));
  final collected = counter + khata;
  final sales = counter + udhaar.amount;
  return ReportTable(
    id: 'payment_modes',
    title: 'Payment-mode summary',
    period: period,
    columns: const [
      ReportColumn('Paid by', CellKind.text),
      ReportColumn('Payments', CellKind.count),
      ReportColumn('Sales paid by it', CellKind.money),
      ReportColumn('Received on khatas', CellKind.money),
      ReportColumn('Total collected', CellKind.money),
    ],
    rows: [
      for (final m in modes)
        ReportRow([
          PaymentMode.label(m),
          byMode[m]!.counterCount + byMode[m]!.khataCount,
          byMode[m]!.counter,
          byMode[m]!.khata,
          byMode[m]!.total,
        ]),
      if (udhaar.bills > 0)
        ReportRow(['Udhaar', udhaar.bills, udhaar.amount, null, null]),
      ReportRow([
        'Total',
        null,
        sales,
        khata,
        collected,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Sales', sales),
      ReportFigure('Collected', collected),
      ReportFigure('Udhaar given', udhaar.amount),
    ],
    notes: const [_tenderNote, _chequeNote],
  );
}

const _tenderNote =
    'Each tender of a split bill is its own payment, in its own line. Sales '
    'paid by it is what was paid with the bills at the counter, and Udhaar '
    'is what they left owing: together they are the sales. Udhaar is not '
    'money, so it is not in the total collected.';

const _chequeNote =
    'A cheque is counted on the day it was taken; a void payment or a '
    'bounced cheque is not counted. The Cash flow counts a cheque when it '
    'clears.';

/// Selling by the hour of the day over [period] (M35): which hours the
/// counter needs a second pair of hands. Every hour from the first sale of
/// the day to the last is shown, a quiet one as nothing.
ReportTable hourlySales(ReportPeriod period, List<HourSales> hours) {
  final byHour = {for (final h in hours) h.hour: h};
  final busy = hours.where((h) => h.bills > 0).toList();
  final first = busy.isEmpty ? 0 : busy.map((h) => h.hour).reduce(_min);
  final last = busy.isEmpty ? -1 : busy.map((h) => h.hour).reduce(_max);
  final total = Money.sum(busy.map((h) => h.sales));
  final bills = busy.fold<int>(0, (n, h) => n + h.bills);
  HourSales? busiest;
  for (final h in busy) {
    if (busiest == null || h.sales > busiest.sales) busiest = h;
  }
  return ReportTable(
    id: 'hourly_sales',
    title: 'Hourly sales',
    period: period,
    columns: const [
      ReportColumn('Hour', CellKind.text),
      ReportColumn('Bills', CellKind.count),
      ReportColumn('Sales', CellKind.money),
      ReportColumn('Average bill', CellKind.money),
      ReportColumn('Share', CellKind.percent),
    ],
    rows: [
      for (var hour = first; hour <= last; hour++)
        ReportRow([
          hourLabel(hour),
          byHour[hour]?.bills ?? 0,
          byHour[hour]?.sales ?? Money.zero,
          averageOf(
            byHour[hour]?.sales ?? Money.zero,
            byHour[hour]?.bills ?? 0,
          ),
          shareBp(byHour[hour]?.sales ?? Money.zero, total),
        ]),
      ReportRow([
        'Total',
        bills,
        total,
        averageOf(total, bills),
        total.isZero ? 0 : 10000,
      ], style: RowStyle.total),
    ],
    summary: [ReportFigure('Sales', total), ReportFigure.count('Bills', bills)],
    notes: [if (busiest != null) _busiest(busiest), _hourNote],
  );
}

const _hourNote =
    'Each bill counts in the hour it was rung up, on Pakistan time, '
    'whatever the phone\'s own clock is set to. Over several days, an hour '
    'is that hour of every day added together.';

int _min(int a, int b) => a < b ? a : b;
int _max(int a, int b) => a > b ? a : b;

/// `09:00-10:00`.
String hourLabel(int hour) =>
    '${hour.toString().padLeft(2, '0')}:00-'
    '${((hour + 1) % 24).toString().padLeft(2, '0')}:00';

/// The night's Z report (M35): one page, and one roll of receipt paper, for
/// the day the shutter came down on. What was sold and brought back, what
/// came in by each mode, the udhaar given and recovered, what was spent,
/// the gross profit to a role that may see it, and the drawer as counted
/// against the books when the day was closed (M9).
///
/// Laid out two columns wide, words and an amount, so every line is one
/// line on a 58mm roll as well as an 80mm one: the receipt-printer path
/// every report already has (M33) prints it as it stands.
ReportTable dailySummary(
  ReportPeriod period,
  DayFigures d, {
  required bool showProfit,
}) {
  final netSales = d.sales - d.returnsValue;
  final collected = Money.sum(d.tenders.map((t) => t.total));
  final recovered = Money.sum(d.tenders.map((t) => t.khata));
  final profit =
      (d.salesTaxable - d.salesCost) - (d.returnsTaxable - d.returnsCost);
  final byMode = {for (final t in d.tenders) t.mode: t};
  final modes = [
    for (final m in PaymentMode.all)
      if (byMode.containsKey(m)) m,
    for (final m in byMode.keys)
      if (!PaymentMode.all.contains(m)) m,
  ];
  ReportRow line(String label, Money? amount, {RowStyle? style}) =>
      ReportRow([label, amount], style: style ?? RowStyle.line);
  String n(int count, String one, String many) =>
      count == 1 ? '1 $one' : '$count $many';

  final rows = <ReportRow>[
    ReportRow.heading('Sales', 2),
    line('Sales, ${n(d.bills, 'bill', 'bills')}', d.sales),
    if (d.returns > 0)
      line('Returns, ${n(d.returns, 'return', 'returns')}', -d.returnsValue),
    line('Net sales', netSales, style: RowStyle.subtotal),
    if (!d.discount.isZero) line('Discount given', d.discount),
    line('Items sold: ${n(d.linesSold, 'line', 'lines')}', null),
    ReportRow.heading('Money in', 2),
    for (final m in modes) line(PaymentMode.label(m), byMode[m]!.total),
    line('Total collected', collected, style: RowStyle.subtotal),
    ReportRow.heading('Udhaar', 2),
    line('Given, ${n(d.udhaar.bills, 'bill', 'bills')}', d.udhaar.amount),
    line('Recovered', recovered),
    ReportRow.heading('Expenses', 2),
    line('Expenses, ${n(d.expenses, 'voucher', 'vouchers')}', d.expensesValue),
    // The home's, apart (M58): it left the drawer, and it is not the shop's.
    if (d.takenHome > 0)
      line(
        'Ghar ka kharcha, ${n(d.takenHome, 'entry', 'entries')}',
        d.takenHomeValue,
      ),
    if (showProfit) ...[
      ReportRow.heading('Profit', 2),
      line('Gross profit', profit, style: RowStyle.subtotal),
    ],
    ReportRow.heading('Drawer', 2),
    if (d.counts.isEmpty)
      line('Not closed yet', null)
    else
      for (final c in d.counts) ...[
        line('Books said, ${c.time} (${c.closedBy})', c.expected),
        line('Counted', c.counted),
        line(
          c.shortBy.isZero
              ? 'Matched'
              : c.shortBy.isPositive
              ? 'Short'
              : 'Over',
          c.shortBy.abs,
          style: RowStyle.subtotal,
        ),
      ],
  ];

  return ReportTable(
    id: 'daily_summary',
    title: period.isOneDay ? 'Day summary (Z report)' : 'Summary (Z report)',
    period: period,
    columns: const [
      ReportColumn('Details', CellKind.text),
      ReportColumn('Amount', CellKind.money),
    ],
    rows: rows,
    summary: [
      ReportFigure(DayFigureLabel.netSales, netSales),
      ReportFigure(DayFigureLabel.collected, collected),
      ReportFigure(DayFigureLabel.udhaarGiven, d.udhaar.amount),
      ReportFigure(DayFigureLabel.expenses, d.expensesValue),
      if (showProfit) ReportFigure(DayFigureLabel.grossProfit, profit),
    ],
    notes: [_zNote, if (showProfit) _grossProfitNote],
  );
}

/// The Z report's headline figures, by the label each carries (M58): the
/// Reports hub's "Today" strip reads these five off today's Z report and
/// names each in the shop's own language, so the strip and the report are
/// one set of figures.
abstract final class DayFigureLabel {
  static const netSales = 'Net sales';
  static const collected = 'Collected';
  static const udhaarGiven = 'Udhaar given';
  static const expenses = 'Expenses';
  static const grossProfit = 'Gross profit';
}

const _zNote =
    'Money in is every payment taken, at the counter and on khatas; '
    'recovered is the part taken on khatas. The drawer is as counted at the '
    'day close against what the books said was in it.';

/// Voids, returns, edits and payments taken back in [period], in the
/// order they were made (M35): who did what to which bill, when, why, and
/// for how much. The page an owner reads when the drawer and the bills do
/// not agree.
///
/// Since M58 it is Marg's "bill value changes" too: an edit says what the
/// entry was and what it is now, Rs 5,000 to Rs 500, side by side; udhaar
/// written off or let go to settle (M44), a loan entry cancelled (M48), and
/// the closed books let into or opened again (M42) are among the changes;
/// and when somebody's PIN let a change through, the report says whose.
/// The [ReportFilter.minAmount] filter keeps it to what is worth an
/// owner's evening.
ReportTable changedBills(ReportPeriod period, List<ChangeRecord> changes) {
  int count(ChangeKind kind) =>
      changes.where((c) => changeKindOf(c.action) == kind).length;
  final letGo = count(ChangeKind.letGo);
  final books = count(ChangeKind.books);
  final allowed = changes.where((c) => c.allowedBy != null).length;
  return ReportTable(
    id: 'changed_bills',
    title: 'Changed and cancelled bills',
    period: period,
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Time', CellKind.text),
      ReportColumn('What', CellKind.text),
      ReportColumn('Number', CellKind.text),
      ReportColumn('Party', CellKind.text),
      ReportColumn('Was', CellKind.money),
      ReportColumn('Amount', CellKind.money),
      ReportColumn('Who', CellKind.text),
      ReportColumn('Allowed by', CellKind.text),
      ReportColumn('Reason', CellKind.text),
    ],
    rows: [
      for (final c in changes)
        ReportRow(
          [
            c.date.value,
            c.time,
            changeLabel(c.action),
            c.reference ?? '',
            c.party ?? '',
            c.was,
            c.amount,
            c.who,
            c.allowedBy ?? '',
            c.reason ?? '',
          ],
          link: c.documentId == null
              ? null
              : ReportLink.document(
                  c.documentId!,
                  label: c.reference ?? c.summary,
                  docType: c.docType,
                ),
        ),
      ReportRow([
        'Total',
        null,
        changes.length == 1 ? '1 change' : '${changes.length} changes',
        null,
        null,
        null,
        null,
        null,
        null,
        null,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('Voids', count(ChangeKind.void_)),
      ReportFigure.count('Returns', count(ChangeKind.return_)),
      ReportFigure.count('Edits', count(ChangeKind.edit)),
      if (letGo > 0) ReportFigure.count('Let go', letGo),
      if (books > 0) ReportFigure.count('Closed books', books),
      if (allowed > 0) ReportFigure.count('By PIN', allowed),
    ],
    notes: const [_changesNote, _wasNote],
  );
}

const _changesNote =
    'Who is whoever made the change, which need not be whoever made the '
    'bill. An edited entry is the old one cancelled and a new one made in '
    'its place; the amount is the new one.';

const _wasNote =
    'Was is what an edited entry or an opening balance came to before. '
    'Allowed by is whose PIN let the change through, when one was asked for.';

/// What kind of change an audit code is (M58).
enum ChangeKind {
  /// Cancelled: a bill, a payment, a loan entry.
  void_,

  /// Goods brought back or sent back.
  return_,

  /// Put right: an entry replaced by a corrected one, an opening balance.
  edit,

  /// Udhaar written off or let go to settle (M44).
  letGo,

  /// The closed books let into or opened again (M42).
  books,
}

/// The kind [action] is.
ChangeKind changeKindOf(String action) => switch (action) {
  'DOCUMENT_VOIDED' ||
  'PAYMENT_VOIDED' ||
  'LOAN_ENTRY_CANCELLED' => ChangeKind.void_,
  'SALE_RETURNED' || 'PURCHASE_RETURNED' => ChangeKind.return_,
  'BAD_DEBT_WRITTEN_OFF' || 'SETTLEMENT_DISCOUNT_GIVEN' => ChangeKind.letGo,
  closedBooksOverrideAction || booksReopenedAction => ChangeKind.books,
  _ => ChangeKind.edit,
};

/// The audit codes the Changed and cancelled bills report lists, as it
/// writes them.
String changeLabel(String action) => switch (action) {
  'DOCUMENT_VOIDED' => 'Voided',
  'PAYMENT_VOIDED' => 'Payment taken back',
  'SALE_RETURNED' => 'Sale return',
  'PURCHASE_RETURNED' => 'Goods sent back',
  'EXPENSE_EDITED' => 'Expense edited',
  'CHARGE_EDITED' => 'Charge edited',
  'PAYMENT_EDITED' => 'Payment edited',
  'OPENING_BALANCE_CORRECTED' => 'Opening balance put right',
  // M58
  'BAD_DEBT_WRITTEN_OFF' => 'Written off',
  'SETTLEMENT_DISCOUNT_GIVEN' => 'Settlement discount',
  'LOAN_ENTRY_CANCELLED' => 'Loan entry cancelled',
  closedBooksOverrideAction => 'Let into closed books',
  booksReopenedAction => 'Books opened again',
  _ => action,
};

/// The audit codes that are a change to something already made.
const changeActions = [
  'DOCUMENT_VOIDED',
  'PAYMENT_VOIDED',
  'SALE_RETURNED',
  'PURCHASE_RETURNED',
  'EXPENSE_EDITED',
  'CHARGE_EDITED',
  'PAYMENT_EDITED',
  'OPENING_BALANCE_CORRECTED',
  // M58: udhaar let go (M44), a loan entry cancelled (M48), and the closed
  // books let into or opened again (M42).
  'BAD_DEBT_WRITTEN_OFF',
  'SETTLEMENT_DISCOUNT_GIVEN',
  'LOAN_ENTRY_CANCELLED',
  closedBooksOverrideAction,
  booksReopenedAction,
];

const _byCashierNote =
    'Each bill and each void counts for whoever rang the bill up, and each '
    'return for whoever took the goods back. Who cancelled a bill is in '
    'Changed and cancelled bills.';

const _byCounterNote =
    'Each bill counts for the phone or till it was rung on, whose letter is '
    'on its number.';

const _standingNote =
    'Sales are bills that stand, tax included; a voided bill is in Voided '
    'and nowhere else.';

String _busiest(HourSales h) =>
    'Busiest hour: ${hourLabel(h.hour)}, Rs ${h.sales.amountOnly} on '
    '${h.bills} ${h.bills == 1 ? 'bill' : 'bills'}.';

const _grossProfitNote =
    'Gross profit is sales before tax less what the goods cost when they '
    'left the shelf, returns taken back.';
