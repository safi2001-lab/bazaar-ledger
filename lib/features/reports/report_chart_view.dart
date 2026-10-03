import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// A report drawn (M46): a trend of columns or a line, the top ten as bars,
/// or a ring, from a [ReportChart] that pk_reports read off the finished
/// table.
///
/// Since M67 a trend carries the period before as a second series, drawn
/// as a lighter line over this period's columns (or under its line), day
/// for day, with both totals named under it in words; the top ten and the
/// ring are as they were, having no "same point" in another period.
///
/// Drawn here with Flutter's own canvas: no chart package, because every
/// kilobyte of an APK is a kilobyte a shop on a 2 GB phone pays for, and the
/// three forms a shop reads are a few rectangles and arcs. The marks are
/// painted; every word and figure around them is an ordinary [Text], so it
/// grows with the shopkeeper's text size, reads in their language, and is
/// spoken by a screen reader. Nothing is added up here: heights and angles
/// are the screen's, from figures and shares the builder computed.
class ReportChartView extends StatefulWidget {
  const ReportChartView({
    required this.chart,
    required this.title,
    this.canOpen,
    this.onOpen,
    super.key,
  });

  final ReportChart chart;

  /// The report's name, for the screen reader's summary.
  final String title;

  /// Whether a bar's link leads anywhere from here, and what opens it.
  final bool Function(ReportLink link)? canOpen;
  final void Function(ReportLink link)? onOpen;

  @override
  State<ReportChartView> createState() => _ReportChartViewState();
}

class _ReportChartViewState extends State<ReportChartView> {
  int? _picked;

  @override
  void didUpdateWidget(ReportChartView old) {
    super.didUpdateWidget(old);
    if (!identical(old.chart, widget.chart)) _picked = null;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final chart = widget.chart;
    if (chart.isEmpty) {
      return BlCard(
        child: Text(s.reportChartNothing, style: TextStyle(color: t.inkMuted)),
      );
    }
    final body = switch (chart.form) {
      ChartForm.trend => _Trend(
        chart: chart,
        picked: _picked,
        onPick: (i) => setState(() => _picked = _picked == i ? null : i),
      ),
      ChartForm.ranked => _Ranked(
        chart: chart,
        canOpen: widget.canOpen,
        onOpen: widget.onOpen,
      ),
      ChartForm.ring => _Ring(chart: chart),
    };
    return Semantics(
      container: true,
      label: s.reportChartSummary(
        widget.title,
        chart.points.length,
        chart.total.toString(),
      ),
      child: BlCard(
        padding: const EdgeInsets.all(BlTokens.space3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            body,
            if (chart.leftOut > 0) ...[
              const SizedBox(height: BlTokens.space2),
              Text(
                s.reportChartLeftOut(chart.leftOut),
                style: TextStyle(fontSize: 12, color: t.inkMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A point's name as a chart writes it: a day as `3 Oct`, an hour as its
/// first hour, the rest in the shop's own words, anything else as the table
/// wrote it.
String chartLabel(AppStrings s, ChartPoint p, {bool short = false}) {
  if (p.isRest) {
    final count = int.tryParse(
      RegExp(r'\((\d+)\)').firstMatch(p.label)?.group(1) ?? '',
    );
    return s.reportChartRest(count ?? 0);
  }
  if (BusinessDate.tryParse(p.label) != null) return shortDate(p.label);
  final hour = RegExp(r'^(\d\d):00-').firstMatch(p.label);
  if (hour != null && short) return hour.group(1)!;
  return p.label;
}

// ---------------------------------------------------------------------------
// Trend: columns, or a line when there are too many to tell apart
// ---------------------------------------------------------------------------

/// Past this many points a column is too thin to read on a phone, and the
/// trend is a line.
const _mostColumns = 31;

class _Trend extends StatelessWidget {
  const _Trend({
    required this.chart,
    required this.picked,
    required this.onPick,
  });

  final ReportChart chart;
  final int? picked;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final points = chart.points;
    final asLine = points.length > _mostColumns;
    final muted = TextStyle(
      fontSize: 12,
      color: t.inkMuted,
      fontFeatures: BlTokens.tabular,
    );
    var highest = 0;
    for (var i = 1; i < points.length; i++) {
      if (points[i].value > points[highest].value) highest = i;
    }
    final shown = picked ?? highest;
    // M67: the same point in the period before, when it is drawn.
    final before = chart.comparesPrevious ? chart.previous[shown] : null;
    final caption = picked == null
        ? s.reportChartHighest(
            chartLabel(s, points[shown]),
            points[shown].value.toString(),
          )
        : before != null
        ? s.reportChartPickedBefore(
            chartLabel(s, points[shown]),
            points[shown].value.toString(),
            before.toString(),
          )
        : s.reportChartPicked(
            chartLabel(s, points[shown]),
            points[shown].value.toString(),
          );
    final lighter = t.chartSeries.first.withValues(alpha: 0.4);
    // A tick under the first, the middle and the last point: enough to say
    // where the row of columns starts and ends at any text size.
    final ticks = <int>{
      0,
      if (points.length > 2) points.length ~/ 2,
      points.length - 1,
    }.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          (chart.comparesPrevious ? chart.peakWithPrevious : chart.peak)
              .toString(),
          style: muted,
        ),
        const SizedBox(height: BlTokens.space1),
        LayoutBuilder(
          builder: (context, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              final slot = box.maxWidth / points.length;
              final i = (d.localPosition.dx / slot).floor();
              onPick(i.clamp(0, points.length - 1));
            },
            child: CustomPaint(
              size: Size(box.maxWidth, 160),
              painter: _TrendPainter(
                values: [for (final p in points) p.value.inPaisa],
                picked: picked,
                asLine: asLine,
                mark: t.chartSeries.first,
                baseline: t.lineStrong,
                pickedInk: t.ink,
                surface: t.surface,
                // M67
                previous: [for (final m in chart.previous) m?.inPaisa],
                previousInk: lighter,
              ),
            ),
          ),
        ),
        const SizedBox(height: BlTokens.space1),
        Row(
          // One column stands in the middle, and so does its name.
          mainAxisAlignment: points.length == 1
              ? MainAxisAlignment.center
              : MainAxisAlignment.spaceBetween,
          children: [
            for (final i in ticks)
              Flexible(
                child: Text(
                  chartLabel(s, points[i], short: true),
                  style: muted,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        const SizedBox(height: BlTokens.space2),
        Text(
          caption,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: t.ink,
            fontFeatures: BlTokens.tabular,
          ),
        ),
        // M67: which series is which, each with its total, in words.
        if (chart.comparesPrevious) ...[
          const SizedBox(height: BlTokens.space2),
          _Key(
            swatch: t.chartSeries.first,
            text: '${s.reportChartThisPeriod}: ${chart.total}',
          ),
          _Key(
            swatch: lighter,
            line: true,
            text: s.reportChartPeriodBefore(
              (chart.previousTotal ?? Money.zero).toString(),
            ),
          ),
        ],
      ],
    );
  }
}

/// One line of a chart's key (M67): a swatch, a square for this period's
/// columns or a bar of line for the period before, and its words.
class _Key extends StatelessWidget {
  const _Key({required this.swatch, required this.text, this.line = false});

  final Color swatch;
  final String text;
  final bool line;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: line ? 7 : 3),
            child: Container(
              width: 14,
              height: line ? 3 : 12,
              decoration: BoxDecoration(
                color: swatch,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(width: BlTokens.space2),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: t.inkMuted,
                fontFeatures: BlTokens.tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.values,
    required this.picked,
    required this.asLine,
    required this.mark,
    required this.baseline,
    required this.pickedInk,
    required this.surface,
    this.previous = const [],
    this.previousInk,
  });

  /// In paisa: pixels are worked out from whole numbers here, never money.
  final List<int> values;

  /// M67: the period before, point for point; null where it has none.
  final List<int?> previous;
  final Color? previousInk;
  final int? picked;
  final bool asLine;
  final Color mark;
  final Color baseline;
  final Color pickedInk;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final both = [...values, for (final v in previous) ?v];
    final top = math.max(0, both.reduce(math.max));
    final bottom = math.min(0, both.reduce(math.min));
    final span = (top - bottom) == 0 ? 1 : top - bottom;
    double y(int v) => size.height * (top - v) / span;
    final zero = y(0);
    final slot = size.width / values.length;

    canvas.drawLine(
      Offset(0, zero),
      Offset(size.width, zero),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );

    // M67: the period before as a lighter line through each slot's middle,
    // a dot on every point it has: under this period's line, over its
    // columns, so neither hides the other.
    void drawPrevious() {
      final ink = previousInk;
      if (ink == null || previous.isEmpty) return;
      final paint = Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      var open = false;
      for (var i = 0; i < previous.length && i < values.length; i++) {
        final v = previous[i];
        if (v == null) {
          open = false;
          continue;
        }
        final p = Offset(slot * (i + 0.5), y(v));
        if (open) {
          path.lineTo(p.dx, p.dy);
        } else {
          path.moveTo(p.dx, p.dy);
          open = true;
        }
        canvas.drawCircle(p, 2.5, Paint()..color = ink);
      }
      canvas.drawPath(path, paint);
    }

    if (asLine) {
      drawPrevious();
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final p = Offset(slot * (i + 0.5), y(values[i]));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = mark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
      if (picked case final i?) {
        final p = Offset(slot * (i + 0.5), y(values[i]));
        canvas
          ..drawCircle(p, 6, Paint()..color = surface)
          ..drawCircle(p, 4, Paint()..color = mark);
      }
      return;
    }

    // A 2px gap between columns while they are wide enough to keep one, no
    // column wider than [_widestColumn] however few there are, each in the
    // middle of its slot, and a rounded end on the value, never on the
    // baseline.
    final gap = slot >= 6 ? 2.0 : 0.0;
    final width = math.min(_widestColumn, math.max(1.0, slot - gap));
    final radius = Radius.circular(math.min(4, width / 2));
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == 0) continue;
      final left = slot * i + (slot - width) / 2;
      final rect = Rect.fromLTRB(
        left,
        math.min(y(v), zero),
        left + width,
        math.max(y(v), zero),
      );
      final shape = v > 0
          ? RRect.fromRectAndCorners(rect, topLeft: radius, topRight: radius)
          : RRect.fromRectAndCorners(
              rect,
              bottomLeft: radius,
              bottomRight: radius,
            );
      canvas.drawRRect(shape, Paint()..color = mark);
      if (picked == i) {
        canvas.drawRRect(
          shape,
          Paint()
            ..color = pickedInk
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
    drawPrevious();
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.picked != picked ||
      old.asLine != asLine ||
      old.mark != mark ||
      old.baseline != baseline ||
      old.previousInk != previousInk ||
      !_same(old.values, values) ||
      !_sameOrNull(old.previous, previous);
}

bool _sameOrNull(List<int?> a, List<int?> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A day or an hour on its own is a column, not a wall.
const _widestColumn = 40.0;

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Ranked: the top ten as bars across
// ---------------------------------------------------------------------------

class _Ranked extends StatelessWidget {
  const _Ranked({required this.chart, this.canOpen, this.onOpen});

  final ReportChart chart;
  final bool Function(ReportLink link)? canOpen;
  final void Function(ReportLink link)? onOpen;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final peak = chart.peak.inPaisa;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in chart.points)
          _bar(context, s, t, p, peak == 0 ? 0 : p.value.inPaisa / peak),
      ],
    );
  }

  Widget _bar(
    BuildContext context,
    AppStrings s,
    BlTokens t,
    ChartPoint p,
    double fraction,
  ) {
    final link = p.link;
    final opens =
        link != null && onOpen != null && (canOpen?.call(link) ?? true);
    // The name and the figure on one line where they fit, the figure under
    // the name where they do not; the bar on a line of its own, so every
    // bar is measured against the same full width.
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: BlTokens.space1 + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: BlTokens.space2,
            children: [
              Text(
                chartLabel(s, p),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: t.ink),
              ),
              Text(
                '${p.value} · ${formatBp(p.shareBp)}',
                style: TextStyle(
                  fontSize: 13,
                  color: t.inkMuted,
                  fontFeatures: BlTokens.tabular,
                ),
              ),
            ],
          ),
          const SizedBox(height: BlTokens.space1),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FractionallySizedBox(
              widthFactor: math.max(0.01, fraction),
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  color: p.isRest ? t.inkFaint : t.chartSeries.first,
                  borderRadius: const BorderRadiusDirectional.horizontal(
                    end: Radius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (!opens) return row;
    return InkWell(onTap: () => onOpen!(link), child: row);
  }
}

// ---------------------------------------------------------------------------
// Ring: parts of a whole
// ---------------------------------------------------------------------------

class _Ring extends StatelessWidget {
  const _Ring({required this.chart});

  final ReportChart chart;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final colours = _colours(t);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final side = math.min(box.maxWidth, 220.0);
            return Center(
              child: SizedBox.square(
                dimension: side,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size.square(side),
                      painter: _RingPainter(
                        shares: [for (final p in chart.points) p.shareBp],
                        colours: colours,
                        surface: t.surface,
                      ),
                    ),
                    // The total in the hole, shrunk to fit it at any text
                    // size rather than spilling over the ring.
                    SizedBox.square(
                      dimension: side * 0.56,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              s.reportChartTotal,
                              style: TextStyle(fontSize: 12, color: t.inkMuted),
                            ),
                            Text(
                              chart.total.toString(),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: t.ink,
                                fontFeatures: BlTokens.tabular,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: BlTokens.space3),
        // The legend names every slice, with its figure and share, so no
        // slice is known by its colour alone.
        for (var i = 0; i < chart.points.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: BlTokens.space1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colours[i],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(width: BlTokens.space2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chartLabel(s, chart.points[i]),
                        style: TextStyle(fontSize: 14, color: t.ink),
                      ),
                      Text(
                        '${chart.points[i].value} · '
                        '${formatBp(chart.points[i].shareBp)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: t.inkMuted,
                          fontFeatures: BlTokens.tabular,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// A colour per slice: one hue light to dark for buckets in order, the
  /// categorical set in its fixed order otherwise, and the rest neutral.
  List<Color> _colours(BlTokens t) {
    final points = chart.points;
    if (chart.ordered) {
      final ramp = t.chartRamp;
      return [
        for (var i = 0; i < points.length; i++)
          ramp[points.length <= ramp.length
              ? i + ramp.length - points.length
              : math.min(i, ramp.length - 1)],
      ];
    }
    final series = t.chartSeries;
    return [
      for (var i = 0; i < points.length; i++)
        points[i].isRest ? t.inkFaint : series[i % series.length],
    ];
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.shares,
    required this.colours,
    required this.surface,
  });

  /// Each slice's share, in basis points.
  final List<int> shares;
  final List<Color> colours;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.max(16.0, size.shortestSide * 0.16);
    final radius = (size.shortestSide - stroke) / 2;
    final centre = size.center(Offset.zero);
    final box = Rect.fromCircle(center: centre, radius: radius);
    final drawn = shares.where((b) => b > 0).length;
    // A 2px gap between slices, as an angle at this radius; none for a
    // ring that is one slice whole.
    final gap = drawn > 1 ? 2 / radius : 0.0;
    var start = -math.pi / 2;
    for (var i = 0; i < shares.length; i++) {
      final sweep = 2 * math.pi * shares[i] / 10000;
      if (sweep <= 0) continue;
      canvas.drawArc(
        box,
        start + gap / 2,
        math.max(0.001, sweep - gap),
        false,
        Paint()
          ..color = colours[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      !_same(old.shares, shares) ||
      old.surface != surface ||
      old.colours.length != colours.length ||
      [
        for (var i = 0; i < colours.length; i++) old.colours[i] != colours[i],
      ].any((changed) => changed);
}
