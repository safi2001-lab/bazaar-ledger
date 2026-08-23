import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pk_domain/pk_domain.dart';

import 'escpos.dart';
import 'receipt_layout.dart';

/// Renders receipts to thermal bytes and to PDF.
///
/// Pure Dart with no Flutter dependency, so the whole of it is testable
/// headless and the byte stream can be asserted command by command.
final class ThermalReceiptRenderer implements ReceiptRenderer {
  const ThermalReceiptRenderer();

  @override
  Uint8List toThermalBytes(
    ReceiptData data, {
    ReceiptPaper paper = ReceiptPaper.mm80,
    bool openDrawer = false,
    bool cut = true,
  }) {
    final layout = ReceiptLayout(paper: paper);
    final out = EscPos()
      ..initialise()
      // PC437. The receipt is Roman Urdu in Latin script, so the ASCII path
      // covers the common case and nothing needs a code page the printer might
      // not have.
      ..codePage(0);

    if (data.shop.logo != null) {
      out
        ..align(EscPosAlign.centre)
        ..raster(data.shop.logo!)
        ..line();
    }

    // The shop name large, then everything else in Font A so the column
    // arithmetic in the layout holds.
    out
      ..align(EscPosAlign.centre)
      ..bold()
      ..size(width: 2, height: 2)
      ..line(_clipDouble(data.shop.name.toUpperCase(), paper))
      ..size()
      ..bold(on: false)
      ..align(EscPosAlign.left);

    final lines = layout.render(data);
    // The shop name is drawn double-size above, so drop the layout's own copy
    // of it rather than printing it twice.
    final nameLines = _headerNameLineCount(data, layout);
    for (final line in lines.skip(nameLines)) {
      out.line(line);
    }

    if (data.bankQr != null) {
      out
        ..line()
        ..align(EscPosAlign.centre)
        ..raster(data.bankQr!)
        ..align(EscPosAlign.left);
    }

    out.feed(3);
    if (openDrawer) out.openDrawer();
    if (cut) out.cut();
    return out.bytes;
  }

  /// The plain-text receipt, for the on-screen print preview.
  ///
  /// The same strings the printer is handed, so what the shopkeeper approves
  /// is what comes out of the machine.
  List<String> toPreview(
    ReceiptData data, {
    ReceiptPaper paper = ReceiptPaper.mm80,
  }) =>
      ReceiptLayout(paper: paper).render(data);

  @override
  Future<Uint8List> toPdf(
    ReceiptData data, {
    PdfPageFormat format = PdfPageFormat.a5,
  }) async {
    final doc = pw.Document(
      title: 'Invoice ${data.docNo}',
      author: data.shop.name,
    );

    // Courier throughout the numeric columns: it is a Type 1 base font, so it
    // needs no embedding, and its figures are tabular, which is the whole
    // requirement for a column of money.
    final mono = pw.Font.courier();
    final monoBold = pw.Font.courierBold();
    final sans = pw.Font.helvetica();
    final sansBold = pw.Font.helveticaBold();

    pw.Widget totalRow(String label, String value, {bool emphasis = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                label,
                style: pw.TextStyle(
                  font: emphasis ? sansBold : sans,
                  fontSize: emphasis ? 11 : 9,
                ),
              ),
              pw.Text(
                value,
                style: pw.TextStyle(
                  font: emphasis ? monoBold : mono,
                  fontSize: emphasis ? 11 : 9,
                ),
              ),
            ],
          ),
        );

    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(
              child: pw.Text(
                data.shop.name.toUpperCase(),
                style: pw.TextStyle(font: sansBold, fontSize: 16),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(
                [
                  data.shop.addressLine1,
                  data.shop.city,
                  data.shop.phone,
                ].whereType<String>().where((s) => s.isNotEmpty).join('  |  '),
                style: pw.TextStyle(font: sans, fontSize: 9),
              ),
            ),
            if (data.shop.ntn != null || data.shop.strn != null) ...[
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(
                  [
                    if (data.shop.ntn != null) 'NTN ${data.shop.ntn}',
                    if (data.shop.strn != null) 'STRN ${data.shop.strn}',
                  ].join('   '),
                  style: pw.TextStyle(font: sans, fontSize: 9),
                ),
              ),
            ],
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1, height: 1),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Bill No: ${data.docNo}',
                      style: pw.TextStyle(font: sansBold, fontSize: 10),
                    ),
                    pw.Text(
                      'Date: ${data.dateTimeLabel}',
                      style: pw.TextStyle(font: sans, fontSize: 9),
                    ),
                    pw.Text(
                      'Cashier: ${data.cashierName}',
                      style: pw.TextStyle(font: sans, fontSize: 9),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (data.customerName != null)
                      pw.Text(
                        data.customerName!,
                        style: pw.TextStyle(font: sansBold, fontSize: 10),
                      ),
                    if (data.customerPhone != null)
                      pw.Text(
                        data.customerPhone!,
                        style: pw.TextStyle(font: sans, fontSize: 9),
                      ),
                    if (data.isReprint)
                      pw.Text(
                        'REPRINT',
                        style: pw.TextStyle(font: sansBold, fontSize: 9),
                      ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              headers: const ['#', 'Item', 'Qty', 'Rate', 'Amount'],
              headerStyle: pw.TextStyle(font: sansBold, fontSize: 9),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellStyle: pw.TextStyle(font: sans, fontSize: 9),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: const pw.FixedColumnWidth(18),
                1: const pw.FlexColumnWidth(4),
                2: const pw.FlexColumnWidth(1.4),
                3: const pw.FlexColumnWidth(1.6),
                4: const pw.FlexColumnWidth(1.8),
              },
              cellDecoration: (i, dynamic v, j) => const pw.BoxDecoration(),
              data: [
                for (var i = 0; i < data.lines.length; i++)
                  [
                    '${i + 1}',
                    data.lines[i].name +
                        (data.lines[i].isFreeItem ? '  (free)' : ''),
                    '${data.lines[i].qtyDisplay} ${data.lines[i].unitCode}',
                    data.lines[i].rate.amountOnly,
                    data.lines[i].amount.amountOnly,
                  ],
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Expanded(flex: 3, child: pw.SizedBox()),
                pw.Expanded(
                  flex: 4,
                  child: pw.Column(
                    children: [
                      totalRow('Subtotal', data.subtotal.amountOnly),
                      if (data.discount.isPositive)
                        totalRow('Discount', '-${data.discount.amountOnly}'),
                      if (data.tax.isPositive)
                        totalRow('Sales Tax', data.tax.amountOnly),
                      if (data.furtherTax.isPositive)
                        totalRow('Further Tax', data.furtherTax.amountOnly),
                      if (data.extraCharges.isPositive)
                        totalRow(
                          'Other Charges',
                          data.extraCharges.amountOnly,
                        ),
                      if (!data.roundOff.isZero)
                        totalRow(
                          'Round Off',
                          data.roundOff.signed.replaceAll('Rs ', ''),
                        ),
                      pw.Divider(thickness: 1, height: 6),
                      totalRow(
                        'TOTAL',
                        'Rs ${data.total.amountOnly}',
                        emphasis: true,
                      ),
                      for (final t in data.tenders)
                        totalRow(t.label, t.amount.amountOnly),
                      if (data.change.isPositive)
                        totalRow('Change', data.change.amountOnly),
                      if (data.balance.isPositive)
                        totalRow(
                          'Baqaya (udhaar)',
                          data.balance.amountOnly,
                          emphasis: true,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            pw.Spacer(),
            if (data.shop.raastAlias != null || data.shop.bankIban != null) ...[
              pw.Divider(thickness: 0.5, height: 8),
              pw.Text(
                'Payment ke liye',
                style: pw.TextStyle(font: sansBold, fontSize: 9),
              ),
              // Text, never a generated QR. The scheme identifier in an
              // interoperable QR is issued by the State Bank to licensed
              // PSO/PSPs only.
              if (data.shop.raastAlias != null)
                pw.Text(
                  'Raast: ${data.shop.raastAlias}',
                  style: pw.TextStyle(font: mono, fontSize: 9),
                ),
              if (data.shop.bankIban != null)
                pw.Text(
                  '${data.shop.bankName ?? 'Bank'}: '
                  '${data.shop.bankIban}'
                  '${data.shop.bankAccountTitle != null ? '  (${data.shop.bankAccountTitle})' : ''}',
                  style: pw.TextStyle(font: mono, fontSize: 9),
                ),
            ],
            if (data.footerLines.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.Text(
                  data.footerLines.join('   '),
                  style: pw.TextStyle(font: sans, fontSize: 9),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return doc.save();
  }

  /// How many of the layout's leading lines are the shop name, so the caller
  /// can skip them after drawing it double-size.
  static int _headerNameLineCount(ReceiptData data, ReceiptLayout layout) {
    final rendered = layout.render(data);
    final name = data.shop.name.toUpperCase();
    var count = 0;
    var consumed = 0;
    for (final line in rendered) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) break;
      if (consumed >= name.replaceAll(' ', '').length) break;
      if (!name.replaceAll(' ', '').contains(trimmed.replaceAll(' ', ''))) {
        break;
      }
      consumed += trimmed.replaceAll(' ', '').length;
      count++;
    }
    return count;
  }

  static String _clipDouble(String s, ReceiptPaper paper) {
    final max = paper.columns ~/ 2;
    return s.length <= max ? s : s.substring(0, max);
  }
}
