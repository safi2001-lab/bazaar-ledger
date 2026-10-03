import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../l10n/app_strings.dart';

/// The staff book's reads, for its screens (M65). Every one is behind the
/// service's own permission; a provider never decides who may see what.

/// Whether whoever is signed in may open the staff book at all: whoever
/// keeps or pays the staff, and a cashier the owner lets mark the register.
final staffBookOpensProvider = FutureProvider.autoDispose<bool>((ref) async {
  ref.watch(refreshTickProvider);
  final services = ref.watch(appServicesProvider);
  final firm = await ref.watch(firmProvider.future);
  if (firm == null) return false;
  final book = services.staffBook;
  return book.mayKeep || book.mayPay || await book.mayMarkRegister();
});

final staffRulesProvider = FutureProvider.autoDispose<StaffRules>((ref) async {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).staffBook.rules();
});

/// Everybody on the books, with what each owes of his advances; nobody for
/// a role that may not see pay.
final employeesProvider =
    FutureProvider.autoDispose<
      ({List<Employee> people, Map<String, Money> owed})
    >((ref) async {
      ref.watch(refreshTickProvider);
      final book = ref.watch(appServicesProvider).staffBook;
      final firm = await ref.watch(firmProvider.future);
      if (firm == null || !book.mayPay) {
        return (people: const <Employee>[], owed: const <String, Money>{});
      }
      return (people: await book.employees(), owed: await book.advancesOwed());
    });

/// One day's register, by `YYYY-MM-DD`.
final registerProvider = FutureProvider.autoDispose
    .family<List<RegisterLine>, String>((ref, day) async {
      ref.watch(refreshTickProvider);
      return ref
          .watch(appServicesProvider)
          .staffBook
          .register(BusinessDate(day));
    });

final employeeProvider = FutureProvider.autoDispose.family<Employee?, String>((
  ref,
  id,
) async {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).staffBook.employee(id);
});

/// One man's month: his marks, his wages as they stand, and the slip that
/// paid them if one has.
typedef EmployeeMonth = ({
  Map<String, AttendanceMark> marks,
  WageWorking working,
  String? paidSlipNo,
});

final employeeMonthProvider = FutureProvider.autoDispose
    .family<EmployeeMonth, ({String id, String month})>((ref, key) async {
      ref.watch(refreshTickProvider);
      final book = ref.watch(appServicesProvider).staffBook;
      final month = SalaryMonth.tryParse(key.month)!;
      return (
        marks: await book.marks(key.id, month),
        working: await book.working(key.id, month),
        paidSlipNo: await book.paidAlready(key.id, month),
      );
    });

final advanceLinesProvider = FutureProvider.autoDispose
    .family<List<AdvanceLine>, String>((ref, id) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).staffBook.advanceLines(id);
    });

final slipsProvider = FutureProvider.autoDispose
    .family<List<SalarySlip>, String>((ref, id) async {
      ref.watch(refreshTickProvider);
      return ref.watch(appServicesProvider).staffBook.slips(id);
    });

final slipProvider = FutureProvider.autoDispose.family<SalarySlip?, String>((
  ref,
  id,
) async {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).staffBook.slip(id);
});

// ---------------------------------------------------------------------------
// Words
// ---------------------------------------------------------------------------

String kaamName(AppStrings s, EmployeeKaam kaam) => switch (kaam) {
  EmployeeKaam.salesman => s.staffKaamSalesman,
  EmployeeKaam.helper => s.staffKaamHelper,
  EmployeeKaam.rider => s.staffKaamRider,
  EmployeeKaam.munshi => s.staffKaamMunshi,
  EmployeeKaam.other => s.staffKaamOther,
};

String markName(AppStrings s, AttendanceMark mark) => switch (mark) {
  AttendanceMark.present => s.staffMarkPresent,
  AttendanceMark.late => s.staffMarkLate,
  AttendanceMark.halfDay => s.staffMarkHalfDay,
  AttendanceMark.paidLeave => s.staffMarkPaidLeave,
  AttendanceMark.unpaidLeave => s.staffMarkUnpaidLeave,
  AttendanceMark.absent => s.staffMarkAbsent,
};

/// The one or two letters a day of the month grid shows.
String markShort(AppStrings s, AttendanceMark mark) => switch (mark) {
  AttendanceMark.present => s.staffMarkShortPresent,
  AttendanceMark.late => s.staffMarkShortLate,
  AttendanceMark.halfDay => '½',
  AttendanceMark.paidLeave => s.staffMarkShortPaidLeave,
  AttendanceMark.unpaidLeave => s.staffMarkShortUnpaidLeave,
  AttendanceMark.absent => s.staffMarkShortAbsent,
};

/// "Mahana Rs 25,000.00", "Dihari Rs 1,200.00".
String payText(AppStrings s, PayBasis basis, Money rate) => switch (basis) {
  PayBasis.monthly => s.staffPayMonthly(rate.amountOnly),
  PayBasis.daily => s.staffPayDaily(rate.amountOnly),
};

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// "Oct 2026", as the bill dates read.
String monthLabel(SalaryMonth month) =>
    '${_months[month.month - 1]} ${month.year}';

/// What went wrong, in the words the books refused it in.
String staffError(AppStrings s, Object error) => switch (error) {
  StaffRefused(:final reason) => reason,
  PermissionDenied(:final reason) => reason,
  ApprovalNeeded() => '$error',
  _ => '${s.commonSomethingWentWrong}: $error',
};
