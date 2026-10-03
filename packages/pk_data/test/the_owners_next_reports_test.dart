import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// The reports an accountant and an owner reach for next (M67), against a
/// real database, each tied to the books it reads.
///
/// The shop: oil and rice bought in August from Punjab Rice Mills on
/// account, sold in August and September for cash and on udhaar (Rashid's
/// August bill a month late by October), the rent paid in September; on
/// the 3rd of October a tin of oil sold under its cost, a bill rung by
/// mistake and cancelled, Surf sold past its shelf and since set to refuse
/// that, sugar sold with none on the shelf, a cheque from Rashid that can
/// be banked and an old one gone stale, a bank account paid out of with
/// nothing in it, a batch of Panadol past its date, and a bill made
/// offline that FBR has still not had a day after it could.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late ReportEngine reports;
  late DriftReportSource source;
  late TxRunner runner;
  late String rashid;
  late String akbar;
  late String oil;
  late String rice;
  late String surf;
  late String sugar;
  late String ghee;
  late String cancelled;
  late String offline;
  late String bank;

  const today = BusinessDate('2026-10-03');
  final september = ReportPeriod.monthOf(const BusinessDate('2026-09-15'));
  final twoMonths = ReportPeriod(
    const BusinessDate('2026-08-01'),
    const BusinessDate('2026-09-30'),
  );

  ActorContext on(String date) =>
      firm.actorAt(DateTime.parse('${date}T04:00:00Z'));

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 10, 3, 4));
    db = await openTestDatabase();
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    source = DriftReportSource(db);
    reports = ReportEngine(source);
    final queries = DriftAppQueries(db);

    final pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');
    late String mill;
    late String panadol;
    await runner.run(on('2026-08-01'), (tx) async {
      rashid = await tx.insert('parties', {
        'name': 'Rashid Traders',
        'name_search': 'rashid traders',
        'party_type': 'customer',
        'phone': '0300 1234567',
      });
      akbar = await tx.insert('parties', {
        'name': 'Akbar',
        'name_search': 'akbar',
        'party_type': 'customer',
      });
      mill = await tx.insert('parties', {
        'name': 'Punjab Rice Mills',
        'name_search': 'punjab rice mills',
        'party_type': 'supplier',
      });
      Future<String> item(
        String name,
        int rupees, {
        String? category,
        Map<String, Object?> more = const {},
      }) => tx.insert('items', {
        'name': name,
        'name_search': name.toLowerCase(),
        'base_unit_id': pcs,
        'category': ?category,
        'sale_rate_milli_paisa': Rate.rupees(rupees).inMilliPaisa,
        ...more,
      });
      oil = await item('Cooking Oil 5L', 2500, category: 'Ghee and oil');
      rice = await item('Chawal 25kg', 3000, category: 'Chawal');
      surf = await item('Surf 1kg', 300);
      sugar = await item('Cheeni 1kg', 160);
      panadol = await item('Panadol', 10, more: {'track_batch': 1});
      final gst = await tx.insert('tax_rules', {
        'pack_version': 'test',
        'code': 'ST_STD_18',
        'name_en': 'Sales tax 18%',
        'name_ur': 'Sales tax 18%',
        'tax_kind': 'sales_tax',
        'jurisdiction': 'federal',
        'rate_bp': 1800,
        'effective_from_local': '2025-07-01',
      });
      // Its price has the tax in it.
      ghee = await item(
        'Ghee 1kg',
        590,
        category: 'Ghee and oil',
        more: {'tax_rule_id': gst, 'price_includes_tax': 1},
      );
    });

    final accounts = await queries.paymentAccounts(firm.firmId);
    final cash = accounts.firstWhere((a) => a.modeLabel == 'cash');
    final chequeDesk = accounts.firstWhere((a) => a.modeLabel == 'cheque');
    bank = accounts.firstWhere((a) => a.modeLabel == 'bank_transfer').id;

    final buy = RecordPurchaseUseCase(
      writer: DriftPurchaseWriter(runner: runner),
    );
    PurchaseLineDraft bought(
      String id,
      String name,
      int qty,
      int rupees, {
      String? batch,
      BusinessDate? expiry,
    }) => PurchaseLineDraft(
      itemId: id,
      itemName: name,
      qty: Qty.units(qty),
      baseQty: Qty.units(qty),
      unitId: pcs,
      unitCode: 'pcs',
      rate: Rate.rupees(rupees),
      batchNo: batch,
      expiry: expiry,
    );
    await buy(
      on('2026-08-01'),
      PurchaseDraft(
        partyId: mill,
        supplierBillNo: 'PRM/1',
        lines: [
          bought(oil, 'Cooking Oil 5L', 20, 2000),
          bought(rice, 'Chawal 25kg', 10, 2400),
          bought(ghee, 'Ghee 1kg', 10, 450),
          bought(
            panadol,
            'Panadol',
            20,
            5,
            batch: 'B-17',
            expiry: const BusinessDate('2026-09-15'),
          ),
        ],
      ),
    );

    final sell = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    SaleLineDraft line(String id, String name, int qty, int rupees) =>
        SaleLineDraft(
          itemId: id,
          itemName: name,
          qty: Qty.units(qty),
          baseQty: Qty.units(qty),
          unitId: pcs,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
        );
    Future<String> cashSale(String date, List<SaleLineDraft> lines) async {
      final total = Money.sum([for (final l in lines) l.rate.amountFor(l.qty)]);
      return (await sell(
        on(date),
        SaleDraft(
          lines: lines,
          roundToRupee: false,
          tenders: [
            TenderDraft(paymentAccountId: cash.id, mode: 'cash', amount: total),
          ],
        ),
      )).documentId;
    }

    await cashSale('2026-08-05', [line(oil, 'Cooking Oil 5L', 4, 2500)]);
    // Rashid's August udhaar: due on the 31st, a month late by October.
    await sell(
      on('2026-08-01'),
      SaleDraft(
        lines: [line(rice, 'Chawal 25kg', 2, 3000)],
        partyId: rashid,
        partyName: 'Rashid Traders',
        roundToRupee: false,
      ),
    );
    await cashSale('2026-09-10', [
      line(oil, 'Cooking Oil 5L', 6, 2500),
      line(rice, 'Chawal 25kg', 3, 3000),
    ]);
    await sell(
      on('2026-09-12'),
      SaleDraft(
        lines: [line(oil, 'Cooking Oil 5L', 1, 2500)],
        partyId: akbar,
        partyName: 'Akbar',
        roundToRupee: false,
      ),
    );
    await RecordExpenseUseCase(writer: DriftExpenseWriter(runner: runner))(
      on('2026-09-20'),
      ExpenseDraft(
        accountSystemKey: 'rent',
        amount: const Money.rupees(5000),
        note: 'Shutter rent',
        paymentAccountId: cash.id,
      ),
    );

    // The 3rd of October.
    await cashSale('2026-10-03', [line(oil, 'Cooking Oil 5L', 1, 1500)]);
    cancelled = await cashSale('2026-10-03', [
      line(rice, 'Chawal 25kg', 1, 3000),
    ]);
    await VoidDocumentUseCase(writer: DriftVoidWriter(runner: runner))(
      on('2026-10-03'),
      documentId: cancelled,
      reason: 'Galti se',
    );
    await cashSale('2026-10-03', [
      line(surf, 'Surf 1kg', 2, 300),
      line(sugar, 'Cheeni 1kg', 1, 160),
    ]);
    // Since set to refuse a sale past the shelf: two counters apart sold.
    await runner.run(on('2026-10-03'), (tx) async {
      await tx.update('items', surf, {'negative_stock': 'block'});
    });
    final receive = RecordReceiptUseCase(
      writer: DriftPaymentWriter(runner: runner),
    );
    for (final (no, dated, rupees) in [
      ('000123', '2026-09-30', 1000),
      ('000456', '2026-03-01', 500),
    ]) {
      await receive(
        on('2026-09-01'),
        ReceiptDraft(
          partyId: rashid,
          amount: Money.rupees(rupees),
          mode: 'cheque',
          paymentAccountId: chequeDesk.id,
          chequeNo: no,
          chequeBank: 'HBL',
          chequeDateUtcMillis: chequeDueUtcMillis(BusinessDate(dated)),
        ),
      );
    }
    // Paid from a bank account with nothing in it.
    await RecordExpenseUseCase(writer: DriftExpenseWriter(runner: runner))(
      on('2026-10-02'),
      ExpenseDraft(
        accountSystemKey: 'utilities',
        amount: const Money.rupees(800),
        note: 'LESCO',
        paymentAccountId: bank,
      ),
    );
    // A bill made on the 1st while FBR could not be reached; FBR answered
    // an hour after, and the bill is still waiting.
    offline = await cashSale('2026-10-01', [
      line(oil, 'Cooking Oil 5L', 1, 2500),
    ]);
    final made = DateTime.parse('2026-10-01T04:00:00Z').millisecondsSinceEpoch;
    await runner.run(on('2026-10-01'), (tx) async {
      await tx.update('documents', offline, {'fbr_status': 'pending'});
      for (final (key, value) in [
        ('fbr.enabled', '1'),
        ('fbr.since', '${made - 1000}'),
        ('fbr.back_at', '${made + 3600 * 1000}'),
      ]) {
        await tx.insert('settings', {
          'setting_key': key,
          'setting_value': value,
        });
      }
    });
  });

  tearDown(() async => db.close());

  Future<ReportTable> run(
    ReportKind kind, {
    ReportPeriod? period,
    BusinessDate asOf = today,
    ReportFilters filters = ReportFilters.none,
    ReportOptions options = ReportOptions.standard,
  }) => reports.run(
    kind,
    firmId: firm.firmId,
    period: period ?? september,
    today: asOf,
    filters: filters,
    options: options,
  );

  Money line(ReportTable t, String label) =>
      t.rows.firstWhere((r) => r.cells.first == label).cells[1]! as Money;

  Object? at(ReportTable t, ReportRow r, String title) =>
      r.cells[t.columns.indexWhere((c) => c.title == title)];

  group('ratio analysis', () {
    test('every input ties to the Profit and Loss and the Balance Sheet of '
        'the period', () async {
      final ratios = await run(ReportKind.ratioAnalysis);
      final pnl = await run(ReportKind.profitAndLoss);
      final sheet = await run(
        ReportKind.balanceSheet,
        asOf: const BusinessDate('2026-09-30'),
      );
      Money tile(String label) =>
          ratios.summary.firstWhere((f) => f.label == label).amount!;
      expect(tile('Net sales'), line(pnl, 'Net sales'));
      expect(tile('Net sales'), const Money.rupees(26500));
      expect(tile('Gross profit'), line(pnl, 'Gross profit'));
      expect(tile('Net profit'), pnl.totals.single.cells[1]);
      String worked(RatioKind k) =>
          ratios.rows.firstWhere((r) => r.cells.first == k.title).cells.last!
              as String;
      expect(
        worked(RatioKind.grossMargin),
        'Gross profit Rs ${line(pnl, 'Gross profit').amountOnly} of net '
        'sales Rs ${line(pnl, 'Net sales').amountOnly}',
      );
      expect(
        worked(RatioKind.currentRatio),
        endsWith(
          'everything owed Rs ${line(sheet, 'Total liabilities').amountOnly}',
        ),
      );
      expect(
        worked(RatioKind.stockTurnover),
        startsWith(
          'Cost of goods sold Rs ${line(pnl, 'Cost of goods sold').amountOnly}',
        ),
      );
      // August beside it: its own Profit and Loss.
      final august = await run(
        ReportKind.profitAndLoss,
        period: ReportPeriod.monthOf(const BusinessDate('2026-08-01')),
      );
      final gross = ratios.rows.firstWhere(
        (r) => r.cells.first == RatioKind.grossMargin.title,
      );
      expect(
        at(ratios, gross, 'Period before'),
        formatBp(
          shareBp(line(august, 'Gross profit'), line(august, 'Net sales')),
        ),
      );
    });
  });

  group('ABC classification', () {
    test("the classes' sales add up to Item-wise profit's and Sales by "
        "item's, and narrow by category", () async {
      final abc = await run(ReportKind.abcClassification, period: twoMonths);
      final items = await run(ReportKind.itemProfitAndLoss, period: twoMonths);
      final byItem = await run(ReportKind.salesByItem, period: twoMonths);
      Money classes() => Money.sum([
        for (final f in abc.summary)
          if (f.label.endsWith(' sales')) f.amount!,
      ]);
      expect(classes(), at(items, items.rows.last, 'Sales'));
      expect(classes(), at(byItem, byItem.rows.last, 'Sales'));
      expect(classes(), const Money.rupees(42500));
      final lines = abc.rows.where((r) => r.style == RowStyle.line).toList();
      expect(lines.map((r) => at(abc, r, 'Item')), [
        'Cooking Oil 5L',
        'Chawal 25kg',
      ]);
      // Oil is 64.7% of the sales: rice starts under the A line too.
      expect(lines.map((r) => at(abc, r, 'Class')), ['A', 'A']);

      final chawal = await run(
        ReportKind.abcClassification,
        period: twoMonths,
        filters: const ReportFilters(category: 'Chawal'),
      );
      expect(
        chawal.rows
            .where((r) => r.style == RowStyle.line)
            .map((r) => at(chawal, r, 'Item')),
        ['Chawal 25kg'],
      );
    });
  });

  group('stock valued four ways', () {
    test('at cost the shelf is Inventory in the books; at a price it is '
        'the stock times the price, the tax in or out', () async {
      final atCost = await run(ReportKind.stockSummary);
      final books = await source.inventoryAsOf(firm.firmId, today);
      Money tile(ReportTable t, String label) =>
          t.summary.firstWhere((f) => f.label == label).amount!;
      expect(tile(atCost, 'Stock value'), books);
      expect(tile(atCost, 'Inventory in the books'), books);

      final lines = await source.stockLines(firm.firmId, today);
      Money priced(StockValuation v) =>
          Money.sum([for (final l in lines) l.valueAt(v)]);
      for (final v in StockValuation.values) {
        final t = await run(
          ReportKind.stockSummary,
          filters: ReportFilters(valuation: v),
        );
        expect(tile(t, 'Stock value'), priced(v), reason: '$v');
        expect(
          t.summary.any((f) => f.label == 'Inventory in the books'),
          v == StockValuation.cost,
        );
      }
      final gheeLine = lines.firstWhere((l) => l.itemId == ghee);
      expect(gheeLine.taxBp, 1800);
      expect(gheeLine.priceIncludesTax, isTrue);
      // Rs 590 with the tax in it, ten on the shelf.
      expect(
        gheeLine.valueAt(StockValuation.salePriceWithTax),
        const Money.rupees(5900),
      );
      expect(
        gheeLine.valueAt(StockValuation.salePrice),
        const Money.rupees(5000),
      );
      final byCategory = await run(
        ReportKind.stockSummaryByCategory,
        filters: const ReportFilters(valuation: StockValuation.salePrice),
      );
      expect(
        byCategory.summary.single.amount,
        priced(StockValuation.salePrice),
      );
    });
  });

  group("ageing in the shop's buckets", () {
    test('the standard buckets read what the old reads read, and other '
        'buckets move money between columns, never the total', () async {
      final old = receivablesByAge(
        today,
        await source.receivables(firm.firmId, today),
      );
      final now = await run(ReportKind.receivables);
      expect(
        [for (final r in now.rows) r.cells],
        [for (final r in old.rows) r.cells],
      );
      final oldOwed = payablesByAge(
        today,
        await source.payables(firm.firmId, today),
      );
      expect(
        [for (final r in (await run(ReportKind.payables)).rows) r.cells],
        [for (final r in oldOwed.rows) r.cells],
      );
      final m58 = receivablesByDueDate(
        today,
        await source.dueAgeing(firm.firmId, today),
      );
      final due = await run(ReportKind.receivablesByDueDate);
      expect(
        [for (final r in due.rows) r.cells],
        [for (final r in m58.rows) r.cells],
      );

      const mine = ReportOptions(ageing: AgeingBuckets([15, 45]));
      final cut = await run(ReportKind.receivables, options: mine);
      expect(cut.bucketColumns, ['0-15 days', '16-45 days', 'Over 45 days']);
      expect(at(cut, cut.rows.last, 'Owed'), at(now, now.rows.last, 'Owed'));
      final rashidRow = cut.rows.firstWhere(
        (r) => r.cells.first == 'Rashid Traders',
      );
      // Rs 6,000 of rice on the 1st of August, 63 days old, less the
      // Rs 1,500 of his two cheques.
      expect(at(cut, rashidRow, 'Over 45 days'), const Money.rupees(4500));
      final lateCut = await run(ReportKind.receivablesByDueDate, options: mine);
      expect(lateCut.bucketColumns.last, 'Over 45 days late');
      expect(
        at(lateCut, lateCut.rows.last, 'Owed'),
        at(due, due.rows.last, 'Owed'),
      );
      final rashidLate = lateCut.rows.firstWhere(
        (r) => r.cells.first == 'Rashid Traders',
      );
      expect(
        at(lateCut, rashidLate, '16-45 days late'),
        const Money.rupees(4500),
      );
      final supplierCut = await run(ReportKind.payables, options: mine);
      expect(
        at(supplierCut, supplierCut.rows.last, 'Owed'),
        at(oldOwed, oldOwed.rows.last, 'Owed'),
      );
    });
  });

  group('needs attention', () {
    test('everything odd today is listed, each from the read its own screen '
        'makes', () async {
      final list = await run(
        ReportKind.needsAttention,
        options: ReportOptions(nowUtc: DateTime.utc(2026, 10, 3, 4)),
      );
      final lines = list.rows.where((r) => r.style == RowStyle.line).toList();
      String what(ReportRow r) => '${r.cells.first}: ${r.cells[1]}';
      expect(lines.map(what), [
        'Oversold while set to block: Surf 1kg',
        'Stock below zero: Cheeni 1kg',
        'Money below zero: Bank Accounts',
        'Not with FBR after 24 hours: ${await _docNo(db, offline)}',
        'Udhaar overdue: Rashid Traders',
        'Cheque gone stale: Rashid Traders',
        'Cheque can be banked: Rashid Traders',
        'Bill cancelled today: ${await _docNo(db, cancelled)}',
        'Sold below cost today: Cooking Oil 5L',
        'Expired batch on the shelf: Panadol',
      ]);
      expect(at(list, lines[2], 'Amount'), const Money.rupees(-800));
      expect(lines[2].link?.kind, ReportLinkKind.account);
      expect(at(list, lines[4], 'Amount'), const Money.rupees(4500));
      expect(lines[4].link?.id, rashid);
      expect(at(list, lines[8], 'Amount'), const Money.rupees(-500));
      expect(at(list, lines[9], 'Amount'), const Money.rupees(100));
      expect(lines[7].cells[2], contains('Galti se'));
      expect(
        list.summary.firstWhere((f) => f.label == attentionTotalLabel).count,
        10,
      );

      // A cashier is never shown a loss on cost, and it is never read.
      final cashier = await ReportEngine(source, canSeeCosts: false).run(
        ReportKind.needsAttention,
        firmId: firm.firmId,
        period: ReportPeriod.day(today),
        today: today,
        options: ReportOptions(nowUtc: DateTime.utc(2026, 10, 3, 4)),
      );
      expect(
        cashier.rows.map((r) => r.cells.first),
        isNot(contains('Sold below cost today')),
      );
      // Udhaar from 60 days: Rashid is 33 days late.
      final later = await run(
        ReportKind.needsAttention,
        filters: const ReportFilters(lateDays: 60),
        options: ReportOptions(nowUtc: DateTime.utc(2026, 10, 3, 4)),
      );
      expect(
        later.rows.map((r) => r.cells.first),
        isNot(contains('Udhaar overdue')),
      );
      expect(later.filters, ['Udhaar 60 days or more past due']);
      // Before FBR's day was up, the offline bill was not late.
      final early = await run(
        ReportKind.needsAttention,
        options: ReportOptions(nowUtc: DateTime.utc(2026, 10, 1, 20)),
      );
      expect(
        early.rows.map((r) => r.cells.first),
        isNot(contains('Not with FBR after 24 hours')),
      );
    });
  });
}

Future<String> _docNo(AppDatabase db, String id) async =>
    (await db
            .customSelect(
              'SELECT doc_no FROM documents WHERE id = ?',
              variables: [Variable<String>(id)],
            )
            .getSingle())
        .read<String>('doc_no');
