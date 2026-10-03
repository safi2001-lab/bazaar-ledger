part of '../drift_report_source.dart';

/// The reads behind the staff book's reports (M65): the register, the
/// slips and the advances. The staff book's own reads, so a report and the
/// screen that shows the same man cannot disagree.
mixin _StaffBookQueries implements StaffBookReportSource {
  AppDatabase get _db;

  @override
  Future<List<Employee>> staffEmployees(String firmId) =>
      DriftStaffBookReads(_db).employees(firmId);

  @override
  Future<Map<String, Map<String, AttendanceMark>>> staffMarks(
    String firmId,
    ReportPeriod period,
  ) => DriftStaffBookReads(_db).marksBetween(firmId, period.from, period.to);

  @override
  Future<List<SalarySlip>> salarySlips(String firmId, ReportPeriod period) =>
      DriftStaffBookReads(_db).slips(
        firmId,
        fromMonth: SalaryMonth.of(period.from),
        toMonth: SalaryMonth.of(period.to),
      );

  @override
  Future<List<AdvanceBalance>> staffAdvanceBalances(String firmId) =>
      DriftStaffBookReads(_db).advanceBalances(firmId);
}
