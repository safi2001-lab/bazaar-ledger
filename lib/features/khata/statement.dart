import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../l10n/app_strings.dart';
import '../printing/pdf_font.dart';

/// How far back a statement goes.
enum StatementSpan { thisMonth, lastMonth, thisYear, all }

/// One party's statement of account over [span], from the same ledger the
/// khata screen shows (M24). A customer's is what they owe the shop; a
/// supplier's, what the shop owes them.
Future<ReportTable> statementFor(
  AppServices services,
  PartySummary party, {
  required StatementSpan span,
  required bool owedToUs,
}) async {
  final firmId = (await services.queries.currentFirm())!.id;
  final entries = owedToUs
      ? await services.queries.partyLedger(firmId, party.id, limit: 100000)
      : await services.queries.payablesLedger(firmId, party.id, limit: 100000);
  final today = BusinessDate.now(services.clock);
  final period = switch (span) {
    StatementSpan.thisMonth => ReportPeriod.monthOf(today),
    StatementSpan.lastMonth => ReportPeriod.monthBefore(today),
    StatementSpan.thisYear => ReportPeriod.fiscalYearOf(today),
    StatementSpan.all => ReportPeriod(
      BusinessDate(
        entries.isEmpty || entries.first.dateLocal.compareTo(today.value) > 0
            ? today.value
            : entries.first.dateLocal,
      ),
      today,
    ),
  };
  return partyStatement(
    partyName: party.name,
    period: period,
    entries: entries,
    owedToUs: owedToUs,
  );
}

/// Asks how far back, then hands the statement to the share sheet as a PDF.
Future<void> shareStatement(
  BuildContext context,
  WidgetRef ref,
  PartySummary party, {
  required bool owedToUs,
}) async {
  final s = AppStrings.of(context);
  final span = await showModalBottomSheet<StatementSpan>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (span, label) in [
            (StatementSpan.thisMonth, s.statementThisMonth),
            (StatementSpan.lastMonth, s.statementLastMonth),
            (StatementSpan.thisYear, s.statementThisYear),
            (StatementSpan.all, s.statementAll),
          ])
            ListTile(
              leading: const Icon(Icons.date_range_outlined),
              title: Text(label),
              onTap: () => Navigator.of(context).pop(span),
            ),
        ],
      ),
    ),
  );
  if (span == null || !context.mounted) return;
  final services = ref.read(appServicesProvider);
  final messenger = ScaffoldMessenger.of(context);
  try {
    final table = await statementFor(
      services,
      party,
      span: span,
      owedToUs: owedToUs,
    );
    final firm = await ref.read(firmProvider.future);
    final bytes = await reportToPdf(
      table,
      shopName: firm?.name ?? '',
      unicodeFont: await PdfUnicodeFont.bytes(),
    );
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}'
      '${reportFileName(table, extension: 'pdf')}',
    );
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: '${table.title}, ${table.period.label}',
      ),
    );
  } on Object catch (error) {
    messenger.showSnackBar(SnackBar(content: Text('$error')));
  }
}
