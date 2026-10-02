import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';
import 'report_table.dart';

/// The udhaar pack's reports in the hub (M58): what customers owe by how
/// late it is against the day it was due (M38), and the udhaar the shop let
/// go, written off or given as a settlement discount (M44).
///
/// Udhaar by age (M8) ages each bill from its date. A wholesaler who gives
/// fifteen days and a household on salary day are not late on the same
/// day, so this one ages each bill from its due date instead: the bill's
/// date plus the customer's credit days, worked out in SQL by the same
/// arithmetic as `dueDateOf`, and bucketed by `DueBucket`. Its buckets add
/// up to the udhaar pack's own `dueAging`, and each customer's owed is the
/// khata's balance, so the total is Udhaar by age's total.

/// What one customer owes, by how late it is against its due date (M58).
final class DueAgeingRow {
  const DueAgeingRow({
    required this.partyId,
    required this.name,
    this.notYetDue = Money.zero,
    this.upTo30 = Money.zero,
    this.upTo60 = Money.zero,
    this.upTo90 = Money.zero,
    this.over90 = Money.zero,
    this.opening = Money.zero,
    this.advance = Money.zero,
  });

  final String partyId;
  final String name;

  /// Open bills inside the customer's terms, the day they fall due
  /// included: [DueBucket.notYetDue].
  final Money notYetDue;

  /// Open bills 1 to 30 days past their due date.
  final Money upTo30;
  final Money upTo60;
  final Money upTo90;

  /// More than ninety days past due: what a write-off is decided from.
  final Money over90;

  /// The balance brought forward when the khata was opened, which has no
  /// bill date and so no due date (M38).
  final Money opening;

  /// Money the shop is holding for them, which comes off what they owe.
  final Money advance;

  /// What is past its due date, in every bucket.
  Money get overdue => upTo30 + upTo60 + upTo90 + over90;

  /// The khata's balance: the same figure Udhaar by age shows them owing.
  Money get owed => opening + notYetDue + overdue - advance;
}

/// Where the udhaar reports read from (M58).
abstract interface class UdhaarReportSource {
  /// Every customer with anything open, their open bills bucketed by days
  /// past due on [asOf]; narrowed by party group.
  Future<List<DueAgeingRow>> dueAgeing(
    String firmId,
    BusinessDate asOf, {
    ReportFilters filters = ReportFilters.none,
  });

  /// Every write-off or settlement discount of [kind] in [period], cancelled
  /// ones included and marked: the udhaar pack's own `allowances` (M44).
  Future<List<AllowanceRow>> allowances(
    String firmId,
    ReportPeriod period, {
    required AllowanceKind kind,
  });
}

/// The bucket columns, in their order: the Udhaar by due date report's,
/// and the slices of its ring (M46).
const dueBucketColumns = [
  'Not yet due',
  '1-30 days late',
  '31-60 days late',
  '61-90 days late',
  'Over 90 days late',
];

/// Who owes the shop, and how late each is against the day it was due, the
/// latest money on the right (M58).
ReportTable receivablesByDueDate(BusinessDate asOf, List<DueAgeingRow> rows) {
  final owing =
      rows
          .where(
            (r) => !r.owed.isZero || !r.notYetDue.isZero || !r.overdue.isZero,
          )
          .toList()
        ..sort((a, b) {
          for (final pair in [
            (a.over90, b.over90),
            (a.upTo90, b.upTo90),
            (a.upTo60, b.upTo60),
            (a.upTo30, b.upTo30),
            (a.owed, b.owed),
          ]) {
            final c = pair.$2.compareTo(pair.$1);
            if (c != 0) return c;
          }
          return a.name.compareTo(b.name);
        });
  Money sum(Money Function(DueAgeingRow r) f) => Money.sum(owing.map(f));
  final anyOpening = owing.any((r) => !r.opening.isZero);
  final anyAdvance = owing.any((r) => !r.advance.isZero);
  final overdue = sum((r) => r.overdue);
  final late = owing.where((r) => r.overdue.isPositive).length;
  return ReportTable(
    id: 'receivables_by_due_date',
    title: 'Udhaar by due date',
    period: ReportPeriod.day(asOf),
    columns: [
      const ReportColumn('Customer', CellKind.text),
      for (final title in dueBucketColumns) ReportColumn(title, CellKind.money),
      const ReportColumn('Opening', CellKind.money),
      const ReportColumn('Advance', CellKind.money),
      const ReportColumn('Owed', CellKind.money),
    ],
    rows: [
      for (final r in owing)
        ReportRow([
          r.name,
          r.notYetDue,
          r.upTo30,
          r.upTo60,
          r.upTo90,
          r.over90,
          r.opening,
          -r.advance,
          r.owed,
        ], link: ReportLink.party(r.partyId, label: r.name)),
      ReportRow([
        'Total',
        sum((r) => r.notYetDue),
        sum((r) => r.upTo30),
        sum((r) => r.upTo60),
        sum((r) => r.upTo90),
        sum((r) => r.over90),
        sum((r) => r.opening),
        -sum((r) => r.advance),
        sum((r) => r.owed),
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Owed', sum((r) => r.owed)),
      ReportFigure('Overdue', overdue),
      ReportFigure.count('Customers late', late),
    ],
    notes: [
      _dueIsTheTerm,
      if (anyOpening) _openingHasNoDueDate,
      if (anyAdvance) _advanceComesOff,
    ],
  );
}

const _dueIsTheTerm =
    "A bill is due its customer's credit days after its date, or thirty "
    'days where none are set; it is late from the day after. Owed is the '
    "khata's balance, and the total is Udhaar by age's.";

const _openingHasNoDueDate =
    'Opening is the balance brought forward when the khata was started: it '
    'has no bill date, so no day it falls due.';

const _advanceComesOff =
    'Advance is money the shop is holding for the customer, and comes off '
    'what they owe.';

/// The udhaar let go in [period] (M58, over M44's allowances): every
/// write-off and settlement discount with who, why, how much and who let it
/// go, oldest first. A cancelled one is listed, marked, and counted nowhere,
/// because the udhaar it let go is owed again.
ReportTable badDebts(ReportPeriod period, List<AllowanceRow> rows) {
  final sorted = rows.toList()
    ..sort((a, b) {
      final byDay = a.dateLocal.compareTo(b.dateLocal);
      return byDay != 0 ? byDay : a.paymentNo.compareTo(b.paymentNo);
    });
  final standing = [
    for (final r in sorted)
      if (!r.cancelled) r,
  ];
  Money of(AllowanceKind kind) => Money.sum([
    for (final r in standing)
      if (r.kind == kind) r.amount,
  ]);
  final writtenOff = of(AllowanceKind.writeOff);
  final discounts = of(AllowanceKind.settlementDiscount);
  final cancelled = sorted.length - standing.length;
  return ReportTable(
    id: 'bad_debts',
    title: 'Bad debts and settlement discounts',
    period: period,
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Number', CellKind.text),
      ReportColumn('What', CellKind.text),
      ReportColumn('Customer', CellKind.text),
      ReportColumn('Why', CellKind.text),
      ReportColumn('Let go by', CellKind.text),
      ReportColumn('Amount', CellKind.money),
      ReportColumn('Status', CellKind.text),
    ],
    rows: [
      for (final r in sorted)
        ReportRow(
          [
            r.dateLocal,
            r.paymentNo,
            r.kind.narration,
            r.partyName,
            r.reason,
            r.byName,
            r.amount,
            r.cancelled ? 'Cancelled, not counted' : '',
          ],
          link: r.partyId.isEmpty
              ? null
              : ReportLink.party(r.partyId, label: r.partyName),
        ),
      ReportRow([
        'Total',
        standing.length == 1 ? '1 entry' : '${standing.length} entries',
        null,
        null,
        null,
        null,
        writtenOff + discounts,
        cancelled == 0 ? null : '$cancelled cancelled',
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Written off', writtenOff),
      ReportFigure('Settlement discounts', discounts),
      ReportFigure('Total let go', writtenOff + discounts),
    ],
    notes: const [_letGoIsAnExpense, _cancelledIsOwedAgain],
  );
}

const _letGoIsAnExpense =
    'A write-off goes to Bad Debts and a settlement discount to Settlement '
    'Discount, both expenses in the profit and loss. Neither moved any money.';

const _cancelledIsOwedAgain =
    'A cancelled one is listed and counted nowhere: the udhaar it let go is '
    'owed again. One cancelled after the period still shows here as '
    'cancelled, though the profit and loss of the period counted it.';
