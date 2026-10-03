import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../cheques/cheques_screen.dart'; // M67
import '../items/item_history_screen.dart';
import '../parties/party_picker.dart';
import '../printing/printing_providers.dart';
import '../sales/receipt_screen.dart';
import '../subscription/plans_screen.dart'; // M67
import '../tax/fbr_screen.dart'; // M67
import 'column_chooser.dart'; // M67
import 'report_chart_view.dart';
import 'report_export.dart';
import 'report_filters_bar.dart';
import 'report_registry.dart';
import 'report_shelf.dart';
import 'report_table_view.dart';
import 'saved_views.dart';

typedef _Request = ({
  ReportKind kind,
  ReportPeriod period,
  ReportFilters filters,
  // M67: the shop's own settings it is run with.
  ReportOptions options,
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
        options: request.options,
      );
    });

/// The same report for the period before, read only once the report itself
/// is on screen, so the comparison never holds the figures up: its headline
/// figures beside this period's, and since M67 its trend drawn lighter
/// behind this period's.
final _previousProvider = FutureProvider.autoDispose
    .family<ReportTable?, _Request>((ref, request) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return null;
      return services.reports.previousTable(
        request.kind,
        firmId: firm.id,
        period: request.period,
        today: BusinessDate.now(services.clock),
        filters: request.filters,
        options: request.options,
      );
    });

/// The reports that age money, which the shop's buckets cut (M67).
const _ageingKinds = {
  ReportKind.receivables,
  ReportKind.payables,
  ReportKind.receivablesByDueDate,
};

/// One report: the period, the filters it takes, the headline figures, the
/// table, and the files it goes out as (M8, rebuilt in M33).
///
/// Every figure is computed by `pk_reports` from the books before it gets
/// here. This screen chooses what to ask for and lays the answer out; it
/// adds nothing up itself.
///
/// Since M61 everything the shop chose here — the period, the filters, the
/// sort, table or chart — can be kept under a name as a view, from the
/// bookmark at the top, and a view opens this screen just so.
///
/// Since M67 the table is the shop's to arrange: columns shown, hidden and
/// moved (remembered for the report on this phone), a filter on any column
/// with what the rows left showing come to, and on the ageing reports the
/// buckets the money is cut into. What is on screen is what every export
/// carries; the totals are still the builder's.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({
    required this.kind,
    this.filters = ReportFilters.none,
    this.view,
    super.key,
  });

  final ReportKind kind;

  /// What it opens narrowed to: a party, when it is opened from a party's
  /// row in another report.
  final ReportFilters filters;

  /// The saved view it opens as (M61), which then sets the period, the
  /// filters, the sort and table or chart in place of [filters] and the
  /// period last read.
  final SavedReportView? view;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  late final ReportEntry _entry = reportEntry(widget.kind);
  late DatePreset _preset;
  ReportPeriod? _custom;
  late ReportFilters _filters = (widget.view?.filters ?? widget.filters).only(
    _entry.filters,
  );
  ReportFormat? _sharing;
  bool _printing = false;

  /// Drawn rather than listed (M46), for a report that declares a chart.
  late bool _asChart = widget.view?.asChart ?? false;

  /// The column the table is sorted by, by its title, and which way (M61):
  /// held here, not only in the table, so a view keeps them and the table
  /// comes back sorted after a turn as a chart.
  late String? _sortColumn = widget.view?.sortColumn;
  late bool _sortAscending = widget.view?.sortAscending ?? false;

  /// The view this screen is showing, once one is opened or saved.
  late SavedReportView? _view = widget.view;

  /// M67: the table as the shop arranged it: a view's, or the columns this
  /// phone remembers for the report.
  late TableArrangement _arrangement =
      widget.view?.arrangement ??
      ref.read(reportShelfProvider).columnsFor(widget.kind);

  /// M67: the moment the screen opened, for what turns on the hour (an FBR
  /// bill's 24 hours) rather than the day.
  late final DateTime _openedAt = ref.read(appServicesProvider).clock.nowUtc();

  /// M67: the arranged table, kept until the table or the arrangement
  /// changes, so a rebuild does not hand the table view a new table and
  /// lose its place.
  ReportTable? _builtFrom;
  TableArrangement? _builtWith;
  ReportTable? _arranged;

  ReportTable _arrange(ReportTable table) {
    if (!identical(table, _builtFrom) || _arrangement != _builtWith) {
      _builtFrom = table;
      _builtWith = _arrangement;
      _arranged = arrangeTable(table, _arrangement);
    }
    return _arranged!;
  }

  void _arrangeAs(TableArrangement next) {
    final columnsChanged = next.columnsOnly != _arrangement.columnsOnly;
    setState(() => _arrangement = next);
    if (columnsChanged && widget.view == null) {
      ref.read(reportShelfProvider.notifier).rememberColumns(widget.kind, next);
    }
  }

  Future<void> _chooseColumns(ReportTable built) async {
    final next = await chooseColumns(context, built, _arrangement);
    if (next != null && mounted) _arrangeAs(next);
  }

  Future<void> _filterAColumn(ReportTable built) async {
    final next = await filterAColumn(context, built, _arrangement);
    if (next != null && mounted) _arrangeAs(next);
  }

  /// M67: what the report is run with beyond its period and filters.
  ReportOptions _options(ReportShelf shelf) => ReportOptions(
    ageing: _ageingKinds.contains(widget.kind)
        ? shelf.ageing
        : AgeingBuckets.standard,
    nowUtc: widget.kind == ReportKind.needsAttention ? _openedAt : null,
  );

  @override
  void initState() {
    super.initState();
    final view = widget.view;
    if (view != null) {
      _preset = view.preset;
      _custom = view.custom;
      return;
    }
    // The period this report was last read for, on this phone.
    final saved = ref.read(reportShelfProvider).periodFor(widget.kind);
    _preset = saved?.preset ?? _entry.defaultPreset;
    _custom = saved?.custom;
  }

  /// Keeps what is on screen as a view, under a name the shop types (M61).
  Future<void> _saveView() async {
    final s = AppStrings.of(context);
    final today = BusinessDate.now(ref.read(appServicesProvider).clock);
    // A name to start from: the view's own, or the report and its period,
    // "Bikri report · Is hafta", for the shop to make its own.
    final period = _preset == DatePreset.custom
        ? _period(today).label
        : reportPresetLabel(s, _preset);
    final kept = await saveReportView(
      context,
      ref,
      SavedReportView(
        id: '',
        name:
            _view?.name ??
            (_entry.isAsOfToday
                ? _entry.name(s)
                : '${_entry.name(s)} · $period'),
        kind: widget.kind,
        preset: _preset,
        custom: _preset == DatePreset.custom ? _period(today) : null,
        filters: _filters,
        sortColumn: _sortColumn,
        sortAscending: _sortAscending,
        asChart: _asChart,
        arrangement: _arrangement, // M67
      ),
    );
    if (kept != null && mounted) setState(() => _view = kept);
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
      // M67: through the sharer, so a test can read what would have gone.
      await ref.read(reportSharerProvider)(
        table,
        format,
        shopName: firm?.name ?? '',
      );
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
    // M67: a money account's statement, another report this person may
    // open, the cheques and the FBR queue.
    ReportLinkKind.account => true,
    ReportLinkKind.report => switch (_reportOf(link)) {
      final kind? =>
        kind != widget.kind &&
            (!reportEntry(kind).showsCost ||
                ref.read(appServicesProvider).can(Permission.seeCosts)),
      null => false,
    },
    ReportLinkKind.screen =>
      link.id == ReportLink.cheques || link.id == ReportLink.fbr,
  };

  static ReportKind? _reportOf(ReportLink link) =>
      ReportKind.values.where((k) => k.name == link.id).firstOrNull;

  void _open(ReportLink link) {
    // M67: another report opens through its own plan, as from the hub.
    if (link.kind == ReportLinkKind.report) {
      final kind = _reportOf(link);
      if (kind == null) return;
      final plan = reportEntry(kind).plan;
      Widget screen() => ReportScreen(kind: kind);
      if (plan != null) {
        unawaited(openWithPlan(context, ref, plan, screen));
      } else {
        unawaited(
          Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => screen())),
        );
      }
      return;
    }
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
      // M67
      ReportLinkKind.account => ReportScreen(
        kind: ReportKind.bankStatement,
        filters: ReportFilters(accountId: link.id, accountName: link.label),
      ),
      ReportLinkKind.screen =>
        link.id == ReportLink.fbr ? const FbrScreen() : const ChequesScreen(),
      // Opened above, through its own plan; never reached.
      ReportLinkKind.report => ReportScreen(
        kind: _reportOf(link) ?? widget.kind,
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
    final shelf = ref.watch(reportShelfProvider);
    final request = (
      kind: widget.kind,
      period: period,
      filters: _filters,
      options: _options(shelf), // M67
    );
    final report = ref.watch(_reportProvider(request));
    final needsParty =
        widget.kind == ReportKind.partyStatement && _filters.partyId == null;

    // M67: what is shown is what goes out: the table as the shop arranged
    // it, its columns and its column filters.
    final built = needsParty ? null : report.valueOrNull;
    final table = built == null ? null : _arrange(built);
    final busy = _sharing != null || _printing;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        // A view opens under its own name, and says which report it is at
        // the head of the page, where large text has room to wrap.
        title: Text(_view?.name ?? _entry.name(s)),
        actions: [
          // M67: the columns shown and their order, and a filter on any of
          // them, once there is a table to arrange.
          if (built != null) ...[
            BlIconButton(
              icon: Icons.view_column_outlined,
              label: s.reportColumns,
              onPressed: () => unawaited(_chooseColumns(built)),
            ),
            if (built.isSortable)
              BlIconButton(
                icon: Icons.filter_alt_outlined,
                label: s.reportColumnFilter,
                onPressed: () => unawaited(_filterAColumn(built)),
              ),
          ],
          // M61: keep this report the way it is on screen, by name.
          BlIconButton(
            icon: _view == null ? Icons.bookmark_add_outlined : Icons.bookmark,
            label: s.reportSaveView,
            onPressed: () => unawaited(_saveView()),
          ),
        ],
      ),
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
            // M61: which report a view is.
            if (_view != null) ...[
              Text(
                _entry.name(s),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: t.inkMuted,
                ),
              ),
              const SizedBox(height: BlTokens.space2),
            ],
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
                          label: Text(reportPresetLabel(s, preset)),
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
                data: (built) {
                  // M46: a report that declares a chart, and whose table
                  // still has the columns it names, can be drawn: off the
                  // builder's own table, never the arranged one.
                  final spec = _entry.chart;
                  var chart = spec == null ? null : chartOf(built, spec);
                  // M67: a trend drawn over last period's, lighter.
                  if (chart != null && chart.form == ChartForm.trend) {
                    final before = ref
                        .watch(_previousProvider(request))
                        .valueOrNull;
                    chart = compareWithPrevious(
                      chart,
                      before == null ? null : chartOf(before, spec!),
                    );
                  }
                  final table = _arrange(built);
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
                      else ...[
                        // M67: the columns, a filter on any of them, and
                        // the buckets an ageing report is cut into.
                        ReportTableTools(
                          table: built,
                          arrangement: _arrangement,
                          onArranged: _arrangeAs,
                          ageing: _ageingKinds.contains(widget.kind)
                              ? shelf.ageing
                              : null,
                          onAgeing: (b) => ref
                              .read(reportShelfProvider.notifier)
                              .setAgeing(b),
                        ),
                        ReportTableView(
                          table: table,
                          canOpen: _canOpen,
                          onOpen: _open,
                          itemId:
                              _filters.itemId, // M45: its quantities in packs
                          // M61: the sort a view keeps, and the one it saves.
                          sortColumn: _sortColumn,
                          sortAscending: _sortAscending,
                          onSorted: (column, ascending) {
                            _sortColumn = column;
                            _sortAscending = ascending;
                          },
                        ),
                      ],
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
          in ref.watch(_previousProvider(request)).valueOrNull?.summary ??
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
