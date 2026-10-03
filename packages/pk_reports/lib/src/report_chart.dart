import 'package:pk_domain/pk_domain.dart';

import 'period.dart';
import 'report_table.dart';

/// A report drawn rather than listed (M46).
///
/// The market's best-known app has a graph on its sale and expense reports
/// and a pie on sale ageing, and a shopkeeper reads "which day was quiet"
/// off a row of columns faster than off thirty lines of figures. So a
/// report that reads well as a picture declares how, in the app's registry,
/// with a [ChartSpec], and the screen offers Table or Chart.
///
/// The chart is read off the finished table and nothing else: every figure
/// on it is a cell the builder already computed, summed only where several
/// rows share a label (a day's bills), so the chart and the table cannot
/// disagree, and a test holds the chart's total to the table's. Geometry —
/// how tall a column, how wide a slice — is the screen's, from these
/// figures and the shares in basis points computed here; nothing in this
/// package is a float.

/// How a report is drawn.
enum ChartForm {
  /// Over time, oldest first: a column per day or hour, a line when there
  /// are too many columns to tell apart.
  trend,

  /// The largest first, as bars across: the top few, and the rest summed.
  ranked,

  /// Parts of a whole, as a ring.
  ring,
}

/// How one report is drawn: its form and which of its columns it reads, by
/// title, so a cost column struck for a cashier (M33) leaves no chart
/// rather than a wrong one.
final class ChartSpec {
  /// [value] over [label], oldest first. With [everyDay], each day of the
  /// table's period is drawn, a day with nothing as nothing, so a quiet day
  /// reads as a gap rather than vanishing.
  const ChartSpec.trend({
    required this.label,
    required this.value,
    this.everyDay = false,
  }) : form = ChartForm.trend,
       top = 0,
       parts = const [],
       buckets = false;

  /// The [top] largest of [value] by [label], and the rest summed.
  const ChartSpec.ranked({
    required this.label,
    required this.value,
    this.top = 10,
  }) : form = ChartForm.ranked,
       everyDay = false,
       parts = const [],
       buckets = false;

  /// [value] by [label] as slices of a ring, in the table's order, at most
  /// [top] of them before the rest are summed.
  const ChartSpec.ring({required this.label, required this.value, this.top = 6})
    : form = ChartForm.ring,
      everyDay = false,
      parts = const [],
      buckets = false;

  /// The total row's own [parts] columns as slices of a ring, every one of
  /// them kept even when it is nothing: the ageing buckets, where a missing
  /// bucket reads as broken.
  const ChartSpec.ringOfTotal(this.parts)
    : form = ChartForm.ring,
      label = '',
      value = '',
      top = 0,
      everyDay = false,
      buckets = false;

  /// The total row's bucket columns as a ring, whatever buckets the table
  /// was built with (M67): an ageing report's, whose buckets the shop sets,
  /// so the ring follows them rather than naming the default five.
  const ChartSpec.ringOfBuckets()
    : form = ChartForm.ring,
      label = '',
      value = '',
      top = 0,
      everyDay = false,
      parts = const [],
      buckets = true;

  final ChartForm form;

  /// The title of the column each point is named by.
  final String label;

  /// The title of the money column each point is drawn from.
  final String value;
  final bool everyDay;
  final int top;
  final List<String> parts;

  /// Whether the ring's parts are the table's own bucket columns (M67).
  final bool buckets;
}

/// One column, bar or slice.
final class ChartPoint {
  const ChartPoint(
    this.label,
    this.value, {
    this.shareBp = 0,
    this.isRest = false,
    this.link,
  });

  /// As the table writes it: a date `2026-10-03`, an hour, a name.
  final String label;
  final Money value;

  /// Its share of [ReportChart.total], in basis points.
  final int shareBp;

  /// Everything past the top few, summed: the screen names it in the
  /// shop's own language.
  final bool isRest;

  /// What a tap on it opens, when it is one row that opens something.
  final ReportLink? link;
}

/// A report as a chart: its points, and the total they come to.
final class ReportChart {
  const ReportChart({
    required this.form,
    required this.valueTitle,
    required this.points,
    required this.total,
    this.leftOut = 0,
    this.ordered = false,
    this.previous = const [],
    this.previousTotal,
  });

  final ChartForm form;

  /// The points are buckets in an order that means something, each worse
  /// than the last (days past due), rather than things side by side: drawn
  /// in one hue, light to dark, instead of a colour each.
  final bool ordered;

  /// The table's title for what is drawn: Sales, Amount.
  final String valueTitle;
  final List<ChartPoint> points;

  /// What every point drawn comes to.
  final Money total;

  /// Rows of nothing or less, which a bar from zero or a slice of a ring
  /// cannot show: left out of a ranked chart or a ring, and said so.
  final int leftOut;

  /// The largest point.
  Money get peak => points.isEmpty
      ? Money.zero
      : points.map((p) => p.value).reduce((a, b) => a > b ? a : b);

  /// The smallest point, below nothing on a trend with a day of returns.
  Money get low => points.isEmpty
      ? Money.zero
      : points.map((p) => p.value).reduce((a, b) => a < b ? a : b);

  /// Whether there is nothing to draw.
  bool get isEmpty => points.every((p) => p.value.isZero);

  // M67: the period before, drawn lighter behind this one.

  /// The same trend for the period before, point for point: the first day
  /// of last month under the first day of this one, the same hour under
  /// the same hour; null where the period before has no such point. Empty
  /// when nothing is compared.
  final List<Money?> previous;

  /// What the period before came to, when it is compared.
  final Money? previousTotal;

  /// Whether the period before is drawn with it.
  bool get comparesPrevious => previous.isNotEmpty;

  /// The highest point of either period, so both are drawn to one scale.
  Money get peakWithPrevious =>
      [peak, for (final m in previous) ?m].reduce((a, b) => a > b ? a : b);

  /// The lowest point of either period.
  Money get lowWithPrevious =>
      [low, for (final m in previous) ?m].reduce((a, b) => a < b ? a : b);
}

/// [now], a trend, with [before] — the same report's trend for the period
/// before — laid point for point under it (M67), so the screen can draw
/// last month as a second, lighter series.
///
/// Days are matched by their place in the period, the first with the first,
/// because the 1st of October and the 1st of September are what a
/// shopkeeper compares; anything else (an hour of the day) by its label.
/// A ranked chart or a ring is returned as it was: a top ten and a ring
/// have no "same point" in another period to stand beside.
ReportChart compareWithPrevious(ReportChart now, ReportChart? before) {
  if (before == null || now.form != ChartForm.trend || now.points.isEmpty) {
    return now;
  }
  final byDay = now.points.every((p) => BusinessDate.tryParse(p.label) != null);
  final theirs = {for (final p in before.points) p.label: p.value};
  return ReportChart(
    form: now.form,
    valueTitle: now.valueTitle,
    points: now.points,
    total: now.total,
    leftOut: now.leftOut,
    ordered: now.ordered,
    previous: [
      for (var i = 0; i < now.points.length; i++)
        byDay
            ? (i < before.points.length ? before.points[i].value : null)
            : theirs[now.points[i].label],
    ],
    previousTotal: before.total,
  );
}

/// [table] drawn as [spec] says, or null when the table does not have the
/// columns it names (a cost column struck for a cashier).
ReportChart? chartOf(ReportTable table, ChartSpec spec) {
  // M67: an ageing report's ring is of the buckets it was built with.
  if (spec.buckets) {
    if (table.bucketColumns.isEmpty) return null;
    return _ringOfTotal(table, ChartSpec.ringOfTotal(table.bucketColumns));
  }
  if (spec.parts.isNotEmpty) return _ringOfTotal(table, spec);
  final at = table.columns.indexWhere((c) => c.title == spec.label);
  final of = table.columns.indexWhere(
    (c) => c.title == spec.value && c.kind == CellKind.money,
  );
  if (at < 0 || of < 0) return null;

  // Summed by label, in the order each label first appears: a day's bills
  // on the sale report are one column.
  final sums = <String, Money>{};
  final links = <String, ReportLink?>{};
  for (final row in table.rows) {
    if (row.style != RowStyle.line) continue;
    final label = '${row.cells[at] ?? ''}';
    final value = row.cells[of];
    final amount = value is Money ? value : Money.zero;
    final was = sums[label];
    sums[label] = (was ?? Money.zero) + amount;
    // A point that is several rows opens none of them.
    links[label] = was == null ? row.link : null;
  }

  return switch (spec.form) {
    ChartForm.trend => _trend(table, spec, sums, links),
    ChartForm.ranked => _ranked(spec, sums, links),
    ChartForm.ring => _ring(spec, sums, links),
  };
}

ReportChart _trend(
  ReportTable table,
  ChartSpec spec,
  Map<String, Money> sums,
  Map<String, ReportLink?> links,
) {
  final labels = sums.keys.toList()..sort();
  if (spec.everyDay && _days(table.period) <= _mostDays) {
    // Every day of the period, a day with no bills as nothing: a quiet
    // Tuesday is a gap in the row, not a column that is not there.
    labels
      ..clear()
      ..addAll([
        for (
          var d = table.period.from;
          d.value.compareTo(table.period.to.value) <= 0;
          d = d.addDays(1)
        )
          d.value,
      ]);
  }
  final total = Money.sum(sums.values);
  return ReportChart(
    form: ChartForm.trend,
    valueTitle: spec.value,
    total: total,
    points: [
      for (final l in labels)
        ChartPoint(
          l,
          sums[l] ?? Money.zero,
          shareBp: shareBp(sums[l] ?? Money.zero, total),
          link: links[l],
        ),
    ],
  );
}

/// A year and a day: past it a period is drawn by the days it has.
const _mostDays = 366;

int _days(ReportPeriod p) =>
    DateTime.utc(
      p.to.year,
      p.to.month,
      p.to.day,
    ).difference(DateTime.utc(p.from.year, p.from.month, p.from.day)).inDays +
    1;

ReportChart _ranked(
  ChartSpec spec,
  Map<String, Money> sums,
  Map<String, ReportLink?> links,
) {
  final drawn = sums.entries.where((e) => e.value.isPositive).toList()
    ..sort((a, b) {
      final byValue = b.value.compareTo(a.value);
      return byValue != 0 ? byValue : a.key.compareTo(b.key);
    });
  final total = Money.sum(drawn.map((e) => e.value));
  final top = drawn.take(spec.top).toList();
  final rest = Money.sum(drawn.skip(spec.top).map((e) => e.value));
  return ReportChart(
    form: ChartForm.ranked,
    valueTitle: spec.value,
    total: total,
    leftOut: sums.length - drawn.length,
    points: [
      for (final e in top)
        ChartPoint(
          e.key,
          e.value,
          shareBp: shareBp(e.value, total),
          link: links[e.key],
        ),
      if (drawn.length > spec.top)
        ChartPoint(
          'Rest (${drawn.length - spec.top})',
          rest,
          shareBp: shareBp(rest, total),
          isRest: true,
        ),
    ],
  );
}

ReportChart _ring(
  ChartSpec spec,
  Map<String, Money> sums,
  Map<String, ReportLink?> links,
) {
  final drawn = sums.entries.where((e) => e.value.isPositive).toList();
  final total = Money.sum(drawn.map((e) => e.value));
  // In the table's order, which means something (cash before the wallets,
  // udhaar last); past [ChartSpec.top] slices, the smallest are summed.
  var kept = drawn;
  var rest = <MapEntry<String, Money>>[];
  if (drawn.length > spec.top) {
    final bySize = drawn.toList()..sort((a, b) => b.value.compareTo(a.value));
    final big = bySize.take(spec.top - 1).map((e) => e.key).toSet();
    kept = [
      for (final e in drawn)
        if (big.contains(e.key)) e,
    ];
    rest = [
      for (final e in drawn)
        if (!big.contains(e.key)) e,
    ];
  }
  final restSum = Money.sum(rest.map((e) => e.value));
  return ReportChart(
    form: ChartForm.ring,
    valueTitle: spec.value,
    total: total,
    leftOut: sums.length - drawn.length,
    points: [
      for (final e in kept)
        ChartPoint(
          e.key,
          e.value,
          shareBp: shareBp(e.value, total),
          link: links[e.key],
        ),
      if (rest.isNotEmpty)
        ChartPoint(
          'Rest (${rest.length})',
          restSum,
          shareBp: shareBp(restSum, total),
          isRest: true,
        ),
    ],
  );
}

ReportChart? _ringOfTotal(ReportTable table, ChartSpec spec) {
  final total = table.totals.firstOrNull;
  if (total == null) return null;
  final columns = [
    for (final title in spec.parts)
      table.columns.indexWhere(
        (c) => c.title == title && c.kind == CellKind.money,
      ),
  ];
  if (columns.any((i) => i < 0)) return null;
  Money cell(int i) => switch (total.cells[i]) {
    final Money m => m,
    _ => Money.zero,
  };
  final whole = Money.sum([
    for (final i in columns)
      if (cell(i).isPositive) cell(i),
  ]);
  return ReportChart(
    form: ChartForm.ring,
    valueTitle: spec.parts.join(', '),
    total: whole,
    ordered: true,
    points: [
      for (var k = 0; k < columns.length; k++)
        ChartPoint(
          spec.parts[k],
          cell(columns[k]).isNegative ? Money.zero : cell(columns[k]),
          shareBp: cell(columns[k]).isNegative
              ? 0
              : shareBp(cell(columns[k]), whole),
        ),
    ],
  );
}
