part of 'bill_pdf.dart';

/// The four PDF layouts M70 added beside M51's four.
///
/// Vyapar's theme list is the first thing its users mention after the bill
/// itself — Tally, GST 1 and 3, Double Divine, French Elite, Landscape 1
/// and 2, Vintage — and most of them are one page in different colours.
/// These are four different pages:
///
/// * **Landscape**: the sheet on its side, for a wholesaler whose bill has
///   more columns than a portrait page holds — HS code, unit, rate,
///   discount, and for a registered seller the value before tax, the rate,
///   the tax and the value with it. It carries every particular s.23 of
///   the Sales Tax Act asks for, as M51's tax invoice does: both parties'
///   names, addresses and registration numbers, and the tax line by line.
///   It calls itself a SALES TAX INVOICE only for a seller with an STRN;
///   anybody else issues an invoice.
/// * **Ruled**: the carbon-copy bill book from the stationer — a border
///   round the page, the name in a panel, "M/s" over a dotted line, every
///   column ruled down to the foot of the table with blank rows under the
///   goods, the amount in words, "E. & O.E." and a line to sign on.
/// * **Elegant**: Times throughout, the name spaced between fine double
///   rules, hairlines between the lines and the amount due in italic.
/// * **Minimal**: no fills and no boxes; the shop's colour only on the
///   figure the customer pays.
///
/// What every layout keeps, these included: the same lines, totals and
/// marks (CANCELLED above everything, the sheet's own name); the transporter's
/// copy with no figure that is money; the khata block as the bill's day had
/// it; the shop's payment details as text and its own QR picture, never one
/// made here; FBR's number; the footer in its own direction; Urdu set right
/// to left so the PDF joins it.
extension _M70Layouts on _Bill {
  /// The page margin of each, the M51 layouts' 24 for the rest.
  double get m70Margin => switch (design.theme) {
    BillTheme.landscape => 20,
    BillTheme.ruled => 28,
    BillTheme.elegant || BillTheme.minimal => 30,
    _ => 24,
  };

  List<pw.Widget> m70Body() => switch (design.theme) {
    BillTheme.landscape => _landscapeBody(),
    BillTheme.ruled => _ruledBody(),
    BillTheme.elegant => _elegantBody(),
    _ => _minimalBody(),
  };

  // --- Shared pieces --------------------------------------------------------

  /// Words in [font], set right to left when they are not Latin.
  pw.Widget _text(
    String value, {
    pw.Font? font,
    double? fontSize,
    PdfColor? color,
    pw.TextAlign? align,
    double? letterSpacing,
  }) {
    final latin = isPrintableLatin(value);
    return pw.Text(
      value,
      textAlign: align,
      style: pw.TextStyle(
        font: font ?? sans,
        fontSize: fontSize ?? size,
        color: color,
        // Spaced only when Latin: spacing Urdu letters apart unjoins them.
        letterSpacing: latin ? letterSpacing : null,
      ),
      textDirection: latin ? null : pw.TextDirection.rtl,
    );
  }

  /// A line's name with what the paper says under it: the free line's
  /// mark (M43), a service's split rates (M61) on a layout that carries
  /// tax, a phone's IMEIs and warranty (M50).
  pw.Widget _nameCell(ReceiptLine l, {pw.Font? font, double? fontSize}) {
    final small = pw.TextStyle(
      font: font ?? sans,
      fontSize: 6.5,
      color: PdfColors.grey700,
    );
    final split = _carriesTax ? l.tax?.rateSplit : null;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _text(
          l.name + (l.isFreeItem ? '  (Bonus / muft)' : ''),
          font: font,
          fontSize: fontSize,
        ),
        if (split != null) pw.Text(split, style: small),
        for (final detail in l.details) pw.Text(detail, style: small),
      ],
    );
  }

  /// The quantity, with its count in packs under it where it says more
  /// (M45).
  pw.Widget _qtyCell(ReceiptLine l, String figure, pw.TextStyle style) {
    final counted = l.qtyWords;
    if (counted == null) return pw.Text(figure, style: style);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(figure, style: style),
        pw.Text(
          counted,
          style: style.copyWith(
            fontSize: (style.fontSize ?? size) - 1.5,
            color: PdfColors.grey700,
          ),
        ),
      ],
    );
  }

  /// A table from columns, each its head, its share of the width, where it
  /// sits and what it says on each line.
  pw.Widget _table(
    List<_Column> columns, {
    required pw.TextStyle headerStyle,
    pw.BoxDecoration? headerDecoration,
    required pw.TextStyle cellStyle,
    required pw.EdgeInsets padding,
    pw.TableBorder? border,
    int minRows = 0,
  }) {
    final rows = <List<Object>>[
      for (final (i, l) in d.lines.indexed)
        [for (final c in columns) c.cell(i, l)],
      // The ruled book's blank rows: the columns run on down the page.
      for (var r = d.lines.length; r < minRows; r++)
        // A line's height of nothing: an empty cell gives the row none.
        [for (final _ in columns) pw.SizedBox(height: size * 1.3)],
    ];
    return pw.TableHelper.fromTextArray(
      headers: [for (final c in columns) c.head],
      data: rows,
      headerStyle: headerStyle,
      headerDecoration: headerDecoration,
      headerAlignments: {for (final (i, c) in columns.indexed) i: c.align},
      cellStyle: cellStyle,
      cellPadding: padding,
      border: border,
      cellAlignments: {for (final (i, c) in columns.indexed) i: c.align},
      columnWidths: {
        for (final (i, c) in columns.indexed)
          i: c.fixed == null
              ? pw.FlexColumnWidth(c.flex)
              : pw.FixedColumnWidth(c.fixed!),
      },
    );
  }

  /// What a line's tax was, or its value after discount with none: a line
  /// nobody read the tax of prints no tax, never a guess.
  ReceiptLineTax _taxOf(ReceiptLine l) =>
      l.tax ??
      ReceiptLineTax(valueExclTax: l.amount - l.discount, salesTax: Money.zero);

  /// Whether this page carries the tax line by line: the landscape page of
  /// a registered seller, or of a bill that charged any.
  bool get _carriesTax =>
      design.theme == BillTheme.landscape &&
      (_Bill._has(d.shop.strn) ||
          d.lines.any((l) => (l.tax?.salesTax ?? Money.zero).isPositive));

  /// The rows above the total, as every layout reads them.
  List<_Figure> get _beforeTotal => [
    if (_carriesTax) ...[
      _Figure(
        'Value excl. tax',
        Money.sum([for (final l in d.lines) _taxOf(l).valueExclTax]).amountOnly,
      ),
      _Figure('Sales tax', d.federalTax.amountOnly),
      for (final t in d.serviceTaxes) _Figure(t.label, t.amount.amountOnly),
    ] else ...[
      _Figure('Subtotal', d.subtotal.amountOnly),
      if (d.discount.isPositive)
        _Figure('Discount', '-${d.discount.amountOnly}'),
      if (d.federalTax.isPositive)
        _Figure('Sales Tax', d.federalTax.amountOnly),
      for (final t in d.serviceTaxes) _Figure(t.label, t.amount.amountOnly),
    ],
    if (d.furtherTax.isPositive)
      _Figure('Further Tax', d.furtherTax.amountOnly),
    if (d.withholding.isPositive)
      _Figure('Withholding', '-${d.withholding.amountOnly}'),
    if (d.extraCharges.isPositive)
      _Figure(d.extraChargesLabel, d.extraCharges.amountOnly), // M50
    if (!d.roundOff.isZero) _Figure('Round Off', _signedRoundOff(d.roundOff)),
  ];

  _Figure get _total => _Figure(
    _carriesTax ? 'Value incl. tax' : 'TOTAL',
    'Rs ${d.total.amountOnly}',
  );

  /// What was handed over, and the bill's own udhaar where no khata block
  /// says it.
  List<_Figure> get _afterTotal => [
    for (final t in d.tenders) _Figure(t.label, t.amount.amountOnly),
    if (d.change.isPositive) _Figure('Change', d.change.amountOnly),
    if (d.balance.isPositive && !_showsKhata)
      _Figure('Baqaya (udhaar)', d.balance.amountOnly),
  ];

  bool get _showsKhata => d.khata != null && !d.isCancelled;

  /// "Rupees Twelve Thousand Five Hundred Fifty only", as a bill book and a
  /// wholesaler's bill write the total under the figure.
  pw.Widget _inWords() => pw.Text(
    'Amount in words: ${rupeesInWords(d.total)}',
    style: pw.TextStyle(
      font: sans,
      fontSize: size - 1,
      color: PdfColors.grey800,
    ),
  );

  /// The shop's payment details beside a QR of [qrSide], for the layouts
  /// that set them in a column rather than across the foot.
  pw.Widget? _paymentColumn(double qrSide) {
    final shop = d.shop;
    final text = <pw.Widget>[
      if (_Bill._has(shop.raastAlias))
        figure('Raast: ${shop.raastAlias}', fontSize: size - 0.5),
      if (_Bill._has(shop.bankIban))
        figure(
          '${shop.bankName ?? 'Bank'}: ${shop.bankIban}',
          fontSize: size - 0.5,
        ),
      if (_Bill._has(shop.bankIban) && _Bill._has(shop.bankAccountTitle))
        words('(${shop.bankAccountTitle})', fontSize: size - 1),
    ];
    if (text.isEmpty && qr == null) return null;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (qr != null) ...[
          pw.Container(
            width: qrSide,
            height: qrSide,
            padding: const pw.EdgeInsets.all(2),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            ),
            child: pw.Image(qr!, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 6),
        ],
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
                    fontSize: 6.5,
                    color: PdfColors.grey700,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Landscape ------------------------------------------------------------

  String get _landscapeTitle => _carriesTax && d.docTitle == 'Invoice'
      ? 'SALES TAX INVOICE'
      : d.docTitle.toUpperCase();

  List<pw.Widget> _landscapeBody() => [
    _landscapeHead(),
    pw.SizedBox(height: 6),
    ...marks(),
    if (!d.transport.isEmpty) ...[transport(), pw.SizedBox(height: 6)],
    _landscapeLines(),
    if (money) ...[pw.SizedBox(height: 8), _landscapeFoot()],
    ...footer(),
  ];

  /// The seller with its registration numbers, the buyer in a box with
  /// theirs, and the paper's title and numbers in the shop's colour: s.23's
  /// particulars across one row, so the page keeps its height for lines.
  pw.Widget _landscapeHead() {
    final white = pw.TextStyle(
      font: sans,
      fontSize: size,
      color: PdfColors.white,
    );
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 5,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logo != null) ...[
                    pw.Image(logo!, height: 38),
                    pw.SizedBox(width: 6),
                  ],
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'SELLER / SUPPLIER',
                          style: pw.TextStyle(
                            font: sansBold,
                            fontSize: 6.5,
                            color: accent,
                          ),
                        ),
                        words(
                          d.shop.name.toUpperCase(),
                          fontSize: 14,
                          bold: true,
                        ),
                        if (shopWhere.isNotEmpty) words(shopWhere),
                        // On a tax invoice a number the seller lacks is
                        // said in words; on anybody else's invoice a line
                        // that says nothing is left off, as the till roll
                        // leaves it.
                        if (_carriesTax || _Bill._has(d.shop.ntn))
                          labelled(
                            'NTN',
                            _Bill._has(d.shop.ntn)
                                ? d.shop.ntn!
                                : 'Unregistered',
                          ),
                        if (_carriesTax || _Bill._has(d.shop.strn))
                          labelled(
                            'STRN',
                            _Bill._has(d.shop.strn)
                                ? d.shop.strn!
                                : 'Unregistered',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              flex: 4,
              child: _partyBox(
                'BUYER / RECIPIENT',
                name: d.customerName ?? 'Walk-in customer',
                address: d.customerAddress,
                phone: d.customerPhone,
                ntn: d.customerNtn,
                strn: d.customerStrn,
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              flex: 3,
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
                color: accent,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      _landscapeTitle,
                      textAlign: pw.TextAlign.right,
                      style: white.copyWith(font: sansBold, fontSize: 11),
                    ),
                    pw.Text('${d.docLabel}: ${d.docNo}', style: white),
                    pw.Text('Date: ${d.dateTimeLabel}', style: white),
                    pw.Text(
                      'Cashier: ${d.cashierName}',
                      style: white.copyWith(fontSize: size - 1),
                    ),
                    // FBR's number with the money it reports on; the
                    // transporter's copy carries neither.
                    if (money)
                      if (d.fbrInvoiceNo case final fbrNo?)
                        pw.Text(
                          'FBR Invoice No: $fbrNo',
                          textAlign: pw.TextAlign.right,
                          style: white.copyWith(fontSize: size - 1),
                        )
                      // Rule 150XC (M59): issued while FBR could not be
                      // reached.
                      else if (d.fbrPending)
                        for (final mark in offlineInvoiceMark)
                          pw.Text(
                            mark,
                            textAlign: pw.TextAlign.right,
                            style: white.copyWith(
                              font: sansBold,
                              fontSize: size - 1,
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Every column a wholesaler's bill is asked for. A registered seller's
  /// carries the value before tax, the rate, the tax and the value with it
  /// on every line; anybody else's the gross, the discount and the net.
  pw.Widget _landscapeLines() {
    final figures = pw.TextStyle(font: mono, fontSize: size);
    pw.Widget fig(String v) => pw.Text(v, style: figures);
    final hs = d.lines.any((l) => l.tax?.hsCode != null);
    final columns = <_Column>[
      _Column('#', (i, _) => '${i + 1}', fixed: 14),
      _Column('Description', (_, l) => _nameCell(l), flex: 4.2),
      if (hs) _Column('HS code', (_, l) => l.tax?.hsCode ?? '', flex: 1.3),
      _Column(
        'Qty',
        (_, l) => _qtyCell(l, l.qtyDisplay, figures),
        flex: 1,
        align: pw.Alignment.centerRight,
      ),
      _Column('Unit', (_, l) => words(l.unitCode), flex: 0.9),
      if (money) ...[
        _Column(
          'Rate',
          (_, l) => fig(l.rate.amountOnly),
          flex: 1.3,
          align: pw.Alignment.centerRight,
        ),
        if (_carriesTax) ...[
          _Column(
            'Disc.',
            (_, l) => fig(l.discount.isPositive ? l.discount.amountOnly : '-'),
            flex: 1.1,
            align: pw.Alignment.centerRight,
          ),
          _Column(
            'Value excl. tax',
            (_, l) => fig(_taxOf(l).valueExclTax.amountOnly),
            flex: 1.5,
            align: pw.Alignment.centerRight,
          ),
          _Column(
            'Tax rate',
            (_, l) => fig(_taxOf(l).rateLabel),
            flex: 0.9,
            align: pw.Alignment.centerRight,
          ),
          _Column(
            'Sales tax',
            (_, l) => fig(_taxOf(l).salesTax.amountOnly),
            flex: 1.3,
            align: pw.Alignment.centerRight,
          ),
          // The unregistered buyer's surcharge in a column of its own when
          // any line carries it, so each row still adds across.
          if (d.lines.any((l) => _taxOf(l).furtherTax.isPositive))
            _Column(
              'Further tax',
              (_, l) => fig(_taxOf(l).furtherTax.amountOnly),
              flex: 1.2,
              align: pw.Alignment.centerRight,
            ),
          _Column(
            'Value incl. tax',
            (_, l) => fig(_taxOf(l).valueInclTax.amountOnly),
            flex: 1.6,
            align: pw.Alignment.centerRight,
          ),
        ] else ...[
          // Gross as every layout prints it, so the column adds up to the
          // Subtotal; the discount beside it and what is left after it.
          _Column(
            'Gross',
            (_, l) => fig(l.amount.amountOnly),
            flex: 1.5,
            align: pw.Alignment.centerRight,
          ),
          _Column(
            'Disc.',
            (_, l) => fig(l.discount.isPositive ? l.discount.amountOnly : '-'),
            flex: 1.1,
            align: pw.Alignment.centerRight,
          ),
          _Column(
            'Net',
            (_, l) => fig((l.amount - l.discount).amountOnly),
            flex: 1.5,
            align: pw.Alignment.centerRight,
          ),
        ],
      ],
    ];
    return _table(
      columns,
      headerStyle: pw.TextStyle(
        font: sansBold,
        fontSize: size - 1,
        color: PdfColors.white,
      ),
      headerDecoration: pw.BoxDecoration(color: accent),
      cellStyle: pw.TextStyle(font: sans, fontSize: size),
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2.5),
      border: pw.TableBorder(
        left: pw.BorderSide(color: accent, width: 0.6),
        right: pw.BorderSide(color: accent, width: 0.6),
        bottom: pw.BorderSide(color: accent, width: 0.6),
        verticalInside: const pw.BorderSide(
          color: PdfColors.grey400,
          width: 0.4,
        ),
        horizontalInside: const pw.BorderSide(
          color: PdfColors.grey300,
          width: 0.4,
        ),
      ),
    );
  }

  /// The khata and the total in words, how to pay, and the figures — side
  /// by side, as the sheet is wide and not tall.
  pw.Widget _landscapeFoot() {
    final paying = _paymentColumn(64);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 4,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _inWords(),
              if (_showsKhata) ...[pw.SizedBox(height: 4), khata()],
            ],
          ),
        ),
        pw.SizedBox(width: 10),
        pw.Expanded(flex: 4, child: paying ?? pw.SizedBox()),
        pw.SizedBox(width: 10),
        pw.Expanded(
          flex: 4,
          child: pw.Column(
            children: [
              for (final f in _beforeTotal) totalRow(f.label, f.value),
              pw.Divider(thickness: 1, height: 6, color: accent),
              totalRow(_total.label, _total.value, emphasis: true),
              for (final f in _afterTotal) totalRow(f.label, f.value),
            ],
          ),
        ),
      ],
    );
  }

  // --- Ruled: the bill book -------------------------------------------------

  /// A border round the page, thick and thin, as the stationer prints it.
  pw.Widget ruledBackground(pw.Context context) => pw.FullPage(
    ignoreMargins: true,
    child: pw.Container(
      margin: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: accent, width: 1.6),
      ),
      child: pw.Container(
        margin: const pw.EdgeInsets.all(2.5),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: accent, width: 0.5),
        ),
      ),
    ),
  );

  List<pw.Widget> _ruledBody() => [
    _ruledHead(),
    pw.SizedBox(height: 6),
    ...marks(),
    _ruledParty(),
    if (!d.transport.isEmpty) ...[pw.SizedBox(height: 4), transport()],
    pw.SizedBox(height: 6),
    _ruledLines(),
    if (money) ...[pw.SizedBox(height: 6), _ruledTotals()],
    if (money) ...fbr(),
    ...footer(),
    _ruledFoot(),
  ];

  pw.Widget _ruledHead() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logo != null) pw.Image(logo!, height: 34, width: 40),
          pw.Expanded(
            child: pw.Column(
              children: [
                words(
                  d.shop.name.toUpperCase(),
                  fontSize: 17,
                  bold: true,
                  color: accent,
                  align: pw.TextAlign.center,
                ),
                if (shopWhere.isNotEmpty)
                  words(shopWhere, fontSize: 8, align: pw.TextAlign.center),
                if (shopTaxIds.isNotEmpty)
                  pw.Text(
                    shopTaxIds,
                    style: pw.TextStyle(font: sans, fontSize: 8),
                  ),
              ],
            ),
          ),
          // The logo's width again on the right, so the name stays in the
          // middle of the page as the stationer sets it.
          if (logo != null) pw.SizedBox(width: 40),
        ],
      ),
      pw.SizedBox(height: 5),
      pw.Row(
        children: [
          pw.Expanded(child: _ruledField('No.', d.docNo)),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text(
              title,
              style: pw.TextStyle(
                font: sansBold,
                fontSize: 9,
                color: PdfColors.white,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: _ruledField('Date', d.dateTimeLabel),
            ),
          ),
        ],
      ),
    ],
  );

  /// "No. INV-0042" with the number on a dotted line, as a bill book is
  /// filled in by hand.
  pw.Widget _ruledField(String label, String value) => pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Text(
        '$label ',
        style: pw.TextStyle(font: sansBold, fontSize: size),
      ),
      pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 1),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(
              color: PdfColors.grey600,
              width: 0.6,
              style: pw.BorderStyle.dotted,
            ),
          ),
        ),
        child: pw.Text(
          value,
          style: pw.TextStyle(font: mono, fontSize: size),
        ),
      ),
    ],
  );

  /// A label and a value on a dotted line that runs to the margin.
  pw.Widget _ruledLine(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          '$label ',
          style: pw.TextStyle(font: sansBold, fontSize: size),
        ),
        pw.Expanded(
          child: pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 1, left: 2),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(
                  color: PdfColors.grey600,
                  width: 0.6,
                  style: pw.BorderStyle.dotted,
                ),
              ),
            ),
            child: words(value),
          ),
        ),
      ],
    ),
  );

  pw.Widget _ruledParty() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      _ruledLine(
        d.partyLabel == 'Supplier' ? 'Supplier' : 'M/s',
        d.customerName ?? '',
      ),
      if (_Bill._has(d.customerAddress))
        _ruledLine('Address', d.customerAddress!),
      if (_Bill._has(d.customerPhone)) _ruledLine('Phone', d.customerPhone!),
      if (_Bill._has(d.customerNtn) || _Bill._has(d.customerStrn))
        _ruledLine(
          'NTN / STRN',
          [
            if (_Bill._has(d.customerNtn)) d.customerNtn!,
            if (_Bill._has(d.customerStrn)) d.customerStrn!,
          ].join('  /  '),
        ),
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2),
        child: pw.Text(
          'Cashier: ${d.cashierName}',
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(
            font: sans,
            fontSize: size - 1.5,
            color: PdfColors.grey700,
          ),
        ),
      ),
    ],
  );

  /// Every column ruled down to the foot of the table, with blank rows
  /// under the goods so a three-line bill still looks like a page of the
  /// book.
  pw.Widget _ruledLines() {
    final figures = pw.TextStyle(font: mono, fontSize: size);
    pw.Widget fig(String v) => pw.Text(v, style: figures);
    final columns = <_Column>[
      _Column(
        'S.No',
        (i, _) => '${i + 1}',
        fixed: 34,
        align: pw.Alignment.center,
      ),
      _Column('Particulars', (_, l) => _nameCell(l), flex: 5),
      _Column(
        'Qty',
        (_, l) => _qtyCell(l, '${l.qtyDisplay} ${l.unitCode}', figures),
        flex: 1.6,
        align: pw.Alignment.centerRight,
      ),
      if (money) ...[
        _Column(
          'Rate',
          (_, l) => fig(l.rate.amountOnly),
          flex: 1.6,
          align: pw.Alignment.centerRight,
        ),
        _Column(
          'Amount',
          (_, l) => fig(l.amount.amountOnly),
          flex: 1.9,
          align: pw.Alignment.centerRight,
        ),
      ],
    ];
    final ink = pw.BorderSide(color: accent, width: 0.8);
    return _table(
      columns,
      headerStyle: pw.TextStyle(font: sansBold, fontSize: size, color: accent),
      headerDecoration: pw.BoxDecoration(
        color: tint,
        border: pw.Border(bottom: ink),
      ),
      cellStyle: pw.TextStyle(font: sans, fontSize: size),
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      border: pw.TableBorder(
        left: ink,
        right: ink,
        top: ink,
        bottom: ink,
        verticalInside: pw.BorderSide(color: accent, width: 0.6),
        horizontalInside: const pw.BorderSide(
          color: PdfColors.grey300,
          width: 0.3,
        ),
      ),
      minRows: design.pageSize == BillPageSize.a4 ? 12 : 5,
    );
  }

  pw.Widget _ruledTotals() => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        flex: 4,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _inWords(),
            if (_showsKhata) ...[pw.SizedBox(height: 4), khata()],
          ],
        ),
      ),
      pw.SizedBox(width: 10),
      pw.Expanded(
        flex: 4,
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: accent, width: 0.8),
          ),
          child: pw.Column(
            children: [
              for (final f in _beforeTotal) totalRow(f.label, f.value),
              pw.Divider(thickness: 0.8, height: 5, color: accent),
              totalRow(_total.label, _total.value, emphasis: true),
              for (final f in _afterTotal) totalRow(f.label, f.value),
            ],
          ),
        ),
      ),
    ],
  );

  /// How to pay on the left, "E. & O.E." under it, and a line for the
  /// signature on the right, for the shop.
  pw.Widget _ruledFoot() {
    final paying = money ? _paymentColumn(60) : null;
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                ?paying,
                pw.SizedBox(height: 4),
                pw.Text(
                  'E. & O.E.',
                  style: pw.TextStyle(
                    font: sans,
                    fontSize: 7,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // "For" over the name rather than beside it: a name in Urdu
              // beside a Latin word is two directions on one line.
              pw.Text(
                'For',
                style: pw.TextStyle(
                  font: sans,
                  fontSize: size - 1.5,
                  color: PdfColors.grey700,
                ),
              ),
              words(d.shop.name, fontSize: size - 1, bold: true),
              pw.SizedBox(height: 18),
              pw.Container(width: 110, height: 0.6, color: PdfColors.grey700),
              pw.Text(
                'Signature / Dastkhat',
                style: pw.TextStyle(
                  font: sans,
                  fontSize: 7,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Elegant --------------------------------------------------------------

  List<pw.Widget> _elegantBody() => [
    _elegantHead(),
    pw.SizedBox(height: 10),
    ...marks(),
    _elegantParties(),
    if (!d.transport.isEmpty) ...[pw.SizedBox(height: 6), transport()],
    pw.SizedBox(height: 10),
    _elegantLines(),
    if (money) ...[pw.SizedBox(height: 10), _elegantTotals()],
    if (money) ...payment(),
    if (money) ...fbr(),
    if (d.footerLines.isNotEmpty) pw.SizedBox(height: 12),
    for (final line in d.footerLines)
      pw.Center(
        child: _text(
          line,
          font: serifItalic,
          fontSize: size,
          align: pw.TextAlign.center,
        ),
      ),
  ];

  /// Two fine rules a hair apart, in the shop's colour.
  pw.Widget _doubleRule() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Container(height: 0.9, color: accent),
      pw.SizedBox(height: 1.5),
      pw.Container(height: 0.3, color: accent),
    ],
  );

  pw.Widget _elegantHead() => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      if (logo != null) ...[
        pw.Center(child: pw.Image(logo!, height: 40)),
        pw.SizedBox(height: 6),
      ],
      pw.Center(
        child: _text(
          d.shop.name.toUpperCase(),
          font: serifBold,
          fontSize: 19,
          letterSpacing: 2.5,
          align: pw.TextAlign.center,
        ),
      ),
      if (shopWhere.isNotEmpty)
        pw.Center(
          child: _text(
            shopWhere,
            font: serifItalic,
            fontSize: 8.5,
            color: PdfColors.grey700,
            align: pw.TextAlign.center,
          ),
        ),
      if (shopTaxIds.isNotEmpty)
        pw.Center(
          child: _text(
            shopTaxIds,
            font: serif,
            fontSize: 8,
            color: PdfColors.grey700,
          ),
        ),
      pw.SizedBox(height: 7),
      _doubleRule(),
      pw.SizedBox(height: 3),
      pw.Center(
        child: _text(
          title,
          font: serif,
          fontSize: 10,
          color: accent,
          letterSpacing: 4,
        ),
      ),
      pw.SizedBox(height: 3),
      _doubleRule(),
    ],
  );

  pw.Widget _elegantParties() {
    final small = pw.TextStyle(font: serif, fontSize: size);
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _text(
                money
                    ? (d.partyLabel == 'Supplier' ? 'Supplier' : 'Billed to')
                    : 'Deliver to',
                font: serifItalic,
                fontSize: size - 0.5,
                color: PdfColors.grey700,
              ),
              if (_Bill._has(d.customerName))
                _text(d.customerName!, font: serifBold, fontSize: size + 2),
              if (_Bill._has(d.customerPhone))
                _text(d.customerPhone!, font: serif),
              if (_Bill._has(d.customerAddress))
                _text(d.customerAddress!, font: serif),
              if (_Bill._has(d.customerNtn))
                _text('NTN ${d.customerNtn}', font: serif),
              if (_Bill._has(d.customerStrn))
                _text('STRN ${d.customerStrn}', font: serif),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              '${d.docLabel} ${d.docNo}',
              style: small.copyWith(font: serifBold, fontSize: size + 1),
            ),
            pw.Text(d.dateTimeLabel, style: small),
            pw.Text(
              'Cashier: ${d.cashierName}',
              style: small.copyWith(
                font: serifItalic,
                color: PdfColors.grey700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _elegantLines() {
    final figures = pw.TextStyle(font: serif, fontSize: size);
    pw.Widget fig(String v) => pw.Text(v, style: figures);
    final columns = <_Column>[
      _Column('Item', (_, l) => _nameCell(l, font: serif), flex: 5),
      _Column(
        'Qty',
        (_, l) => _qtyCell(l, '${l.qtyDisplay} ${l.unitCode}', figures),
        flex: 1.5,
        align: pw.Alignment.centerRight,
      ),
      if (money) ...[
        _Column(
          'Rate',
          (_, l) => fig(l.rate.amountOnly),
          flex: 1.6,
          align: pw.Alignment.centerRight,
        ),
        _Column(
          'Amount',
          (_, l) => fig(l.amount.amountOnly),
          flex: 1.8,
          align: pw.Alignment.centerRight,
        ),
      ],
    ];
    return _table(
      columns,
      headerStyle: pw.TextStyle(
        font: serifBoldItalic,
        fontSize: size,
        color: accent,
      ),
      cellStyle: figures,
      padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3.5),
      border: pw.TableBorder(
        top: pw.BorderSide(color: accent, width: 0.8),
        bottom: pw.BorderSide(color: accent, width: 0.8),
        horizontalInside: const pw.BorderSide(
          color: PdfColors.grey300,
          width: 0.3,
        ),
      ),
    );
  }

  pw.Widget _serifRow(
    String label,
    String value, {
    pw.Font? font,
    double? fontSize,
    PdfColor? color,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            font: font ?? serif,
            fontSize: fontSize ?? size,
            color: color,
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(
            font: font ?? serif,
            fontSize: fontSize ?? size,
            color: color,
          ),
        ),
      ],
    ),
  );

  pw.Widget _elegantTotals() {
    final k = d.khata;
    // What the customer is asked for, in italic under the total: the khata
    // after this bill, or the bill's own udhaar.
    final due = _showsKhata ? k!.after : d.balance;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 3,
          child: !_showsKhata
              ? pw.SizedBox()
              : pw.Container(
                  padding: const pw.EdgeInsets.only(left: 6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border(
                      left: pw.BorderSide(color: accent, width: 1.2),
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      _text(
                        _laterCopy ? 'Khata (bill ke din ka hisaab)' : 'Khata',
                        font: serifItalic,
                        fontSize: size - 0.5,
                        color: accent,
                      ),
                      _serifRow('Pichhla baqaya', k!.before.amountOnly),
                      _serifRow('Is bill', k.thisBill.amountOnly),
                      _serifRow(
                        'Kul baqaya',
                        k.after.amountOnly,
                        font: serifBold,
                      ),
                    ],
                  ),
                ),
        ),
        pw.SizedBox(width: 14),
        pw.Expanded(
          flex: 4,
          child: pw.Column(
            children: [
              for (final f in _beforeTotal) _serifRow(f.label, f.value),
              pw.SizedBox(height: 2),
              _doubleRule(),
              _serifRow(
                'Total',
                _total.value,
                font: serifBold,
                fontSize: size + 2,
              ),
              for (final f in _afterTotal) _serifRow(f.label, f.value),
              if (due.isPositive)
                _serifRow(
                  'Amount due',
                  'Rs ${due.amountOnly}',
                  font: serifBoldItalic,
                  fontSize: size + 2,
                  color: accent,
                ),
            ],
          ),
        ),
      ],
    );
  }

  bool get _laterCopy =>
      d.copyMark != null && d.copyMark != ReceiptCopy.original;

  // --- Minimal --------------------------------------------------------------

  List<pw.Widget> _minimalBody() => [
    _minimalHead(),
    pw.SizedBox(height: 16),
    ...marks(),
    _minimalParties(),
    if (!d.transport.isEmpty) ...[pw.SizedBox(height: 6), transport()],
    pw.SizedBox(height: 14),
    _minimalLines(),
    if (money) ...[pw.SizedBox(height: 12), _minimalTotals()],
    if (money) ...payment(),
    if (money) ...fbr(),
    if (d.footerLines.isNotEmpty) pw.SizedBox(height: 14),
    for (final line in d.footerLines)
      pw.Center(
        child: _text(
          line,
          fontSize: size - 1,
          color: PdfColors.grey700,
          align: pw.TextAlign.center,
        ),
      ),
  ];

  pw.TextStyle get _quiet =>
      pw.TextStyle(font: sans, fontSize: size - 1.5, color: PdfColors.grey600);

  pw.Widget _minimalHead() => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if (logo != null) ...[pw.Image(logo!, height: 28), pw.SizedBox(width: 8)],
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            words(d.shop.name, fontSize: 14, bold: true),
            if (shopWhere.isNotEmpty)
              _text(shopWhere, fontSize: size - 1.5, color: PdfColors.grey600),
            if (shopTaxIds.isNotEmpty) pw.Text(shopTaxIds, style: _quiet),
          ],
        ),
      ),
      pw.SizedBox(width: 10),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(title, style: _quiet.copyWith(letterSpacing: 1.5)),
          pw.Text(
            d.docNo,
            style: pw.TextStyle(font: monoBold, fontSize: size + 1),
          ),
          pw.Text(d.dateTimeLabel, style: _quiet),
        ],
      ),
    ],
  );

  pw.Widget _minimalParties() => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              d.partyLabel.toUpperCase(),
              style: _quiet.copyWith(letterSpacing: 1),
            ),
            if (_Bill._has(d.customerName))
              words(d.customerName!, fontSize: size + 1, bold: true),
            if (_Bill._has(d.customerPhone)) words(d.customerPhone!),
            if (_Bill._has(d.customerAddress)) words(d.customerAddress!),
            if (_Bill._has(d.customerNtn)) labelled('NTN', d.customerNtn!),
            if (_Bill._has(d.customerStrn)) labelled('STRN', d.customerStrn!),
          ],
        ),
      ),
      pw.Text('Cashier: ${d.cashierName}', style: _quiet),
    ],
  );

  pw.Widget _minimalLines() {
    final figures = pw.TextStyle(font: mono, fontSize: size);
    pw.Widget fig(String v) => pw.Text(v, style: figures);
    final columns = <_Column>[
      _Column('ITEM', (_, l) => _nameCell(l), flex: 5),
      _Column(
        'QTY',
        (_, l) => _qtyCell(l, '${l.qtyDisplay} ${l.unitCode}', figures),
        flex: 1.5,
        align: pw.Alignment.centerRight,
      ),
      if (money) ...[
        _Column(
          'RATE',
          (_, l) => fig(l.rate.amountOnly),
          flex: 1.6,
          align: pw.Alignment.centerRight,
        ),
        _Column(
          'AMOUNT',
          (_, l) => fig(l.amount.amountOnly),
          flex: 1.8,
          align: pw.Alignment.centerRight,
        ),
      ],
    ];
    return _table(
      columns,
      headerStyle: _quiet.copyWith(letterSpacing: 1),
      headerDecoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
        ),
      ),
      cellStyle: pw.TextStyle(font: sans, fontSize: size),
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 4),
    );
  }

  pw.Widget _plainRow(String label, String value, {bool emphasis = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                font: emphasis ? sansBold : sans,
                fontSize: emphasis ? size + 1 : size,
                color: emphasis ? null : PdfColors.grey800,
              ),
            ),
            figure(
              value,
              fontSize: emphasis ? size + 4 : size,
              bold: emphasis,
              color: emphasis ? accent : null,
            ),
          ],
        ),
      );

  pw.Widget _minimalTotals() {
    final k = d.khata;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 3,
          child: !_showsKhata
              ? pw.SizedBox()
              : pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Text(
                      _laterCopy ? 'KHATA (bill ke din ka hisaab)' : 'KHATA',
                      style: _quiet.copyWith(letterSpacing: 1),
                    ),
                    _plainRow('Pichhla baqaya', k!.before.amountOnly),
                    _plainRow('Is bill', k.thisBill.amountOnly),
                    _plainRow('Kul baqaya', k.after.amountOnly),
                  ],
                ),
        ),
        pw.SizedBox(width: 24),
        pw.Expanded(
          flex: 4,
          child: pw.Column(
            children: [
              for (final f in _beforeTotal) _plainRow(f.label, f.value),
              pw.Container(
                margin: const pw.EdgeInsets.symmetric(vertical: 3),
                height: 0.4,
                color: PdfColors.grey400,
              ),
              _plainRow(_total.label, _total.value, emphasis: true),
              for (final f in _afterTotal) _plainRow(f.label, f.value),
            ],
          ),
        ),
      ],
    );
  }
}

/// One column of a table: its head, its share of the page, where its
/// figures sit, and what it says on each line.
final class _Column {
  _Column(
    this.head,
    this.cell, {
    this.flex = 1,
    this.fixed,
    this.align = pw.Alignment.centerLeft,
  });

  final String head;
  final Object Function(int index, ReceiptLine line) cell;
  final double flex;
  final double? fixed;
  final pw.Alignment align;
}

/// One row of the totals: what it is and its figure as printed.
final class _Figure {
  const _Figure(this.label, this.value);

  final String label;
  final String value;
}
