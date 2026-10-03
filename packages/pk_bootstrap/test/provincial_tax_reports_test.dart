import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// The province's tax on services in every tax report, and given back as
/// it was charged (M61), against a real database: a Lahore salon on PRA
/// that also sells hair gel, its tax rows on the bills, the rate report,
/// the summary, the party and HS reports, Annex-C, a return, and the tax
/// invoice of a bill paid two ways — every figure tied to the others.
void main() {
  late AppServices shop;
  late FixedClock clock;
  late String firmId;
  late String pcs;
  late Map<String, String> accounts;

  setUp(() async {
    clock = FixedClock(DateTime.utc(2026, 10, 3, 5));
    shop = await openInMemoryServices(clock: clock);
    await shop.setUpShop(
      shopName: 'Lahore Hair Studio',
      ownerName: 'Bilal',
      deviceLabel: 'Counter 1',
    );
    firmId = (await shop.queries.currentFirm())!.id;
    pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs').id;
    accounts = {
      for (final a in await shop.queries.paymentAccounts(firmId))
        a.modeLabel: a.id,
    };
    await shop.updateFirm({'is_sales_tax_registered': 1});
    await shop.counterTax.setServiceTax(
      ServiceTaxSetting.publishedFor(ServiceTaxAuthority.pra),
    );
  });

  tearDown(() => shop.close());

  Future<String> item(String name, int rupees, {bool service = false}) =>
      shop.catalogue.addItem(
        shop.actorNow(),
        ItemDraft(
          name: name,
          baseUnitId: pcs,
          saleRate: Rate.rupees(rupees),
          hsCode: service ? '9802.1000' : '3305.1000',
          tracksStock: !service,
          openingStock: service ? Qty.zero : Qty.units(50),
          openingRate: Rate.rupees(rupees ~/ 2),
          isService: service,
        ),
      );

  Future<SaleLineDraft> line(String itemId) async {
    final it = (await shop.queries.itemById(firmId, itemId))!;
    return SaleLineDraft(
      itemId: it.id,
      itemName: it.name,
      hsCode: it.hsCode,
      qty: Qty.units(1),
      baseQty: Qty.units(1),
      unitId: it.unitId,
      unitCode: it.unitCode,
      rate: it.saleRate,
      isService: it.isService,
      tracksStock: it.tracksStock,
    );
  }

  TenderDraft tender(String mode, Money amount) => TenderDraft(
    paymentAccountId: accounts[mode]!,
    mode: mode,
    amount: amount,
  );

  Future<int> scalar(String sql) async {
    final row = await shop.database.customSelect(sql).getSingle();
    return row.read<int?>('n') ?? 0;
  }

  /// What the books owe PRA, read straight off the bills' own tax rows.
  Future<int> praOnTheBills() => scalar(
    'SELECT SUM(CASE WHEN d.doc_type = \'sale_return\' '
    '  THEN -t.amount_paisa ELSE t.amount_paisa END) AS n '
    'FROM document_line_taxes t JOIN documents d ON d.id = t.document_id '
    "WHERE t.tax_kind = 'provincial_st' AND d.status = 'posted' "
    "  AND t.tax_code LIKE 'PRA%'",
  );

  Future<int> outputTax() => scalar(
    'SELECT SUM(jl.credit_paisa - jl.debit_paisa) AS n '
    'FROM journal_lines jl JOIN accounts a ON a.id = jl.account_id '
    "WHERE a.system_key = 'output_tax'",
  );

  Future<int> outOfBalance() => scalar(
    'SELECT COALESCE(SUM(debit_paisa) - SUM(credit_paisa), 0) AS n '
    'FROM journal_lines',
  );

  Future<ReportTable> run(ReportKind kind) {
    final today = BusinessDate.now(shop.clock);
    return shop.reports.run(
      kind,
      firmId: firmId,
      period: ReportPeriod.monthOf(today),
      today: today,
    );
  }

  Object? cell(ReportTable t, String first, [int column = 1]) =>
      t.rows.firstWhere((r) => r.cells.first == first).cells[column];

  Future<RecordedReturn> giveBack(PostedSale sale, Money refund) async {
    final sold = (await shop.queries.returnableLines(
      firmId,
      sale.documentId,
    )).firstWhere((l) => l.itemName != 'Hair gel');
    return shop.recordReturn(
      shop.actorNow(),
      ReturnDraft(
        originalDocumentId: sale.documentId,
        reason: 'Customer not happy',
        refundNow: refund,
        paymentAccountId: accounts['cash'],
        lines: [
          ReturnLineDraft(
            documentLineId: sold.documentLineId,
            qty: sold.returnable,
          ),
        ],
      ),
    );
  }

  group('provincial tax reports', () {
    test(
      'PRA\'s tax in the rate report is PRA\'s in the summary is the tax rows on the bills, and none of it is FBR\'s',
      () async {
        final cut = await item('Haircut', 1000, service: true);
        final bridal = await item('Bridal makeup', 1000, service: true);
        final gel = await item('Hair gel', 500);
        final ayesha = await shop.catalogue.addParty(
          shop.actorNow(),
          const PartyDraft(name: 'Ayesha Bridal', phone: '0300-1112223'),
        );

        // A haircut and a gel by card; a bridal package part card, part
        // cash; a haircut in cash, which comes back.
        await shop.postSale(
          shop.actorNow(),
          SaleDraft(
            lines: [await line(cut), await line(gel)],
            tenders: [tender('card', const Money.rupees(1670))],
          ),
        );
        final split = await shop.postSale(
          shop.actorNow(),
          SaleDraft(
            partyId: ayesha,
            lines: [await line(bridal)],
            roundToRupee: false,
            tenders: [
              tender('card', const Money.rupees(500)),
              tender('cash', const Money.rupees(700)),
            ],
          ),
        );
        final cash = await shop.postSale(
          shop.actorNow(),
          SaleDraft(
            lines: [await line(cut)],
            tenders: [tender('cash', const Money.rupees(1160))],
          ),
        );
        await giveBack(cash, const Money.rupees(1160));

        // On the bills: 80 + 37.04 + 85.93 + 160 charged, 160 given back.
        final owed = await praOnTheBills();
        expect(owed, 8000 + 3704 + 8593);

        final rate = await run(ReportKind.taxRateReport);
        expect(cell(rate, 'Owed to PRA', 4), Money.paisa(owed));
        final lines = rate.rows.where((r) => r.style == RowStyle.line);
        expect([
          for (final r in lines) r.cells.first,
        ], containsAll(['PRA 16%', 'PRA 8% (card)']));
        final back = rate.rows
            .skipWhile((r) => r.cells.first != 'Given back on returns')
            .elementAt(1);
        expect(
          back.cells,
          [
            'PRA 16%',
            1600,
            -1,
            -const Money.rupees(1000),
            -const Money.rupees(160),
          ],
          reason: 'at the rate it was charged, not ST_RETURN at no rate',
        );
        expect(
          lines.where((r) => r.cells.first == 'No sales tax charged'),
          isEmpty,
          reason: 'a service the province taxed is not an untaxed supply',
        );
        expect(rate.totals.single.cells.last, const Money.rupees(90));

        final summary = await run(ReportKind.salesTax);
        expect(cell(summary, 'Owed to PRA', 3), Money.paisa(owed));
        expect(cell(summary, 'Owed to PRA', 3), cell(rate, 'Owed to PRA', 4));
        expect(summary.totals.single.cells.last, const Money.rupees(90));
        expect(
          cell(summary, 'PRA 16% given back on returns', 3),
          -const Money.rupees(160),
        );
        expect(
          summary.rows.where((r) => '${r.cells.first}'.contains('_')),
          isEmpty,
          reason: 'no raw codes',
        );

        // The books: FBR's 90 and PRA's together on Output Sales Tax, as
        // the sale posts them, and balanced.
        expect(await outputTax(), 9000 + owed);
        expect(await outOfBalance(), 0);

        // The party register and the HS codes keep the province apart.
        final party = await run(ReportKind.taxReport);
        expect(party.columns.map((c) => c.title), contains('Provincial tax'));
        expect(cell(party, 'Ayesha Bridal', 9), const Money.paisa(12297));
        expect(cell(party, 'Ayesha Bridal', 4), Money.zero);
        expect(cell(party, 'Ayesha Bridal', 3), Money.zero);
        expect(cell(party, 'Total', 9), Money.paisa(owed));
        expect(cell(party, 'Total', 4), summary.totals.single.cells.last);

        final hs = await run(ReportKind.salesByHsCode);
        expect(cell(hs, '9802.1000', 8), Money.paisa(owed));
        expect(cell(hs, '9802.1000', 7), Money.zero);
        expect(cell(hs, '3305.1000', 7), const Money.rupees(90));

        // Annex-C: the gel alone, and a note of what was left out.
        final annex = await run(ReportKind.annexC);
        expect(
          [
            for (final r in annex.rows.where((r) => r.style == RowStyle.line))
              r.cells[26],
          ],
          ['Hair gel'],
        );
        expect(
          annex.notes,
          contains(
            startsWith('4 lines are services taxed by PRA and left out'),
          ),
        );

        // The tax invoice of the bill paid two ways says both rates.
        final extras = (await shop.queries.billExtras(
          firmId,
          split.documentId,
        ))!;
        final tax = extras.lineTaxes.single;
        expect(tax.rateLabel, '16% / 8%');
        expect(tax.rateSplit, 'PRA 16% on Rs 537.04, 8% (card) on Rs 462.96');
        expect(tax.salesTax, const Money.paisa(12297));
      },
    );

    test(
      'a service paid two ways and given back whole leaves PRA owed nothing, and the return says PRA on its paper',
      () async {
        final bridal = await item('Bridal makeup', 1000, service: true);
        final sale = await shop.postSale(
          shop.actorNow(),
          SaleDraft(
            lines: [await line(bridal)],
            roundToRupee: false,
            tenders: [
              tender('card', const Money.rupees(500)),
              tender('cash', const Money.rupees(700)),
            ],
          ),
        );
        expect(await praOnTheBills(), 3704 + 8593);

        final back = await giveBack(sale, const Money.paisa(112297));
        final rows = await shop.database
            .customSelect(
              'SELECT tax_kind, tax_code, rate_bp, base_paisa, amount_paisa '
              'FROM document_line_taxes WHERE document_id = ? '
              'ORDER BY tax_code',
              variables: [Variable<String>(back.documentId)],
            )
            .get();
        expect(
          [for (final r in rows) r.data],
          [
            {
              'tax_kind': 'provincial_st',
              'tax_code': 'PRA_CARD_RETURN',
              'rate_bp': 800,
              'base_paisa': 46296,
              'amount_paisa': 3704,
            },
            {
              'tax_kind': 'provincial_st',
              'tax_code': 'PRA_STD_RETURN',
              'rate_bp': 1600,
              'base_paisa': 53704,
              'amount_paisa': 8593,
            },
          ],
        );

        expect(await praOnTheBills(), 0);
        expect(await outputTax(), 0);
        expect(await outOfBalance(), 0);
        final summary = await run(ReportKind.salesTax);
        expect(cell(summary, 'Owed to PRA', 3), Money.zero);
        expect(summary.totals.single.cells.last, Money.zero);
        final rate = await run(ReportKind.taxRateReport);
        expect(cell(rate, 'Owed to PRA', 4), Money.zero);
        expect(cell(rate, 'Owed to PRA', 3), Money.zero);

        // The return's own paper names the province, as the bill did.
        final receipt = (await shop.queries.receiptFor(
          firmId,
          back.documentId,
        ))!;
        expect(
          [for (final t in receipt.serviceTaxes) t.label],
          ['PRA 16%', 'PRA 8% (card)'],
        );
        expect(receipt.federalTax, Money.zero);

        // Nothing is left to come back.
        final left = await shop.queries.returnableLines(
          firmId,
          sale.documentId,
        );
        expect(left.single.returnable, Qty.zero);
      },
    );
  });
}
