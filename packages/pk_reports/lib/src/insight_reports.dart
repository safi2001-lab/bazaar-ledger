/// The reports an accountant and an owner reach for next (M67): ratio
/// analysis, the attention list, ABC classes, and the ageing reports in
/// the buckets the shop sets.
///
/// Kept here, out of `ReportEngine._build`, as M35's, M58's and M54's
/// reports are, so the engine's switch carries them as one case and the
/// milestones adding reports beside them in parallel touch other lines.
library;

import 'package:pk_domain/pk_domain.dart';

import 'abc_reports.dart';
import 'ageing_buckets.dart';
import 'attention_reports.dart';
import 'filters.dart';
import 'period.dart';
import 'ratio_reports.dart';
import 'report_engine.dart';
import 'report_source.dart';
import 'report_table.dart';

/// What a report is run with beyond its period and filters (M67): the
/// shop's own settings, which are not narrowing and are never printed as
/// a filter, and the moment it is run.
final class ReportOptions {
  const ReportOptions({this.ageing = AgeingBuckets.standard, this.nowUtc});

  /// As the reports were before any setting.
  static const standard = ReportOptions();

  /// Where the ageing reports cut their buckets.
  final AgeingBuckets ageing;

  /// Now, for what turns on the hour rather than the day (an FBR bill's 24
  /// hours); null is the end of the day the report is read for.
  final DateTime? nowUtc;

  @override
  bool operator ==(Object other) =>
      other is ReportOptions &&
      other.ageing == ageing &&
      other.nowUtc == nowUtc;

  @override
  int get hashCode => Object.hash(ageing, nowUtc);
}

/// The reports this file builds: M67's own, and the three ageing reports
/// it now builds in the shop's buckets.
const insightReportKinds = {
  ReportKind.ratioAnalysis,
  ReportKind.needsAttention,
  ReportKind.abcClassification,
  ReportKind.receivables,
  ReportKind.payables,
  ReportKind.receivablesByDueDate,
};

/// The M67 kinds that are as of today rather than over a period.
const insightReportsAsOfToday = {ReportKind.needsAttention};

/// Builds [kind], one of [insightReportKinds], from [source].
Future<ReportTable> buildInsightReport(
  ReportKind kind, {
  required ReportSource source,
  required String firmId,
  required ReportPeriod period,
  required BusinessDate today,
  required ReportFilters filters,
  required ReportOptions options,
  required bool canSeeCosts,
}) async {
  final buckets = options.ageing.isValid
      ? options.ageing
      : AgeingBuckets.standard;
  switch (kind) {
    case ReportKind.ratioAnalysis:
      return buildRatioReport(
        source,
        firmId: firmId,
        period: period,
        today: today,
      );
    case ReportKind.needsAttention:
      final lateDays = filters.lateDays ?? attentionLateDays;
      return needsAttention(
        today,
        await source.exceptions(
          firmId,
          today,
          lateDays: lateDays,
          nowUtc: options.nowUtc ?? _endOf(today),
          withCosts: canSeeCosts,
        ),
        lateDays: lateDays,
      );
    case ReportKind.abcClassification:
      final basis = filters.abcBasis ?? AbcBasis.sales;
      if (basis == AbcBasis.margin && !canSeeCosts) {
        throw const PermissionDenied(
          Permission.seeCosts,
          'Ranking by profit shows what the goods cost, which this role does '
          'not see.',
        );
      }
      final a = (filters.abcA ?? AbcDefaults.a).clamp(1, 99);
      final b = (filters.abcB ?? AbcDefaults.b).clamp(a, 100);
      return abcClassification(
        period,
        await source.itemTrade(firmId, period, filters: filters),
        basis: basis,
        aAt: a,
        bAt: b,
      );
    case ReportKind.receivables:
      return receivablesAged(
        today,
        await source.agedReceivables(firmId, today, buckets),
        buckets,
      );
    case ReportKind.payables:
      return payablesAged(
        today,
        await source.agedPayables(firmId, today, buckets),
        buckets,
      );
    case ReportKind.receivablesByDueDate:
      return receivablesByDueDateIn(
        today,
        await source.dueAgeingIn(firmId, today, buckets, filters: filters),
        buckets,
      );
    default:
      throw ArgumentError.value(kind, 'kind', 'is not an M67 report');
  }
}

/// The last moment of [day] in Pakistan, as an instant.
DateTime _endOf(BusinessDate day) => DateTime.utc(
  day.year,
  day.month,
  day.day,
).add(const Duration(days: 1)).subtract(pakistanStandardTime);
