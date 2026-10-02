import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'loan_reports.dart';
import 'period.dart';
import 'report_engine.dart';
import 'report_source.dart';
import 'report_table.dart';
import 'udhaar_reports.dart';

/// The reports M58 added: money owed both ways. What the shop owes on the
/// loans it has taken (M48), and what customers owe it by the day each bill
/// was due and what it let go of (M38, M44).
///
/// Kept here, out of `ReportEngine._build`, as M35's reports are, so the
/// engine's switch carries them as one case and the groups adding reports
/// beside them in parallel touch different lines of it.
const moneyOwedReportKinds = {
  ReportKind.loanStatement,
  ReportKind.receivablesByDueDate,
  ReportKind.badDebts,
};

/// The M58 kinds that are as of today rather than over a period.
const moneyOwedReportsAsOfToday = {ReportKind.receivablesByDueDate};

/// Builds [kind], one of [moneyOwedReportKinds], from [source].
Future<ReportTable> buildMoneyOwedReport(
  ReportKind kind, {
  required ReportSource source,
  required String firmId,
  required ReportPeriod period,
  required BusinessDate today,
  required ReportFilters filters,
}) async => switch (kind) {
  ReportKind.loanStatement => loanReport(
    source,
    firmId: firmId,
    period: period,
    filters: filters,
  ),
  ReportKind.receivablesByDueDate => receivablesByDueDate(
    today,
    await source.dueAgeing(firmId, today, filters: filters),
  ),
  ReportKind.badDebts => badDebts(period, [
    for (final kind in AllowanceKind.values)
      ...await source.allowances(firmId, period, kind: kind),
  ]),
  _ => throw ArgumentError.value(kind, 'kind', 'is not an M58 report'),
};
