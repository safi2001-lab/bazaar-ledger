/// The staff book's reports (M65): the month's register in totals, the
/// salary register, and what each man still owes of his advances; and the
/// salary slip itself as a table, so it goes out as a PDF through the same
/// export every report does, Urdu names and all.
///
/// Kept here, out of `ReportEngine._build` and the other groups' files, so
/// the engine carries them as one case and the reports other milestones add
/// touch different lines.
library;

import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';
import 'report_engine.dart';
import 'report_table.dart';

/// Where the staff book's reports read from.
abstract interface class StaffBookReportSource {
  /// Everybody on the books but those in the recycle bin.
  Future<List<Employee>> staffEmployees(String firmId);

  /// Every mark in [period]: by man, then by day.
  Future<Map<String, Map<String, AttendanceMark>>> staffMarks(
    String firmId,
    ReportPeriod period,
  );

  /// Every slip for a month that falls in [period], cancelled ones too.
  Future<List<SalarySlip>> salarySlips(String firmId, ReportPeriod period);

  /// What each man has taken in advances and given back.
  Future<List<AdvanceBalance>> staffAdvanceBalances(String firmId);
}

/// The reports this file builds.
const staffBookReportKinds = {
  ReportKind.staffAttendance,
  ReportKind.salaryRegister,
  ReportKind.staffAdvances,
};

/// Builds [kind], one of [staffBookReportKinds].
Future<ReportTable> buildStaffBookReport(
  ReportKind kind, {
  required StaffBookReportSource source,
  required String firmId,
  required ReportPeriod period,
  required BusinessDate today,
  required ReportFilters filters,
}) async => switch (kind) {
  ReportKind.staffAttendance => staffAttendanceReport(
    period,
    today,
    await source.staffEmployees(firmId),
    await source.staffMarks(firmId, period),
  ),
  ReportKind.salaryRegister => salaryRegisterReport(
    period,
    await source.salarySlips(firmId, period),
  ),
  ReportKind.staffAdvances => staffAdvancesReport(
    today,
    await source.staffAdvanceBalances(firmId),
  ),
  _ => throw ArgumentError.value(kind, 'kind', 'is not an M65 report'),
};

String _kaam(EmployeeKaam k) => switch (k) {
  EmployeeKaam.salesman => 'Salesman',
  EmployeeKaam.helper => 'Helper',
  EmployeeKaam.rider => 'Rider',
  EmployeeKaam.munshi => 'Munshi',
  EmployeeKaam.other => 'Other',
};

/// Each man's register over [period] in totals: the days he came, came
/// late, came for half the day, was away paid or unpaid, did not come, and
/// the days nobody marked.
ReportTable staffAttendanceReport(
  ReportPeriod period,
  BusinessDate today,
  List<Employee> people,
  Map<String, Map<String, AttendanceMark>> marks,
) {
  final rows = <(Employee, MonthTally)>[
    for (final e in people)
      (
        e,
        tallyMarks(
          employee: e.onRoster,
          from: period.from,
          to: period.to,
          marks: marks[e.id] ?? const {},
          today: today,
        ),
      ),
  ].where((r) => r.$2.employedDays > 0).toList();
  int sum(int Function(MonthTally t) f) =>
      rows.fold(0, (total, r) => total + f(r.$2));
  return ReportTable(
    id: 'staff_attendance',
    title: 'Attendance summary',
    period: period,
    columns: const [
      ReportColumn('Employee', CellKind.text),
      ReportColumn('Work', CellKind.text),
      ReportColumn('Present', CellKind.count),
      ReportColumn('Late', CellKind.count),
      ReportColumn('Half day', CellKind.count),
      ReportColumn('Paid leave', CellKind.count),
      ReportColumn('Unpaid leave', CellKind.count),
      ReportColumn('Absent', CellKind.count),
      ReportColumn('Not marked', CellKind.count),
    ],
    rows: [
      for (final (e, t) in rows)
        ReportRow([
          e.name,
          _kaam(e.kaam),
          t.present,
          t.late,
          t.halfDay,
          t.paidLeave,
          t.unpaidLeave,
          t.absent,
          t.unmarked,
        ]),
      if (rows.isNotEmpty)
        ReportRow([
          'Total',
          null,
          sum((t) => t.present),
          sum((t) => t.late),
          sum((t) => t.halfDay),
          sum((t) => t.paidLeave),
          sum((t) => t.unpaidLeave),
          sum((t) => t.absent),
          sum((t) => t.unmarked),
        ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('People', rows.length),
      ReportFigure.count('Days absent', sum((t) => t.absent)),
      ReportFigure.count('Days late', sum((t) => t.late)),
    ],
    notes: const [_attendanceNote],
  );
}

/// Every slip for a month in [period]: what the month came to, what was cut,
/// what came off his advance, and what he was handed. Cancelled slips are
/// listed, marked, and left out of the totals.
ReportTable salaryRegisterReport(ReportPeriod period, List<SalarySlip> slips) {
  final standing = [
    for (final s in slips)
      if (!s.cancelled) s,
  ];
  Money total(Money Function(SalaryFigures f) pick) =>
      Money.sum([for (final s in standing) pick(s.figures)]);
  return ReportTable(
    id: 'salary_register',
    title: 'Salary register',
    period: period,
    columns: const [
      ReportColumn('Employee', CellKind.text),
      ReportColumn('Month', CellKind.text),
      ReportColumn('Slip', CellKind.text),
      ReportColumn('Paid on', CellKind.text),
      ReportColumn('Days paid', CellKind.text),
      ReportColumn('Base pay', CellKind.money),
      ReportColumn('Bonus and overtime', CellKind.money),
      ReportColumn('Gross', CellKind.money),
      ReportColumn('Deductions', CellKind.money),
      ReportColumn('Advance taken back', CellKind.money),
      ReportColumn('Paid', CellKind.money),
    ],
    rows: [
      for (final s in slips)
        ReportRow([
          s.employeeName,
          s.month.code,
          s.cancelled ? '${s.slipNo} (cancelled)' : s.slipNo,
          s.paidOn.value,
          s.paidDaysPlain,
          s.figures.basePay,
          s.figures.additions,
          s.figures.gross,
          s.figures.deductions,
          s.figures.recovered,
          s.figures.net,
        ]),
      if (standing.isNotEmpty)
        ReportRow([
          'Total',
          null,
          null,
          null,
          null,
          total((f) => f.basePay),
          total((f) => f.additions),
          total((f) => f.gross),
          total((f) => f.deductions),
          total((f) => f.recovered),
          total((f) => f.net),
        ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Wages', total((f) => f.earned)),
      ReportFigure('Paid in hand', total((f) => f.net)),
      ReportFigure('Advances taken back', total((f) => f.recovered)),
    ],
    notes: const [_registerNote],
  );
}

/// What each man has taken in advances, given back off his wages, and
/// still owes, as of [today]; those who owe most first.
ReportTable staffAdvancesReport(
  BusinessDate today,
  List<AdvanceBalance> balances,
) {
  final owing = [
    for (final b in balances)
      if (!b.owed.isZero) b,
  ];
  return ReportTable(
    id: 'staff_advances',
    title: 'Advances outstanding',
    period: ReportPeriod.day(today),
    columns: const [
      ReportColumn('Employee', CellKind.text),
      ReportColumn('Work', CellKind.text),
      ReportColumn('Given', CellKind.money),
      ReportColumn('Taken back', CellKind.money),
      ReportColumn('Still owed', CellKind.money),
    ],
    rows: [
      for (final b in owing)
        ReportRow([
          b.employee.name,
          _kaam(b.employee.kaam),
          b.given,
          b.recovered,
          b.owed,
        ]),
      if (owing.isNotEmpty)
        ReportRow([
          'Total',
          null,
          Money.sum([for (final b in owing) b.given]),
          Money.sum([for (final b in owing) b.recovered]),
          Money.sum([for (final b in owing) b.owed]),
        ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure.count('People owing', owing.length),
      ReportFigure('Still owed', Money.sum([for (final b in owing) b.owed])),
    ],
    notes: const [_advancesNote],
  );
}

/// The slip in a man's hand, as a table: the month's days, how the wages
/// were worked out, and what he was given.
///
/// English labels, as every report's are; his name in whatever script it
/// was written in, which the PDF export sets right to left with the Urdu
/// face it carries (M30).
ReportTable salarySlipTable(SalarySlip slip) {
  final t = slip.tally;
  final rule = switch ((slip.basis, slip.dayRule)) {
    (PayBasis.daily, _) => 'Rs ${slip.rate.amountOnly} a day',
    (PayBasis.monthly, DayRule.calendar) =>
      'Rs ${slip.rate.amountOnly} a month, a day is 1/${slip.basisDays}',
    (PayBasis.monthly, _) =>
      'Rs ${slip.rate.amountOnly} a month, a day is 1/30',
  };
  return ReportTable(
    id: 'salary_slip',
    title: 'Salary slip ${slip.slipNo}${slip.cancelled ? ' (cancelled)' : ''}',
    period: ReportPeriod(slip.month.first, slip.month.last),
    columns: const [
      ReportColumn('', CellKind.text),
      ReportColumn('Days', CellKind.text),
      ReportColumn('Rs', CellKind.money),
    ],
    rows: [
      ReportRow(['Employee', slip.employeeName, null]),
      ReportRow(['Month', slip.month.code, null]),
      ReportRow(['Pay', rule, null]),
      ReportRow(['On the payroll', '${t.employedDays}', null]),
      ReportRow(['Present', '${t.present}', null]),
      if (t.late > 0) ReportRow(['Late', '${t.late}', null]),
      if (t.halfDay > 0) ReportRow(['Half day', '${t.halfDay}', null]),
      if (t.paidLeave > 0) ReportRow(['Paid leave', '${t.paidLeave}', null]),
      if (t.unpaidLeave > 0)
        ReportRow(['Unpaid leave', '${t.unpaidLeave}', null]),
      if (t.absent > 0) ReportRow(['Absent', '${t.absent}', null]),
      if (t.unmarked > 0) ReportRow(['Not marked', '${t.unmarked}', null]),
      ReportRow([
        'Base pay',
        slip.paidDaysPlain,
        slip.figures.basePay,
      ], style: RowStyle.subtotal),
      for (final l in slip.lines)
        ReportRow([
          l.label,
          switch (l.kind) {
            SalaryLineKind.bonus => 'Bonus',
            SalaryLineKind.overtime => 'Overtime',
            SalaryLineKind.deduction => 'Deduction',
          },
          l.kind.adds ? l.amount : -l.amount,
        ]),
      ReportRow(['Gross', null, slip.figures.gross]),
      if (slip.figures.deductions.isPositive)
        ReportRow(['Deductions', null, -slip.figures.deductions]),
      if (slip.figures.recovered.isPositive)
        ReportRow(['Advance taken back', null, -slip.figures.recovered]),
      ReportRow([
        'Paid',
        slip.paidOn.value,
        slip.figures.net,
      ], style: RowStyle.total),
    ],
    notes: [_paidNote(slip), if (slip.cancelled) _cancelledNote(slip)],
  );
}

String _paidNote(SalarySlip slip) {
  final from = slip.paymentAccountName;
  final by = slip.paidBy;
  return 'Paid on ${slip.paidOn.value}'
      '${from == null ? '' : ' from $from'}'
      '${by == null ? '' : ' by $by'}.';
}

String _cancelledNote(SalarySlip slip) {
  final by = slip.replacedBySlipNo;
  return 'Cancelled: ${slip.voidReason ?? ''}'
      '${by == null ? '' : ' (put right as $by)'}';
}

const _attendanceNote =
    'A day nobody marked counts as worked for a monthly salary and as not '
    'worked for a daily wage, as the staff book reckons wages. Days before '
    'a man joined or after he left are not counted.';

const _registerNote =
    'Gross is base pay with bonus and overtime. Paid is what was put in '
    'hand after deductions and the advance taken back. Wages, the gross '
    'less deductions, are in the profit and loss under Salaries and Wages.';

const _advancesNote =
    'Advances sit in Staff Advances on the balance sheet until they come '
    'back off wages.';
