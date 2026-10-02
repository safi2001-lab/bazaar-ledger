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
/// the same sample bill, so the owner can choose between four layouts at a
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
    // A5 and A4 are the same shape; one ratio serves both.
    const height = _width * 1.414;
    return AspectRatio(
      aspectRatio: 1 / 1.414,
      child: FittedBox(
        child: Container(
          width: _width,
          height: height,
          decoration: BoxDecoration(
            color: _paper,
            border: Border.all(color: _rule),
          ),
          padding: EdgeInsets.all(design.theme == BillTheme.compact ? 10 : 14),
          // Clipped rather than allowed to overflow: a long footer on a
          // sketch is cut at the page edge, as it would run onto page two.
          //
          // And drawn at the page's own type size whatever the phone's text
          // setting: this is a picture of paper, scaled whole to fit, and a
          // shopkeeper reading at 200% enlarges the picture, not the ink on
          // a fixed-size sheet until it runs off the edge.
          child: MediaQuery.withNoTextScaling(
            child: ClipRect(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
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

  bool get compact => design.theme == BillTheme.compact;
  bool get modern => design.theme == BillTheme.modern;
  bool get tax => design.theme == BillTheme.taxInvoice;
  double get size => compact ? 6.5 : 7.5;

  TextStyle style({
    double? fontSize,
    bool bold = false,
    Color? color,
    bool mono = false,
  }) => TextStyle(
    fontSize: fontSize ?? size,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    color: color ?? BillDesignPreview._ink,
    fontFamily: mono ? 'monospace' : null,
    height: 1.25,
  );

  String get title => tax ? 'SALES TAX INVOICE' : d.docTitle.toUpperCase();

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
      if (!tax) ...[party(), SizedBox(height: compact ? 4 : 6)],
      table(),
      SizedBox(height: compact ? 4 : 6),
      totals(),
      ...payment(),
      const SizedBox(height: 6),
      for (final line in d.footerLines)
        Text(line, textAlign: TextAlign.center, style: style()),
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
            style: style(color: BillDesignPreview._muted),
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
              color: BillDesignPreview._paper,
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
                  style: style(
                    fontSize: 11,
                    bold: true,
                    color: BillDesignPreview._paper,
                  ),
                ),
                if (where.isNotEmpty)
                  Text(
                    where,
                    style: style(
                      fontSize: 6.5,
                      color: BillDesignPreview._paper,
                    ),
                  ),
              ],
            ),
          ),
          Flexible(
            child: Text(
              title,
              textAlign: TextAlign.right,
              style: style(
                fontSize: 9,
                bold: true,
                color: BillDesignPreview._paper,
              ),
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
            Expanded(
              child: box('BUYER', [
                d.customerName ?? '-',
                d.customerAddress ?? '-',
                'NTN ${d.customerNtn ?? 'Unregistered'}',
              ]),
            ),
          ],
        ),
      ],
    ),
  };

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
    final bill = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${d.docLabel}: ${d.docNo}', style: style(bold: true)),
        Text(['Date:', d.dateTimeLabel].join(' '), style: style()),
      ],
    );
    final who = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
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
    final headers = tax
        ? const ['Item', 'Qty', 'Excl. tax', 'Rate', 'Tax', 'Incl. tax']
        : const ['Item', 'Qty', 'Rate', 'Amount'];
    final headerColour = switch (design.theme) {
      BillTheme.modern => accent,
      BillTheme.taxInvoice => accent.withValues(alpha: 0.1),
      BillTheme.classic => BillDesignPreview._rule,
      BillTheme.compact => null,
    };
    List<String> row(ReceiptLine l) => tax
        ? [
            l.name,
            '${l.qtyDisplay} ${l.unitCode}',
            (l.tax?.valueExclTax ?? l.amount).amountOnly,
            l.tax?.rateLabel ?? '-',
            (l.tax?.salesTax ?? Money.zero).amountOnly,
            (l.tax?.valueInclTax ?? l.amount).amountOnly,
          ]
        : [
            l.name,
            '${l.qtyDisplay} ${l.unitCode}',
            l.rate.amountOnly,
            l.amount.amountOnly,
          ];
    Widget cell(String v, int i, {bool head = false}) => Expanded(
      flex: i == 0 ? 3 : 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1.5),
        child: Text(
          v,
          textAlign: i == 0 ? TextAlign.left : TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: style(
            fontSize: tax ? size - 1 : size,
            bold: head,
            mono: !head && i > 0,
            color: head && modern ? BillDesignPreview._paper : null,
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: headerColour,
          child: Row(
            children: [
              for (var i = 0; i < headers.length; i++)
                cell(headers[i], i, head: true),
            ],
          ),
        ),
        for (var r = 0; r < d.lines.length; r++)
          Container(
            decoration: BoxDecoration(
              color: modern && r.isOdd ? accent.withValues(alpha: 0.08) : null,
              border: const Border(
                bottom: BorderSide(color: BillDesignPreview._rule, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                for (final (i, v) in row(d.lines[r]).indexed) cell(v, i),
              ],
            ),
          ),
      ],
    );
  }

  Widget totals() {
    final khata = d.khata;
    Widget pair(String label, String value, {bool bold = false}) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // The label gives way, never the figure.
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: style(bold: bold),
          ),
        ),
        const SizedBox(width: 4),
        Text(value, style: style(bold: bold, mono: true)),
      ],
    );
    final total = Container(
      color: modern ? accent : null,
      padding: modern ? const EdgeInsets.symmetric(horizontal: 2) : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              tax ? 'Value incl. tax' : 'TOTAL',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.clip,
              style: style(
                bold: true,
                color: modern ? BillDesignPreview._paper : null,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            d.total.toString(),
            style: style(
              bold: true,
              mono: true,
              color: modern ? BillDesignPreview._paper : null,
            ),
          ),
        ],
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: khata == null
              ? const SizedBox()
              : Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
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
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: Column(
            children: [
              pair(tax ? 'Value excl. tax' : 'Subtotal', d.subtotal.amountOnly),
              if (d.tax.isPositive) pair('Sales tax', d.tax.amountOnly),
              total,
              for (final t in d.tenders) pair(t.label, t.amount.amountOnly),
            ],
          ),
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
      Divider(color: accent, height: 4, thickness: 0.5),
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
              decoration: BoxDecoration(
                border: Border.all(color: BillDesignPreview._rule),
              ),
              child: Image.memory(qr, fit: BoxFit.contain),
            ),
        ],
      ),
    ];
  }
}

/// The paper's own words. A bill is printed in English and Roman Urdu
/// whatever language the phone is in, so the sketch of one says what the
/// paper says rather than the app's translation of it.
const _payTo = 'Payment ke liye';
