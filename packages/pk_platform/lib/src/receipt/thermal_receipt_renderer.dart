import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pk_domain/pk_domain.dart';

import 'escpos.dart';
import 'printable.dart';
import 'receipt_layout.dart';

/// A run of text in the PDF, laid out right to left when it is not Latin.
///
/// The pdf package applies the bidirectional algorithm only when the
/// direction is RTL, and that is also where its Arabic joining lives. A
/// string left at the default prints as isolated, unjoined letters in logical
/// order — unreadable, and it reads as a missing font rather than as a
/// direction that was never set.
///
/// Per string rather than per document, because a receipt is mixed: the
/// labels and every money column are Latin and have to stay that way, and
/// only the shop's own words are not.
pw.Widget _pdfText(String value, {required pw.TextStyle style}) => pw.Text(
  value,
  style: style,
  textDirection: isPrintableLatin(value) ? null : pw.TextDirection.rtl,
);

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
    Map<String, MonoBitmap> drawn = const {},
  }) {
    final layout = ReceiptLayout(paper: paper);
    final out = EscPos()
      ..initialise()
      // PC437. The receipt is Roman Urdu in Latin script, so the ASCII path
      // covers the common case and nothing needs a code page the printer might
      // not have.
      ..codePage(0)
      // Font A, explicitly, because the layout's column count depends on it
      // and the default is not the same on every machine. `ESC @` above
      // resets to the printer's OWN default, which is not necessarily this
      // one — and a receipt laid out for 48 columns that meets a printer
      // sitting in a 42-column font wraps every single line.
      ..font(EscPosFont.a);

    if (data.shop.logo != null) {
      out
        ..align(EscPosAlign.centre)
        ..raster(data.shop.logo!)
        ..line();
    }

    // The shop name large, then everything else in Font A so the column
    // arithmetic in the layout holds.
    final name = data.shop.name.toUpperCase();
    final nameBitmap = drawn[name];
    out.align(EscPosAlign.centre);
    if (nameBitmap != null) {
      // Drawn, not typed. A shop called `الفلاح سٹور` has no byte sequence any
      // printer would render, so the name arrives as pixels or as question
      // marks, and question marks on the top line of every receipt a shop
      // hands out is not a thing to ship.
      out.raster(nameBitmap);
    } else {
      out
        ..bold()
        ..size(width: 2, height: 2)
        ..lines(_wrapDouble(name, paper))
        ..size()
        ..bold(on: false);
    }
    out.align(EscPosAlign.left);

    final lines = layout.render(data);
    // The shop name is drawn double-size above, so drop the layout's own copy
    // of it rather than printing it twice.
    final nameLines = _headerNameLineCount(data, layout);
    for (final line in lines.skip(nameLines)) {
      final bitmap = drawn[line];
      if (bitmap == null) {
        // Either it is Latin, or nobody supplied a picture of it. The encoder
        // replaces what it cannot represent, so this degrades to question
        // marks rather than to a code page byte the printer would draw as an
        // unrelated glyph — legibly wrong beats illegibly wrong.
        out.line(line);
      } else {
        out.raster(bitmap);
      }
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

  /// Every line of this receipt that has to be drawn instead of typed.
  ///
  /// Lives on the renderer rather than beside [isPrintableLatin] because only
  /// the renderer knows what it actually emits. The layout puts the shop name
  /// in the body and the renderer prints its own larger copy above instead,
  /// skipping the layout's; a survey that walked the layout alone would name
  /// a line nobody prints, and the caller would rasterise it — a wasted image
  /// per receipt, on a phone, on the path with a customer waiting.
  ///
  /// Returned as the exact strings the renderer will look up, because that is
  /// the key each picture comes back under. Whole lines, never fragments: an
  /// `Customer` label beside an Urdu name is one string with an LTR run and an
  /// RTL one in it, and deciding the order of those is the bidirectional
  /// algorithm's job, done once, by a text engine that has one.
  @override
  Set<String> unprintableLines(
    ReceiptData data, {
    ReceiptPaper paper = ReceiptPaper.mm80,
  }) {
    final layout = ReceiptLayout(paper: paper);
    final needed = <String>{};
    for (final line in layout.render(data).skip(
      _headerNameLineCount(data, layout),
    )) {
      if (line.trim().isEmpty) continue;
      if (!isPrintableLatin(line)) needed.add(line);
    }
    // The name as the renderer prints it: uppercased, and its own line.
    final name = data.shop.name.toUpperCase();
    if (!isPrintableLatin(name)) needed.add(name);
    return needed;
  }

  /// The plain-text receipt, for the on-screen print preview.
  ///
  /// The same strings the printer is handed, so what the shopkeeper approves
  /// is what comes out of the machine.
  @override
  List<String> toPreview(
    ReceiptData data, {
    ReceiptPaper paper = ReceiptPaper.mm80,
  }) => ReceiptLayout(paper: paper).render(data);

  @override
  Future<Uint8List> toPdf(
    ReceiptData data, {
    PdfPageFormat format = PdfPageFormat.a5,
    Uint8List? unicodeFont,
  }) async {
    // Without a face that has the glyphs, Urdu in the PDF does not become
    // question marks — it becomes nothing. Courier and Helvetica are Type 1
    // base fonts: no embedding, tabular figures, and no Unicode at all. The
    // pdf package says so on stderr and carries on with a blank where the
    // shop's name should be.
    //
    // A PDF has no system font fallback to lean on the way the thermal path
    // does, because the file is read on somebody else's phone. The face has
    // to travel inside it.
    //
    // Handed in as bytes rather than loaded here, because this package has no
    // Flutter and therefore no asset bundle — and keeping it that way is what
    // makes the receipt path testable headless.
    final fallback = unicodeFont == null
        ? null
        : pw.Font.ttf(ByteData.view(unicodeFont.buffer));

    final doc = pw.Document(
      title: '${data.docTitle} ${data.docNo}',
      author: data.shop.name,
      // A fallback, not a replacement. Every Latin run keeps Courier's
      // tabular figures — which is the whole reason a column of money is
      // readable — and only the glyphs Helvetica cannot draw come from here.
      theme: fallback == null
          ? null
          : pw.ThemeData.withFont(fontFallback: [fallback]),
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

    // MultiPage, not Page. A single fixed page clipped or threw on a
    // wholesale bill of thirty or forty lines — which is the bill a
    // distributor actually prints, and the one where losing lines matters
    // most. The header repeats on every sheet so page two is still a receipt
    // rather than an orphaned table.
    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(24),
        // The shop's own identity, on every sheet. It was inside `build:`,
        // which puts it on page one only — so page two of a wholesale bill
        // was an orphaned table with no shop name, no bill number and no
        // date, which is exactly the failure the switch to MultiPage was
        // supposed to fix.
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox.shrink()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    _pdfText(
                      data.shop.name.toUpperCase(),
                      style: pw.TextStyle(
                        font: pw.Font.helveticaBold(),
                        fontSize: 11,
                      ),
                    ),
                    pw.Text(
                      '${data.docLabel}: ${data.docNo}   ${data.dateTimeLabel}',
                      style: pw.TextStyle(
                        font: pw.Font.helvetica(),
                        fontSize: 9,
                      ),
                    ),
                    pw.Divider(thickness: 0.5, height: 6),
                  ],
                ),
              ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${data.docNo}   ${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(font: pw.Font.helvetica(), fontSize: 8),
          ),
        ),
        build: (context) => [
          pw.Center(
            child: _pdfText(
              data.shop.name.toUpperCase(),
              style: pw.TextStyle(font: sansBold, fontSize: 16),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: _pdfText(
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
                    '${data.docLabel}: ${data.docNo}',
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
                    _pdfText(
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
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
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
                  _pdfText(
                    data.lines[i].name +
                        (data.lines[i].isFreeItem ? '  (free)' : ''),
                    style: pw.TextStyle(font: sans, fontSize: 9),
                  ),
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
                    if (data.withholding.isPositive)
                      totalRow(
                        'Withholding',
                        '-${data.withholding.amountOnly}',
                      ),
                    if (data.extraCharges.isPositive)
                      totalRow('Other Charges', data.extraCharges.amountOnly),
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
          // No Spacer: MultiPage has no fixed height to push against.
          pw.SizedBox(height: 12),
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
    );

    return doc.save();
  }

  /// How many of the layout's leading lines are the shop name, so the caller
  /// can skip them after drawing it double-size.
  static int _headerNameLineCount(ReceiptData data, ReceiptLayout layout) {
    final rendered = layout.render(data);
    // All whitespace, not only spaces. `_wrap` splits on `\s+`, so a tab or
    // a newline pasted into the shop name from a form left the name unmatched
    // on the first line, the count at zero, and the name printed twice.
    String bare(String s) => s.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    final name = data.shop.name.toUpperCase();
    var count = 0;
    var consumed = 0;
    for (final line in rendered) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) break;
      if (consumed >= bare(name).length) break;
      if (!bare(name).contains(bare(trimmed))) break;
      consumed += bare(trimmed).length;
      count++;
    }
    return count;
  }

  /// The shop name at double width, wrapped rather than cut.
  ///
  /// Double-size glyphs are twice as wide, so only half the columns fit — 24
  /// at 80mm, 16 at 58mm. Truncating there printed "Al-Madina Kiryan" for a
  /// shop the preview showed in full, which breaks the one promise this file
  /// makes: what the shopkeeper approves on screen is what comes out of the
  /// machine.
  static List<String> _wrapDouble(String s, ReceiptPaper paper) {
    final max = paper.columns ~/ 2;
    final out = <String>[];
    var current = '';
    for (final word in s.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final candidate = current.isEmpty ? word : '$current $word';
      if (candidate.length <= max) {
        current = candidate;
        continue;
      }
      if (current.isNotEmpty) out.add(current);
      // A single word longer than the line is broken rather than dropped.
      var rest = word;
      while (rest.length > max) {
        out.add(rest.substring(0, max));
        rest = rest.substring(max);
      }
      current = rest;
    }
    if (current.isNotEmpty) out.add(current);
    return out.isEmpty ? [''] : out;
  }
}
