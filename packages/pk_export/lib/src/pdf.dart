import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';

/// A report as an A4 page, for WhatsApp or the printer.
///
/// The table as computed: headings, lines, subtotals and the total in bold,
/// numbers right-aligned, then the notes. [shopName] heads the page, because
/// a PDF forwarded twice has lost every other clue whose figures these are.
/// [unicodeFont] lets an Urdu item or customer name survive into the file.
///
/// [compress] is for tests, which read the words back out of the page.
Future<Uint8List> reportToPdf(
  ReportTable table, {
  required String shopName,
  Uint8List? unicodeFont,
  bool compress = true,
}) async {
  final fallback = unicodeFont == null
      ? null
      : pw.Font.ttf(ByteData.view(unicodeFont.buffer));
  final doc = pw.Document(
    title: '${table.title}, ${table.period.label}',
    author: shopName,
    compress: compress,
    theme: fallback == null
        ? null
        : pw.ThemeData.withFont(fontFallback: [fallback]),
  );

  final sans = pw.Font.helvetica();
  final sansBold = pw.Font.helveticaBold();
  final columns = table.columns;
  final wide = columns.length > 5;

  pw.Widget cell(Object? value, int i, {required bool strong}) {
    final text = _cellText(value, columns[i].kind);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Text(
        text,
        textAlign: columns[i].isNumeric ? pw.TextAlign.right : null,
        textDirection: _isLatin(text) ? null : pw.TextDirection.rtl,
        style: pw.TextStyle(
          font: strong ? sansBold : sans,
          fontSize: wide ? 8 : 10,
        ),
      ),
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: wide ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      header: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            shopName,
            textDirection: _isLatin(shopName) ? null : pw.TextDirection.rtl,
            style: pw.TextStyle(font: sansBold, fontSize: 14),
          ),
          pw.Text(
            '${table.title} · ${table.period.label}',
            style: pw.TextStyle(font: sans, fontSize: 11),
          ),
          pw.SizedBox(height: 12),
        ],
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: pw.TextStyle(font: sans, fontSize: 8),
        ),
      ),
      build: (context) => [
        pw.Table(
          border: const pw.TableBorder(
            horizontalInside: pw.BorderSide(width: 1, color: PdfColors.grey400),
          ),
          children: [
            pw.TableRow(
              repeat: true,
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                for (var i = 0; i < columns.length; i++)
                  cell(columns[i].title, i, strong: true),
              ],
            ),
            for (final row in table.rows)
              pw.TableRow(
                decoration: row.style == RowStyle.total
                    ? const pw.BoxDecoration(
                        border: pw.Border(top: pw.BorderSide(width: 1)),
                      )
                    : null,
                children: [
                  for (var i = 0; i < columns.length; i++)
                    cell(row.cells[i], i, strong: row.style != RowStyle.line),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 10),
        for (final note in table.notes)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(note, style: pw.TextStyle(font: sans, fontSize: 9)),
          ),
      ],
    ),
  );
  return doc.save();
}

String _cellText(Object? value, CellKind kind) => switch (value) {
  null => '',
  final Money m => m.amountOnly,
  final Qty q => q.display,
  final int bp when kind == CellKind.percent => formatBp(bp),
  _ => '$value',
};

/// Whether [s] sets in the built-in Latin font, left to right.
bool _isLatin(String s) => s.codeUnits.every((c) => c < 0x250);
