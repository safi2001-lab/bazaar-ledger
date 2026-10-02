import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// The item and stock reports (M34) against a real database, each tied to
/// the books: the stock detail's closing value to Inventory, the item-wise
/// profit to the bill-wise profit, the item-wise discount to the Discount
/// Given account, every category total to the items under it.
///
/// Half a year of a kiryana store that also sells phones and medicine and
/// packs its own masala. Oil came in as opening stock on 1 March; rice and
/// two phones on 1 August; sugar, two batches of Panadol, chilli and salt
/// on 20 September; on the 25th two runs of masala were packed. On the
/// 26th: a walk-in buys oil and rice with Rs 500 off the bill; Rashid
/// takes three tins on udhaar and brings one back; Akbar buys one of the
/// phones; a tin rung by mistake is voided; sugar and a strip of Panadol
/// are sold; two tins go to the godown and a sack of rice is written off.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late ReportEngine reports;
  late DriftReportSource source;
  late DriftAppQueries queries;
  late String oil;
  late String rice;
  late String sugar;
  late String phone;
  late String rashid;
  late String rashidBill;
  late String akbarBill;

  final today = ReportPeriod.day(const BusinessDate('2026-09-26'));
  final september = ReportPeriod.monthOf(const BusinessDate('2026-09-26'));

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 9, 26, 9, 15));
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
    final runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    source = DriftReportSource(db);
    reports = ReportEngine(source);

    // Each act at its own moment, so no two share a timestamp.
    var minute = 0;
    ActorContext on(int month, int day) =>
        firm.actorAt(DateTime.utc(2026, month, day, 5, minute++));

    final pcs =
        (await db
                .customSelect("SELECT id FROM units WHERE code = 'pcs'")
                .getSingle())
            .read<String>('id');
    final catalogue = DriftCatalogueWriter(runner);
    Future<String> item(
      String name, {
      required int sale,
      String? category,
      int opening = 0,
      int cost = 0,
      int min = 0,
      bool serial = false,
      bool batch = false,
      ActorContext? actor,
    }) => catalogue.addItem(
      actor ?? on(9, 20),
      ItemDraft(
        name: name,
        baseUnitId: pcs,
        saleRate: Rate.rupees(sale),
        category: category,
        openingStock: Qty.units(opening),
        openingRate: Rate.rupees(cost),
        minStock: Qty.units(min),
        tracksSerial: serial,
        tracksBatch: batch,
      ),
    );

    oil = await item(
      'Cooking Oil 5L',
      sale: 2500,
      category: 'Ghee and oil',
      opening: 10,
      cost: 2000,
      actor: on(3, 1),
    );
    rice = await item('Chawal Basmati', sale: 150, category: 'Chawal', min: 20);
    sugar = await item('Cheeni', sale: 160, min: 10);
    phone = await item(
      'Tecno Spark',
      sale: 30000,
      category: 'Mobiles',
      serial: true,
    );
    final panadol = await item('Panadol strip', sale: 40, batch: true);
    final chilli = await item('Lal Mirch', sale: 500, opening: 5, cost: 400);
    final salt = await item('Namak', sale: 60, opening: 10, cost: 50);
    final masala = await item('Masala Pack', sale: 400, category: 'Masala');

    Future<String> supplier(String name) => catalogue.addParty(
      on(3, 1),
      PartyDraft(name: name, partyType: 'supplier'),
    );
    final mill = await supplier('Punjab Rice Mills');
    final mart = await supplier('Mobile Mart');
    final wholesale = await supplier('Akbari Mandi');
    final medi = await supplier('Medi Distributors');
    rashid = await catalogue.addParty(
      on(3, 1),
      const PartyDraft(name: 'Rashid Traders', partyType: 'customer'),
    );
    final akbar = await catalogue.addParty(
      on(3, 1),
      const PartyDraft(name: 'Akbar', partyType: 'customer'),
    );

    final buy = RecordPurchaseUseCase(
      writer: DriftPurchaseWriter(runner: runner),
    );
    Future<void> receive(
      ActorContext actor,
      String partyId,
      String itemId,
      String name,
      int units,
      int rate, {
      String? batch,
      String? expiry,
      List<String> serials = const [],
    }) => buy(
      actor,
      PurchaseDraft(
        partyId: partyId,
        lines: [
          PurchaseLineDraft(
            itemId: itemId,
            itemName: name,
            qty: Qty.units(units),
            baseQty: Qty.units(units),
            unitId: pcs,
            unitCode: 'pcs',
            rate: Rate.rupees(rate),
            batchNo: batch,
            expiry: expiry == null ? null : BusinessDate(expiry),
            serials: serials,
          ),
        ],
      ),
    ).then((_) {});

    await receive(on(8, 1), mill, rice, 'Chawal Basmati', 30, 120);
    await receive(
      on(8, 1),
      mart,
      phone,
      'Tecno Spark',
      2,
      25000,
      serials: ['IMEI-111', 'IMEI-222'],
    );
    await receive(on(9, 20), wholesale, sugar, 'Cheeni', 5, 140);
    await receive(
      on(9, 20),
      medi,
      panadol,
      'Panadol strip',
      10,
      30,
      batch: 'B1',
      expiry: '2026-12-31',
    );
    await receive(
      on(9, 20),
      medi,
      panadol,
      'Panadol strip',
      5,
      32,
      batch: 'B2',
      expiry: '2026-10-10',
    );

    // Two runs of masala: four packs from two of chilli and two of salt,
    // with Rs 100 of work a run.
    final making = DriftManufacturingWriter(runner: runner);
    final recipe = await making.saveBom(
      on(9, 25),
      BomDraft(
        name: 'Masala',
        outputItemId: masala,
        outputQty: Qty.units(2),
        lines: [
          BomLineDraft(itemId: chilli, qty: Qty.units(1)),
          BomLineDraft(itemId: salt, qty: Qty.units(1)),
        ],
        overhead: const Money.rupees(100),
      ),
    );
    await making.assemble(on(9, 25), recipe, 2);

    final cash = (await queries.paymentAccounts(
      firm.firmId,
    )).firstWhere((a) => a.modeLabel == 'cash');
    final sell = PostSaleUseCase(writer: DriftSaleWriter(runner: runner));
    SaleLineDraft line(String id, String name, int units, int rate) =>
        SaleLineDraft(
          itemId: id,
          itemName: name,
          qty: Qty.units(units),
          baseQty: Qty.units(units),
          unitId: pcs,
          unitCode: 'pcs',
          rate: Rate.rupees(rate),
        );
    TenderDraft paid(int rupees) => TenderDraft(
      paymentAccountId: cash.id,
      mode: 'cash',
      amount: Money.rupees(rupees),
    );

    // A walk-in: two tins and five of rice, Rs 500 off the bill.
    await sell(
      on(9, 26),
      SaleDraft(
        lines: [
          line(oil, 'Cooking Oil 5L', 2, 2500),
          line(rice, 'Chawal Basmati', 5, 150),
        ],
        billDiscount: const Money.rupees(500),
        roundToRupee: false,
        tenders: [paid(5250)],
      ),
    );
    // Rashid, three tins on udhaar.
    rashidBill = (await sell(
      on(9, 26),
      SaleDraft(
        lines: [line(oil, 'Cooking Oil 5L', 3, 2500)],
        partyId: rashid,
        partyName: 'Rashid Traders',
        roundToRupee: false,
      ),
    )).documentId;
    // Akbar, the first phone.
    final imei = await queries.serialOnHand(firm.firmId, 'IMEI-111');
    akbarBill = (await sell(
      on(9, 26),
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: phone,
            itemName: 'Tecno Spark',
            qty: Qty.units(1),
            baseQty: Qty.units(1),
            unitId: pcs,
            unitCode: 'pcs',
            rate: Rate.rupees(30000),
            lotId: imei!.lotId,
          ),
        ],
        partyId: akbar,
        partyName: 'Akbar',
        roundToRupee: false,
        tenders: [paid(30000)],
      ),
    )).documentId;
    // Rung by mistake, and voided.
    final mistake = await sell(
      on(9, 26),
      SaleDraft(
        lines: [line(oil, 'Cooking Oil 5L', 1, 2500)],
        roundToRupee: false,
        tenders: [paid(2500)],
      ),
    );
    await VoidDocumentUseCase(writer: DriftVoidWriter(runner: runner))(
      on(9, 26),
      documentId: mistake.documentId,
      reason: 'Rung by mistake',
    );
    // Rashid brings one tin back.
    final rashidLine =
        (await db
                .customSelect(
                  'SELECT id FROM document_lines WHERE document_id = ?',
                  variables: [Variable<String>(rashidBill)],
                )
                .getSingle())
            .read<String>('id');
    await RecordReturnUseCase(writer: DriftReturnWriter(runner: runner))(
      on(9, 26),
      ReturnDraft(
        originalDocumentId: rashidBill,
        reason: 'Dabba pichka hua',
        lines: [ReturnLineDraft(documentLineId: rashidLine, qty: Qty.units(1))],
      ),
    );
    // Sugar and a strip of Panadol, the batch nearest its date first.
    await sell(
      on(9, 26),
      SaleDraft(
        lines: [
          line(sugar, 'Cheeni', 2, 160),
          line(panadol, 'Panadol strip', 1, 40),
        ],
        roundToRupee: false,
        tenders: [paid(360)],
      ),
    );
    // Two tins to the godown, and a sack of rice the rats got.
    await catalogue.transferStock(
      on(9, 26),
      StockTransferDraft(
        itemId: oil,
        qty: Qty.units(2),
        from: 'MAIN',
        to: 'GODOWN',
      ),
    );
    await catalogue.adjustStock(
      on(9, 26),
      StockAdjustmentDraft.byDelta(
        itemId: rice,
        change: Qty.units(-1),
        reason: 'Choohon ne kaat diya',
      ),
    );
  });

  tearDown(() async => db.close());

  Future<ReportTable> run(
    ReportKind kind, {
    ReportPeriod? period,
    ReportFilters filters = ReportFilters.none,
  }) => reports.run(
    kind,
    firmId: firm.firmId,
    period: period ?? today,
    today: today.from,
    filters: filters,
  );

  ReportRow row(ReportTable t, String first) =>
      t.rows.firstWhere((r) => r.cells.first == first);

  Object? cell(ReportTable t, String first, String column) =>
      row(t, first).cells[t.columns.indexWhere((c) => c.title == column)];

  Object? total(ReportTable t, String column) =>
      t.totals.single.cells[t.columns.indexWhere((c) => c.title == column)];

  Future<Money> books(String date) =>
      source.inventoryAsOf(firm.firmId, BusinessDate(date));

  group('stock summary', () {
    test('every item\'s shelf and book value, which is Inventory to the '
        'paisa, today and on a day gone by', () async {
      final now = await run(ReportKind.stockSummary);
      expect(cell(now, 'Cooking Oil 5L', 'Stock'), Qty.units(6));
      expect(cell(now, 'Cooking Oil 5L', 'Value'), const Money.rupees(12000));
      expect(
        cell(now, 'Cooking Oil 5L', 'Sale price'),
        const Money.rupees(2500),
      );
      expect(cell(now, 'Cooking Oil 5L', 'Cost'), const Money.rupees(2000));
      expect(cell(now, 'Chawal Basmati', 'Stock'), Qty.units(24));
      expect(total(now, 'Value'), await books('2026-09-26'));
      expect(
        now.notes,
        contains('The stock value agrees with Inventory in the books.'),
      );
      expect(row(now, 'Cooking Oil 5L').link?.kind, ReportLinkKind.item);
      expect(row(now, 'Cooking Oil 5L').link?.id, oil);

      final august = await run(
        ReportKind.stockSummary,
        filters: const ReportFilters(asOf: BusinessDate('2026-08-31')),
      );
      expect(august.period.to.value, '2026-08-31');
      expect(cell(august, 'Cooking Oil 5L', 'Stock'), Qty.units(10));
      expect(cell(august, 'Chawal Basmati', 'Stock'), Qty.units(30));
      expect(cell(august, 'Cheeni', 'Stock'), Qty.zero);
      expect(total(august, 'Value'), await books('2026-08-31'));
      expect(total(august, 'Value'), const Money.rupees(20000 + 3600 + 50000));
    });

    test(
      'narrowed by category, place and what is in stock, in the query',
      () async {
        final oils = await run(
          ReportKind.stockSummary,
          filters: const ReportFilters(category: 'Ghee and oil'),
        );
        expect(oils.rows.where((r) => r.style == RowStyle.line), hasLength(1));
        expect(
          oils.summary.map((f) => f.label),
          isNot(contains('Inventory in the books')),
        );
        final godown = await run(
          ReportKind.stockSummary,
          filters: const ReportFilters(location: 'GODOWN', inStockOnly: true),
        );
        expect(
          godown.rows
              .where((r) => r.style == RowStyle.line)
              .map((r) => r.cells.first),
          ['Cooking Oil 5L'],
        );
        expect(cell(godown, 'Cooking Oil 5L', 'Stock'), Qty.units(2));
        expect(
          cell(godown, 'Cooking Oil 5L', 'Value'),
          const Money.rupees(4000),
        );
        final inStock = await run(
          ReportKind.stockSummary,
          filters: const ReportFilters(
            inStockOnly: true,
            asOf: BusinessDate('2026-08-31'),
          ),
        );
        expect(
          inStock.rows.map((r) => r.cells.first),
          isNot(contains('Cheeni')),
        );
        expect(inStock.filters, contains('Only items in stock'));
      },
    );

    test('by category, each category the sum of its items', () async {
      final items = await run(ReportKind.stockSummary);
      final byCategory = await run(ReportKind.stockSummaryByCategory);
      expect(total(byCategory, 'Value'), total(items, 'Value'));
      expect(
        cell(byCategory, 'Ghee and oil', 'Value'),
        const Money.rupees(12000),
      );
      expect(cell(byCategory, 'No category', 'Items'), 4);
    });
  });

  group('stock detail', () {
    test('opening, in and out, and closing for every item, closing on '
        'Inventory in the books on both days', () async {
      final t = await run(ReportKind.stockDetail, period: september);
      expect(total(t, 'Opening value'), await books('2026-08-31'));
      expect(total(t, 'Closing value'), await books('2026-09-30'));
      expect(
        t.notes,
        contains(startsWith('The opening and closing values agree')),
      );

      Object? oilCell(String column) => cell(t, 'Cooking Oil 5L', column);
      expect(oilCell('Opening'), Qty.units(10));
      expect(oilCell('Opening value'), const Money.rupees(20000));
      expect(
        oilCell('Sold'),
        Qty.units(5),
        reason: 'the voided tin is not a sale',
      );
      expect(oilCell('Returns in'), Qty.units(1));
      expect(oilCell('Moved in'), Qty.units(2));
      expect(oilCell('Moved out'), Qty.units(2));
      expect(oilCell('Adjusted'), Qty.zero, reason: 'out and back on the void');
      expect(oilCell('Closing'), Qty.units(6));
      expect(oilCell('Closing value'), const Money.rupees(12000));
      expect(cell(t, 'Chawal Basmati', 'Wasted'), Qty.units(1));
      expect(cell(t, 'Masala Pack', 'Made'), Qty.units(4));
      expect(cell(t, 'Lal Mirch', 'Used'), Qty.units(2));
      expect(cell(t, 'Cheeni', 'Purchased'), Qty.units(5));

      final godown = await run(
        ReportKind.stockDetail,
        period: september,
        filters: const ReportFilters(location: 'GODOWN'),
      );
      expect(cell(godown, 'Cooking Oil 5L', 'Closing'), Qty.units(2));
      expect(
        godown.summary.map((f) => f.label),
        isNot(contains('Inventory in the books')),
      );
    });

    test('one item day by day, from its opening to its closing', () async {
      final t = await run(
        ReportKind.itemDetail,
        period: september,
        filters: ReportFilters(itemId: oil, itemName: 'Cooking Oil 5L'),
      );
      expect(t.title, 'Item detail: Cooking Oil 5L');
      final day = row(t, '2026-09-26');
      expect(day.cells, [
        '2026-09-26',
        Qty.units(10),
        Qty.zero,
        Qty.units(5),
        Qty.units(1),
        Qty.zero,
        Qty.zero,
        Qty.zero,
        Qty.zero,
        Qty.units(6),
      ]);
      expect(t.totals.single.cells.last, Qty.units(6));
      final none = await run(ReportKind.itemDetail, period: september);
      expect(none.rows, isEmpty);
    });
  });

  group('profit and discount', () {
    test('item-wise profit is the bill-wise profit, and each category the '
        'sum of its items', () async {
      final items = await run(ReportKind.itemProfitAndLoss);
      final bills = await run(ReportKind.billWiseProfit);
      final categories = await run(ReportKind.categoryProfitAndLoss);
      expect(total(items, 'Profit'), total(bills, 'Profit'));
      expect(total(items, 'Sales'), total(bills, 'Sale amount'));
      expect(total(categories, 'Profit'), total(items, 'Profit'));
      expect(total(categories, 'Sales'), total(items, 'Sales'));
      expect(cell(items, 'Cooking Oil 5L', 'Qty sold'), Qty.units(4));
      expect(cell(items, 'Tecno Spark', 'Profit'), const Money.rupees(5000));
      expect(cell(categories, 'Mobiles', 'Profit'), const Money.rupees(5000));
    });

    test(
      'a role that may not see costs is refused item and category profit',
      () async {
        final counter = ReportEngine(source, canSeeCosts: false);
        for (final kind in [
          ReportKind.itemProfitAndLoss,
          ReportKind.categoryProfitAndLoss,
        ]) {
          await expectLater(
            counter.run(
              kind,
              firmId: firm.firmId,
              period: today,
              today: today.from,
            ),
            throwsA(isA<PermissionDenied>()),
          );
        }
        final shelf = await counter.run(
          ReportKind.stockSummary,
          firmId: firm.firmId,
          period: today,
          today: today.from,
        );
        expect(shelf.columns.map((c) => c.title), [
          'Item',
          'Category',
          'Unit',
          'Sale price',
          'Stock',
        ]);
        expect(shelf.summary.map((f) => f.label), ['Items']);
      },
    );

    test('the item-wise discount is the Discount Given account', () async {
      final t = await run(ReportKind.itemDiscount);
      final given = (await source.accountMovements(
        firm.firmId,
        today,
      )).firstWhere((a) => a.systemKey == 'discount_given').net;
      expect(total(t, 'Discount'), given);
      expect(given, const Money.rupees(500));
      expect(
        (cell(t, 'Cooking Oil 5L', 'Discount')! as Money) +
            (cell(t, 'Chawal Basmati', 'Discount')! as Money),
        const Money.rupees(500),
      );
      expect(
        cell(t, 'Cooking Oil 5L', 'Before discount'),
        const Money.rupees(12500),
        reason: 'every tin sold, at its rate',
      );
    });

    test('sale and purchase by category, each net of returns', () async {
      final t = await run(ReportKind.salePurchaseByCategory, period: september);
      expect(cell(t, 'Mobiles', 'Sale amount'), const Money.rupees(30000));
      expect(
        cell(t, 'No category', 'Purchase amount'),
        const Money.rupees(700 + 300 + 160),
      );
      final items = await run(ReportKind.itemProfitAndLoss, period: september);
      expect(total(t, 'Sale amount'), total(items, 'Sales'));
    });

    test('who bought and supplied one item', () async {
      final t = await run(
        ReportKind.itemByParty,
        period: september,
        filters: ReportFilters(itemId: oil, itemName: 'Cooking Oil 5L'),
      );
      expect(cell(t, 'Rashid Traders', 'Sold qty'), Qty.units(2));
      expect(
        cell(t, 'Rashid Traders', 'Sale amount'),
        const Money.rupees(5000),
      );
      expect(row(t, 'Rashid Traders').link?.id, rashid);
      expect(cell(t, 'Walk-in customers', 'Sold qty'), Qty.units(2));
      final rices = await run(
        ReportKind.itemByParty,
        period: ReportPeriod(const BusinessDate('2026-08-01'), september.to),
        filters: ReportFilters(itemId: rice, itemName: 'Chawal Basmati'),
      );
      expect(cell(rices, 'Punjab Rice Mills', 'Bought qty'), Qty.units(30));
      expect(
        cell(rices, 'Punjab Rice Mills', 'Purchase amount'),
        const Money.rupees(3600),
      );
    });
  });

  group('what to order and what has stopped selling', () {
    test('low stock lists what the counter\'s alert lists, with what to '
        'order', () async {
      final t = await run(ReportKind.lowStock);
      final alert = await queries.lowStockItems(firm.firmId);
      expect(
        [for (final r in t.rows.where((r) => r.link != null)) r.link!.id],
        [for (final i in alert) i.id],
      );
      expect(cell(t, 'Cheeni', 'Stock'), Qty.units(3));
      expect(cell(t, 'Cheeni', 'Short by'), Qty.units(7));
      expect(cell(t, 'Cheeni', 'Sold in 30 days'), Qty.units(2));
      expect(cell(t, 'Cheeni', 'Last supplier'), 'Akbari Mandi');
      expect(
        cell(t, 'Cheeni', 'Order'),
        Qty.units(7),
        reason: 'up to its floor',
      );
      final none = await run(
        ReportKind.lowStock,
        filters: const ReportFilters(category: 'Chawal'),
      );
      expect(none.rows.where((r) => r.style == RowStyle.line), isEmpty);
    });

    test(
      'fast, slow and dead stock, by bills in the days looked back over',
      () async {
        final t = await run(ReportKind.fastSlowStock);
        expect(
          cell(t, 'Cooking Oil 5L', 'Bills'),
          2,
          reason: 'the void is no bill',
        );
        expect(cell(t, 'Cooking Oil 5L', 'Moving'), 'Slow');
        expect(cell(t, 'Lal Mirch', 'Moving'), 'Not sold');
        expect(cell(t, 'Lal Mirch', 'Last sold'), 'Never');
        expect(cell(t, 'Cooking Oil 5L', 'Last sold'), '2026-09-26');
        final fast = await run(
          ReportKind.fastSlowStock,
          filters: const ReportFilters(fastAt: 2, slowBelow: 2),
        );
        expect(cell(fast, 'Cooking Oil 5L', 'Moving'), 'Fast');
        expect(cell(fast, 'Cheeni', 'Moving'), 'Slow');
        final stock = await run(ReportKind.stockSummary);
        expect(
          total(t, 'Value'),
          total(stock, 'Value'),
          reason: 'every item with stock is in a band',
        );
      },
    );

    test('stock ageing, first in first out, ties to the shelf', () async {
      final t = await run(ReportKind.stockAgeing);
      expect(
        row(t, 'Cooking Oil 5L').cells.sublist(2),
        [
          Qty.units(6),
          const Money.rupees(2000),
          Money.zero,
          Money.zero,
          const Money.rupees(10000),
          const Money.rupees(12000),
        ],
        reason: 'the tin brought back today, five from the March opening',
      );
      expect(cell(t, 'Chawal Basmati', '46-90 days'), const Money.rupees(2880));
      final stock = await run(
        ReportKind.stockSummary,
        filters: const ReportFilters(inStockOnly: true),
      );
      expect(total(t, 'Value'), total(stock, 'Value'));
    });
  });

  group('batches, serials, moves and production', () {
    test('every batch on the shelf with its days left', () async {
      final t = await run(ReportKind.itemBatches);
      expect(
        [
          for (final r in t.rows.where((r) => r.style == RowStyle.line))
            [r.cells[1], r.cells[3], r.cells[5]],
        ],
        [
          ['B2', 14, Qty.units(4)],
          ['B1', 96, Qty.units(10)],
        ],
      );
      final stock = await run(
        ReportKind.stockSummary,
        filters: const ReportFilters(inStockOnly: true),
      );
      expect(
        total(t, 'Value'),
        cell(stock, 'Panadol strip', 'Value'),
        reason: 'the batches add up to the item',
      );
    });

    test('a phone found by its IMEI, sold to Akbar on his bill; the other '
        'still here', () async {
      final t = await run(ReportKind.itemSerials);
      final sold = row(t, 'IMEI-111');
      expect(sold.cells.sublist(2, 7), [
        'Sold',
        'Mobile Mart',
        '2026-08-01',
        'Akbar',
        '2026-09-26',
      ]);
      expect(sold.link?.id, akbarBill);
      expect(cell(t, 'IMEI-222', 'Status'), 'In stock');
      final found = await run(
        ReportKind.itemSerials,
        filters: const ReportFilters(serial: '222'),
      );
      expect(
        found.rows
            .where((r) => r.style == RowStyle.line)
            .map((r) => r.cells.first),
        ['IMEI-222'],
      );
    });

    test('a move to the godown, from where to where', () async {
      final t = await run(ReportKind.stockTransfers);
      expect(t.rows.first.cells.sublist(1), [
        'Cooking Oil 5L',
        Qty.units(2),
        'pcs',
        'Shop floor',
        'GODOWN',
        const Money.rupees(4000),
      ]);
      final elsewhere = await run(
        ReportKind.stockTransfers,
        filters: const ReportFilters(location: 'VAN-1'),
      );
      expect(elsewhere.rows.where((r) => r.style == RowStyle.line), isEmpty);
    });

    test('a production run with what it used and what it cost', () async {
      final t = await run(ReportKind.productionRegister, period: september);
      final run0 = t.rows.first;
      expect(run0.cells[2], 'Masala Pack');
      expect(run0.cells[3], Qty.units(4));
      expect(run0.cells[5], 'Lal Mirch 2 pcs, Namak 2 pcs');
      expect(run0.cells.sublist(6), [
        const Money.rupees(900),
        const Money.rupees(200),
        const Money.rupees(1100),
      ]);
    });
  });

  test('a place filter offers the shop floor and every godown', () async {
    final places = await source.choices(firm.firmId, ReportFilter.location);
    expect([for (final c in places) c.id], ['MAIN', 'GODOWN']);
    expect(places.first.label, 'Shop floor');
  });
}
