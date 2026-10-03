import 'package:pk_domain/pk_domain.dart';

import 'period.dart';
import 'report_table.dart';
import 'tax_source.dart';

/// The Pakistan tax reports (M35), mapped from the GST reports of the
/// market's best-known app onto what a sales-tax-registered shop here
/// files: output tax against input tax party by party, the tax split by
/// rate and regime, sales by HS code, and the per-invoice registers the
/// monthly return's Annex-C (sales) and Annex-A (purchases) are filled
/// from.
///
/// Everything is computed on this phone from what each bill recorded when
/// it was made, at that day's rates, and nothing is sent anywhere: the
/// Annex registers are files for the shop's accountant to put into FBR's
/// own template and file on IRIS.

const _neverSent =
    'Computed on this phone and never sent anywhere. File the return on '
    'IRIS.';

const _inputTaxNote =
    'Input tax is the tax on the shop\'s purchase bills as it recorded them. '
    'The purchase screen does not split a supplier\'s tax out of what was '
    'paid yet, so take it from their invoices when filing.';

/// Output tax on sales against input tax on purchases, party by party,
/// with each party's NTN and STRN (M35): the register a registered shop's
/// accountant reconciles the return against. Its output tax is the Sales
/// tax report's total to the paisa.
///
/// A shop whose services the province taxes (M59) gets two more columns
/// (M61): the services' value and the province's tax on them, net of
/// returns. Never added into Output tax or Net, which are FBR's, and the
/// services are taken out of Sales value, which is what FBR's return
/// counts: the two are owed to different authorities, filed on different
/// portals, and a figure that adds them is a figure nobody can file.
ReportTable taxReport(ReportPeriod period, List<PartyTax> parties) {
  final rows =
      parties
          .where(
            (p) =>
                !p.outputTax.isZero ||
                !p.netInputTax.isZero ||
                !(p.salesValue - p.returnsValue).isZero ||
                !(p.purchasesValue - p.purchaseReturnsValue).isZero ||
                !p.netProvincialTax.isZero,
          )
          .toList()
        ..sort((a, b) {
          final byOutput = b.outputTax.compareTo(a.outputTax);
          if (byOutput != 0) return byOutput;
          final byInput = b.netInputTax.compareTo(a.netInputTax);
          return byInput != 0 ? byInput : a.name.compareTo(b.name);
        });
  Money sum(Money Function(PartyTax p) f) => Money.sum(rows.map(f));
  final output = sum((p) => p.outputTax);
  final input = sum((p) => p.netInputTax);
  // M61: the province's columns only for a shop the province taxed in the
  // period, so a shop that sells goods alone reads exactly as before.
  final services = rows.any(
    (p) => !p.provincialTax.isZero || !p.returnsProvincialTax.isZero,
  );
  final provincial = sum((p) => p.netProvincialTax);
  return ReportTable(
    id: 'tax_report',
    title: 'Tax report',
    period: period,
    columns: [
      const ReportColumn('Party', CellKind.text),
      const ReportColumn('NTN', CellKind.text),
      const ReportColumn('STRN', CellKind.text),
      const ReportColumn('Sales value', CellKind.money),
      const ReportColumn('Output tax', CellKind.money),
      const ReportColumn('Purchases value', CellKind.money),
      const ReportColumn('Input tax', CellKind.money),
      const ReportColumn('Net', CellKind.money),
      if (services) ...const [
        ReportColumn('Services value', CellKind.money),
        ReportColumn('Provincial tax', CellKind.money),
      ],
    ],
    rows: [
      for (final p in rows)
        ReportRow(
          [
            p.name,
            p.ntn ?? '',
            p.strn ?? '',
            p.netFbrSalesValue,
            p.outputTax,
            p.purchasesValue - p.purchaseReturnsValue,
            p.netInputTax,
            p.outputTax - p.netInputTax,
            if (services) ...[p.netServicesValue, p.netProvincialTax],
          ],
          link: p.partyId == null
              ? null
              : ReportLink.party(p.partyId!, label: p.name),
        ),
      ReportRow([
        'Total',
        null,
        null,
        sum((p) => p.netFbrSalesValue),
        output,
        sum((p) => p.purchasesValue - p.purchaseReturnsValue),
        input,
        output - input,
        if (services) ...[sum((p) => p.netServicesValue), provincial],
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Output tax', output),
      ReportFigure('Input tax', input),
      ReportFigure('Net', output - input),
      if (services) ReportFigure('Provincial tax', provincial),
    ],
    notes: [
      _outputTaxNote,
      _inputTaxNote,
      if (services) _partyProvincialNote,
      _neverSent,
    ],
  );
}

/// One footing in the tax rate report, in the order it lists them.
enum TaxRegime {
  standard('Standard rate'),
  reduced('Reduced rate'),
  thirdSchedule('Third Schedule, on retail price'),
  zeroRated('Zero-rated'),
  exempt('Exempt'),
  untaxed('No sales tax charged'),
  furtherTax('Further tax'),

  /// The province's tax on a service (M61): PRA's, SRB's, KPRA's or BRA's,
  /// each row named by its authority and rate, "PRA 8% (card)".
  provincial('Provincial tax on services'),

  /// Tax given back on a return whose sale could not be found to say on
  /// what footing it was charged.
  givenBack('Given back, footing not known');

  const TaxRegime(this.label);

  final String label;
}

/// Which footing [r] is on.
TaxRegime taxRegimeOf(RateTax r) {
  if (r.kind == 'provincial_st') return TaxRegime.provincial;
  if (r.kind == 'further_tax') return TaxRegime.furtherTax;
  if ((r.code ?? '').endsWith('_RETURN')) return TaxRegime.givenBack;
  if (r.kind == 'sales_tax') {
    if (r.code == 'ST_3RD_18' || (r.code ?? '').startsWith('ST_3RD')) {
      return TaxRegime.thirdSchedule;
    }
    if (r.rateBp == 0) return TaxRegime.zeroRated;
    if (r.rateBp < standardSalesTaxBp) return TaxRegime.reduced;
    return TaxRegime.standard;
  }
  return switch (r.code) {
    'exempt' => TaxRegime.exempt,
    'zero_rated' => TaxRegime.zeroRated,
    _ => TaxRegime.untaxed,
  };
}

/// The value of supplies and the tax on them over [period], split by rate
/// and regime (M35): the standard 18%, any reduced rate, Third Schedule
/// goods taxed on their printed retail price, zero-rated, exempt, lines
/// that carried no tax, and the 4% further tax. Returns are taken back,
/// each on its own footing, and the tax at the foot is the Sales tax
/// report's total owed.
///
/// The province's tax on services (M61) is its own rows, one per
/// authority and rate as the bill printed it, "PRA 16%" and "PRA 8%
/// (card)", and its own figure under the total: "Owed to PRA", the same
/// figure the Sales tax summary owes PRA. Never in the sales tax, the value
/// of supplies FBR counts, or the total owed to FBR.
ReportTable taxRateReport(ReportPeriod period, List<RateTax> rates) {
  final sales = [
    for (final r in rates)
      if (!r.isReturn) r,
  ]..sort(_byRegimeAndRate);
  final returns = [
    for (final r in rates)
      if (r.isReturn) r,
  ]..sort(_byRegimeAndRate);
  Money taxOf(Iterable<RateTax> rs, String kind) => Money.sum([
    for (final r in rs)
      if (r.kind == kind) r.tax,
  ]);
  final st = taxOf(sales, 'sales_tax') - taxOf(returns, 'sales_tax');
  final ft = taxOf(sales, 'further_tax') - taxOf(returns, 'further_tax');
  // What sales tax was charged on, net: the further tax is charged on the
  // same supplies and would count them twice, and a service the province
  // taxed is not a supply FBR's return counts (M61).
  Money valueOf(Iterable<RateTax> rs) => Money.sum([
    for (final r in rs)
      if (r.kind != 'further_tax' && r.kind != 'provincial_st') r.value,
  ]);
  final value = valueOf(sales) - valueOf(returns);
  // M61: what each province is owed, net of returns.
  final owedTo = provincialOwed(rates);

  ReportRow row(RateTax r, {required bool back}) {
    final regime = taxRegimeOf(r);
    final sign = back ? -1 : 1;
    return ReportRow([
      regime == TaxRegime.provincial
          ? serviceTaxLabel(r.code ?? '', r.rateBp)
          : regime.label,
      regime == TaxRegime.untaxed ||
              regime == TaxRegime.exempt ||
              regime == TaxRegime.givenBack
          ? null
          : r.rateBp,
      r.lines * sign,
      r.value * sign,
      r.tax * sign,
    ]);
  }

  return ReportTable(
    id: 'tax_rate',
    title: 'Tax rate report',
    period: period,
    columns: const [
      ReportColumn('Tax', CellKind.text),
      ReportColumn('Rate', CellKind.percent),
      ReportColumn('Lines', CellKind.count),
      ReportColumn('Value of supplies', CellKind.money),
      ReportColumn('Tax', CellKind.money),
    ],
    rows: [
      ReportRow.heading('Sales', 5),
      for (final r in sales) row(r, back: false),
      if (returns.isNotEmpty) ...[
        ReportRow.heading('Given back on returns', 5),
        for (final r in returns) row(r, back: true),
      ],
      ReportRow(['Sales tax', null, null, value, st], style: RowStyle.subtotal),
      ReportRow([
        'Further tax',
        null,
        null,
        null,
        ft,
      ], style: RowStyle.subtotal),
      ReportRow([
        'Total owed to FBR',
        null,
        null,
        null,
        st + ft,
      ], style: RowStyle.total),
      for (final o in owedTo)
        ReportRow([
          'Owed to ${o.authority}',
          null,
          null,
          o.value,
          o.tax,
        ], style: RowStyle.subtotal),
    ],
    summary: [
      ReportFigure('Value of supplies', value),
      ReportFigure('Sales tax', st),
      ReportFigure('Further tax', ft),
      for (final o in owedTo) ReportFigure('Owed to ${o.authority}', o.tax),
    ],
    notes: [
      _regimeNote,
      if (owedTo.isNotEmpty)
        _provincialNote([for (final o in owedTo) o.authority]),
      _neverSent,
    ],
  );
}

/// What each province is owed for the services in [rates], net of what
/// returns gave back (M61): the value the tax was charged on and the tax,
/// by authority, in the order of their names. The Tax rate report's "Owed
/// to PRA" is this, and so is the Sales tax summary's.
List<({String authority, Money value, Money tax})> provincialOwed(
  Iterable<RateTax> rates,
) {
  final value = <String, Money>{};
  final tax = <String, Money>{};
  for (final r in rates) {
    if (r.kind != 'provincial_st') continue;
    final who = serviceTaxAuthorityOf(r.code ?? '');
    final sign = r.isReturn ? -1 : 1;
    value[who] = (value[who] ?? Money.zero) + r.value * sign;
    tax[who] = (tax[who] ?? Money.zero) + r.tax * sign;
  }
  return [
    for (final who in value.keys.toList()..sort())
      (authority: who, value: value[who]!, tax: tax[who]!),
  ];
}

int _byRegimeAndRate(RateTax a, RateTax b) {
  final byRegime = taxRegimeOf(a).index.compareTo(taxRegimeOf(b).index);
  if (byRegime != 0) return byRegime;
  // M61: the province's rows by authority first, then the higher rate.
  if (a.kind == 'provincial_st') {
    final who = serviceTaxAuthorityOf(
      a.code ?? '',
    ).compareTo(serviceTaxAuthorityOf(b.code ?? ''));
    if (who != 0) return who;
  }
  final byRate = b.rateBp.compareTo(a.rateBp);
  return byRate != 0 ? byRate : (a.code ?? '').compareTo(b.code ?? '');
}

/// What was sold under each HS code over [period], net of returns (M35),
/// the biggest first and the lines with no code last: what FBR's Digital
/// Invoicing and the Annex-C both ask every line for.
///
/// The province's tax on services sold under a code is a column of its own
/// (M61), after FBR's Total tax and never in it.
ReportTable salesByHsCode(ReportPeriod period, List<HsCodeSales> codes) {
  final rows = codes.toList()
    ..sort((a, b) {
      if ((a.hsCode == null) != (b.hsCode == null)) {
        return a.hsCode == null ? 1 : -1;
      }
      final byValue = b.netValue.compareTo(a.netValue);
      return byValue != 0
          ? byValue
          : (a.hsCode ?? '').compareTo(b.hsCode ?? '');
    });
  final missing = rows.where((r) => r.hsCode == null).toList();
  Money sum(Money Function(HsCodeSales r) f) => Money.sum(rows.map(f));
  // M61: a column for the province's tax only where the period has any.
  final services = rows.any(
    (r) => !r.provincialTax.isZero || !r.returnsProvincialTax.isZero,
  );
  return ReportTable(
    id: 'sales_by_hs_code',
    title: 'Sales by HS code',
    period: period,
    columns: [
      const ReportColumn('HS code', CellKind.text),
      const ReportColumn('For example', CellKind.text),
      const ReportColumn('Items', CellKind.count),
      const ReportColumn('Lines', CellKind.count),
      const ReportColumn('Value', CellKind.money),
      const ReportColumn('Sales tax', CellKind.money),
      const ReportColumn('Further tax', CellKind.money),
      const ReportColumn('Total tax', CellKind.money),
      if (services) const ReportColumn('Provincial tax', CellKind.money),
    ],
    rows: [
      for (final r in rows)
        ReportRow([
          r.hsCode ?? 'No HS code',
          r.example ?? '',
          r.items,
          r.lines,
          r.netValue,
          r.netSalesTax,
          r.netFurtherTax,
          r.netTax,
          if (services) r.netProvincialTax,
        ]),
      ReportRow([
        'Total',
        null,
        rows.fold<int>(0, (n, r) => n + r.items),
        rows.fold<int>(0, (n, r) => n + r.lines),
        sum((r) => r.netValue),
        sum((r) => r.netSalesTax),
        sum((r) => r.netFurtherTax),
        sum((r) => r.netTax),
        if (services) sum((r) => r.netProvincialTax),
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Value', sum((r) => r.netValue)),
      ReportFigure('Tax', sum((r) => r.netTax)),
      if (services)
        ReportFigure('Provincial tax', sum((r) => r.netProvincialTax)),
    ],
    notes: [
      _hsNote,
      if (services) _hsProvincialNote,
      if (missing.isNotEmpty) _noHsCode(missing.single.lines),
    ],
  );
}

// ---------------------------------------------------------------------------
// The Annex registers
// ---------------------------------------------------------------------------

/// The columns of FBR's Domestic Sales Invoices template for the sales tax
/// return's Annex-C, from column B to column AD, in its own order and
/// words: `Sales_Invoice_Template.xlsm`, version 1.0.44, downloaded from
/// e.fbr.gov.pk/SOP/IRIS/help on 3 October 2026, and checked against the
/// template's own validation code (column letters, the lists each column is
/// checked against, a value never below nothing).
///
/// Column M is in the template but hidden; it is here, blank, so the rows
/// copied from this file paste into the template at B7 in one go and every
/// figure lands under its own heading.
const annexCColumns = [
  'Buyer Registration No',
  'Buyer Name',
  'Buyer Type',
  'Sale Origination Province of Supplier',
  'Destination of Supply',
  'Document Type',
  'Document Number',
  'Document Date',
  'HS Code Description',
  'Sale Type',
  'Rate',
  '(hidden in the template; leave blank)',
  'Quantity',
  'UoM',
  'Value of Sales Excluding Sales Tax',
  'Sales Tax/ FED in ST Mode',
  _retailPriceTitle,
  'Extra Tax',
  'Further Tax',
  'Total Value of Sales (In case of PFAD only)',
  'ST Withheld at Source',
  'SRO No./ Schedule No.',
  'Item S. No.',
  'Invoice Reference No.',
  'Reasons',
  'Reason Remarks',
  'Product Description',
  'Petroleum Levy Rate',
  'Additional Sales Tax Rate',
];

/// The columns of FBR's Domestic Purchase Invoices template for Annex-A,
/// B to AB, the same way: `Purchase_Invoice_Template.xlsm`, version 1.0.29,
/// downloaded the same day. Its columns M, T, W and X are hidden and kept
/// here blank for the same reason.
const annexAColumns = [
  'Supplier Registration No',
  'Supplier Name',
  'Supplier Type',
  'Sale Origination Province of Supplier',
  'Destination of Supply',
  'Document Type',
  'Document Number',
  'Document Date',
  'HS Code Description',
  'Purchase Type',
  'Rate',
  '(hidden in the template; leave blank)',
  'Quantity',
  'UoM',
  'Value of Purchases',
  'Sales Tax/ FED in ST Mode',
  'Fixed Retail Value',
  'Extra Tax',
  '(hidden in the template; leave blank) ',
  'FED Charged',
  'ST Withheld as WH Agent',
  '(hidden: SRO No./ Schedule No.)',
  '(hidden: Item S. No.)',
  'Invoice Ref No.',
  'Reasons',
  'Reason Remarks',
  'Product Description',
];

/// Every sale line and credit note line of [period] as the Annex-C asks
/// for it (M35), in FBR's own column order: a file the shop's accountant
/// pastes into FBR's template, validates there, and imports into IRIS.
/// Nothing is uploaded from the phone.
///
/// A service the province taxed (M59) is left out (M61), and a note says
/// how many lines and how much. Since the Eighteenth Amendment a service is
/// the province's to tax: it is not a supply on FBR's sales tax return, and
/// the template has no row for it — M35 checked its columns and lists, and
/// a salon in Lahore is none of its sale types. Listed as a supply at no
/// tax, as it used to be, it told IRIS the shop sold something for nothing
/// tax. The province's own return is filed on the province's own portal,
/// from the Sales tax summary's "Owed to PRA".
ReportTable annexC(ReportPeriod period, List<AnnexLine> lines) {
  bool isSale(AnnexLine l) =>
      l.docType == 'sale_invoice' || l.docType == 'sale_return';
  final sales = [
    for (final l in lines)
      if (isSale(l) && !l.isProvincialService) l,
  ];
  final services = [
    for (final l in lines)
      if (isSale(l) && l.isProvincialService) l,
  ];
  final problems = _AnnexProblems();
  final rows = [for (final l in sales) ReportRow(_annexCRow(l, problems))];
  return ReportTable(
    id: 'annex_c',
    title: 'Annex-C, sales',
    period: period,
    columns: _annexColumns(annexCColumns, _annexCKinds),
    rows: rows,
    summary: _annexSummary(sales),
    notes: [
      _annexHowTo(_dsiTemplate, _dsiVersion, 'Sales Ledger'),
      _creditNoteNote,
      if (services.isNotEmpty) _servicesLeftOut(services),
      ...problems.notes(),
      _neverSent,
    ],
  );
}

/// What the Annex-C left out, in a sentence the accountant can act on
/// (M61): how many service lines, worth how much, carrying how much of
/// which province's tax, net of returns.
String _servicesLeftOut(List<AnnexLine> services) {
  Money net(Money Function(AnnexLine l) f) =>
      Money.sum([for (final l in services) l.isReturn ? -f(l) : f(l)]);
  final who = {
    for (final l in services) serviceTaxAuthorityOf(l.provincialCode ?? ''),
  }.toList()..sort();
  final authorities = who.join(' and ');
  final n = services.length;
  return '$n ${n == 1 ? 'line is a service' : 'lines are services'} taxed '
      'by $authorities and left out: Rs ${net((l) => l.value).amountOnly} '
      'of services and Rs ${net((l) => l.provincialTax).amountOnly} of '
      '$authorities tax, net of returns. A service the province taxes is not '
      'a supply on FBR\'s return; file it with $authorities from the Sales '
      'tax summary.';
}

/// Every purchase line of [period] as the Annex-A asks for it (M35).
ReportTable annexA(ReportPeriod period, List<AnnexLine> lines) {
  final purchases = [
    for (final l in lines)
      if (l.docType == 'purchase_bill' || l.docType == 'purchase_return') l,
  ];
  final problems = _AnnexProblems();
  final rows = [for (final l in purchases) ReportRow(_annexARow(l, problems))];
  return ReportTable(
    id: 'annex_a',
    title: 'Annex-A, purchases',
    period: period,
    columns: _annexColumns(annexAColumns, _annexAKinds),
    rows: rows,
    summary: _annexSummary(purchases),
    notes: [
      _annexHowTo(_dpiTemplate, _dpiVersion, 'Purchase Ledger'),
      _annexAFromSuppliers,
      _annexAValueNote,
      ...problems.notes(),
      _neverSent,
    ],
  );
}

String _annexHowTo(String template, String version, String ledger) =>
    'Copy the rows into FBR\'s $template at cell B7, press Validate in it, '
    'then import it on IRIS under Invoice Management, $ledger. Column order '
    'is the template\'s own, checked against version $version.';

/// FBR's templates, and the versions the columns were checked against.
const _dsiTemplate = 'Sales_Invoice_Template.xlsm';
const _dsiVersion = '1.0.44';
const _dpiTemplate = 'Purchase_Invoice_Template.xlsm';
const _dpiVersion = '1.0.29';

List<ReportFigure> _annexSummary(List<AnnexLine> lines) => [
  ReportFigure.count('Lines', lines.length),
  ReportFigure('Value', Money.sum(lines.map((l) => l.value))),
  ReportFigure('Sales tax', Money.sum(lines.map((l) => l.salesTax))),
  ReportFigure('Further tax', Money.sum(lines.map((l) => l.furtherTax))),
];

List<ReportColumn> _annexColumns(List<String> titles, List<CellKind> kinds) => [
  for (var i = 0; i < titles.length; i++) ReportColumn(titles[i], kinds[i]),
];

const _annexCKinds = [
  CellKind.text, // B registration
  CellKind.text, // C name
  CellKind.text, // D type
  CellKind.text, // E origin
  CellKind.text, // F destination
  CellKind.text, // G document type
  CellKind.text, // H number
  CellKind.text, // I date
  CellKind.text, // J HS code
  CellKind.text, // K sale type
  CellKind.percent, // L rate
  CellKind.text, // M hidden
  CellKind.qty, // N quantity
  CellKind.text, // O UoM
  CellKind.money, // P value
  CellKind.money, // Q sales tax
  CellKind.money, // R retail price
  CellKind.money, // S extra tax
  CellKind.money, // T further tax
  CellKind.money, // U PFAD
  CellKind.money, // V withheld
  CellKind.text, // W SRO
  CellKind.text, // X item no
  CellKind.text, // Y invoice ref
  CellKind.text, // Z reasons
  CellKind.text, // AA remarks
  CellKind.text, // AB description
  CellKind.text, // AC petroleum levy
  CellKind.text, // AD additional tax
];

const _annexAKinds = [
  CellKind.text, // B registration
  CellKind.text, // C name
  CellKind.text, // D type
  CellKind.text, // E origin
  CellKind.text, // F destination
  CellKind.text, // G document type
  CellKind.text, // H number
  CellKind.text, // I date
  CellKind.text, // J HS code
  CellKind.text, // K purchase type
  CellKind.percent, // L rate
  CellKind.text, // M hidden
  CellKind.qty, // N quantity
  CellKind.text, // O UoM
  CellKind.money, // P value
  CellKind.money, // Q sales tax
  CellKind.money, // R retail value
  CellKind.money, // S extra tax
  CellKind.text, // T hidden
  CellKind.money, // U FED
  CellKind.money, // V withheld
  CellKind.text, // W hidden
  CellKind.text, // X hidden
  CellKind.text, // Y invoice ref
  CellKind.text, // Z reasons
  CellKind.text, // AA remarks
  CellKind.text, // AB description
];

List<Object?> _annexCRow(AnnexLine l, _AnnexProblems problems) {
  final walkIn = l.partyName == null || l.partyName!.trim().isEmpty;
  final buyerType = walkIn
      ? 'Retail Consumer'
      : l.isRegistered
      ? 'Registered'
      : 'Unregistered';
  final registration = walkIn ? '' : registrationNo(l);
  if (l.isRegistered && registration.isEmpty) problems.noRegistration++;
  final saleType = annexSaleType(l);
  final hs = fbrHsCode(l.hsCode);
  if (hs.isEmpty) problems.noHsCode++;
  final uom = fbrUnit(l.unitCode);
  if (uom == null) problems.units.add(l.unitCode);
  final origin = fbrProvince(l.shopProvince) ?? '';
  if (origin.isEmpty) problems.noProvince = true;
  return [
    registration,
    walkIn ? 'Walk-in customer' : l.partyName!.trim(),
    buyerType,
    origin,
    fbrProvince(l.partyProvince) ?? origin,
    l.isReturn ? 'Credit Note' : 'Sale Invoice',
    l.docNo,
    fbrDate(l.date),
    hs,
    saleType,
    _annexRate(l),
    null,
    l.qty.abs,
    uom ?? l.unitCode,
    l.value.abs,
    l.salesTax.abs,
    l.isThirdSchedule ? (l.value + l.salesTax).abs : null,
    null,
    l.furtherTax.abs,
    null,
    null,
    l.isThirdSchedule ? '3rd Schedule goods' : '',
    '',
    l.isReturn ? (l.reference ?? '') : '',
    l.isReturn ? 'Return of goods' : '',
    l.isReturn ? (l.reason ?? '') : '',
    l.itemName,
    '',
    '',
  ];
}

List<Object?> _annexARow(AnnexLine l, _AnnexProblems problems) {
  final registration = registrationNo(l);
  if (l.isRegistered && registration.isEmpty) problems.noRegistration++;
  final hs = fbrHsCode(l.hsCode);
  if (hs.isEmpty) problems.noHsCode++;
  final uom = fbrUnit(l.unitCode);
  if (uom == null) problems.units.add(l.unitCode);
  final destination = fbrProvince(l.shopProvince) ?? '';
  if (destination.isEmpty) problems.noProvince = true;
  return [
    registration,
    (l.partyName ?? '').trim(),
    l.isRegistered ? 'Registered' : 'Unregistered',
    fbrProvince(l.partyProvince) ?? destination,
    destination,
    l.isReturn ? 'Debit Note' : 'Purchase Invoice',
    l.docNo,
    fbrDate(l.date),
    hs,
    annexSaleType(l),
    l.salesTaxRateBp,
    null,
    l.qty.abs,
    uom ?? l.unitCode,
    l.value.abs,
    l.salesTax.abs,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    l.isReturn ? (l.reference ?? '') : '',
    l.isReturn ? 'Return of goods' : '',
    l.isReturn ? (l.reason ?? '') : '',
    l.itemName,
  ];
}

/// The rate the template's Rate column expects: the sales tax rate as a
/// share, nothing for an exempt line (the template's own list has
/// "Exempt" for it, chosen there), and nought for a zero-rated one.
int? _annexRate(AnnexLine l) {
  if (l.exemptRule == 'exempt') return null;
  if (l.exemptRule == 'zero_rated') return 0;
  return l.salesTaxRateBp;
}

/// The template's Sale Type for [l], from its own list.
String annexSaleType(AnnexLine l) {
  if (l.isThirdSchedule) return '3rd Schedule Goods';
  if (l.exemptRule == 'exempt') return 'Exempt goods';
  if (l.exemptRule == 'zero_rated' || l.salesTaxRateBp == 0) {
    return 'Goods at zero-rate';
  }
  final rate = l.salesTaxRateBp;
  if (rate != null && rate < standardSalesTaxBp) return 'Goods at Reduced Rate';
  return 'Goods at standard rate (default)';
}

/// The registration number the template's validation accepts: an NTN with
/// its check digit (`1234567-8`), else a 13-digit STRN or CNIC, else
/// whatever the khata holds, for the accountant to put right.
String registrationNo(AnnexLine l) {
  final ntn = l.ntn?.trim() ?? '';
  if (_ntnWithCheckDigit.hasMatch(ntn)) return ntn;
  for (final n in [l.strn, l.cnic]) {
    final digits = (n ?? '').replaceAll(_spacesAndDashes, '');
    if (_thirteenDigits.hasMatch(digits)) return digits;
  }
  return ntn;
}

// Compiled once: the Annex registers run them on every line of a month.
final _ntnWithCheckDigit = RegExp(r'^[A-Za-z0-9]{7}-\d$');
final _spacesAndDashes = RegExp(r'[\s-]');
final _thirteenDigits = RegExp(r'^\d{13}$');
final _dottedHs = RegExp(r'^\d{4}\.\d{4}$');
final _eightDigits = RegExp(r'^\d{8}$');
final _spaces = RegExp(r'\s+');

/// An HS code as the template's list writes it: `1006.3090:-`. A code kept
/// without its dot is given one; anything else is left as typed, for the
/// accountant to put right, and none is blank.
String fbrHsCode(String? code) {
  final c = (code ?? '').trim();
  if (c.isEmpty) return '';
  if (_dottedHs.hasMatch(c)) return '$c:-';
  if (_eightDigits.hasMatch(c)) {
    return '${c.substring(0, 4)}.${c.substring(4)}:-';
  }
  return c;
}

/// A shop's units as the template's UoM list names them, or null for a
/// unit the list does not have.
String? fbrUnit(String unitCode) => switch (unitCode.trim().toLowerCase()) {
  'pcs' || 'pc' || 'nos' || 'no' => 'Numbers, pieces, units',
  'dozen' || 'doz' => 'Dozen',
  'kg' => 'KG',
  'g' || 'gm' => 'Gram',
  'maund' => '40KG',
  'l' || 'ltr' || 'litre' || 'liter' => 'Liter',
  'm' || 'meter' || 'metre' => 'Meter',
  'pair' => 'Pair',
  'set' => 'SET',
  'bag' => 'Bag',
  'ft' || 'foot' => 'Foot',
  'carat' => 'Carat',
  _ => null,
};

/// A province as the template's list names it, from the shop's own code
/// (`punjab`, `kpk`...) or a name typed on a khata; null when it is not
/// one the list has.
String? fbrProvince(String? province) {
  final p = (province ?? '').trim().toLowerCase().replaceAll(_spaces, ' ');
  return switch (p) {
    'punjab' => 'PUNJAB',
    'sindh' => 'SINDH',
    'kpk' ||
    'kp' ||
    'khyber pakhtunkhwa' ||
    'khyber pakhtoonkhwa' => 'KHYBER PAKHTUNKHWA',
    'balochistan' || 'baluchistan' => 'BALOCHISTAN',
    'ict' || 'islamabad' || 'capital territory' => 'CAPITAL TERRITORY',
    'gb' || 'gilgit baltistan' || 'gilgit-baltistan' => 'GILGIT BALTISTAN',
    'ajk' ||
    'azad kashmir' ||
    'azad jammu and kashmir' => 'AZAD JAMMU AND KASHMIR',
    _ => null,
  };
}

/// `15-Sep-2026`: a date the template's validation reads as one in every
/// locale (it asks VBA's IsDate), and that Excel turns into a date when it
/// opens the CSV.
String fbrDate(BusinessDate d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day.toString().padLeft(2, '0')}-${months[d.month - 1]}-${d.year}';
}

/// What the accountant has to put right before the template validates.
final class _AnnexProblems {
  int noHsCode = 0;
  int noRegistration = 0;
  bool noProvince = false;
  final Set<String> units = {};

  List<String> notes() => [
    if (noHsCode > 0) _noHsCode(noHsCode),
    if (noRegistration > 0) _noRegistration(noRegistration),
    if (noProvince)
      'The shop\'s province is not one FBR\'s list has: set it in Settings.',
    if (units.isNotEmpty) _noUnit(units),
  ];
}

const _outputTaxNote =
    'Output tax is sales tax and further tax charged, less what returns gave '
    'back. Values are before tax and net of returns.';

const _partyProvincialNote =
    'Provincial tax is the province\'s tax on services (PRA, SRB, KPRA or '
    'BRA), net of returns: owed to the province, not FBR, and never in '
    'Output tax or Net. Sales value leaves those services out; they are in '
    'Services value.';

const _hsProvincialNote =
    'Provincial tax is the province\'s tax on the services sold under a '
    'code, net of returns. It is owed to the province, not FBR, and is never '
    'in Total tax.';

String _provincialNote(List<String> authorities) {
  final who = authorities.join(' and ');
  return 'Services are taxed by $who, not FBR: their rows are the rates the '
      'bills charged, in cash and by card, and what is owed to $who is never '
      'in the sales tax, the value of supplies or the total owed to FBR.';
}

const _regimeNote =
    'Third Schedule goods are taxed inside their printed retail price; the '
    'value shown is that price less the tax in it. Exempt and zero-rated are '
    'read from the item\'s tax rule as it stands now; a line with no tax and '
    'no such rule is under No sales tax charged.';

const _hsNote =
    'Values are before tax and net of returns; the code is the one on the '
    'bill line, or the item\'s where the line has none.';

String _noHsCode(int lines) =>
    '$lines ${lines == 1 ? 'line has' : 'lines have'} no HS code. FBR asks '
    'for one on every line: add it to the item.';

String _noRegistration(int lines) =>
    '$lines ${lines == 1 ? 'line is' : 'lines are'} to a registered party '
    'with no NTN, STRN or CNIC on their khata.';

String _noUnit(Set<String> units) =>
    'FBR\'s list has no unit for ${(units.toList()..sort()).join(', ')}: '
    'choose the nearest in the template.';

const _retailPriceTitle =
    'Fixed / Notified value or Retail Price / Higher of actual and minimum '
    'fixed value of supplies';

const _creditNoteNote =
    'A return is a Credit Note against the bill it returns, its figures '
    'written as they are, never below nothing, as the template asks.';

const _annexAFromSuppliers =
    'Most of Annex-A is filled on IRIS from what suppliers filed; this '
    'register is what to check it against, and what to enter for a supplier '
    'who did not file.';

const _annexAValueNote =
    'Value of Purchases is what the shop recorded paying for the goods. The '
    'purchase screen does not split a supplier\'s tax out of it yet: take '
    'the value without tax, the rate and the tax from their invoice. Goods '
    'sent back are written as a Debit Note.';
