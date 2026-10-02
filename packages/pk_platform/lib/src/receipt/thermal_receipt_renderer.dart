import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pk_domain/pk_domain.dart';

import 'bill_pdf.dart';
import 'escpos.dart';
import 'fbr_qr.dart';
import 'printable.dart';
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

    // Neither picture goes on the transporter's copy (M51): one is how to
    // pay and the other is a tax invoice's number, and that sheet carries
    // neither money nor tax.
    if (data.bankQr != null && data.showsMoney) {
      out
        ..line()
        ..align(EscPosAlign.centre)
        ..raster(data.bankQr!)
        ..align(EscPosAlign.left);
    }

    // FBR's number as a QR, under the number printed as text (M19).
    if (data.fbrInvoiceNo case final fbrNo? when data.showsMoney) {
      out
        ..align(EscPosAlign.centre)
        ..raster(fbrQrBitmap(fbrNo, widthDots: paper.dots))
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
    for (final line
        in layout.render(data).skip(_headerNameLineCount(data, layout))) {
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
    PdfPageFormat? format,
    Uint8List? unicodeFont,
    BillDesign design = const BillDesign(),
    bool compress = true,
  }) =>
      // The PDF lives in its own file since M51, where the shop's design
      // decides its layout, colour and page. [format] still overrides the
      // page for callers that need a particular sheet.
      billPdf(
        data,
        design: design,
        unicodeFont: unicodeFont,
        format: format,
        compress: compress,
      );

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
