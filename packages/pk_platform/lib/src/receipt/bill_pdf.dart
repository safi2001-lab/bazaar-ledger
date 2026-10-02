import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pk_domain/pk_domain.dart';

import 'printable.dart';

/// A bill as a PDF, in the shop's own design (M51).
///
/// Four layouts — classic, modern, compact and the sales tax invoice — in
/// the shop's colour, with its logo, on A5 or A4. Every one of them is the
/// same bill: the same lines, the same totals, the same marks. What changes
/// is where things sit and how loud they are, never what is said.
///
/// ## What does not change with the design
///
/// * **The faces.** Courier for every figure, because its digits are
///   tabular and a column of money lines up; Helvetica for words. Both are
///   PDF base fonts and travel in no file. [unicodeFont] is a fallback for
///   the glyphs neither has — Urdu, in practice — and only the glyphs used
///   are embedded, so a bill in Roman Urdu costs nothing extra.
/// * **The direction.** Any run that is not Latin is set right to left, which
///   is also where the pdf package does its Arabic joining. A shop name in
///   Urdu left at the default prints as disconnected letters.
/// * **The marks.** CANCELLED in red above everything, and the sheet's own
///   name — ORIGINAL, DUPLICATE, TRIPLICATE, TRANSPORTER — under the shop's.
/// * **No QR is ever made here.** The payment QR is a picture the shop's
///   own bank or wallet gave it, reprinted as it was picked; a page with no
///   picture has no QR at all, only the alias and IBAN as text. The scheme
///   identifier inside a payment QR belongs to the State Bank's licensed
///   PSO/PSPs, and minting one is an offence under s.56 PS&EFT Act.
///
/// ## The transporter's copy
///
/// The same page with every figure that is money taken out: no rate, no
/// amount, no total, no tender, no khata, no payment details. What is left
/// is what the driver needs — what is in the load, how much of it, whose it
/// is, where it goes and on which bilty.
///
/// [format] overrides the design's page size, for tests that need a
/// particular sheet; [compress] is for tests that read words back out.
Future<Uint8List> billPdf(
  ReceiptData data, {
  BillDesign design = const BillDesign(),
  Uint8List? unicodeFont,
  PdfPageFormat? format,
  bool compress = true,
}) async {
  // Handed in as bytes rather than loaded here: this package has no
  // Flutter and so no asset bundle, which is what keeps it testable
  // headless.
  final fallback = unicodeFont == null
      ? null
      : pw.Font.ttf(ByteData.view(unicodeFont.buffer));

  final doc = pw.Document(
    // The marks in the title too (M30), so a viewer's title bar and a file
    // list say what the page says before anybody scrolls.
    title: [
      '${data.docTitle} ${data.docNo}',
      if (data.isCancelled) 'CANCELLED',
      if (data.copyMark case final copy?) copy.titleWord,
    ].join(' - '),
    author: data.shop.name,
    compress: compress,
    // A fallback, not a replacement: every Latin run keeps its base font.
    theme: fallback == null
        ? null
        : pw.ThemeData.withFont(fontFallback: [fallback]),
  );

  final bill = _Bill(data, design);
  doc.addPage(
    pw.MultiPage(
      pageFormat:
          format ??
          (design.pageSize == BillPageSize.a4
              ? PdfPageFormat.a4
              : PdfPageFormat.a5),
      margin: pw.EdgeInsets.all(bill.compact ? 18 : 24),
      // MultiPage, not Page: a wholesale bill of forty lines is the bill a
      // distributor prints, and it must paginate rather than clip. The shop
      // and the bill's number repeat on every sheet after the first, so page
      // two is still a bill and not an orphaned table.
      header: (context) =>
          context.pageNumber == 1 ? pw.SizedBox.shrink() : bill.runningHead(),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${data.docNo}   ${context.pageNumber} / ${context.pagesCount}',
          style: pw.TextStyle(font: bill.sans, fontSize: 8),
        ),
      ),
      build: (context) => bill.body(),
    ),
  );

  return doc.save();
}

/// One bill being laid out: its data, its design, and the pieces every
/// layout is built from.
final class _Bill {
  _Bill(this.d, this.design)
    : accent = PdfColor.fromInt(design.accent.argb),
      tint = _tintOf(PdfColor.fromInt(design.accent.argb)),
      logo = _picture(d.shop.logoImage),
      qr = d.showsMoney ? _picture(d.paymentQr) : null;

  final ReceiptData d;
  final BillDesign design;
  final PdfColor accent;

  /// The accent at a tenth of its strength, for boxes the eye should find
  /// without reading them as a warning.
  final PdfColor tint;
  final pw.ImageProvider? logo;
  final pw.ImageProvider? qr;

  // Base fonts: no embedding, and Courier's figures are tabular.
  final sans = pw.Font.helvetica();
  final sansBold = pw.Font.helveticaBold();
  final mono = pw.Font.courier();
  final monoBold = pw.Font.courierBold();

  bool get compact => design.theme == BillTheme.compact;
  bool get modern => design.theme == BillTheme.modern;
  bool get taxInvoice => design.theme == BillTheme.taxInvoice;
  bool get money => d.showsMoney;

  /// The body size: one point smaller on the compact layout, which is the
  /// whole of how it fits a wholesale bill on one sheet.
  double get size => compact ? 8 : 9;

  static PdfColor _tintOf(PdfColor c) => PdfColor(
    c.red + (1 - c.red) * 0.9,
    c.green + (1 - c.green) * 0.9,
    c.blue + (1 - c.blue) * 0.9,
  );

  /// A picture the owner chose, or null when there is none or it cannot be
  /// read. A logo that will not decode costs the bill its logo, never the
  /// bill.
  static pw.ImageProvider? _picture(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return pw.MemoryImage(bytes);
    } on Object {
      return null;
    }
  }

  static bool _has(String? s) => s != null && s.trim().isNotEmpty;

  // --- Type -----------------------------------------------------------------

  /// Words, set right to left when they are not Latin.
  pw.Widget words(
    String value, {
    double? fontSize,
    bool bold = false,
    PdfColor? color,
    pw.TextAlign? align,
  }) => pw.Text(
    value,
    textAlign: align,
    style: pw.TextStyle(
      font: bold ? sansBold : sans,
      fontSize: fontSize ?? size,
      color: color,
    ),
    textDirection: isPrintableLatin(value) ? null : pw.TextDirection.rtl,
  );

  /// A figure, in the tabular face.
  pw.Widget figure(
    String value, {
    double? fontSize,
    bool bold = false,
    PdfColor? color,
  }) => pw.Text(
    value,
    style: pw.TextStyle(
      font: bold ? monoBold : mono,
      fontSize: fontSize ?? size,
      color: color,
    ),
  );

  /// A label and a value on one line: the label in grey, the value as
  /// words. Kept as two runs so an Urdu value is set right to left without
  /// dragging the Latin label with it.
  pw.Widget labelled(String label, String value, {PdfColor? color}) => pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        '$label: ',
        style: pw.TextStyle(
          font: sans,
          fontSize: size,
          color: color ?? PdfColors.grey700,
        ),
      ),
      pw.Flexible(child: words(value, color: color)),
    ],
  );

  String get shopWhere => [
    d.shop.addressLine1,
    d.shop.city,
    d.shop.phone,
  ].whereType<String>().where((s) => s.trim().isNotEmpty).join('  |  ');

  String get shopTaxIds => [
    if (_has(d.shop.ntn)) 'NTN ${d.shop.ntn}',
    if (_has(d.shop.strn)) 'STRN ${d.shop.strn}',
  ].join('   ');

  /// "SALES TAX INVOICE" on a sale bill in the tax layout; whatever the
  /// paper is everywhere else. A quotation is never called a tax invoice.
  String get title => taxInvoice && d.docTitle == 'Invoice'
      ? 'SALES TAX INVOICE'
      : d.docTitle.toUpperCase();

  // --- The page ---------------------------------------------------------------

  List<pw.Widget> body() => [
    head(),
    pw.SizedBox(height: compact ? 6 : 8),
    ...marks(),
    if (!taxInvoice) ...[parties(), pw.SizedBox(height: compact ? 6 : 10)],
    if (!d.transport.isEmpty) ...[
      transport(),
      pw.SizedBox(height: compact ? 6 : 8),
    ],
    lines(),
    if (money) ...[pw.SizedBox(height: compact ? 6 : 10), totals()],
    if (money) ...payment(),
    if (money) ...fbr(),
    ...footer(),
  ];

  /// What repeats at the top of every sheet after the first.
  pw.Widget runningHead() => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        words(d.shop.name.toUpperCase(), fontSize: 11, bold: true),
        pw.Text(
          '${d.docLabel}: ${d.docNo}   ${d.dateTimeLabel}',
          style: pw.TextStyle(font: sans, fontSize: 9),
        ),
        pw.Divider(thickness: 0.5, height: 6, color: accent),
      ],
    ),
  );

  pw.Widget head() => switch (design.theme) {
    BillTheme.classic => _classicHead(),
    BillTheme.modern => _modernHead(),
    BillTheme.compact => _compactHead(),
    BillTheme.taxInvoice => _taxHead(),
  };

  pw.Widget _classicHead() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      if (logo != null) ...[
        pw.Center(child: pw.Image(logo!, height: 44)),
        pw.SizedBox(height: 4),
      ],
      pw.Center(
        child: words(d.shop.name.toUpperCase(), fontSize: 16, bold: true),
      ),
      pw.SizedBox(height: 2),
      if (shopWhere.isNotEmpty) pw.Center(child: words(shopWhere)),
      if (shopTaxIds.isNotEmpty) ...[
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            shopTaxIds,
            style: pw.TextStyle(font: sans, fontSize: size),
          ),
        ),
      ],
      pw.SizedBox(height: 8),
      pw.Center(
        child: pw.Text(
          title,
          style: pw.TextStyle(font: sansBold, fontSize: 11, color: accent),
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Divider(thickness: 1, height: 1, color: accent),
    ],
  );

  pw.Widget _modernHead() => pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: accent,
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logo != null) ...[
          pw.Container(
            width: 46,
            height: 46,
            padding: const pw.EdgeInsets.all(3),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Image(logo!, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 10),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              words(
                d.shop.name.toUpperCase(),
                fontSize: 16,
                bold: true,
                color: PdfColors.white,
              ),
              if (shopWhere.isNotEmpty)
                words(shopWhere, fontSize: 8.5, color: PdfColors.white),
              if (shopTaxIds.isNotEmpty)
                pw.Text(
                  shopTaxIds,
                  style: pw.TextStyle(
                    font: sans,
                    fontSize: 8.5,
                    color: PdfColors.white,
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                font: sansBold,
                fontSize: 13,
                color: PdfColors.white,
              ),
            ),
            pw.Text(
              d.docNo,
              style: pw.TextStyle(
                font: monoBold,
                fontSize: 10,
                color: PdfColors.white,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  pw.Widget _compactHead() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logo != null) ...[
            pw.Image(logo!, height: 30),
            pw.SizedBox(width: 6),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                words(d.shop.name.toUpperCase(), fontSize: 12, bold: true),
                if (shopWhere.isNotEmpty) words(shopWhere, fontSize: 7.5),
                if (shopTaxIds.isNotEmpty)
                  pw.Text(
                    shopTaxIds,
                    style: pw.TextStyle(font: sans, fontSize: 7.5),
                  ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  font: sansBold,
                  fontSize: 10,
                  color: accent,
                ),
              ),
              pw.Text(
                '${d.docLabel}: ${d.docNo}',
                style: pw.TextStyle(font: sans, fontSize: 8),
              ),
              pw.Text(
                d.dateTimeLabel,
                style: pw.TextStyle(font: sans, fontSize: 8),
              ),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Divider(thickness: 0.6, height: 1, color: accent),
    ],
  );

  /// The tax invoice's head: the title and the bill's numbers, then the
  /// seller and the buyer side by side, each with name, address and
  /// registration numbers, as s.23 asks.
  pw.Widget _taxHead() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logo != null) pw.Image(logo!, height: 36),
          pw.Spacer(),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  font: sansBold,
                  fontSize: 14,
                  color: accent,
                ),
              ),
              pw.Text(
                '${d.docLabel}: ${d.docNo}',
                style: pw.TextStyle(font: sansBold, fontSize: size),
              ),
              pw.Text(
                'Date: ${d.dateTimeLabel}',
                style: pw.TextStyle(font: sans, fontSize: size),
              ),
              if (d.fbrInvoiceNo case final fbrNo?)
                pw.Text(
                  'FBR Invoice No: $fbrNo',
                  style: pw.TextStyle(font: sans, fontSize: size),
                ),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: _partyBox(
              'SELLER / SUPPLIER',
              name: d.shop.name,
              address: [
                d.shop.addressLine1,
                d.shop.city,
              ].whereType<String>().where(_has).join(', '),
              phone: d.shop.phone,
              ntn: d.shop.ntn,
              strn: d.shop.strn,
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: _partyBox(
              'BUYER / RECIPIENT',
              name: d.customerName ?? 'Walk-in customer',
              address: d.customerAddress,
              phone: d.customerPhone,
              ntn: d.customerNtn,
              strn: d.customerStrn,
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        'Cashier: ${d.cashierName}',
        style: pw.TextStyle(font: sans, fontSize: 8, color: PdfColors.grey700),
      ),
    ],
  );

  /// One side of the tax invoice. A registration number the party does not
  /// have says so in words, because a blank reads as one somebody forgot.
  pw.Widget _partyBox(
    String heading, {
    required String name,
    String? address,
    String? phone,
    String? ntn,
    String? strn,
  }) => pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: accent, width: 0.8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          color: tint,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text(
            heading,
            style: pw.TextStyle(font: sansBold, fontSize: 8, color: accent),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              words(name, bold: true),
              if (_has(address)) labelled('Address', address!),
              if (_has(phone)) labelled('Phone', phone!),
              labelled('NTN', _has(ntn) ? ntn! : 'Unregistered'),
              labelled('STRN', _has(strn) ? strn! : 'Unregistered'),
            ],
          ),
        ),
      ],
    ),
  );

  /// CANCELLED above everything, then the sheet's own name.
  List<pw.Widget> marks() {
    final copy = d.copyMark;
    return [
      if (d.isCancelled) ...[
        pw.Center(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.red800, width: 2),
            ),
            child: pw.Text(
              'CANCELLED / MANSOOKH',
              style: pw.TextStyle(
                font: sansBold,
                fontSize: 16,
                color: PdfColors.red800,
              ),
            ),
          ),
        ),
        pw.SizedBox(height: 8),
      ],
      if (copy != null) ...[
        pw.Center(
          child: pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: accent, width: 1.2),
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Column(
              children: [
                pw.Text(
                  copy.mark,
                  style: pw.TextStyle(
                    font: sansBold,
                    fontSize: 10,
                    color: accent,
                  ),
                ),
                if (!copy.showsMoney)
                  pw.Text(
                    'Qeemat ke baghair / without prices',
                    style: pw.TextStyle(font: sans, fontSize: 8),
                  ),
              ],
            ),
          ),
        ),
        pw.SizedBox(height: 8),
      ],
    ];
  }

  /// The bill's numbers on one side and who it is for on the other.
  pw.Widget parties() {
    final bill = <pw.Widget>[
      pw.Text(
        '${d.docLabel}: ${d.docNo}',
        style: pw.TextStyle(font: sansBold, fontSize: size + 1),
      ),
      pw.Text(
        'Date: ${d.dateTimeLabel}',
        style: pw.TextStyle(font: sans, fontSize: size),
      ),
      pw.Text(
        'Cashier: ${d.cashierName}',
        style: pw.TextStyle(font: sans, fontSize: size),
      ),
    ];
    final party = <pw.Widget>[
      if (_has(d.customerName)) ...[
        if (modern || !money)
          pw.Text(
            d.partyLabel.toUpperCase(),
            style: pw.TextStyle(font: sansBold, fontSize: 7.5, color: accent),
          ),
        words(d.customerName!, fontSize: size + 1, bold: true),
      ],
      if (_has(d.customerPhone)) words(d.customerPhone!),
      if (_has(d.customerAddress)) words(d.customerAddress!),
      if (_has(d.customerNtn)) labelled('NTN', d.customerNtn!),
      if (_has(d.customerStrn)) labelled('STRN', d.customerStrn!),
    ];

    if (modern) {
      pw.Widget box(List<pw.Widget> children, {required bool end}) =>
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: tint,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: end
                  ? pw.CrossAxisAlignment.end
                  : pw.CrossAxisAlignment.start,
              children: children,
            ),
          );
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: party.isEmpty ? pw.SizedBox() : box(party, end: false),
          ),
          pw.SizedBox(width: 8),
          box(bill, end: true),
        ],
      );
    }

    if (compact) {
      // One line, because a compact bill spends its sheet on lines.
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: party,
            ),
          ),
          pw.Text(
            'Cashier: ${d.cashierName}',
            style: pw.TextStyle(font: sans, fontSize: size),
          ),
        ],
      );
    }

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: bill,
        ),
        pw.SizedBox(width: 12),
        pw.Flexible(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: party,
          ),
        ),
      ],
    );
  }

  /// Transporter, truck, bilty, destination, whichever are known.
  pw.Widget transport() {
    final t = d.transport;
    return pw.Row(
      children: [
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.all(6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: accent, width: 0.6),
            ),
            child: pw.Wrap(
              spacing: 14,
              runSpacing: 2,
              children: [
                if (_has(t.transporter))
                  labelled('Transporter', t.transporter!),
                if (_has(t.vehicleNo)) labelled('Gaari no', t.vehicleNo!),
                if (_has(t.biltyNo)) labelled('Bilty no', t.biltyNo!),
                if (_has(t.shipTo)) labelled('Ship to', t.shipTo!),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Lines ------------------------------------------------------------------

  pw.Widget lines() {
    final headerStyle = pw.TextStyle(
      font: sansBold,
      fontSize: size,
      color: modern ? PdfColors.white : PdfColors.black,
    );
    final headerDecoration = switch (design.theme) {
      BillTheme.modern => pw.BoxDecoration(color: accent),
      BillTheme.classic => const pw.BoxDecoration(color: PdfColors.grey300),
      BillTheme.compact => const pw.BoxDecoration(),
      BillTheme.taxInvoice => pw.BoxDecoration(color: tint),
    };
    final border = switch (design.theme) {
      BillTheme.compact || BillTheme.modern => pw.TableBorder(
        bottom: pw.BorderSide(color: accent, width: 0.6),
        horizontalInside: const pw.BorderSide(
          color: PdfColors.grey300,
          width: 0.5,
        ),
      ),
      _ => pw.TableBorder.all(color: PdfColors.grey600, width: 0.5),
    };
    final cellStyle = pw.TextStyle(font: sans, fontSize: size);
    final figures = pw.TextStyle(font: mono, fontSize: size);
    final padding = pw.EdgeInsets.symmetric(
      horizontal: 4,
      vertical: compact ? 2 : 4,
    );

    pw.Widget name(ReceiptLine l) {
      final hs = taxInvoice ? l.tax?.hsCode : null;
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          words(l.name + (l.isFreeItem ? '  (free)' : '')),
          if (hs != null)
            pw.Text(
              'HS $hs',
              style: pw.TextStyle(
                font: sans,
                fontSize: 7,
                color: PdfColors.grey700,
              ),
            ),
        ],
      );
    }

    pw.Widget fig(String v) => pw.Text(v, style: figures);

    if (!money) {
      return pw.TableHelper.fromTextArray(
        headers: const ['#', 'Item', 'Qty', 'Unit'],
        headerStyle: headerStyle,
        headerDecoration: headerDecoration,
        cellStyle: cellStyle,
        cellPadding: padding,
        border: border,
        cellAlignments: const {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.centerLeft,
          2: pw.Alignment.centerRight,
          3: pw.Alignment.centerLeft,
        },
        columnWidths: const {
          0: pw.FixedColumnWidth(18),
          1: pw.FlexColumnWidth(5),
          2: pw.FlexColumnWidth(1.4),
          3: pw.FlexColumnWidth(1.4),
        },
        data: [
          for (var i = 0; i < d.lines.length; i++)
            [
              '${i + 1}',
              name(d.lines[i]),
              fig(d.lines[i].qtyDisplay),
              words(d.lines[i].unitCode),
            ],
        ],
      );
    }

    if (taxInvoice) {
      // Value excluding tax, rate, tax and value including tax on every
      // line: what s.23 asks for, and what a buyer claiming the tax back
      // claims against. A line nobody read the tax of prints its net value
      // and no tax, never a guess.
      ReceiptLineTax taxOf(ReceiptLine l) =>
          l.tax ??
          ReceiptLineTax(
            valueExclTax: l.amount - l.discount,
            salesTax: Money.zero,
          );
      // Further tax, the unregistered buyer's surcharge, in a column of its
      // own when any line carries it, so the sales tax column is the sales
      // tax and each row still adds across to its value including tax.
      final further = d.lines.any((l) => taxOf(l).furtherTax.isPositive);
      return pw.TableHelper.fromTextArray(
        headers: [
          '#',
          'Description',
          'Qty',
          'Value excl. tax',
          'Rate',
          'Sales tax',
          if (further) 'Further tax',
          'Value incl. tax',
        ],
        headerStyle: pw.TextStyle(font: sansBold, fontSize: size - 1),
        headerDecoration: headerDecoration,
        cellStyle: cellStyle,
        cellPadding: padding,
        border: border,
        headerAlignment: pw.Alignment.center,
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          1: pw.Alignment.centerLeft,
          for (var c = 2; c < (further ? 8 : 7); c++)
            c: pw.Alignment.centerRight,
        },
        columnWidths: {
          0: const pw.FixedColumnWidth(16),
          1: const pw.FlexColumnWidth(3.2),
          2: const pw.FlexColumnWidth(1.3),
          3: const pw.FlexColumnWidth(1.7),
          4: const pw.FlexColumnWidth(0.9),
          5: const pw.FlexColumnWidth(1.5),
          6: const pw.FlexColumnWidth(1.5),
          if (further) 7: const pw.FlexColumnWidth(1.7),
        },
        data: [
          for (final (i, l) in d.lines.indexed)
            [
              '${i + 1}',
              name(l),
              fig('${l.qtyDisplay} ${l.unitCode}'),
              fig(taxOf(l).valueExclTax.amountOnly),
              fig(taxOf(l).rateLabel),
              fig(taxOf(l).salesTax.amountOnly),
              if (further) fig(taxOf(l).furtherTax.amountOnly),
              fig(taxOf(l).valueInclTax.amountOnly),
            ],
        ],
      );
    }

    return pw.TableHelper.fromTextArray(
      headers: const ['#', 'Item', 'Qty', 'Rate', 'Amount'],
      headerStyle: headerStyle,
      headerDecoration: headerDecoration,
      cellStyle: cellStyle,
      cellPadding: padding,
      border: border,
      oddRowDecoration: modern ? pw.BoxDecoration(color: tint) : null,
      cellAlignments: const {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.centerLeft,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
      },
      columnWidths: const {
        0: pw.FixedColumnWidth(18),
        1: pw.FlexColumnWidth(4),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(1.6),
        4: pw.FlexColumnWidth(1.8),
      },
      data: [
        for (var i = 0; i < d.lines.length; i++)
          [
            '${i + 1}',
            name(d.lines[i]),
            fig('${d.lines[i].qtyDisplay} ${d.lines[i].unitCode}'),
            fig(d.lines[i].rate.amountOnly),
            fig(d.lines[i].amount.amountOnly),
          ],
      ],
    );
  }

  // --- Totals -----------------------------------------------------------------

  pw.Widget totalRow(String label, String value, {bool emphasis = false}) {
    final row = pw.Padding(
      padding: pw.EdgeInsets.symmetric(
        vertical: compact ? 1 : 1.5,
        horizontal: emphasis && modern ? 4 : 0,
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: emphasis ? sansBold : sans,
              fontSize: emphasis ? size + 2 : size,
              color: emphasis && modern ? PdfColors.white : null,
            ),
          ),
          figure(
            value,
            fontSize: emphasis ? size + 2 : size,
            bold: emphasis,
            color: emphasis && modern ? PdfColors.white : null,
          ),
        ],
      ),
    );
    if (emphasis && modern) {
      return pw.Container(color: accent, child: row);
    }
    return row;
  }

  String _signedRoundOff(Money m) =>
      m.isNegative ? m.amountOnly : '+${m.amountOnly}';

  pw.Widget totals() {
    final rows = <pw.Widget>[
      if (taxInvoice) ...[
        totalRow(
          'Value excl. tax',
          Money.sum([
            for (final l in d.lines)
              l.tax?.valueExclTax ?? (l.amount - l.discount),
          ]).amountOnly,
        ),
        totalRow('Sales tax', d.tax.amountOnly),
      ] else ...[
        totalRow('Subtotal', d.subtotal.amountOnly),
        if (d.discount.isPositive)
          totalRow('Discount', '-${d.discount.amountOnly}'),
        if (d.tax.isPositive) totalRow('Sales Tax', d.tax.amountOnly),
      ],
      if (d.furtherTax.isPositive)
        totalRow('Further Tax', d.furtherTax.amountOnly),
      if (d.withholding.isPositive)
        totalRow('Withholding', '-${d.withholding.amountOnly}'),
      if (d.extraCharges.isPositive)
        totalRow('Other Charges', d.extraCharges.amountOnly),
      if (!d.roundOff.isZero)
        totalRow('Round Off', _signedRoundOff(d.roundOff)),
      pw.Divider(thickness: 1, height: 6, color: accent),
      totalRow(
        taxInvoice ? 'Value incl. tax' : 'TOTAL',
        'Rs ${d.total.amountOnly}',
        emphasis: true,
      ),
      for (final t in d.tenders) totalRow(t.label, t.amount.amountOnly),
      if (d.change.isPositive) totalRow('Change', d.change.amountOnly),
      // The bill's own udhaar, unless the khata block beside it says it.
      if (d.balance.isPositive && (d.khata == null || d.isCancelled))
        totalRow('Baqaya (udhaar)', d.balance.amountOnly, emphasis: !modern),
    ];

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 3,
          child: d.khata == null || d.isCancelled ? pw.SizedBox() : khata(),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(flex: 4, child: pw.Column(children: rows)),
      ],
    );
  }

  /// "Pichhla baqaya / Is bill / Kul baqaya": the khata as it stood when the
  /// bill was made. On a later sheet, said to be the bill's day, so nobody
  /// reads it as today's.
  pw.Widget khata() {
    final k = d.khata!;
    final later = d.copyMark != null && d.copyMark != ReceiptCopy.original;
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: accent, width: 0.8),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            later ? 'KHATA (bill ke din ka hisaab)' : 'KHATA',
            style: pw.TextStyle(font: sansBold, fontSize: 8, color: accent),
          ),
          pw.SizedBox(height: 2),
          totalRow('Pichhla baqaya', k.before.amountOnly),
          totalRow('Is bill', k.thisBill.amountOnly),
          pw.Divider(thickness: 0.5, height: 4, color: accent),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Kul baqaya',
                style: pw.TextStyle(font: sansBold, fontSize: size + 1),
              ),
              figure(k.after.amountOnly, fontSize: size + 1, bold: true),
            ],
          ),
        ],
      ),
    );
  }

  // --- How to pay -------------------------------------------------------------

  /// The shop's alias and IBAN as text, and the QR picture its own bank or
  /// wallet issued, when the owner added one. No picture, no QR: nothing
  /// is drawn in its place.
  List<pw.Widget> payment() {
    final shop = d.shop;
    final text = <pw.Widget>[
      if (_has(shop.raastAlias)) figure('Raast: ${shop.raastAlias}'),
      if (_has(shop.bankIban))
        figure(
          '${shop.bankName ?? 'Bank'}: ${shop.bankIban}'
          '${_has(shop.bankAccountTitle) ? '  (${shop.bankAccountTitle})' : ''}',
        ),
    ];
    if (text.isEmpty && qr == null) return const [];
    return [
      pw.SizedBox(height: compact ? 6 : 10),
      pw.Divider(thickness: 0.5, height: 8, color: accent),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Payment ke liye',
                  style: pw.TextStyle(font: sansBold, fontSize: size),
                ),
                ...text,
                if (qr != null)
                  pw.Text(
                    'QR scan karke Raast / JazzCash / Easypaisa se bhejein',
                    style: pw.TextStyle(
                      font: sans,
                      fontSize: 7.5,
                      color: PdfColors.grey700,
                    ),
                  ),
              ],
            ),
          ),
          if (qr != null)
            pw.Container(
              width: compact ? 72 : 92,
              height: compact ? 72 : 92,
              padding: const pw.EdgeInsets.all(3),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
              ),
              child: pw.Image(qr!, fit: pw.BoxFit.contain),
            ),
        ],
      ),
    ];
  }

  /// FBR's own number for the bill, as text, once it has one (M19). The tax
  /// invoice has it in its head already.
  List<pw.Widget> fbr() {
    if (taxInvoice) return const [];
    if (d.fbrInvoiceNo case final fbrNo?) {
      return [
        pw.SizedBox(height: 6),
        pw.Text(
          'FBR Invoice No: $fbrNo',
          style: pw.TextStyle(font: sans, fontSize: size),
        ),
      ];
    }
    if (d.fbrPending) {
      return [
        pw.SizedBox(height: 6),
        pw.Text(
          'FBR: pending',
          style: pw.TextStyle(font: sans, fontSize: size),
        ),
      ];
    }
    return const [];
  }

  /// The shop's own lines, one to a row, each in its own direction: a
  /// thank-you in Urdu script and a return policy in English are two runs,
  /// and setting them as one would reverse the English.
  List<pw.Widget> footer() => [
    if (d.footerLines.isNotEmpty) pw.SizedBox(height: compact ? 6 : 10),
    for (final line in d.footerLines)
      pw.Center(
        child: words(line, fontSize: size, align: pw.TextAlign.center),
      ),
  ];
}
