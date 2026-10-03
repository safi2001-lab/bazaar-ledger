import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

/// M61 without a database: the province's tax on services in every tax
/// report, apart from FBR's and never added to it; and a report kept the
/// way the shop likes it, written down and read back.
final _october = ReportPeriod(
  const BusinessDate('2026-10-01'),
  const BusinessDate('2026-10-31'),
);

Money _paisa(int p) => Money.paisa(p);

Object? _cell(ReportTable t, String first, [int column = 1]) =>
    t.rows.firstWhere((r) => r.cells.first == first).cells[column];

List<ReportRow> _lines(ReportTable t) =>
    t.rows.where((r) => r.style == RowStyle.line).toList();

/// A salon's October: an 18% bottle of gel, a haircut in cash at 16%, a
/// bridal package paid part by card (8% on the card's share, 16% on the
/// rest), and the cash haircut given back.
const _rates = [
  RateTax(
    kind: 'sales_tax',
    code: 'ST_STD_18',
    rateBp: 1800,
    isReturn: false,
    lines: 1,
    value: Money.rupees(500),
    tax: Money.rupees(90),
  ),
  RateTax(
    kind: 'provincial_st',
    code: 'PRA_STD',
    rateBp: 1600,
    isReturn: false,
    lines: 2,
    value: Money.paisa(153704),
    tax: Money.paisa(24593),
  ),
  RateTax(
    kind: 'provincial_st',
    code: 'PRA_CARD',
    rateBp: 800,
    isReturn: false,
    lines: 1,
    value: Money.paisa(46296),
    tax: Money.paisa(3704),
  ),
  RateTax(
    kind: 'provincial_st',
    code: 'PRA_STD',
    rateBp: 1600,
    isReturn: true,
    lines: 1,
    value: Money.rupees(1000),
    tax: Money.rupees(160),
  ),
];

/// The same month as the Sales tax summary reads it: the same rows, the
/// return's under the code it gave the tax back under.
List<TaxLine> _summaryLines() => [
  for (final r in _rates)
    TaxLine(
      code: r.isReturn && r.kind == 'provincial_st'
          ? serviceTaxReturnCode(r.code!)
          : r.code!,
      kind: r.kind,
      rateBp: r.rateBp,
      base: r.value,
      amount: r.tax,
      isReturn: r.isReturn,
    ),
];

AnnexLine _line({
  String type = 'sale_invoice',
  String item = 'Hair gel',
  int value = 50000,
  int salesTax = 9000,
  int provincialTax = 0,
  String? provincialCode,
}) => AnnexLine(
  documentId: 'doc-$item-$type',
  docType: type,
  docNo: 'INV-0001',
  date: const BusinessDate('2026-10-03'),
  hsCode: '3305.1000',
  itemName: item,
  qty: Qty.units(1),
  unitCode: 'pcs',
  value: _paisa(value),
  salesTax: _paisa(salesTax),
  furtherTax: Money.zero,
  salesTaxRateBp: salesTax == 0 ? null : 1800,
  taxCode: salesTax == 0 ? null : 'ST_STD_18',
  shopProvince: 'punjab',
  provincialTax: _paisa(provincialTax),
  provincialCode: provincialCode,
);

void main() {
  group('provincial tax in the reports', () {
    test(
      'the tax rate report lists PRA 16% and PRA 8% (card) as rows of their own, gives a return back at its rate, and owes PRA apart from FBR',
      () {
        final t = taxRateReport(_october, _rates);
        expect(_lines(t).map((r) => r.cells.first), [
          'Standard rate',
          'PRA 16%',
          'PRA 8% (card)',
          'PRA 16%',
        ]);
        expect(_lines(t)[1].cells.sublist(1), [
          1600,
          2,
          _paisa(153704),
          _paisa(24593),
        ]);
        expect(_lines(t).last.cells.sublist(1), [
          1600,
          -1,
          -Money.rupees(1000),
          -Money.rupees(160),
        ]);
        // FBR's figures are the gel's alone: the services are not supplies
        // FBR counts, and their tax is not FBR's.
        expect(_cell(t, 'Sales tax', 3), Money.rupees(500));
        expect(_cell(t, 'Sales tax', 4), Money.rupees(90));
        expect(t.totals.single.cells.first, 'Total owed to FBR');
        expect(t.totals.single.cells.last, Money.rupees(90));
        expect(_cell(t, 'Owed to PRA', 3), Money.rupees(1000));
        expect(_cell(t, 'Owed to PRA', 4), _paisa(24593 + 3704 - 16000));
        expect(
          t.summary.singleWhere((f) => f.label == 'Owed to PRA').amount,
          _paisa(12297),
        );
        expect(t.notes, contains(startsWith('Services are taxed by PRA')));
      },
    );

    test(
      'the sales tax summary names the province\'s rows and owes PRA beside FBR, the same figure as the rate report, never added together',
      () {
        final t = salesTaxSummary(_october, _summaryLines());
        final names = t.rows.map((r) => r.cells.first).toList();
        expect(names, [
          'Sales tax 18%',
          'Sales tax owed (FBR)',
          'Further tax owed (FBR)',
          'Total owed to FBR',
          'Provincial tax on services',
          'PRA 16%',
          'PRA 8% (card)',
          'PRA 16% given back on returns',
          'Owed to PRA',
        ]);
        expect(names.where((n) => '$n'.contains('PRA_')), isEmpty);
        expect(t.totals.single.cells.last, Money.rupees(90));
        expect(_cell(t, 'Owed to PRA', 3), _paisa(12297));
        expect(
          _cell(t, 'Owed to PRA', 3),
          _cell(taxRateReport(_october, _rates), 'Owed to PRA', 4),
        );
        expect(_cell(t, 'PRA 16% given back on returns', 3), -_paisa(16000));
        expect(
          [for (final f in t.summary) (f.label, f.amount)],
          [('Owed to FBR', Money.rupees(90)), ('Owed to PRA', _paisa(12297))],
        );
        expect(
          t.notes,
          contains(startsWith('The tax on services is owed to PRA')),
        );
      },
    );

    test('two provinces are owed apart, each its own figure', () {
      final t = salesTaxSummary(_october, const [
        TaxLine(
          code: 'SRB_STD',
          kind: 'provincial_st',
          rateBp: 1500,
          base: Money.rupees(1000),
          amount: Money.rupees(150),
          isReturn: false,
        ),
        TaxLine(
          code: 'PRA_CARD',
          kind: 'provincial_st',
          rateBp: 800,
          base: Money.rupees(1000),
          amount: Money.rupees(80),
          isReturn: false,
        ),
      ]);
      expect(_cell(t, 'Owed to PRA', 3), Money.rupees(80));
      expect(_cell(t, 'Owed to SRB', 3), Money.rupees(150));
      expect(t.totals.single.cells.last, Money.zero);
    });

    test(
      'the tax report and sales by HS code carry the province\'s tax in a column of its own, out of FBR\'s figures',
      () {
        final party = taxReport(_october, [
          PartyTax(
            name: 'Ayesha',
            partyId: 'p-1',
            salesValue: Money.rupees(2500),
            salesTax: Money.rupees(90),
            furtherTax: Money.zero,
            returnsValue: Money.rupees(1000),
            returnsTax: Money.zero,
            purchasesValue: Money.zero,
            inputTax: Money.zero,
            purchaseReturnsValue: Money.zero,
            purchaseReturnsTax: Money.zero,
            servicesValue: Money.rupees(2000),
            provincialTax: _paisa(28297),
            returnsServicesValue: Money.rupees(1000),
            returnsProvincialTax: Money.rupees(160),
          ),
        ]);
        expect(party.columns.map((c) => c.title).skip(8), [
          'Services value',
          'Provincial tax',
        ]);
        final ayesha = _lines(party).single.cells;
        expect(ayesha[3], Money.rupees(500), reason: 'the gel alone');
        expect(ayesha[4], Money.rupees(90), reason: 'FBR\'s output tax');
        expect(ayesha[7], Money.rupees(90), reason: 'FBR\'s net');
        expect(ayesha.sublist(8), [Money.rupees(1000), _paisa(12297)]);
        expect(party.totals.single.cells.last, _paisa(12297));

        final hs = salesByHsCode(_october, [
          HsCodeSales(
            hsCode: '9802.0000',
            example: 'Haircut',
            lines: 3,
            items: 2,
            value: Money.rupees(2000),
            salesTax: Money.zero,
            furtherTax: Money.zero,
            returnsValue: Money.rupees(1000),
            returnsSalesTax: Money.zero,
            returnsFurtherTax: Money.zero,
            provincialTax: _paisa(28297),
            returnsProvincialTax: Money.rupees(160),
          ),
        ]);
        expect(hs.columns.last.title, 'Provincial tax');
        expect(_lines(hs).single.cells.sublist(7), [Money.zero, _paisa(12297)]);
        expect(
          hs.summary.singleWhere((f) => f.label == 'Tax').amount,
          Money.zero,
          reason: 'FBR\'s tax under the code',
        );
      },
    );

    test(
      'Annex-C leaves out a service the province taxed, and says how many lines and how much',
      () {
        final t = annexC(_october, [
          _line(),
          _line(
            item: 'Bridal makeup',
            value: 100000,
            salesTax: 0,
            provincialTax: 12297,
            provincialCode: 'PRA_CARD',
          ),
          _line(
            item: 'Haircut',
            value: 100000,
            salesTax: 0,
            provincialTax: 16000,
            provincialCode: 'PRA_STD',
          ),
          _line(
            type: 'sale_return',
            item: 'Haircut',
            value: 100000,
            salesTax: 0,
            provincialTax: 16000,
            provincialCode: 'PRA_STD_RETURN',
          ),
        ]);
        expect(_lines(t).map((r) => r.cells[26]), ['Hair gel']);
        expect(
          t.summary.singleWhere((f) => f.label == 'Value').amount,
          Money.rupees(500),
        );
        expect(
          t.notes,
          contains(
            '3 lines are services taxed by PRA and left out: Rs 1,000.00 of '
            'services and Rs 122.97 of PRA tax, net of returns. A service the '
            'province taxes is not a supply on FBR\'s return; file it with PRA '
            'from the Sales tax summary.',
          ),
        );
      },
    );

    test('a shop that sells only goods reads exactly as before', () {
      const goods = [
        RateTax(
          kind: 'sales_tax',
          code: 'ST_STD_18',
          rateBp: 1800,
          isReturn: false,
          lines: 1,
          value: Money.rupees(500),
          tax: Money.rupees(90),
        ),
      ];
      final rate = taxRateReport(_october, goods);
      expect(
        rate.rows.where((r) => '${r.cells.first}'.startsWith('Owed')),
        isEmpty,
      );
      expect(rate.summary, hasLength(3));
      final summary = salesTaxSummary(_october, const [
        TaxLine(
          code: 'ST_STD_18',
          kind: 'sales_tax',
          rateBp: 1800,
          base: Money.rupees(500),
          amount: Money.rupees(90),
          isReturn: false,
        ),
      ]);
      expect(summary.summary, isEmpty);
      expect(summary.rows, hasLength(4));
      final party = taxReport(_october, [
        PartyTax(
          name: 'Walk-in',
          salesValue: Money.rupees(500),
          salesTax: Money.rupees(90),
          furtherTax: Money.zero,
          returnsValue: Money.zero,
          returnsTax: Money.zero,
          purchasesValue: Money.zero,
          inputTax: Money.zero,
          purchaseReturnsValue: Money.zero,
          purchaseReturnsTax: Money.zero,
        ),
      ]);
      expect(party.columns, hasLength(8));
      expect(annexC(_october, [_line()]).notes.join(), isNot(contains('PRA')));
    });
  });

  group('saved views', () {
    test(
      'a view keeps its report, its period as chosen, its filters, its sort and its chart, and reads back the same',
      () {
        final view = SavedReportView(
          id: 'v1',
          name: 'Monday udhaar list',
          kind: ReportKind.saleReport,
          preset: DatePreset.thisWeek,
          filters: ReportFilters(
            partyId: 'p-1',
            partyName: 'Rashid Traders',
            partyGroup: 'Mandi',
            paymentStatus: PaymentStatus.unpaid,
            paymentMode: 'jazzcash',
            withBalanceOnly: true,
            asOf: const BusinessDate('2026-09-30'),
            salesDays: 30,
            minAmount: Money.rupees(5000),
          ),
          sortColumn: 'Balance',
          asChart: true,
        );
        final back = decodeSavedViews(encodeSavedViews([view])).single;
        expect(back, view);
        expect(back.filters.partyName, 'Rashid Traders');
        expect(back.filters.minAmount, Money.rupees(5000));
        expect(back.sortColumn, 'Balance');
        expect(back.sortAscending, isFalse);
        expect(back.asChart, isTrue);
      },
    );

    test(
      'a this-week view opens on the week it is opened in, and picked dates stay those dates',
      () {
        const week = SavedReportView(
          id: 'v1',
          name: 'This week',
          kind: ReportKind.dayBook,
          preset: DatePreset.thisWeek,
        );
        expect(
          week.periodOn(const BusinessDate('2026-10-07')).label,
          '2026-10-05 to 2026-10-11',
        );
        expect(
          week.periodOn(const BusinessDate('2026-10-14')).label,
          '2026-10-12 to 2026-10-18',
        );
        final picked = SavedReportView(
          id: 'v2',
          name: 'Eid week',
          kind: ReportKind.saleReport,
          preset: DatePreset.custom,
          custom: ReportPeriod(
            const BusinessDate('2026-03-18'),
            const BusinessDate('2026-03-24'),
          ),
        );
        final back = decodeSavedViews(encodeSavedViews([picked])).single;
        expect(
          back.periodOn(const BusinessDate('2026-10-14')).label,
          '2026-03-18 to 2026-03-24',
        );
      },
    );

    test(
      'a view this build cannot open is dropped, never the rest, and nonsense is no views',
      () {
        const text =
            '{"views": ['
            '{"id": "a", "name": "Gone", "kind": "noSuchReport", "preset": "today"},'
            '{"id": "b", "name": "Kept", "kind": "dayBook", "preset": "today",'
            ' "filters": {"minAmountPaisa": "lots", "paymentStatus": "maybe"}},'
            '{"id": "b", "name": "Twice", "kind": "dayBook", "preset": "today"},'
            '{"id": "c", "name": "  ", "kind": "dayBook", "preset": "today"},'
            '{"id": "d", "name": "Bad dates", "kind": "dayBook", "preset": "custom",'
            ' "from": "2026-10-09", "to": "2026-10-01"}'
            ']}';
        final views = decodeSavedViews(text);
        expect([for (final v in views) v.name], ['Kept']);
        expect(views.single.filters, ReportFilters.none);
        expect(decodeSavedViews('not json'), isEmpty);
        expect(decodeSavedViews('{"views": 7}'), isEmpty);
      },
    );
  });
}
