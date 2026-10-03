import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// A bill to show a design on (M51): the shop's own name, address, logo and
/// QR, with three lines of goods to a named credit customer, so every part
/// of a design — the khata block, the payment QR, the footer — has
/// something to show.
///
/// Dressed by the same [dressBill] a real bill is, so the footer and the
/// khata block follow the same rules on the sample as on the counter.
ReceiptData sampleBill(
  FirmProfile firm,
  BillDesign design, {
  Uint8List? logo,
  Uint8List? paymentQr,
}) {
  ReceiptLine line(String name, int qty, String unit, int rupees) =>
      ReceiptLine(
        name: name,
        qtyDisplay: '$qty',
        unitCode: unit,
        rate: Rate.rupees(rupees),
        amount: Money.rupees(rupees * qty),
      );
  final lines = [
    line('Cooking Oil 5L', 2, 'pcs', 2450),
    line('Chawal Basmati', 1, 'bori', 6200),
    line('Cheeni', 10, 'kg', 145),
  ];
  // A registered shop's sample carries 18% on top, so the tax layout has a
  // rate and a tax to show; an unregistered one's carries none, as its
  // bills do.
  final taxed =
      firm.isSalesTaxRegistered || design.theme == BillTheme.taxInvoice;
  final taxes = [
    for (final l in lines)
      ReceiptLineTax(
        valueExclTax: l.amount,
        salesTax: taxed
            ? Money.paisa(l.amount.inPaisa * 18 ~/ 100)
            : Money.zero,
        rateBp: taxed ? 1800 : null,
      ),
  ];
  final subtotal = Money.sum([for (final l in lines) l.amount]);
  final tax = Money.sum([for (final t in taxes) t.salesTax]);
  final total = subtotal + tax;
  const paid = Money.rupees(5000);
  return dressBill(
    ReceiptData(
      shop: firm.toReceiptShop(),
      docNo: 'INV-2627-0042',
      dateTimeLabel: '02-10-2026  4:30 PM',
      cashierName: 'Malik Sahib',
      customerName: 'Rashid Traders',
      lines: lines,
      subtotal: subtotal,
      tax: tax,
      total: total,
      tenders: const [ReceiptTender(label: 'Cash', amount: paid, isCash: true)],
      paid: paid,
      balance: total - paid,
      change: Money.zero,
      footerLines: const [BillDesign.defaultThanks],
    ),
    extras: BillExtras(
      docType: 'sale_invoice',
      partyId: 'sample',
      partyAddress: 'Shop 5, Shah Alam Market, Lahore',
      partyNtn: taxed ? '1234567-8' : null,
      lineTaxes: taxes,
      khata: KhataAtBill(
        before: const Money.rupees(3500),
        thisBill: total - paid,
      ),
    ),
    design: design,
    logo: logo,
    paymentQr: paymentQr,
  );
}

/// A picture of what a design looks like on a PDF page (M51).
///
/// Not the bill. The PDF itself cannot be drawn on screen without a PDF
/// renderer, which this build deliberately does not carry (a native plugin
/// through the release gates for one preview). This is a sketch of the
/// design's choices — where the logo and the name sit, the band, the
/// colour, the columns, the khata block, the QR, the footer — drawn from
/// the same sample bill, so the owner can choose between the layouts at a
/// glance. The real page is one tap away: the sample PDF button renders it
/// through the very renderer the bills go through.
class BillDesignPreview extends StatelessWidget {
  const BillDesignPreview({
    super.key,
    required this.design,
    required this.receipt,
  });

  final BillDesign design;
  final ReceiptData receipt;

  @override
  Widget build(BuildContext context) =>
      _Sheet(design: design, receipt: receipt);
}

/// One layout, small, for the row of designs to choose from (M70): the
/// same sketch as [BillDesignPreview], of the same sample bill, at the size
/// of a thumbnail. A widget of its own so the one large sketch stays the
/// one large sketch.
class BillDesignThumbnail extends StatelessWidget {
  const BillDesignThumbnail({
    super.key,
    required this.design,
    required this.receipt,
  });

  final BillDesign design;
  final ReceiptData receipt;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: _Sheet(design: design, receipt: receipt),
  );
}

/// The page, scaled whole to fit.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.design, required this.receipt});

  final BillDesign design;
  final ReceiptData receipt;

  /// The page and the ink on it. Not tokens, deliberately: this is a
  /// picture of paper, white whatever theme the phone is in, as the bill is.
  static const _paper = Color(
    0xFFFFFFFF,
  ); // arch_check: allow no_hardcoded_colour - the paper itself
  static const _ink = Color(
    0xFF111111,
  ); // arch_check: allow no_hardcoded_colour - ink on a picture of paper
  static const _muted = Color(
    0xFF6B7280,
  ); // arch_check: allow no_hardcoded_colour - grey ink on a picture of paper
  static const _rule = Color(
    0xFFD1D5DB,
  ); // arch_check: allow no_hardcoded_colour - a ruled line on paper

  /// The page is drawn at this width and scaled to fit, so the sketch looks
  /// the same on a small phone and a tablet.
  static const _width = 300.0;

  @override
  Widget build(BuildContext context) {
    final accent = Color(design.accent.argb);
    // A5 and A4 are the same shape; one ratio serves both. The landscape
    // layout (M70) turns it on its side.
    final side = design.theme == BillTheme.landscape;
    final width = side ? _width * 1.414 : _width;
    final height = side ? _width : _width * 1.414;
    final ruled = design.theme == BillTheme.ruled;
    return AspectRatio(
      aspectRatio: width / height,
      child: FittedBox(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: _paper,
            border: Border.all(color: _rule),
          ),
          padding: EdgeInsets.all(design.theme == BillTheme.compact ? 10 : 14),
          // The bill book's border round the page (M70).
          foregroundDecoration: ruled
              ? BoxDecoration(
                  border: Border.all(color: accent, width: 2),
                  borderRadius: BorderRadius.circular(1),
                )
              : null,
          // Clipped rather than allowed to overflow: a long footer on a
          // sketch is cut at the page edge, as it would run onto page two.
          //
          // And drawn at the page's own type size whatever the phone's text
          // setting: this is a picture of paper, scaled whole to fit, and a
          // shopkeeper reading at 200% enlarges the picture, not the ink on
          // a fixed-size sheet until it runs off the edge.
          child: MediaQuery.withNoTextScaling(
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topCenter,
                maxHeight: double.infinity,
                child: _Page(design: design, d: receipt, accent: accent),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.design, required this.d, required this.accent});

  final BillDesign design;
  final ReceiptData d;
  final Color accent;

  static const _paper = _Sheet._paper;
  static const _ink = _Sheet._ink;
  static const _muted = _Sheet._muted;
  static const _rule = _Sheet._rule;

  bool get compact => design.theme == BillTheme.compact;
  bool get modern => design.theme == BillTheme.modern;
  bool get tax => design.theme == BillTheme.taxInvoice;
  // M70's four.
  bool get landscape => design.theme == BillTheme.landscape;
  bool get ruled => design.theme == BillTheme.ruled;
  bool get elegant => design.theme == BillTheme.elegant;
  bool get minimal => design.theme == BillTheme.minimal;

  /// The landscape page carries the tax line by line when the bill does.
  bool get taxColumns =>
      tax ||
      (landscape && d.lines.any((l) => l.tax?.salesTax.isPositive ?? false));

  double get size => compact ? 6.5 : 7.5;

  TextStyle style({
    double? fontSize,
    bool bold = false,
    Color? color,
    bool mono = false,
    bool italic = false,
    double? spacing,
  }) => TextStyle(
    fontSize: fontSize ?? size,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    color: color ?? _ink,
    fontFamily: mono
        ? 'monospace'
        : elegant
        ? 'serif'
        : null,
    letterSpacing: spacing,
    height: 1.25,
  );

  String get title => tax || (landscape && taxColumns)
      ? 'SALES TAX INVOICE'
      : d.docTitle.toUpperCase();

  Widget? get logo => d.shop.logoImage == null
      ? null
      : Image.memory(d.shop.logoImage!, height: compact ? 22 : 30);

  String get where => [
    d.shop.addressLine1,
    d.shop.city,
    d.shop.phone,
  ].whereType<String>().where((s) => s.trim().isNotEmpty).join('  |  ');

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      head(),
      SizedBox(height: compact ? 4 : 6),
      if (!tax && !landscape) ...[party(), SizedBox(height: compact ? 4 : 6)],
      table(),
      SizedBox(height: compact ? 4 : 6),
      totals(),
      ...payment(),
      const SizedBox(height: 6),
      for (final line in d.footerLines)
        Text(
          line,
          textAlign: TextAlign.center,
          style: style(italic: elegant, color: minimal ? _muted : null),
        ),
      if (ruled) ...signature(),
    ],
  );

  Widget head() => switch (design.theme) {
    BillTheme.classic => Column(
      children: [
        ?logo,
        Text(
          d.shop.name.toUpperCase(),
          textAlign: TextAlign.center,
          style: style(fontSize: 12, bold: true),
        ),
        if (where.isNotEmpty)
          Text(
            where,
            textAlign: TextAlign.center,
            style: style(color: _muted),
          ),
        const SizedBox(height: 4),
        Text(title, style: style(fontSize: 8.5, bold: true, color: accent)),
        Divider(color: accent, height: 6, thickness: 1),
      ],
    ),
    BillTheme.modern => Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          if (logo != null) ...[
            Container(
              padding: const EdgeInsets.all(2),
              color: _paper,
              child: logo,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.shop.name.toUpperCase(),
                  style: style(fontSize: 11, bold: true, color: _paper),
                ),
                if (where.isNotEmpty)
                  Text(where, style: style(fontSize: 6.5, color: _paper)),
              ],
            ),
          ),
          Flexible(
            child: Text(
              title,
              textAlign: TextAlign.right,
              style: style(fontSize: 9, bold: true, color: _paper),
            ),
          ),
        ],
      ),
    ),
    BillTheme.compact => Column(
      children: [
        Row(
          children: [
            if (logo != null) ...[logo!, const SizedBox(width: 4)],
            Expanded(
              child: Text(
                d.shop.name.toUpperCase(),
                style: style(fontSize: 9, bold: true),
              ),
            ),
            Flexible(
              child: Text(
                title,
                textAlign: TextAlign.right,
                style: style(bold: true, color: accent),
              ),
            ),
          ],
        ),
        Divider(color: accent, height: 4, thickness: 0.6),
      ],
    ),
    BillTheme.taxInvoice => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ?logo,
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.right,
                style: style(fontSize: 10, bold: true, color: accent),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: box('SELLER', [
                d.shop.name,
                'NTN ${d.shop.ntn ?? '-'}',
                'STRN ${d.shop.strn ?? '-'}',
              ]),
            ),
            const SizedBox(width: 4),
            Expanded(child: buyer()),
          ],
        ),
      ],
    ),
    // M70: the seller, the buyer and the title across one row.
    BillTheme.landscape => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ?logo,
              Text(
                _seller,
                style: style(fontSize: 6, bold: true, color: accent),
              ),
              Text(
                d.shop.name.toUpperCase(),
                style: style(fontSize: 11, bold: true),
              ),
              if (where.isNotEmpty) Text(where, style: style(fontSize: 6.5)),
              Text(
                [
                  'NTN',
                  d.shop.ntn ?? '-',
                  ' STRN',
                  d.shop.strn ?? '-',
                ].join(' '),
                style: style(fontSize: 6.5, color: _muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Expanded(flex: 4, child: buyer()),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.all(5),
            color: accent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.right,
                  style: style(fontSize: 8, bold: true, color: _paper),
                ),
                Text(d.docNo, style: style(fontSize: 6.5, color: _paper)),
                Text(
                  d.dateTimeLabel,
                  style: style(fontSize: 6.5, color: _paper),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
    // M70: the name in the shop's colour over the number, the paper's
    // pill and the date, as a bill book is printed.
    BillTheme.ruled => Column(
      children: [
        ?logo,
        Text(
          d.shop.name.toUpperCase(),
          textAlign: TextAlign.center,
          style: style(fontSize: 12, bold: true, color: accent),
        ),
        if (where.isNotEmpty)
          Text(where, textAlign: TextAlign.center, style: style(fontSize: 6.5)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                ['No.', d.docNo].join(' '),
                style: style(fontSize: 6.5, bold: true),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                title,
                style: style(fontSize: 6.5, bold: true, color: _paper),
              ),
            ),
            Expanded(
              child: Text(
                d.dateTimeLabel,
                textAlign: TextAlign.right,
                style: style(fontSize: 6.5),
              ),
            ),
          ],
        ),
      ],
    ),
    // M70: a serif name spaced out between fine double rules.
    BillTheme.elegant => Column(
      children: [
        ?logo,
        Text(
          d.shop.name.toUpperCase(),
          textAlign: TextAlign.center,
          style: style(fontSize: 12, bold: true, spacing: 1.5),
        ),
        if (where.isNotEmpty)
          Text(
            where,
            textAlign: TextAlign.center,
            style: style(fontSize: 6.5, italic: true, color: _muted),
          ),
        const SizedBox(height: 4),
        doubleRule(),
        Text(
          title,
          textAlign: TextAlign.center,
          style: style(fontSize: 7.5, color: accent, spacing: 3),
        ),
        doubleRule(),
      ],
    ),
    // M70: the name on the left, the number on the right, and space.
    BillTheme.minimal => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (logo != null) ...[logo!, const SizedBox(width: 6)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(d.shop.name, style: style(fontSize: 11, bold: true)),
              if (where.isNotEmpty)
                Text(where, style: style(fontSize: 6, color: _muted)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(title, style: style(fontSize: 6, color: _muted, spacing: 1.2)),
            Text(d.docNo, style: style(fontSize: 8, bold: true, mono: true)),
          ],
        ),
      ],
    ),
  };

  Widget doubleRule() => Column(
    children: [
      Container(height: 0.9, color: accent),
      const SizedBox(height: 1.2),
      Container(height: 0.3, color: accent),
    ],
  );

  Widget buyer() => box('BUYER', [
    d.customerName ?? '-',
    d.customerAddress ?? '-',
    'NTN ${d.customerNtn ?? 'Unregistered'}',
  ]);

  Widget box(String heading, List<String> lines) => Container(
    decoration: BoxDecoration(border: Border.all(color: accent, width: 0.6)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: accent.withValues(alpha: 0.1),
          padding: const EdgeInsets.all(2),
          child: Text(heading, style: style(bold: true, color: accent)),
        ),
        Padding(
          padding: const EdgeInsets.all(3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final l in lines) Text(l, style: style())],
          ),
        ),
      ],
    ),
  );

  Widget party() {
    if (ruled) {
      // "M/s" over a dotted line, as the book is filled in by hand.
      return Container(
        padding: const EdgeInsets.only(bottom: 1),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _rule)),
        ),
        child: Text(
          ['M/s', d.customerName ?? ''].join('  '),
          style: style(bold: true),
        ),
      );
    }
    final bill = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${d.docLabel}: ${d.docNo}', style: style(bold: true)),
        Text(['Date:', d.dateTimeLabel].join(' '), style: style()),
      ],
    );
    final who = Column(
      crossAxisAlignment: elegant || minimal
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        if (elegant) Text(_billedTo, style: style(italic: true, color: _muted)),
        if (minimal)
          Text(
            d.partyLabel.toUpperCase(),
            style: style(fontSize: 6, color: _muted, spacing: 1),
          ),
        if (d.customerName != null)
          Text(d.customerName!, style: style(bold: true)),
        if (d.customerAddress != null) Text(d.customerAddress!, style: style()),
      ],
    );
    if (modern) {
      return Container(
        padding: const EdgeInsets.all(5),
        color: accent.withValues(alpha: 0.1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(child: who),
            const SizedBox(width: 6),
            Flexible(child: bill),
          ],
        ),
      );
    }
    if (elegant || minimal) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(child: who),
          const SizedBox(width: 6),
          if (elegant) Flexible(child: bill),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(child: bill),
        const SizedBox(width: 6),
        Flexible(child: who),
      ],
    );
  }

  Widget table() {
    final List<String> headers;
    if (landscape) {
      headers = taxColumns
          ? const ['Item', 'Qty', 'Unit', 'Rate', 'Excl. tax', 'Tax', 'Incl.']
          : const ['Item', 'Qty', 'Unit', 'Rate', 'Gross', 'Disc.', 'Net'];
    } else if (tax) {
      headers = const ['Item', 'Qty', 'Excl. tax', 'Rate', 'Tax', 'Incl. tax'];
    } else if (ruled) {
      headers = const ['Particulars', 'Qty', 'Rate', 'Amount'];
    } else if (minimal) {
      headers = const ['ITEM', 'QTY', 'RATE', 'AMOUNT'];
    } else {
      headers = const ['Item', 'Qty', 'Rate', 'Amount'];
    }
    List<String> cells(ReceiptLine l) {
      if (landscape) {
        return [
          l.name,
          l.qtyDisplay,
          l.unitCode,
          l.rate.amountOnly,
          if (taxColumns) ...[
            (l.tax?.valueExclTax ?? l.amount).amountOnly,
            (l.tax?.salesTax ?? Money.zero).amountOnly,
            (l.tax?.valueInclTax ?? l.amount).amountOnly,
          ] else ...[
            l.amount.amountOnly,
            l.discount.isPositive ? l.discount.amountOnly : '-',
            (l.amount - l.discount).amountOnly,
          ],
        ];
      }
      if (tax) {
        return [
          l.name,
          '${l.qtyDisplay} ${l.unitCode}',
          (l.tax?.valueExclTax ?? l.amount).amountOnly,
          l.tax?.rateLabel ?? '-',
          (l.tax?.salesTax ?? Money.zero).amountOnly,
          (l.tax?.valueInclTax ?? l.amount).amountOnly,
        ];
      }
      return [
        l.name,
        '${l.qtyDisplay} ${l.unitCode}',
        l.rate.amountOnly,
        l.amount.amountOnly,
      ];
    }

    final headerColour = switch (design.theme) {
      BillTheme.modern || BillTheme.landscape => accent,
      BillTheme.taxInvoice || BillTheme.ruled => accent.withValues(alpha: 0.1),
      BillTheme.classic => _rule,
      _ => null,
    };
    final whiteHead = modern || landscape;
    final small = tax || landscape;
    Widget cell(String v, int i, {bool head = false}) => Expanded(
      flex: i == 0 ? 3 : 2,
      child: Container(
        // The bill book rules every column down the page.
        decoration: ruled && i < headers.length - 1
            ? BoxDecoration(
                border: Border(right: BorderSide(color: accent, width: 0.5)),
              )
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1.5),
        child: Text(
          v,
          textAlign: i == 0 ? TextAlign.left : TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: style(
            fontSize: small ? size - 1 : (minimal && head ? size - 1.5 : size),
            bold: head && !minimal,
            italic: head && elegant,
            mono: !head && i > 0 && !elegant,
            color: head && whiteHead
                ? _paper
                : head && (elegant || ruled)
                ? accent
                : head && minimal
                ? _muted
                : null,
          ),
        ),
      ),
    );
    Widget line(List<String> values, {bool shaded = false}) => Container(
      decoration: BoxDecoration(
        color: shaded ? accent.withValues(alpha: 0.08) : null,
        border: minimal
            ? null
            : Border(
                bottom: BorderSide(
                  color: elegant ? accent.withValues(alpha: 0.3) : _rule,
                  width: 0.5,
                ),
              ),
      ),
      child: Row(children: [for (final (i, v) in values.indexed) cell(v, i)]),
    );

    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: headerColour,
            border: elegant || minimal
                ? Border(
                    top: elegant
                        ? BorderSide(color: accent, width: 0.8)
                        : BorderSide.none,
                    bottom: BorderSide(
                      color: elegant ? accent : _rule,
                      width: elegant ? 0.8 : 0.5,
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              for (var i = 0; i < headers.length; i++)
                cell(headers[i], i, head: true),
            ],
          ),
        ),
        for (var r = 0; r < d.lines.length; r++)
          line(cells(d.lines[r]), shaded: modern && r.isOdd),
        // Two blank rows under the goods, as the book has.
        if (ruled)
          for (var r = 0; r < 2; r++) line([for (final _ in headers) '']),
      ],
    );
    return ruled
        ? Container(
            decoration: BoxDecoration(
              border: Border.all(color: accent, width: 0.8),
            ),
            child: rows,
          )
        : rows;
  }

  Widget totals() {
    final khata = d.khata;
    Widget pair(
      String label,
      String value, {
      bool bold = false,
      bool italic = false,
      Color? colour,
      double? fontSize,
    }) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // The label gives way, never the figure.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: style(
              bold: bold,
              italic: italic,
              color: colour,
              fontSize: fontSize,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: style(
            bold: bold,
            italic: italic,
            mono: !elegant,
            color: colour,
            fontSize: fontSize,
          ),
        ),
      ],
    );
    final taxed = tax || (landscape && taxColumns);
    final total = Container(
      color: modern ? accent : null,
      padding: modern ? const EdgeInsets.symmetric(horizontal: 2) : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              taxed
                  ? 'Value incl. tax'
                  : elegant
                  ? 'Total'
                  : 'TOTAL',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: style(bold: true, color: modern ? _paper : null),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            d.total.toString(),
            style: style(
              bold: true,
              mono: !elegant,
              fontSize: minimal ? size + 2 : null,
              color: modern
                  ? _paper
                  : minimal
                  ? accent
                  : null,
            ),
          ),
        ],
      ),
    );
    final figures = Column(
      children: [
        pair(taxed ? 'Value excl. tax' : 'Subtotal', d.subtotal.amountOnly),
        if (d.tax.isPositive) pair('Sales tax', d.tax.amountOnly),
        if (elegant) doubleRule(),
        total,
        for (final t in d.tenders) pair(t.label, t.amount.amountOnly),
        if (elegant && khata != null)
          pair(
            'Amount due',
            khata.after.toString(),
            bold: true,
            italic: true,
            colour: accent,
          ),
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The total in words (M70), on the papers that write it.
              if (ruled || landscape)
                Text(
                  rupeesInWords(d.total),
                  style: style(fontSize: 6, color: _muted),
                ),
              if (khata != null)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: minimal
                      ? null
                      : elegant
                      ? BoxDecoration(
                          border: Border(
                            left: BorderSide(color: accent, width: 1.2),
                          ),
                        )
                      : BoxDecoration(
                          border: Border.all(color: accent, width: 0.6),
                        ),
                  child: Column(
                    children: [
                      pair('Pichhla baqaya', khata.before.amountOnly),
                      pair('Is bill', khata.thisBill.amountOnly),
                      pair('Kul baqaya', khata.after.amountOnly, bold: true),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: ruled
              ? Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    border: Border.all(color: accent, width: 0.6),
                  ),
                  child: figures,
                )
              : figures,
        ),
      ],
    );
  }

  List<Widget> payment() {
    final qr = d.paymentQr;
    final alias = d.shop.raastAlias;
    final iban = d.shop.bankIban;
    if (qr == null && alias == null && iban == null) return const [];
    return [
      const SizedBox(height: 6),
      if (!minimal) Divider(color: accent, height: 4, thickness: 0.5),
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_payTo, style: style(bold: true)),
                if (alias != null)
                  Text(['Raast:', alias].join(' '), style: style()),
                if (iban != null) Text(iban, style: style(mono: true)),
              ],
            ),
          ),
          if (qr != null)
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(border: Border.all(color: _rule)),
              child: Image.memory(qr, fit: BoxFit.contain),
            ),
        ],
      ),
    ];
  }

  /// The bill book's foot (M70): "E. & O.E." and a line to sign on.
  List<Widget> signature() => [
    const SizedBox(height: 10),
    Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('E. & O.E.', style: style(fontSize: 6, color: _muted)),
        const Spacer(),
        Column(
          children: [
            Container(width: 70, height: 0.6, color: _muted),
            Text(_signature, style: style(fontSize: 6, color: _muted)),
          ],
        ),
      ],
    ),
  ];
}

/// The paper's own words. A bill is printed in English and Roman Urdu
/// whatever language the phone is in, so the sketch of one says what the
/// paper says rather than the app's translation of it.
const _payTo = 'Payment ke liye';
const _seller = 'SELLER';
const _billedTo = 'Billed to';
const _signature = 'Signature';
