/// The staff book (M65): who works in the shop, who came today, what each
/// has taken against his wages, and what he was paid.
///
/// Every shop this is built for keeps a register of its people beside the
/// khata, and DigiKhata sells it as its Staff Book: attendance, salary,
/// advance. The people in it are not the app's users. The boy who carries
/// the sacks never touches the phone and is on the payroll all the same;
/// the cashier who signs in every morning (M9) is paid too, and may be
/// linked to his sign-in, but the link is a convenience, never a condition.
///
/// ## Where the money lives
///
/// In the ledger, as every rupee in this app does. An advance (peshgi) is an
/// entry: Dr Staff Advances, an asset, Cr the drawer or the bank. A month's
/// wages are an entry: Dr Salaries and Wages, the expense the chart has
/// carried since M0, Cr Staff Advances for what came off his advance, Cr
/// the drawer or the bank for what was put in his hand. Every line of both
/// carries `staff:<employee id>` in `journal_lines.cost_centre`, as M48's
/// loans carry `loan:<account id>`, so what one man owes the shop is that
/// tag's balance on Staff Advances and the staff book cannot disagree with
/// the balance sheet.
///
/// ## Who may do what
///
/// The owner and the manager keep the staff book: they add people, set
/// what each is paid, and mark who has left. The accountant sees what each
/// is paid, gives advances and pays wages, as he pays every other bill.
/// What anybody is paid is seen by those three and nobody else. A cashier
/// may mark the day's register only when the owner has said he may, and
/// then sees names and nothing more.
library;

import 'package:pk_money/pk_money.dart';

import '../mobile/imei.dart' show cnicDigits, cnicWellFormed;
import '../time/clock.dart';

/// What every line of an employee's entries carries in `cost_centre`.
///
/// The column is shared since M47, each feature behind its own prefix;
/// `shop_money/tags.dart` lists them all.
String staffTag(String employeeId) => 'staff:$employeeId';

/// The account an advance sits in until it comes back off his wages.
const staffAdvancesKey = 'staff_advances';

/// The expense a month's wages are posted to: the chart's own since M0.
const salariesKey = 'salaries';

/// The shop's rule for a monthly salary's day, `thirty` or `calendar`.
const staffDayRuleSetting = 'staff.day_rule';

/// `1` when the owner lets a cashier mark the day's register.
const staffCashierAttendanceSetting = 'staff.cashier_attendance';

// The audit codes the staff book writes. The ones that undo something are
// in Data Lock's list (M42, `book_locks.dart`), and hiding an employee is
// in the recycle bin's (M60, `hidden_things.dart`).
const employeeAddedAction = 'EMPLOYEE_ADDED';
const employeeEditedAction = 'EMPLOYEE_EDITED';
const employeeHiddenAction = 'EMPLOYEE_HIDDEN';
const employeeRestoredAction = 'EMPLOYEE_RESTORED';
const attendanceMarkedAction = 'ATTENDANCE_MARKED';
const staffAdvanceGivenAction = 'STAFF_ADVANCE_GIVEN';
const staffAdvanceCancelledAction = 'STAFF_ADVANCE_CANCELLED';
const salaryPaidAction = 'SALARY_PAID';
const salaryCancelledAction = 'SALARY_CANCELLED';
const salaryCorrectedAction = 'SALARY_CORRECTED';
const staffRulesSetAction = 'STAFF_RULES_SET';

/// The register row for [employeeId] on [day]: one per man per day, so two
/// counters marking him while apart write one row and the merge keeps the
/// later mark.
String attendanceRowId(String employeeId, BusinessDate day) =>
    'att-$employeeId-${day.value}';

/// Why something in the staff book was refused, in words.
final class StaffRefused implements Exception {
  const StaffRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// What a man does in the shop.
enum EmployeeKaam {
  salesman,
  helper,
  rider,
  munshi,
  other;

  /// As the schema's `kaam` column holds it.
  String get code => name;

  static EmployeeKaam parse(String code) => values.firstWhere(
    (k) => k.code == code,
    orElse: () => EmployeeKaam.other,
  );
}

/// How a man is paid.
enum PayBasis {
  /// A salary for the month, cut for the days he was away unpaid.
  monthly,

  /// A wage for each day he came; a half day is half of it.
  daily;

  String get code => name;

  static PayBasis parse(String code) =>
      code == 'daily' ? PayBasis.daily : PayBasis.monthly;
}

/// One day of the register.
enum AttendanceMark {
  present('present'),

  /// Came, late. Paid as present; counted so the owner can see it.
  late('late'),

  /// Half a day's pay.
  halfDay('half_day'),

  /// Away, paid all the same.
  paidLeave('paid_leave'),

  /// Away, and not paid for it.
  unpaidLeave('unpaid_leave'),

  /// Did not come, and did not say. Not paid.
  absent('absent');

  const AttendanceMark(this.code);

  /// As the schema's `mark` column holds it.
  final String code;

  static AttendanceMark? parse(String code) {
    for (final m in values) {
      if (m.code == code) return m;
    }
    return null;
  }
}

/// What a monthly salary is divided by to give one day's pay.
///
/// Both are how Pakistani shops reckon it, and the shop says which in the
/// staff book's rules; neither is guessed for it.
enum DayRule {
  /// A day is a thirtieth of the month's salary in every month, February
  /// and the 31-day months alike, as most shops and the labour courts
  /// reckon it. A month with no day away is the full salary.
  thirtyDay('thirty'),

  /// A day is the month's salary over that month's own days: a 28th in
  /// February, a 31st in October.
  calendar('calendar');

  const DayRule(this.code);

  final String code;

  static DayRule parse(String? code) =>
      code == 'calendar' ? DayRule.calendar : DayRule.thirtyDay;
}

/// A month of the calendar, `2026-10`.
extension type const SalaryMonth._(String code) implements Object {
  factory SalaryMonth(int year, int month) => SalaryMonth._(
    '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}',
  );

  /// The month [day] falls in.
  factory SalaryMonth.of(BusinessDate day) => SalaryMonth(day.year, day.month);

  /// Parses `YYYY-MM`, or null.
  static SalaryMonth? tryParse(String input) {
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(input)) return null;
    final month = int.parse(input.substring(5, 7));
    if (month < 1 || month > 12) return null;
    return SalaryMonth._(input);
  }

  int get year => int.parse(code.substring(0, 4));
  int get month => int.parse(code.substring(5, 7));

  /// How many days it has: 28 to 31.
  int get days => DateTime.utc(year, month + 1, 0).day;

  BusinessDate get first => BusinessDate('$code-01');
  BusinessDate get last =>
      BusinessDate('$code-${days.toString().padLeft(2, '0')}');

  SalaryMonth get previous =>
      month == 1 ? SalaryMonth(year - 1, 12) : SalaryMonth(year, month - 1);
  SalaryMonth get next =>
      month == 12 ? SalaryMonth(year + 1, 1) : SalaryMonth(year, month + 1);

  /// Every day of it, first to last.
  List<BusinessDate> get everyDay => [
    for (var d = 1; d <= days; d++)
      BusinessDate('$code-${d.toString().padLeft(2, '0')}'),
  ];

  bool contains(BusinessDate day) => day.value.startsWith('$code-');

  /// Whether it comes after [other].
  bool isAfter(SalaryMonth other) => code.compareTo(other.code) > 0;
}

/// Somebody the shop is about to add, or the same with his details changed.
final class EmployeeDraft {
  const EmployeeDraft({
    required this.name,
    required this.basis,
    required this.rate,
    required this.joinedOn,
    this.kaam = EmployeeKaam.helper,
    this.phone,
    this.cnic,
    this.userId,
    this.leftOn,
    this.note,
  });

  final String name;
  final PayBasis basis;

  /// The month's salary, or the day's wage.
  final Money rate;
  final BusinessDate joinedOn;
  final EmployeeKaam kaam;
  final String? phone;

  /// As typed: with or without its dashes, or empty.
  final String? cnic;

  /// His own sign-in, when he has one.
  final String? userId;

  /// The last day he worked, when he has left.
  final BusinessDate? leftOn;
  final String? note;

  /// The CNIC as the books keep it, or null when none was given.
  String? get cnicKept {
    final raw = cnic?.trim() ?? '';
    return raw.isEmpty ? null : cnicDigits(raw);
  }
}

/// Refuses an employee who cannot be right, before anything is written.
void checkEmployeeDraft(EmployeeDraft draft, {required BusinessDate today}) {
  if (draft.name.trim().isEmpty) {
    throw const StaffRefused('Write his name: a register needs a name.');
  }
  if (!draft.rate.isPositive) {
    throw StaffRefused(
      draft.basis == PayBasis.monthly
          ? 'Write his monthly salary.'
          : "Write his day's wage.",
    );
  }
  final cnic = draft.cnic?.trim() ?? '';
  if (cnic.isNotEmpty && !cnicWellFormed(cnic)) {
    throw const StaffRefused(
      'A CNIC is 13 digits, like 35202-1234567-1. Leave it empty if you '
      'do not have it.',
    );
  }
  if (draft.joinedOn.value.compareTo(today.value) > 0) {
    throw const StaffRefused(
      'He has not joined yet. Add him on the day he starts.',
    );
  }
  final left = draft.leftOn;
  if (left != null && left.value.compareTo(draft.joinedOn.value) < 0) {
    throw const StaffRefused('He cannot have left before he joined.');
  }
}

/// Somebody the shop pays, as the staff book shows him to whoever may see
/// what he is paid.
final class Employee {
  const Employee({
    required this.id,
    required this.name,
    required this.kaam,
    required this.basis,
    required this.rate,
    required this.joinedOn,
    this.phone,
    this.cnic,
    this.leftOn,
    this.userId,
    this.userName,
    this.hidden = false,
    this.note,
  });

  final String id;
  final String name;
  final EmployeeKaam kaam;
  final PayBasis basis;
  final Money rate;
  final BusinessDate joinedOn;
  final String? phone;

  /// Thirteen digits, or null.
  final String? cnic;
  final BusinessDate? leftOn;
  final String? userId;

  /// The name he signs in under, when he is linked to a sign-in.
  final String? userName;
  final bool hidden;
  final String? note;

  /// Whether he was on the payroll on [day].
  bool worksOn(BusinessDate day) =>
      joinedOn.value.compareTo(day.value) <= 0 &&
      (leftOn == null || day.value.compareTo(leftOn!.value) <= 0);

  /// Whether he has left by [today].
  bool hasLeftBy(BusinessDate today) =>
      leftOn != null && leftOn!.value.compareTo(today.value) < 0;

  /// The register's view of him: no pay.
  RosterEntry get onRoster => RosterEntry(
    id: id,
    name: name,
    kaam: kaam,
    joinedOn: joinedOn,
    leftOn: leftOn,
  );
}

/// A man on the day's register, as a cashier marking it may see him: his
/// name and his work, never his pay.
final class RosterEntry {
  const RosterEntry({
    required this.id,
    required this.name,
    required this.kaam,
    required this.joinedOn,
    this.leftOn,
  });

  final String id;
  final String name;
  final EmployeeKaam kaam;
  final BusinessDate joinedOn;
  final BusinessDate? leftOn;

  bool worksOn(BusinessDate day) =>
      joinedOn.value.compareTo(day.value) <= 0 &&
      (leftOn == null || day.value.compareTo(leftOn!.value) <= 0);
}

/// One man's line on one day's register.
final class RegisterLine {
  const RegisterLine({required this.employee, this.mark, this.markedBy});

  final RosterEntry employee;

  /// Null when nobody has marked him that day.
  final AttendanceMark? mark;

  /// Who marked him, by name.
  final String? markedBy;
}

/// The staff book's two rules, as the shop has set them.
final class StaffRules {
  const StaffRules({
    this.dayRule = DayRule.thirtyDay,
    this.cashierMarksAttendance = false,
  });

  final DayRule dayRule;
  final bool cashierMarksAttendance;
}
