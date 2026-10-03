part of '../drift_report_source.dart';

/// The reads behind the mobile-shop reports (M50): the used phones bought
/// register and the instalments. The pack's own reads, so the report and
/// the screens that show the same plans cannot disagree.
mixin _MobileQueries implements MobileReportSource {
  AppDatabase get _db;

  @override
  Future<List<UsedPhoneBuy>> usedPhonesBought(
    String firmId,
    ReportPeriod period,
  ) => DriftMobileReads(
    _db,
  ).usedPhonesBought(firmId, from: period.from, to: period.to);

  @override
  Future<List<QistPlan>> qistPlans(String firmId) =>
      DriftMobileReads(_db).qistPlans(firmId);
}
