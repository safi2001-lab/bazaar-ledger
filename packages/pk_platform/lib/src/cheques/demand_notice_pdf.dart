import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pk_domain/pk_domain.dart';

import '../receipt/printable.dart';

/// A bounced cheque's demand notice, as an A4 page ready to print and sign.
///
/// Set the way such notices are typed in the courts: sender at the top, the
/// date, the addressee, a subject line in capitals, numbered paragraphs, and
/// a signature line for the shop. English, because that is the language the
/// notice is filed in; the shop's and the customer's names can be in Urdu,
/// and [unicodeFont] is what lets them survive into the file.
///
/// [compress] is for tests, which read the words back out of the page.
Future<Uint8List> demandNoticePdf(
  DemandNotice notice, {
  Uint8List? unicodeFont,
  bool compress = true,
}) async {
  final fallback = unicodeFont == null
      ? null
      : pw.Font.ttf(ByteData.view(unicodeFont.buffer));
  final doc = pw.Document(
    title: notice.title,
    author: notice.shopName,
    compress: compress,
    theme: fallback == null
        ? null
        : pw.ThemeData.withFont(fontFallback: [fallback]),
  );

  final sans = pw.Font.helvetica();
  final sansBold = pw.Font.helveticaBold();
  final body = pw.TextStyle(font: sans, fontSize: 11, lineSpacing: 3);
  final bold = pw.TextStyle(font: sansBold, fontSize: 11);

  // A name in Urdu is set right to left; everything else as it is.
  pw.Widget line(String value, {pw.TextStyle? style}) => pw.Text(
    value,
    style: style ?? body,
    textDirection: isPrintableLatin(value) ? null : pw.TextDirection.rtl,
  );

  pw.Widget block(List<String> lines, {bool firstBold = true}) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < lines.length; i++)
        line(lines[i], style: i == 0 && firstBold ? bold : body),
    ],
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(56, 48, 56, 48),
      build: (context) => [
        block(notice.from),
        pw.SizedBox(height: 16),
        pw.Text('Dated: ${formatNoticeDate(notice.issuedOn)}', style: body),
        pw.SizedBox(height: 16),
        pw.Text('To,', style: body),
        block(notice.to),
        pw.SizedBox(height: 20),
        pw.Text(
          'Subject: ${notice.subject}',
          style: pw.TextStyle(font: sansBold, fontSize: 11, lineSpacing: 3),
        ),
        pw.SizedBox(height: 16),
        pw.Text('Sir,', style: body),
        pw.SizedBox(height: 8),
        for (final (i, paragraph) in notice.paragraphs.indexed)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 22,
                  child: pw.Text('${i + 1}.', style: body),
                ),
                pw.Expanded(
                  child: pw.Text(
                    paragraph,
                    style: body,
                    textAlign: pw.TextAlign.justify,
                  ),
                ),
              ],
            ),
          ),
        pw.SizedBox(height: 40),
        pw.Container(width: 180, height: 0.8, color: PdfColors.black),
        pw.SizedBox(height: 4),
        pw.Text('Signature', style: body),
        line('For ${notice.shopName}', style: bold),
      ],
    ),
  );
  return doc.save();
}

/// A file name for a notice, safe on any filesystem it lands on.
String demandNoticeFileName(DemandNotice notice) {
  final safe = notice.chequeNo
      .replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_')
      .replaceAll(RegExp(r'^[_-]+|[_-]+$'), '');
  return 'notice-${safe.isEmpty ? 'cheque' : safe}.pdf';
}
