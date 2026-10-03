import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus/share_plus.dart';

import '../printing/pdf_font.dart';

/// The files a report goes out as (M33).
enum ReportFormat {
  /// For WhatsApp and the printer: Android prints a PDF from any viewer.
  pdf('pdf', 'application/pdf'),

  /// For the accountant who asks for Excel by name.
  xlsx(
    'xlsx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ),

  /// For any spreadsheet at all.
  csv('csv', 'text/csv');

  const ReportFormat(this.extension, this.mimeType);

  final String extension;
  final String mimeType;
}

/// Writes [table] as [format] and hands it to the share sheet. Every figure
/// in the file is the table's own; nothing is added up here.
Future<void> shareReport(
  ReportTable table,
  ReportFormat format, {
  required String shopName,
}) async {
  final List<int> bytes = switch (format) {
    ReportFormat.pdf => await reportToPdf(
      table,
      shopName: shopName,
      unicodeFont: await PdfUnicodeFont.bytes(),
    ),
    ReportFormat.xlsx => reportToXlsx(table, shopName: shopName),
    ReportFormat.csv => reportToCsvBytes(table),
  };
  final dir = await getTemporaryDirectory();
  final name = reportFileName(table, extension: format.extension);
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: format.mimeType)],
      subject: '${table.title}, ${table.period.label}',
    ),
  );
}

/// How a report screen sends a table out (M67): [shareReport], unless a
/// test stands in for the share sheet to read what would have gone, so a
/// test can hold an export to the columns and rows the shop arranged.
typedef ReportSharer =
    Future<void> Function(
      ReportTable table,
      ReportFormat format, {
      required String shopName,
    });

final reportSharerProvider = Provider<ReportSharer>((ref) => shareReport);
