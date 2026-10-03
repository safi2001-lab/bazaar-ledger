/// A month's wages worked out from the register, an advance against them,
/// and the entries both post (M65).
///
/// ## The rule, said once
///
/// A **monthly** man is paid his salary for the month, less a day's pay for
/// each day he was away unpaid: absent, or on unpaid leave, a half day
/// counting half. A day's pay is the salary over 30 under the 30-day rule,
/// or over the month's own days under the calendar rule; the shop says
/// which. A man who joined or left inside the month is paid for the days he
/// was on the payroll, at the same day's pay (never more than the whole
/// month). A day nobody marked is a day he worked: the shop marks the days
/// that differ, and a month left unmarked is the full salary — the screen
/// says how many there were before it is paid.
///
/// A **daily** man is paid his wage for each day he came: present, late, or
/// on paid leave a whole day, a half day half. A day nobody marked is a day
/// he did not come, because a daily wage is for the days worked and nothing
/// else.
///
/// Base pay is rounded to the whole rupee, half up, because it is counted
/// out of the drawer. Bonus and overtime are added and cuts taken off as the
/// shopkeeper types them; then as much of his advance as the shopkeeper
/// chooses to take back, never more than he owes or than the month earned.
/// What is left is put in his hand.
library;

import 'package:pk_money/pk_money.dart';

import '../sales/sale_posting.dart'
    show JournalEntryPosting, JournalLinePosting;
import '../time/clock.dart';
import 'staff_book.dart';

/// One man's register over a span: how many days of each kind.
final class MonthTally {
  const MonthTally({
    this.present = 0,
    this.late = 0,
    this.halfDay = 0,
    this.paidLeave = 0,
    this.unpaidLeave = 0,
    this.absent = 0,
    this.unmarked = 0,
    this.toCome = 0,
    this.employedDays = 0,
  });

  final int present;
  final int late;
  final int halfDay;
  final int paidLeave;
  final int unpaidLeave;
  final int absent;

  /// Days gone by that nobody marked.
  final int unmarked;

  /// Days of the span still to come.
  final int toCome;

  /// The days of the span he was on the payroll.
  final int employedDays;

  int get marked => present + late + halfDay + paidLeave + unpaidLeave + absent;
}

/// Counts [marks] (by `YYYY-MM-DD`) from [from] to [to], only the days the
/// man was on the payroll; a day after [today] is still to come.
MonthTally tallyMarks({
  required RosterEntry employee,
  required BusinessDate from,
  required BusinessDate to,
  required Map<String, AttendanceMark> marks,
  required BusinessDate today,
}) {
  var present = 0;
  var late = 0;
  var halfDay = 0;
  var paidLeave = 0;
  var unpaidLeave = 0;
  var absent = 0;
  var unmarked = 0;
  var toCome = 0;
  var employed = 0;
  for (final day in daysFrom(from, to)) {
    if (!employee.worksOn(day)) continue;
    employed++;
    switch (marks[day.value]) {
      case AttendanceMark.present:
        present++;
      case AttendanceMark.late:
        late++;
      case AttendanceMark.halfDay:
        halfDay++;
      case AttendanceMark.paidLeave:
        paidLeave++;
      case AttendanceMark.unpaidLeave:
        unpaidLeave++;
      case AttendanceMark.absent:
        absent++;
      case null:
        if (day.value.compareTo(today.value) > 0) {
          toCome++;
        } else {
          unmarked++;
        }
    }
  }
  return MonthTally(
    present: present,
    late: late,
    halfDay: halfDay,
    paidLeave: paidLeave,
    unpaidLeave: unpaidLeave,
    absent: absent,
    unmarked: unmarked,
    toCome: toCome,
    employedDays: employed,
  );
}

/// Every day from [from] to [to], both included.
List<BusinessDate> daysFrom(BusinessDate from, BusinessDate to) {
  final days = <BusinessDate>[];
  var d = DateTime.utc(from.year, from.month, from.day);
  final end = DateTime.utc(to.year, to.month, to.day);
  while (!d.isAfter(end)) {
    days.add(BusinessDate.fromUtc(d, Duration.zero));
    d = d.add(const Duration(days: 1));
  }
  return days;
}

/// A month's wages for one man, worked out from the register by the rule
/// at the top of this file, before any bonus, cut or advance.
final class WageWorking {
  const WageWorking({
    required this.month,
    required this.basis,
    required this.rate,
    required this.dayRule,
    required this.basisDays,
    required this.tally,
    required this.paidHalves,
    required this.basePay,
  });

  final SalaryMonth month;
  final PayBasis basis;

  /// The salary or the day's wage it was worked out on.
  final Money rate;

  /// The rule a monthly salary was divided by; null for a daily wage.
  final DayRule? dayRule;

  /// 30, or the month's own days.
  final int basisDays;
  final MonthTally tally;

  /// The days paid for, in half days.
  final int paidHalves;

  /// Rounded to the whole rupee.
  final Money basePay;

  /// The days paid for, as a shopkeeper writes it: `27`, `26½`.
  String get paidDaysText =>
      paidHalves.isEven ? '${paidHalves ~/ 2}' : '${paidHalves ~/ 2}½';

  /// The same in plain figures, `26.5`, for paper whose face may not carry
  /// the half sign.
  String get paidDaysPlain =>
      paidHalves.isEven ? '${paidHalves ~/ 2}' : '${paidHalves ~/ 2}.5';

  /// The days away unpaid, in half days.
  int get unpaidHalves =>
      2 * (tally.absent + tally.unpaidLeave) + tally.halfDay;
}

/// Works out [employee]'s base pay for [month] from [marks] under [rule].
WageWorking workWages({
  required Employee employee,
  required SalaryMonth month,
  required Map<String, AttendanceMark> marks,
  required DayRule rule,
  required BusinessDate today,
}) {
  final tally = tallyMarks(
    employee: employee.onRoster,
    from: month.first,
    to: month.last,
    marks: marks,
    today: today,
  );
  switch (employee.basis) {
    case PayBasis.monthly:
      final basisDays = rule == DayRule.thirtyDay ? 30 : month.days;
      // A whole month on the payroll is the whole salary, whatever the
      // month's length; part of one is its days at a day's pay, never more
      // than the whole.
      final onPayroll = tally.employedDays == month.days
          ? basisDays
          : (tally.employedDays < basisDays ? tally.employedDays : basisDays);
      final unpaid = 2 * (tally.absent + tally.unpaidLeave) + tally.halfDay;
      final paid = onPayroll * 2 - unpaid;
      final paidHalves = paid < 0 ? 0 : paid;
      return WageWorking(
        month: month,
        basis: PayBasis.monthly,
        rate: employee.rate,
        dayRule: rule,
        basisDays: basisDays,
        tally: tally,
        paidHalves: paidHalves,
        basePay: _rupees(employee.rate.inPaisa * paidHalves, basisDays * 2),
      );
    case PayBasis.daily:
      final paidHalves =
          2 * (tally.present + tally.late + tally.paidLeave) + tally.halfDay;
      return WageWorking(
        month: month,
        basis: PayBasis.daily,
        rate: employee.rate,
        dayRule: null,
        basisDays: month.days,
        tally: tally,
        paidHalves: paidHalves,
        basePay: _rupees(employee.rate.inPaisa * paidHalves, 2),
      );
  }
}

/// [numerator] paisa over [denominator], to the nearest whole rupee.
Money _rupees(int numerator, int denominator) => Money.paisa(
  divideRounded(numerator, denominator * 100, RoundingMode.halfUp) * 100,
);

/// A bonus, overtime, or a cut.
enum SalaryLineKind {
  bonus,
  overtime,
  deduction;

  String get code => name;

  bool get adds => this != SalaryLineKind.deduction;

  static SalaryLineKind parse(String code) => values.firstWhere(
    (k) => k.code == code,
    orElse: () => SalaryLineKind.bonus,
  );
}

/// One bonus, overtime or cut on a slip.
final class SalaryLine {
  const SalaryLine({
    required this.kind,
    required this.label,
    required this.amount,
  });

  final SalaryLineKind kind;

  /// "Eid bonus", "Sunday overtime", "Broken glass".
  final String label;
  final Money amount;
}

/// A month's wages about to be paid.
final class SalaryDraft {
  const SalaryDraft({
    required this.employeeId,
    required this.month,
    required this.paidOn,
    this.lines = const [],
    this.advanceRecovered = Money.zero,
    this.paymentAccountId,
    this.note,
  });

  final String employeeId;
  final SalaryMonth month;

  /// The day the money is handed over.
  final BusinessDate paidOn;
  final List<SalaryLine> lines;

  /// How much of what he owes comes off this month.
  final Money advanceRecovered;

  /// The drawer or the bank it is paid from. Not needed when the whole of
  /// it goes against his advance.
  final String? paymentAccountId;
  final String? note;
}

/// A slip's figures, worked out and checked.
final class SalaryFigures {
  const SalaryFigures({
    required this.basePay,
    required this.additions,
    required this.deductions,
    required this.recovered,
  });

  final Money basePay;

  /// Bonus and overtime.
  final Money additions;

  /// Cuts.
  final Money deductions;

  /// Taken back off his advance.
  final Money recovered;

  /// Base pay with bonus and overtime: the month's gross.
  Money get gross => basePay + additions;

  /// What the month cost the shop in wages: gross less cuts.
  Money get earned => gross - deductions;

  /// What is put in his hand.
  Money get net => earned - recovered;
}

/// Checks [draft] against [working] and what he owes, and returns the
/// slip's figures; refuses in words what cannot be paid.
SalaryFigures checkSalary({
  required Employee employee,
  required WageWorking working,
  required SalaryDraft draft,
  required Money advanceOwed,
  required BusinessDate today,
}) {
  if (draft.month.isAfter(SalaryMonth.of(today))) {
    throw StaffRefused(
      '${draft.month.code} has not come yet. Wages are paid for a month '
      'that has begun.',
    );
  }
  if (draft.paidOn.value.compareTo(today.value) > 0) {
    throw const StaffRefused('Wages cannot be paid on a day not yet come.');
  }
  if (working.tally.employedDays == 0) {
    throw StaffRefused(
      '${employee.name} was not on the payroll in ${draft.month.code}.',
    );
  }
  for (final line in draft.lines) {
    if (line.label.trim().isEmpty) {
      throw const StaffRefused('Say what each bonus or cut is for.');
    }
    if (!line.amount.isPositive) {
      throw const StaffRefused('A bonus or a cut is more than nothing.');
    }
  }
  final figures = SalaryFigures(
    basePay: working.basePay,
    additions: Money.sum([
      for (final l in draft.lines)
        if (l.kind.adds) l.amount,
    ]),
    deductions: Money.sum([
      for (final l in draft.lines)
        if (!l.kind.adds) l.amount,
    ]),
    recovered: draft.advanceRecovered,
  );
  if (figures.deductions > figures.gross) {
    throw StaffRefused(
      'Cuts of Rs ${figures.deductions.amountOnly} are more than the '
      "month's Rs ${figures.gross.amountOnly}.",
    );
  }
  if (!figures.earned.isPositive) {
    throw const StaffRefused(
      'Nothing is due for this month: no day paid for, and no bonus.',
    );
  }
  if (figures.recovered.isNegative) {
    throw const StaffRefused('An advance taken back is more than nothing.');
  }
  if (figures.recovered > advanceOwed) {
    throw StaffRefused(
      '${employee.name} owes Rs ${advanceOwed.amountOnly} of advances. '
      'No more than that can come off his wages.',
    );
  }
  if (figures.recovered > figures.earned) {
    throw StaffRefused(
      'The month comes to Rs ${figures.earned.amountOnly}; no more than '
      'that can come off his advance this month.',
    );
  }
  if (figures.net.isPositive && draft.paymentAccountId == null) {
    throw const StaffRefused('Pick the cash or the bank it is paid from.');
  }
  return figures;
}

/// The entry that pays a month's wages: Dr Salaries and Wages for what the
/// month earned, Cr Staff Advances for what came off his advance, Cr the
/// drawer or bank for what he was handed. Accounts are already ids.
JournalEntryPosting salaryEntry({
  required SalaryFigures figures,
  required String employeeName,
  required SalaryMonth month,
  required BusinessDate paidOn,
  required String entryNo,
  required int recordedAtUtcMillis,
  required String salariesAccountId,
  required String advancesAccountId,
  String? moneyAccountId,
}) {
  final what = 'Wages, $employeeName, ${month.code}';
  final lines = <JournalLinePosting>[
    JournalLinePosting(
      lineNo: 1,
      accountSystemKey: '#$salariesAccountId',
      debit: figures.earned,
      credit: Money.zero,
      narration: what,
    ),
    if (figures.recovered.isPositive)
      JournalLinePosting(
        lineNo: 2,
        accountSystemKey: '#$advancesAccountId',
        debit: Money.zero,
        credit: figures.recovered,
        narration: 'Advance taken back, $employeeName',
      ),
    if (figures.net.isPositive)
      JournalLinePosting(
        lineNo: figures.recovered.isPositive ? 3 : 2,
        accountSystemKey: '#$moneyAccountId',
        debit: Money.zero,
        credit: figures.net,
        narration: what,
      ),
  ];
  return JournalEntryPosting(
    entryNo: entryNo,
    entryDateUtcMillis: recordedAtUtcMillis,
    entryDateLocal: paidOn.value,
    fiscalYear: paidOn.fiscalYear,
    sourceType: 'manual',
    totalDebit: figures.earned,
    totalCredit: figures.earned,
    narration: what,
    lines: lines,
  );
}

/// An advance (peshgi) about to be given.
final class AdvanceDraft {
  const AdvanceDraft({
    required this.employeeId,
    required this.amount,
    required this.paymentAccountId,
    required this.givenOn,
    this.note,
  });

  final String employeeId;
  final Money amount;
  final String paymentAccountId;
  final BusinessDate givenOn;
  final String? note;
}

/// Refuses an advance that cannot be given.
void checkAdvance(
  AdvanceDraft draft, {
  required Employee employee,
  required BusinessDate today,
}) {
  if (!draft.amount.isPositive) {
    throw const StaffRefused('An advance of nothing is not an advance.');
  }
  if (draft.givenOn.value.compareTo(today.value) > 0) {
    throw const StaffRefused(
      'An advance cannot be given on a day not yet come.',
    );
  }
  if (!employee.worksOn(draft.givenOn)) {
    throw StaffRefused(
      '${employee.name} was not working here on ${draft.givenOn.value}.',
    );
  }
}

/// The entry that gives an advance: Dr Staff Advances, Cr the drawer or
/// the bank.
JournalEntryPosting advanceEntry({
  required AdvanceDraft draft,
  required String employeeName,
  required String entryNo,
  required int recordedAtUtcMillis,
  required String advancesAccountId,
  required String moneyAccountId,
}) {
  final note = draft.note?.trim() ?? '';
  final what = note.isEmpty
      ? 'Advance to $employeeName'
      : 'Advance to $employeeName: $note';
  return JournalEntryPosting(
    entryNo: entryNo,
    entryDateUtcMillis: recordedAtUtcMillis,
    entryDateLocal: draft.givenOn.value,
    fiscalYear: draft.givenOn.fiscalYear,
    sourceType: 'manual',
    totalDebit: draft.amount,
    totalCredit: draft.amount,
    narration: what,
    lines: [
      JournalLinePosting(
        lineNo: 1,
        accountSystemKey: '#$advancesAccountId',
        debit: draft.amount,
        credit: Money.zero,
        narration: what,
      ),
      JournalLinePosting(
        lineNo: 2,
        accountSystemKey: '#$moneyAccountId',
        debit: Money.zero,
        credit: draft.amount,
        narration: what,
      ),
    ],
  );
}

/// What a line of a man's advance account was.
enum AdvanceLineKind {
  /// Money given to him.
  given,

  /// Taken back off his wages.
  recovered,

  /// An advance cancelled as entered by mistake.
  givenCancelled,

  /// A slip cancelled, so what it took back is owed again.
  recoveryCancelled,
}

/// One movement on a man's advance account, oldest first.
final class AdvanceLine {
  const AdvanceLine({
    required this.entryId,
    required this.entryNo,
    required this.on,
    required this.kind,
    required this.amount,
    required this.owedAfter,
    this.narration,
    this.slipId,
    this.cancelled = false,
  });

  final String entryId;
  final String entryNo;
  final BusinessDate on;
  final AdvanceLineKind kind;

  /// Always positive; [kind] says which way.
  final Money amount;

  /// What he owed after it.
  final Money owedAfter;
  final String? narration;

  /// The slip it came off, for [AdvanceLineKind.recovered].
  final String? slipId;

  /// An advance since cancelled by a later entry.
  final bool cancelled;
}

/// What one man has taken and given back.
final class AdvanceBalance {
  const AdvanceBalance({
    required this.employee,
    required this.given,
    required this.recovered,
  });

  final Employee employee;

  /// Every advance, less those cancelled.
  final Money given;

  /// Every rupee taken back off his wages, less slips cancelled.
  final Money recovered;

  Money get owed => given - recovered;
}

/// A month's wages as paid: the slip.
final class SalarySlip {
  const SalarySlip({
    required this.id,
    required this.slipNo,
    required this.employeeId,
    required this.employeeName,
    required this.month,
    required this.paidOn,
    required this.basis,
    required this.rate,
    required this.basisDays,
    required this.tally,
    required this.paidHalves,
    required this.figures,
    required this.entryId,
    required this.entryNo,
    this.dayRule,
    this.employeePhone,
    this.paymentAccountId,
    this.paymentAccountName,
    this.lines = const [],
    this.cancelled = false,
    this.voidReason,
    this.replacesSlipId,
    this.replacedBySlipNo,
    this.note,
    this.paidBy,
  });

  final String id;

  /// `SAL-2627-0001`.
  final String slipNo;
  final String employeeId;
  final String employeeName;
  final String? employeePhone;
  final SalaryMonth month;
  final BusinessDate paidOn;
  final PayBasis basis;
  final Money rate;
  final DayRule? dayRule;
  final int basisDays;
  final MonthTally tally;
  final int paidHalves;
  final SalaryFigures figures;
  final String entryId;
  final String entryNo;
  final String? paymentAccountId;
  final String? paymentAccountName;
  final List<SalaryLine> lines;
  final bool cancelled;
  final String? voidReason;

  /// The slip this one corrected.
  final String? replacesSlipId;

  /// The slip that corrected this one, by number.
  final String? replacedBySlipNo;
  final String? note;

  /// Who paid it, by name.
  final String? paidBy;

  /// The days paid for, as a shopkeeper writes it: `27`, `26½`.
  String get paidDaysText =>
      paidHalves.isEven ? '${paidHalves ~/ 2}' : '${paidHalves ~/ 2}½';

  /// The same in plain figures, `26.5`, for paper whose face may not carry
  /// the half sign.
  String get paidDaysPlain =>
      paidHalves.isEven ? '${paidHalves ~/ 2}' : '${paidHalves ~/ 2}.5';
}
