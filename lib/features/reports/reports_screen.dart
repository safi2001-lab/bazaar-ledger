import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../printing/pdf_font.dart';

/// The report pack: did the shop make money this month, and where did it go.
///
/// Every figure is computed by `pk_reports` from the books before it gets
/// here. This screen lays the table out and adds nothing up itself.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.reportsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            for (final kind in ReportKind.values)
              Padding(
                padding: const EdgeInsets.only(bottom: BlTokens.space2),
                child: BlCard(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ReportScreen(kind: kind),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(_icon(kind), color: t.inkMuted),
                      const SizedBox(width: BlTokens.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              reportName(s, kind),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: t.ink,
                              ),
                            ),
                            Text(
                              _hint(s, kind),
                              style: TextStyle(fontSize: 13, color: t.inkMuted),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: t.inkMuted),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static IconData _icon(ReportKind kind) => switch (kind) {
    ReportKind.profitAndLoss => Icons.trending_up,
    ReportKind.salesByDay => Icons.calendar_month_outlined,
    ReportKind.receivables => Icons.hourglass_bottom_outlined,
    ReportKind.payables => Icons.local_shipping_outlined,
    ReportKind.trialBalance => Icons.balance_outlined,
    ReportKind.balanceSheet => Icons.account_balance_outlined,
    ReportKind.expiry => Icons.event_busy_outlined,
    ReportKind.salesByItem => Icons.shopping_basket_outlined,
    ReportKind.expenses => Icons.receipt_outlined,
    ReportKind.cashBook => Icons.point_of_sale_outlined,
    ReportKind.dayBook => Icons.menu_book_outlined,
    ReportKind.stockValue => Icons.inventory_2_outlined,
  };

  static String _hint(AppStrings s, ReportKind kind) => switch (kind) {
    ReportKind.profitAndLoss => s.reportProfitAndLossHint,
    ReportKind.salesByDay => s.reportSalesByDayHint,
    ReportKind.receivables => s.reportReceivablesHint,
    ReportKind.payables => s.reportPayablesHint,
    ReportKind.trialBalance => s.reportTrialBalanceHint,
    ReportKind.balanceSheet => s.reportBalanceSheetHint,
    ReportKind.expiry => s.reportExpiryHint,
    ReportKind.salesByItem => s.reportSalesByItemHint,
    ReportKind.expenses => s.reportExpensesHint,
    ReportKind.cashBook => s.reportCashBookHint,
    ReportKind.dayBook => s.reportDayBookHint,
    ReportKind.stockValue => s.reportStockValueHint,
  };
}

/// A report's name as the shop reads it.
String reportName(AppStrings s, ReportKind kind) => switch (kind) {
  ReportKind.profitAndLoss => s.reportProfitAndLoss,
  ReportKind.salesByDay => s.reportSalesByDay,
  ReportKind.receivables => s.reportReceivables,
  ReportKind.payables => s.reportPayables,
  ReportKind.trialBalance => s.reportTrialBalance,
  ReportKind.balanceSheet => s.reportBalanceSheet,
  ReportKind.expiry => s.reportExpiry,
  ReportKind.salesByItem => s.reportSalesByItem,
  ReportKind.expenses => s.reportExpenses,
  ReportKind.cashBook => s.reportCashBook,
  ReportKind.dayBook => s.reportDayBook,
  ReportKind.stockValue => s.reportStockValue,
};

/// The periods offered, as the shop says them.
enum _Span { today, thisMonth, lastMonth, thisYear }

typedef _Request = ({ReportKind kind, ReportPeriod period});

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
      );
    });

/// One report, for the period chosen.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({required this.kind, super.key});

  final ReportKind kind;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  late _Span _span = switch (widget.kind) {
    ReportKind.cashBook || ReportKind.dayBook => _Span.today,
    _ => _Span.thisMonth,
  };
  bool _sharing = false;

  bool get _hasPeriod => !ReportEngine.isAsOfToday(widget.kind);

  ReportPeriod _period(BusinessDate today) => switch (_span) {
    _Span.today => ReportPeriod.day(today),
    _Span.thisMonth => ReportPeriod.monthOf(today),
    _Span.lastMonth => ReportPeriod.monthBefore(today),
    _Span.thisYear => ReportPeriod.fiscalYearOf(today),
  };

  /// Sends [table] on as a CSV, or as a PDF when [pdf].
  Future<void> _share(ReportTable table, {required bool pdf}) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final List<int> bytes;
      if (pdf) {
        final firm = await ref.read(firmProvider.future);
        bytes = await reportToPdf(
          table,
          shopName: firm?.name ?? '',
          unicodeFont: await PdfUnicodeFont.bytes(),
        );
      } else {
        bytes = reportToCsvBytes(table);
      }
      final dir = await getTemporaryDirectory();
      final name = reportFileName(table, extension: pdf ? 'pdf' : 'csv');
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(file.path, mimeType: pdf ? 'application/pdf' : 'text/csv'),
          ],
          subject: '${table.title}, ${table.period.label}',
        ),
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final today = BusinessDate.now(ref.watch(appServicesProvider).clock);
    final period = _period(today);
    final report = ref.watch(
      _reportProvider((kind: widget.kind, period: period)),
    );

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(
        title: Text(reportName(s, widget.kind)),
        actions: [
          if (report.valueOrNull case final table?) ...[
            BlIconButton(
              icon: Icons.picture_as_pdf_outlined,
              label: s.reportSharePdf,
              onPressed: _sharing
                  ? null
                  : () => unawaited(_share(table, pdf: true)),
            ),
            BlIconButton(
              icon: Icons.table_view_outlined,
              label: s.reportShareCsv,
              onPressed: _sharing
                  ? null
                  : () => unawaited(_share(table, pdf: false)),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            if (_hasPeriod)
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space2,
                children: [
                  for (final span in _Span.values)
                    ChoiceChip(
                      selected: span == _span,
                      label: Text(switch (span) {
                        _Span.today => s.reportToday,
                        _Span.thisMonth => s.reportThisMonth,
                        _Span.lastMonth => s.reportLastMonth,
                        _Span.thisYear => s.reportThisYear,
                      }),
                      onSelected: (_) => setState(() => _span = span),
                    ),
                ],
              )
            else
              Text(
                s.reportAsOfNow,
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
            const SizedBox(height: BlTokens.space2),
            Text(
              _hasPeriod ? period.label : today.value,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            const SizedBox(height: BlTokens.space3),
            report.when(
              loading: () => const BlSkeletonList(rows: 6),
              error: (error, _) => BlError(
                title: s.commonSomethingWentWrong,
                message: '$error',
                retryLabel: s.actionRetry,
                onRetry: () => ref.invalidate(_reportProvider),
              ),
              data: (table) => _Table(table: table),
            ),
          ],
        ),
      ),
    );
  }
}

/// The table as computed, one row per row, totals in bold.
class _Table extends StatelessWidget {
  const _Table({required this.table});

  final ReportTable table;

  @override
  Widget build(BuildContext context) {
    final t = context.bl;
    final columns = table.columns;

    Widget cell(Object? value, int i, RowStyle style) {
      final numeric = columns[i].isNumeric && style != RowStyle.heading;
      final strong = style != RowStyle.line;
      final negative = switch (value) {
        final Money m => m.isNegative,
        _ => false,
      };
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BlTokens.space2,
          vertical: BlTokens.space1 + 2,
        ),
        child: Text(
          reportCellText(value, columns[i].kind),
          textAlign: numeric ? TextAlign.end : TextAlign.start,
          style: TextStyle(
            fontSize: 14,
            fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
            color: negative ? t.danger : t.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BlCard(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: t.line)),
                  ),
                  children: [
                    for (var i = 0; i < columns.length; i++)
                      Padding(
                        padding: const EdgeInsets.all(BlTokens.space2),
                        child: Text(
                          columns[i].title,
                          textAlign: columns[i].isNumeric
                              ? TextAlign.end
                              : TextAlign.start,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: t.inkMuted,
                          ),
                        ),
                      ),
                  ],
                ),
                for (final row in table.rows)
                  TableRow(
                    decoration: row.style == RowStyle.total
                        ? BoxDecoration(
                            border: Border(top: BorderSide(color: t.line)),
                          )
                        : null,
                    children: [
                      for (var i = 0; i < columns.length; i++)
                        cell(row.cells[i], i, row.style),
                    ],
                  ),
              ],
            ),
          ),
        ),
        for (final note in table.notes) ...[
          const SizedBox(height: BlTokens.space2),
          Text(note, style: TextStyle(fontSize: 13, color: t.inkMuted)),
        ],
      ],
    );
  }
}

/// A cell as the screen writes it.
String reportCellText(Object? value, CellKind kind) => switch (value) {
  null => '',
  final Money m => m.amountOnly,
  final Qty q => q.display,
  final int bp when kind == CellKind.percent => formatBp(bp),
  _ => '$value',
};
