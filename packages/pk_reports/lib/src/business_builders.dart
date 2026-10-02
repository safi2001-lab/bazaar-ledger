import 'package:pk_domain/pk_domain.dart';

import 'business_source.dart';
import 'period.dart';
import 'report_table.dart';
import 'staff_source.dart';

/// The business status reports (M35): the bank statement, the discounts,
/// and how customers pay. Pure builders, like every other report: each
/// total is on the table before the screen or an export sees it.

/// Each money account's statement over [period]: what it held when the
/// period began, every deposit and withdrawal with the balance after it,
/// and what it holds at the end, which is the account's balance in the
/// books on the period's last day.
///
/// The bank's own statement and this one should agree line for line once
/// every cheque has cleared; where they do not, the difference is a line
/// one side has and the other does not, which is what a shopkeeper takes
/// to the bank.
ReportTable bankStatement(
  ReportPeriod period,
  List<BankStatementAccount> accounts,
) {
  final rows = <ReportRow>[];
  var opening = Money.zero;
  var deposits = Money.zero;
  var withdrawals = Money.zero;
  var closing = Money.zero;
  final several = accounts.length > 1;

  for (final a in accounts) {
    var running = a.opening;
    final inAccount = Money.sum(a.lines.map((l) => l.deposit));
    final outOfAccount = Money.sum(a.lines.map((l) => l.withdrawal));
    if (several) rows.add(ReportRow.heading(a.name, 6));
    rows.add(
      ReportRow([
        period.from.value,
        'Opening balance',
        null,
        null,
        null,
        a.opening,
      ], style: RowStyle.subtotal),
    );
    for (final l in a.lines) {
      running = running + l.deposit - l.withdrawal;
      rows.add(
        ReportRow(
          [
            l.date.value,
            l.reference == null || l.description.contains(l.reference!)
                ? l.description
                : '${l.description} ${l.reference}',
            l.party ?? '',
            l.withdrawal.isZero ? null : l.withdrawal,
            l.deposit.isZero ? null : l.deposit,
            running,
          ],
          link: l.documentId == null
              ? null
              : ReportLink.document(
                  l.documentId!,
                  label: l.reference ?? l.description,
                  docType: l.docType,
                ),
        ),
      );
    }
    rows.add(
      ReportRow([
        period.to.value,
        several ? 'Closing balance, ${a.name}' : 'Closing balance',
        null,
        outOfAccount,
        inAccount,
        running,
      ], style: several ? RowStyle.subtotal : RowStyle.total),
    );
    opening += a.opening;
    deposits += inAccount;
    withdrawals += outOfAccount;
    closing += running;
  }
  if (several || accounts.isEmpty) {
    rows.add(
      ReportRow([
        period.to.value,
        several ? 'All accounts' : 'No bank or wallet account',
        null,
        withdrawals,
        deposits,
        closing,
      ], style: RowStyle.total),
    );
  }

  return ReportTable(
    id: 'bank_statement',
    title: accounts.length == 1
        ? 'Bank statement: ${accounts.single.name}'
        : 'Bank statement',
    period: period,
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Description', CellKind.text),
      ReportColumn('Party', CellKind.text),
      ReportColumn('Withdrawal', CellKind.money),
      ReportColumn('Deposit', CellKind.money),
      ReportColumn('Balance', CellKind.money),
    ],
    rows: rows,
    summary: [
      ReportFigure('Opening balance', opening),
      ReportFigure('Deposits', deposits),
      ReportFigure('Withdrawals', withdrawals),
      ReportFigure('Closing balance', closing),
    ],
    notes: const [_bankNote],
  );
}

const _bankNote =
    'From the books: every entry against the account. A cheque is in the '
    'bank on the day it clears, not the day it was taken, and money moved '
    'between the drawer and the bank shows on both. The closing balance is '
    'the account in the Balance Sheet on that day.';

/// The discounts given to each party on its sale bills over [period], and
/// taken from each supplier on theirs (M35), largest first.
ReportTable discountByParty(ReportPeriod period, List<PartyDiscount> rows) {
  final parties =
      rows
          .where((r) => !r.discountGiven.isZero || !r.discountReceived.isZero)
          .toList()
        ..sort((a, b) {
          final byGiven = b.discountGiven.compareTo(a.discountGiven);
          if (byGiven != 0) return byGiven;
          final byTaken = b.discountReceived.compareTo(a.discountReceived);
          return byTaken != 0 ? byTaken : a.name.compareTo(b.name);
        });
  Money sum(Money Function(PartyDiscount r) f) => Money.sum(parties.map(f));
  final given = sum((r) => r.discountGiven);
  final before = sum((r) => r.salesBeforeDiscount);
  final received = sum((r) => r.discountReceived);
  return ReportTable(
    id: 'discount_by_party',
    title: 'Discount report',
    period: period,
    columns: const [
      ReportColumn('Party', CellKind.text),
      ReportColumn('Sale bills', CellKind.count),
      ReportColumn('Sales before discount', CellKind.money),
      ReportColumn('Discount given', CellKind.money),
      ReportColumn('Share', CellKind.percent),
      ReportColumn('Purchase bills', CellKind.count),
      ReportColumn('Discount received', CellKind.money),
    ],
    rows: [
      for (final r in parties)
        ReportRow(
          [
            r.name,
            r.saleBills,
            r.salesBeforeDiscount,
            r.discountGiven,
            shareBp(r.discountGiven, r.salesBeforeDiscount),
            r.purchaseBills,
            r.discountReceived,
          ],
          link: r.partyId == null
              ? null
              : ReportLink.party(r.partyId!, label: r.name),
        ),
      ReportRow([
        'Total',
        parties.fold<int>(0, (n, r) => n + r.saleBills),
        before,
        given,
        shareBp(given, before),
        parties.fold<int>(0, (n, r) => n + r.purchaseBills),
        received,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Discount given', given),
      ReportFigure('Discount received', received),
    ],
    notes: const [_discountNote],
  );
}

const _discountNote =
    'Discount is every line and bill discount on the bills, and share is it '
    'as a part of what those bills came to before it. A supplier whose rate '
    'already has the discount in it shows none received.';

/// The discount each member of staff gave over [period] (M35), the
/// largest share first: where a counter's discount is leaking, it shows
/// here before it shows in the month's profit.
ReportTable discountByCashier(ReportPeriod period, List<StaffSales> staff) {
  final rows = staff.where((s) => s.bills > 0).toList()
    ..sort((a, b) {
      final byShare = shareBp(
        b.discount,
        b.salesBeforeDiscount,
      ).compareTo(shareBp(a.discount, a.salesBeforeDiscount));
      return byShare != 0 ? byShare : a.name.compareTo(b.name);
    });
  final before = Money.sum(rows.map((s) => s.salesBeforeDiscount));
  final given = Money.sum(rows.map((s) => s.discount));
  return ReportTable(
    id: 'discount_by_cashier',
    title: 'Discount by cashier',
    period: period,
    columns: const [
      ReportColumn('Cashier', CellKind.text),
      ReportColumn('Role', CellKind.text),
      ReportColumn('Bills', CellKind.count),
      ReportColumn('Bills with discount', CellKind.count),
      ReportColumn('Sales before discount', CellKind.money),
      ReportColumn('Discount', CellKind.money),
      ReportColumn('Share', CellKind.percent),
    ],
    rows: [
      for (final s in rows)
        ReportRow([
          s.name,
          s.detail ?? '',
          s.bills,
          s.discountedBills,
          s.salesBeforeDiscount,
          s.discount,
          shareBp(s.discount, s.salesBeforeDiscount),
        ]),
      ReportRow([
        'Total',
        null,
        rows.fold<int>(0, (n, s) => n + s.bills),
        rows.fold<int>(0, (n, s) => n + s.discountedBills),
        before,
        given,
        shareBp(given, before),
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Discount given', given),
      ReportFigure.count(
        'Bills with discount',
        rows.fold<int>(0, (n, s) => n + s.discountedBills),
      ),
    ],
    notes: const [_cashierDiscountNote],
  );
}

const _cashierDiscountNote =
    'Each bill counts for whoever rang it up. Share is the discount as a '
    'part of what their bills came to before it; one cashier far above the '
    'rest is the first question to ask at closing time.';

/// How each customer pays (M35): of the bills in [period] that went on
/// udhaar, how many are settled and how long they took, how many were paid
/// late, and how many are past due on [today]. The slowest first.
///
/// Late is against the customer's own credit days, or [defaultCreditDays]
/// where the khata sets none; a bill paid in full at the counter was never
/// udhaar and is not counted.
ReportTable paymentPerformance(
  ReportPeriod period,
  BusinessDate today,
  List<PaymentRecord> records,
) {
  final rows = records.where((r) => r.udhaarBills > 0).toList()
    ..sort((a, b) {
      final byOverdue = b.overdue.compareTo(a.overdue);
      if (byOverdue != 0) return byOverdue;
      final byDays = (_averageDays(b) ?? -1).compareTo(_averageDays(a) ?? -1);
      return byDays != 0 ? byDays : a.name.compareTo(b.name);
    });
  int count(int Function(PaymentRecord r) f) =>
      rows.fold<int>(0, (n, r) => n + f(r));
  final settled = count((r) => r.settledBills);
  final days = count((r) => r.daysToSettle);
  final overdue = Money.sum(rows.map((r) => r.overdue));
  final open = Money.sum(rows.map((r) => r.open));
  final average = settled == 0 ? null : _roundedDays(days, settled);
  return ReportTable(
    id: 'payment_performance',
    title: 'Customer payment performance',
    period: period,
    columns: const [
      ReportColumn('Customer', CellKind.text),
      ReportColumn('Credit days', CellKind.count),
      ReportColumn('Udhaar bills', CellKind.count),
      ReportColumn('Settled', CellKind.count),
      ReportColumn('Average days to pay', CellKind.count),
      ReportColumn('Paid late', CellKind.count),
      ReportColumn('Overdue bills', CellKind.count),
      ReportColumn('Overdue', CellKind.money),
      ReportColumn('Still open', CellKind.money),
    ],
    rows: [
      for (final r in rows)
        ReportRow([
          r.name,
          r.creditDays,
          r.udhaarBills,
          r.settledBills,
          _averageDays(r),
          r.paidLate,
          r.overdueBills,
          r.overdue,
          r.open,
        ], link: ReportLink.party(r.partyId, label: r.name)),
      ReportRow([
        'Total',
        null,
        count((r) => r.udhaarBills),
        settled,
        average,
        count((r) => r.paidLate),
        count((r) => r.overdueBills),
        overdue,
        open,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('Udhaar bills', count((r) => r.udhaarBills)),
      if (average != null) ReportFigure.count('Average days to pay', average),
      ReportFigure('Overdue', overdue),
    ],
    notes: [_periodBills(period, today), _performanceNote],
  );
}

const _performanceNote =
    'Days to pay run from the bill to the payment or return that cleared '
    'it. Late is past the credit days on the khata, or '
    '$defaultCreditDays days where it sets none.';

int? _averageDays(PaymentRecord r) =>
    r.settledBills == 0 ? null : _roundedDays(r.daysToSettle, r.settledBills);

/// [days] over [bills], to the nearest whole day, a half going up.
int _roundedDays(int days, int bills) => (days * 2 + bills) ~/ (bills * 2);

/// Every customer with udhaar past its due date on [today] (M35), the most
/// overdue first: the list a shopkeeper works through before giving anyone
/// more.
ReportTable defaulterList(BusinessDate today, List<DefaulterRow> rows) {
  final owing = rows.where((r) => r.overdue.isPositive).toList()
    ..sort((a, b) {
      final byOverdue = b.overdue.compareTo(a.overdue);
      return byOverdue != 0 ? byOverdue : a.name.compareTo(b.name);
    });
  final overdue = Money.sum(owing.map((r) => r.overdue));
  final open = Money.sum(owing.map((r) => r.open));
  return ReportTable(
    id: 'defaulters',
    title: 'Defaulter list',
    period: ReportPeriod.day(today),
    columns: const [
      ReportColumn('Customer', CellKind.text),
      ReportColumn('Phone', CellKind.text),
      ReportColumn('Credit days', CellKind.count),
      ReportColumn('Oldest bill', CellKind.text),
      ReportColumn('Days overdue', CellKind.count),
      ReportColumn('Overdue bills', CellKind.count),
      ReportColumn('Overdue', CellKind.money),
      ReportColumn('Owed in all', CellKind.money),
      ReportColumn('Credit limit', CellKind.money),
      ReportColumn('Last paid', CellKind.text),
    ],
    rows: [
      for (final r in owing)
        ReportRow([
          r.name,
          r.phone ?? '',
          r.creditDays,
          r.oldestBill.value,
          calendarDays(r.oldestBill, today) - r.creditDays,
          r.overdueBills,
          r.overdue,
          r.open,
          r.creditLimit,
          r.lastPayment?.value ?? 'Never',
        ], link: ReportLink.party(r.partyId, label: r.name)),
      ReportRow([
        'Total',
        null,
        null,
        null,
        null,
        owing.fold<int>(0, (n, r) => n + r.overdueBills),
        overdue,
        open,
        null,
        null,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('Defaulters', owing.length),
      ReportFigure('Overdue', overdue),
    ],
    notes: const [_defaulterNote],
  );
}

const _defaulterNote =
    'A bill or charge is due its credit days after its date: the khata\'s '
    'own, or $defaultCreditDays where it sets none. An opening balance has '
    'no date to fall due from and is not counted as overdue.';

/// The whole days from [from] to [to], counted on the calendar.
int calendarDays(BusinessDate from, BusinessDate to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

String _periodBills(ReportPeriod period, BusinessDate today) =>
    'Bills dated ${period.label} that were not paid in full at the '
    'counter; overdue is as of ${today.value}.';
