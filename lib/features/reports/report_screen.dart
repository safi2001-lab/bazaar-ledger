import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../items/item_history_screen.dart';
import '../parties/party_picker.dart';
import '../printing/printing_providers.dart';
import '../sales/receipt_screen.dart';
import 'report_chart_view.dart';
import 'report_export.dart';
import 'report_filters_bar.dart';
import 'report_registry.dart';
import 'report_shelf.dart';
import 'report_table_view.dart';

typedef _Request = ({
  ReportKind kind,
  ReportPeriod period,
  ReportFilters filters,
});

final _reportProvider = FutureProvider.autoDispose
    .family<ReportTable, _Request>((ref, request) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) throw StateError('No shop is set up yet.');
      return services.reports.run(
        request.kind,
        firmId: firm.id,
        period: request.period,
        today: BusinessDate.now(services.clock),
        filters: request.filters,
      );
    });

/// The same report's headline figures for the period before, read only
/// once the report itself is on screen, so the comparison never holds the
/// figures up.
final _previousProvider = FutureProvider.autoDispose
    .family<List<ReportFigure>, _Request>((ref, request) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return const [];
      return services.reports.previousSummary(
        request.kind,
        firmId: firm.id,
        period: request.period,
        today: BusinessDate.now(services.clock),
        filters: request.filters,
      );
    });

/// One report: the period, the filters it takes, the headline figures, the
/// table, and the files it goes out as (M8, rebuilt in M33).
///
/// Every figure is computed by `pk_reports` from the books before it gets
/// here. This screen chooses what to ask for and lays the answer out; it
/// adds nothing up itself.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({
    required this.kind,
    this.filters = ReportFilters.none,
    super.key,
  });

  final ReportKind kind;

  /// What it opens narrowed to: a party, when it is opened from a party's
  /// row in another report.
  final ReportFilters filters;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  late final ReportEntry _entry = reportEntry(widget.kind);
  late DatePreset _preset;
  ReportPeriod? _custom;
  late ReportFilters _filters = widget.filters.only(_entry.filters);
  ReportFormat? _sharing;
  bool _printing = false;

  /// Drawn rather than listed (M46), for a report that declares a chart.
  bool _asChart = false;

  @override
  void initState() {
    super.initState();
    // The period this report was last read for, on this phone.
    final saved = ref.read(reportShelfProvider).periodFor(widget.kind);
    _preset = saved?.preset ?? _entry.defaultPreset;
    _custom = saved?.custom;
  }

  ReportPeriod _period(BusinessDate today) =>
      (_preset == DatePreset.custom ? _custom : null) ??
      _preset.resolve(today) ??
      ReportPeriod.day(today);

  void _choose(DatePreset preset, {ReportPeriod? custom}) {
    setState(() {
      _preset = preset;
      if (custom != null) _custom = custom;
    });
    ref
        .read(reportShelfProvider.notifier)
        .rememberPeriod(widget.kind, preset, custom: custom ?? _custom);
  }

  Future<void> _pickDates(BusinessDate today) async {
    DateTime asDate(BusinessDate d) => DateTime.utc(d.year, d.month, d.day);
    final current = _period(today);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.utc(2000),
      lastDate: asDate(today.addDays(365)),
      initialDateRange: DateTimeRange(
        start: asDate(current.from),
        end: asDate(current.to),
      ),
    );
    if (picked == null || !mounted) return;
    BusinessDate business(DateTime d) => BusinessDate(
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}',
    );
    _choose(
      DatePreset.custom,
      custom: ReportPeriod(business(picked.start), business(picked.end)),
    );
  }

  Future<void> _share(ReportTable table, ReportFormat format) async {
    if (_sharing != null) return;
    setState(() => _sharing = format);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final firm = await ref.read(firmProvider.future);
      await shareReport(table, format, shopName: firm?.name ?? '');
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _sharing = null);
    }
  }

  /// Prints [table] on the counter's receipt printer, through the same
  /// queue and the same log every receipt goes through. The roll is narrow,
  /// so a long report prints its figures and totals and leaves the rows to
  /// the PDF; a name the printer's font cannot say comes out as question
  /// marks, which the PDF does not do.
  Future<void> _print(ReportTable table) async {
    if (_printing) return;
    final s = AppStrings.of(context);
    setState(() => _printing = true);
    final messenger = ScaffoldMessenger.of(context);
    void say(String message) =>
        messenger.showSnackBar(SnackBar(content: Text(message)));
    try {
      final settings = await ref.read(printerSettingsProvider.future);
      if (settings == null) {
        say(s.receiptNoPrinter);
        return;
      }
      final services = ref.read(appServicesProvider);
      final firm = await ref.read(firmProvider.future);
      final slip = reportToSlip(
        table,
        width: settings.columns,
        shopName: firm?.name ?? '',
      );
      final paper = EscPos()..initialise();
      for (final line in slip) {
        paper
          ..align(line.centred ? EscPosAlign.centre : EscPosAlign.left)
          ..bold(on: line.bold)
          ..line(line.text);
      }
      paper
        ..bold(on: false)
        ..feed(3)
        ..cut();
      final result = await services.printing.print(
        actor: services.actorNow(),
        settings: settings,
        // A report is printed afresh each time it is asked for, so each
        // press is its own job; the key is never reused.
        jobKey:
            'report#${table.id}#${table.period.label}#'
            '${services.clock.nowUtc().microsecondsSinceEpoch}',
        bytes: paper.bytes,
      );
      say(switch (result.outcome) {
        PrintOutcome.printed => s.printerDone,
        PrintOutcome.notSent => s.printerNotSent,
        PrintOutcome.partial || PrintOutcome.unknown => s.printerPartial,
      });
    } on Object catch (error) {
      say('${s.commonSomethingWentWrong}: $error');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _chooseParty() async {
    final party = await showModalBottomSheet<PartySummary>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PartyPicker(),
    );
    if (party == null || !mounted) return;
    setState(
      () => _filters = _filters.copyWith(
        partyId: party.id,
        partyName: party.name,
      ),
    );
  }

  /// What a tap on a row can open from here: a sale bill's receipt, a
  /// party's statement, an item's stock history (M34), or a loan's
  /// statement (M58). Purchases and the rest have no screen of their own to
  /// open yet.
  bool _canOpen(ReportLink link) => switch (link.kind) {
    ReportLinkKind.document => link.docType == TransactionType.sale,
    ReportLinkKind.party =>
      widget.kind != ReportKind.partyStatement || link.id != _filters.partyId,
    ReportLinkKind.item => true,
    ReportLinkKind.loan => _filters.loanId != link.id,
  };

  void _open(ReportLink link) {
    final Widget screen = switch (link.kind) {
      ReportLinkKind.document => ReceiptScreen(
        documentId: link.id,
        docNo: link.label,
      ),
      ReportLinkKind.party => ReportScreen(
        kind: ReportKind.partyStatement,
        filters: ReportFilters(partyId: link.id, partyName: link.label),
      ),
      ReportLinkKind.item => ItemHistoryScreen(
        itemId: link.id,
        itemName: link.label,
        unitCode: link.unitCode ?? '',
      ),
      ReportLinkKind.loan => ReportScreen(
        kind: ReportKind.loanStatement,
        filters: ReportFilters(loanId: link.id, loanName: link.label),
      ),
    };
    unawaited(
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => screen)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final today = BusinessDate.now(ref.watch(appServicesProvider).clock);
    final period = _period(today);
    final request = (kind: widget.kind, period: period, filters: _filters);
    final report = ref.watch(_reportProvider(request));
    final needsParty =
        widget.kind == ReportKind.partyStatement && _filters.partyId == null;

    final table = needsParty ? null : report.valueOrNull;
    final busy = _sharing != null || _printing;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(_entry.name(s))),
      // The ways out, along the foot where a thumb finds them, each with
      // its name under it: PDF for WhatsApp, Excel and CSV for the
      // accountant, and the counter's own printer.
      bottomNavigationBar: table == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: BlTokens.space1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final (icon, label, caption, action) in [
                      (
                        Icons.picture_as_pdf_outlined,
                        s.reportSharePdf,
                        'PDF',
                        () => _share(table, ReportFormat.pdf),
                      ),
                      (
                        Icons.grid_on_outlined,
                        s.reportShareExcel,
                        s.reportExcel,
                        () => _share(table, ReportFormat.xlsx),
                      ),
                      (
                        Icons.table_view_outlined,
                        s.reportShareCsv,
                        s.reportCsv,
                        () => _share(table, ReportFormat.csv),
                      ),
                      (
                        Icons.print_outlined,
                        s.reportPrintTitle,
                        s.reportPrint,
                        () => _print(table),
                      ),
                    ])
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BlIconButton(
                            icon: icon,
                            label: label,
                            onPressed: busy ? null : () => unawaited(action()),
                          ),
                          ExcludeSemantics(
                            child: Text(
                              caption,
                              style: TextStyle(fontSize: 11, color: t.inkMuted),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            if (_entry.isAsOfToday)
              Text(
                // A stock report read for a day gone by (M34) says which.
                _filters.asOf == null ? s.reportAsOfNow : s.reportFilterAsOf,
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final preset in DatePreset.values)
                      Padding(
                        padding: const EdgeInsets.only(right: BlTokens.space2),
                        child: ChoiceChip(
                          selected: preset == _preset,
                          label: Text(_presetLabel(s, preset)),
                          onSelected: (_) => preset == DatePreset.custom
                              ? unawaited(_pickDates(today))
                              : _choose(preset),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: BlTokens.space2),
            Text(
              _entry.isAsOfToday
                  ? (_filters.asOf ?? today).value
                  : period.label,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            if (_entry.filters.isNotEmpty) ...[
              const SizedBox(height: BlTokens.space2),
              ReportFiltersBar(
                accepted: _entry.filters,
                filters: _filters,
                onChanged: (f) => setState(() => _filters = f),
              ),
            ],
            const SizedBox(height: BlTokens.space3),
            if (needsParty)
              BlEmpty(
                title: s.reportChooseParty,
                icon: Icons.person_search_outlined,
                action: BlButton(
                  label: s.reportFilterParty,
                  icon: Icons.person_search_outlined,
                  onPressed: () => unawaited(_chooseParty()),
                ),
              )
            else
              report.when(
                loading: () => const BlSkeletonList(rows: 6),
                error: (error, _) => BlError(
                  title: s.commonSomethingWentWrong,
                  message: '$error',
                  retryLabel: s.actionRetry,
                  onRetry: () => ref.invalidate(_reportProvider),
                ),
                data: (table) {
                  // M46: a report that declares a chart, and whose table
                  // still has the columns it names, can be drawn.
                  final spec = _entry.chart;
                  final chart = spec == null ? null : chartOf(table, spec);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (table.summary.isNotEmpty) ...[
                        _SummaryTiles(table: table, request: request),
                        const SizedBox(height: BlTokens.space3),
                      ],
                      if (chart != null) ...[
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: false,
                              icon: const Icon(Icons.table_rows_outlined),
                              label: Text(s.reportViewTable),
                            ),
                            ButtonSegment(
                              value: true,
                              icon: const Icon(Icons.bar_chart_outlined),
                              label: Text(s.reportViewChart),
                            ),
                          ],
                          selected: {_asChart},
                          onSelectionChanged: (v) =>
                              setState(() => _asChart = v.first),
                        ),
                        const SizedBox(height: BlTokens.space3),
                      ],
                      if (chart != null && _asChart)
                        ReportChartView(
                          chart: chart,
                          title: _entry.name(s),
                          canOpen: _canOpen,
                          onOpen: _open,
                        )
                      else
                        ReportTableView(
                          table: table,
                          canOpen: _canOpen,
                          onOpen: _open,
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

String _presetLabel(AppStrings s, DatePreset preset) => switch (preset) {
  DatePreset.today => s.reportToday,
  DatePreset.yesterday => s.reportYesterday,
  DatePreset.thisWeek => s.reportThisWeek,
  DatePreset.thisMonth => s.reportThisMonth,
  DatePreset.lastMonth => s.reportLastMonth,
  DatePreset.thisQuarter => s.reportThisQuarter,
  DatePreset.thisFiscalYear => s.reportThisYear,
  DatePreset.lastFiscalYear => s.reportLastYear,
  DatePreset.custom => s.reportCustom,
};

/// The report's headline figures as tiles, each with how it compares with
/// the period before once that has been read.
class _SummaryTiles extends ConsumerWidget {
  const _SummaryTiles({required this.table, required this.request});

  final ReportTable table;
  final _Request request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final before = {
      for (final f
          in ref.watch(_previousProvider(request)).valueOrNull ??
              const <ReportFigure>[])
        f.label: f,
    };
    return Wrap(
      spacing: BlTokens.space2,
      runSpacing: BlTokens.space2,
      children: [
        for (final f in table.summary)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 140),
            child: BlCard(
              padding: const EdgeInsets.all(BlTokens.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    f.label,
                    style: TextStyle(fontSize: 12, color: t.inkMuted),
                  ),
                  const SizedBox(height: BlTokens.space1),
                  if (f.amount case final amount?)
                    BlMoney(amount, size: 18, withSymbol: true)
                  else
                    Text(
                      '${f.count ?? 0}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: t.ink,
                        fontFeatures: BlTokens.tabular,
                      ),
                    ),
                  if (before[f.label] case final was?)
                    if (f.changeFrom(was) case final bp?)
                      Text(
                        s.reportVsPrevious(
                          '${bp > 0 ? '+' : ''}${formatBp(bp)}',
                        ),
                        style: TextStyle(fontSize: 11, color: t.inkMuted),
                      ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
