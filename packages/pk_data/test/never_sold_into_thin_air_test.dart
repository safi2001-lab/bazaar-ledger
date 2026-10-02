import 'dart:convert';

import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Never sold into thin air, and packed by the carton (M53), against a real
/// database.
///
/// A Pakistani shopkeeper's review of Vyapar: seven hundred kilos sold
/// against six hundred in stock, and not a word said. Here an item set to
/// refuse is refused by the sale path itself, beneath every screen, and
/// nothing of the bill survives; an item set to ask is the counter's to
/// ask, and the sale path lets it through to read below nothing, where the
/// lists show it; an item that sells on sells on.
///
/// And a carton of twenty-four is the item's own conversion, so it sells,
/// is bought and comes off the item again without anybody doing arithmetic,
/// and without the struck-out carton holding its place for ever — the
/// index that did (M56 said so) counts live rows only since v10.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late TxRunner runner;
  late DriftAppQueries queries;
  late DriftCatalogueWriter catalogue;
  late PostSaleUseCase postSale;
  late IssueChallanUseCase send;
  late RecordPurchaseUseCase buy;
  late RecordReturnUseCase takeBack;
  late RecordPurchaseReturnUseCase sendBack;
  late ActorContext actor;
  late Map<String, String> unit;
  late String customer;
  late String supplier;

  setUp(() async {
    final clock = FixedClock(DateTime.utc(2026, 10, 3, 6));
    db = await openTestDatabase();
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    actor = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    catalogue = DriftCatalogueWriter(runner);
    final shelf = DriftShelfReader(db);
    postSale = PostSaleUseCase(
      writer: DriftSaleWriter(runner: runner),
      shelf: shelf,
    );
    send = IssueChallanUseCase(
      writer: DriftChallanWriter(runner: runner),
      shelf: shelf,
    );
    buy = RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: runner));
    takeBack = RecordReturnUseCase(writer: DriftReturnWriter(runner: runner));
    sendBack = RecordPurchaseReturnUseCase(
      writer: DriftPurchaseReturnWriter(runner: runner),
    );
    unit = {
      for (final r in await db.customSelect('SELECT id, code FROM units').get())
        r.read<String>('code'): r.read<String>('id'),
    };
    customer = await catalogue.addParty(
      actor,
      const PartyDraft(name: 'Rashid Traders'),
    );
    supplier = await catalogue.addParty(
      actor,
      const PartyDraft(name: 'Punjab Flour Mills', partyType: 'supplier'),
    );
  });

  tearDown(() async => db.close());

  Future<String> item(
    String name, {
    String unitCode = 'kg',
    int onHand = 0,
    int rupees = 120,
    NegativeStock? rule,
    List<ItemPack>? packs,
    bool batches = false,
  }) => catalogue.addItem(
    actor,
    ItemDraft(
      name: name,
      baseUnitId: unit[unitCode]!,
      saleRate: Rate.rupees(rupees),
      openingStock: Qty.units(onHand),
      openingRate: Rate.rupees(rupees - 20),
      negativeStock: rule,
      packs: packs,
      tracksBatch: batches,
    ),
  );

  SaleLineDraft line(
    String itemId,
    Qty qty, {
    String unitCode = 'kg',
    Qty? baseQty,
    int rupees = 120,
  }) => SaleLineDraft(
    itemId: itemId,
    itemName: 'Item',
    qty: qty,
    baseQty: baseQty ?? qty,
    unitId: unit[unitCode],
    unitCode: unitCode,
    rate: Rate.rupees(rupees),
  );

  Future<PostedSale> sell(
    List<SaleLineDraft> lines, {
    String location = 'MAIN',
    String? fromChallan,
  }) => postSale(
    actor,
    SaleDraft(
      partyId: customer,
      partyName: 'Rashid Traders',
      lines: lines,
      locationCode: location,
      convertedFromId: fromChallan,
      roundToRupee: false,
    ),
  );

  Future<int> stockOf(String itemId, {String? at}) async =>
      (await db
              .customSelect(
                'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS q '
                'FROM stock_ledger WHERE item_id = ? '
                'AND (? IS NULL OR location_code = ?)',
                variables: [
                  Variable<String>(itemId),
                  Variable<String>(at),
                  Variable<String>(at),
                ],
              )
              .getSingle())
          .read<int>('q');

  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<int>('n');

  Future<void> shopSays(NegativeStock rule) => runner.run(
    actor,
    (tx) => tx.insert('settings', {
      'setting_key': negativeStockSettingKey,
      'setting_value': rule.code,
    }),
  );

  Future<void> booksBalance() async {
    expect(await db.findLedgerImbalances(), isEmpty);
  }

  group('selling below nothing', () {
    test('an item set to refuse is refused at the service past its shelf, and '
        'nothing of the bill is written', () async {
      final atta = await item(
        'Atta Chakki',
        onHand: 600,
        rule: NegativeStock.block,
      );

      await expectLater(
        sell([line(atta, Qty.units(700))]),
        throwsA(
          isA<ShelfRefused>()
              .having((e) => e.short.single.shortBy, 'short by', Qty.units(100))
              .having((e) => '$e', 'words', contains('Only 600 kg')),
        ),
      );
      expect(
        await count(
          "SELECT COUNT(*) AS n FROM documents WHERE doc_type = 'sale_invoice'",
        ),
        0,
      );
      expect(await stockOf(atta), 600000, reason: 'the shelf is untouched');

      // Nothing was burned either: the next bill is the first.
      final ok = await sell([line(atta, Qty.units(600))]);
      expect(ok.docNo, endsWith('0001'));
      expect(await stockOf(atta), 0, reason: 'the last kilo sells');
      await booksBalance();
    });

    test('an item set to ask is let through by the service and reads below '
        'nothing, in the lists', () async {
      final atta = await item(
        'Atta Chakki',
        onHand: 600,
        rule: NegativeStock.warn,
      );

      await sell([line(atta, Qty.units(700))]);

      expect(await stockOf(atta), -100000);
      final found = (await queries.searchItems(
        firm.firmId,
        query: 'Atta',
      )).single;
      expect(found.isBelowNothing, isTrue);
      expect(found.negativeStock, NegativeStock.warn);
      final low = await queries.lowStockItems(firm.firmId);
      expect(
        low.map((i) => i.id),
        contains(atta),
        reason: 'below nothing is listed with no floor set',
      );
      await booksBalance();
    });

    test('an item that sells on is never refused', () async {
      await shopSays(NegativeStock.block);
      final service = await item('Tandoor ka kaam', rule: NegativeStock.allow);
      await sell([line(service, Qty.units(3))]);
      expect(await stockOf(service), -3000);
    });

    test("the shop's own rule applies to every item without one, a new shop "
        'asks, and the item that has its own keeps it', () async {
      final reader = DriftShelfReader(db);
      expect(await reader.shopRule(firm.firmId), NegativeStock.warn);

      final cheeni = await item('Cheeni');
      final ghee = await item('Ghee', rule: NegativeStock.allow);
      await sell([line(cheeni, Qty.units(2))]);

      await shopSays(NegativeStock.block);
      expect(await reader.shopRule(firm.firmId), NegativeStock.block);
      await expectLater(
        sell([line(cheeni, Qty.one)]),
        throwsA(isA<ShelfRefused>()),
      );
      await sell([line(ghee, Qty.one)]);
      expect(await stockOf(ghee), -1000);
    });

    test('every line of one item is counted together', () async {
      final atta = await item(
        'Atta Chakki',
        onHand: 50,
        rule: NegativeStock.block,
      );
      // A maund (40 kg) and twenty kilos: each fits, together they do not.
      await expectLater(
        sell([
          line(atta, Qty.one, unitCode: 'maund', baseQty: Qty.units(40)),
          line(atta, Qty.units(20)),
        ]),
        throwsA(
          isA<ShelfRefused>().having(
            (e) => e.short.single.wanted,
            'wanted',
            Qty.units(60),
          ),
        ),
      );
    });

    test('a challan is refused as a bill is, and a bill made from a challan is '
        'not asked, the goods having gone', () async {
      final atta = await item(
        'Atta Chakki',
        onHand: 30,
        rule: NegativeStock.block,
      );
      SaleDraft challan(int kilos) => SaleDraft(
        partyId: customer,
        partyName: 'Rashid Traders',
        lines: [line(atta, Qty.units(kilos))],
      );

      await expectLater(send(actor, challan(31)), throwsA(isA<ShelfRefused>()));
      final sent = await send(actor, challan(30));
      expect(await stockOf(atta), 0);

      await sell([line(atta, Qty.units(30))], fromChallan: sent.id);
      expect(await stockOf(atta), 0, reason: 'the challan moved it already');
    });

    test("a van phone sells from the van's own stock", () async {
      final atta = await item(
        'Atta Chakki',
        onHand: 100,
        rule: NegativeStock.block,
      );
      await catalogue.transferStock(
        actor,
        StockTransferDraft(
          itemId: atta,
          qty: Qty.units(10),
          from: 'MAIN',
          to: 'VAN-1',
        ),
      );

      await expectLater(
        sell([line(atta, Qty.units(11))], location: 'VAN-1'),
        throwsA(isA<ShelfRefused>()),
        reason: 'ninety kilos at the shop are not in the van',
      );
      await sell([line(atta, Qty.units(10))], location: 'VAN-1');
      expect(await stockOf(atta, at: 'VAN-1'), 0);
      expect(await stockOf(atta, at: 'MAIN'), 90000);
    });

    test("a delivery, a customer's return and a return to the supplier are "
        'never refused', () async {
      await shopSays(NegativeStock.block);
      final atta = await item('Atta Chakki');

      final delivery = await buy(
        actor,
        PurchaseDraft(
          partyId: supplier,
          lines: [
            PurchaseLineDraft(
              itemId: atta,
              itemName: 'Atta Chakki',
              qty: Qty.units(10),
              baseQty: Qty.units(10),
              unitId: unit['kg']!,
              unitCode: 'kg',
              rate: Rate.rupees(100),
            ),
          ],
        ),
      );
      final sale = await sell([line(atta, Qty.units(8))]);
      final sold = (await queries.returnableLines(
        firm.firmId,
        sale.documentId,
      )).single;
      await takeBack(
        actor,
        ReturnDraft(
          originalDocumentId: sale.documentId,
          reason: 'Geela tha',
          lines: [
            ReturnLineDraft(documentLineId: sold.documentLineId, qty: Qty.one),
          ],
        ),
      );
      expect(await stockOf(atta), 3000);

      // The three on the shelf go back to the mill. A return to a
      // supplier has its own rule — what was sold cannot go back — and
      // the shop's rule for selling is not asked.
      final bought = (await queries.returnableDelivery(
        firm.firmId,
        delivery.documentId,
      ))!.lines.single;
      await sendBack(
        actor,
        PurchaseReturnDraft(
          originalDocumentId: delivery.documentId,
          reason: 'Keeray',
          lines: [
            ReturnLineDraft(
              documentLineId: bought.documentLineId,
              qty: Qty.units(3),
            ),
          ],
        ),
      );
      expect(await stockOf(atta), 0);
      await booksBalance();
    });

    test('an item kept by batch is refused past its whole shelf, as a serial '
        'already was', () async {
      final syrup = await item(
        'Panadol Syrup',
        unitCode: 'pcs',
        rule: NegativeStock.block,
        batches: true,
      );
      await buy(
        actor,
        PurchaseDraft(
          partyId: supplier,
          lines: [
            PurchaseLineDraft(
              itemId: syrup,
              itemName: 'Panadol Syrup',
              qty: Qty.units(5),
              baseQty: Qty.units(5),
              unitId: unit['pcs']!,
              unitCode: 'pcs',
              rate: Rate.rupees(80),
              batchNo: 'B1',
              expiry: const BusinessDate('2027-06-30'),
            ),
          ],
        ),
      );
      // First-expiry-first-out used to take the sixth from no batch at all.
      await expectLater(
        sell([line(syrup, Qty.units(6), unitCode: 'pcs')]),
        throwsA(isA<ShelfRefused>()),
      );
      await sell([line(syrup, Qty.units(5), unitCode: 'pcs')]);
      expect(await stockOf(syrup), 0);
    });

    test("an item's rule is kept on the item and carried to the other counters "
        'in its change', () async {
      final atta = await item('Atta Chakki', rule: NegativeStock.block);
      final inserted = await db
          .customSelect(
            "SELECT payload_json FROM change_log WHERE entity_table = 'items' "
            "AND entity_id = ? AND op = 'insert'",
            variables: [Variable<String>(atta)],
          )
          .getSingle();
      expect(
        jsonDecode(inserted.read<String>('payload_json')),
        containsPair('negative_stock', 'block'),
      );

      await catalogue.updateItem(
        actor,
        atta,
        ItemDraft(
          name: 'Atta Chakki',
          baseUnitId: unit['kg']!,
          saleRate: Rate.rupees(120),
          negativeStock: NegativeStock.warn,
        ),
      );
      final updated = await db
          .customSelect(
            "SELECT payload_json FROM change_log WHERE entity_table = 'items' "
            "AND entity_id = ? AND op = 'update'",
            variables: [Variable<String>(atta)],
          )
          .getSingle();
      expect(
        jsonDecode(updated.read<String>('payload_json')),
        containsPair('negative_stock', 'warn'),
      );
      final audit = await db
          .customSelect(
            'SELECT before_json, after_json FROM audit_log '
            "WHERE action_code = 'ITEM_UPDATED'",
          )
          .getSingle();
      expect(audit.read<String>('before_json'), contains('block'));
      expect(audit.read<String>('after_json'), contains('warn'));
    });
  });

  group('packed by the carton', () {
    Future<UnitConverter> converter() async =>
        UnitConverter(await queries.unitConversions(firm.firmId));

    Future<String> biscuits({int onHand = 100}) => item(
      'Gala Biscuit',
      unitCode: 'pcs',
      onHand: onHand,
      rupees: 50,
      packs: [ItemPack(unitId: unit['carton']!, size: Qty.units(24))],
    );

    test(
      'a carton of 24 sells as one carton, takes 24 pieces off the shelf and '
      "charges 24 pieces' worth",
      () async {
        final gala = await biscuits();
        final units = await converter();
        final perCarton = units.convertRate(
          Rate.rupees(50),
          fromUnitId: unit['pcs']!,
          toUnitId: unit['carton']!,
          itemId: gala,
        );
        expect(perCarton, Rate.rupees(1200));
        final base = units.convert(
          Qty.one,
          fromUnitId: unit['carton']!,
          toUnitId: unit['pcs']!,
          itemId: gala,
        );
        expect(base, Qty.units(24));

        final sale = await sell([
          line(gala, Qty.one, unitCode: 'carton', baseQty: base, rupees: 1200),
        ]);

        expect(sale.total, const Money.rupees(1200));
        final row = await db
            .customSelect(
              'SELECT unit_code_snapshot AS u, qty_thousandths AS q, '
              'base_qty_thousandths AS b FROM document_lines',
            )
            .getSingle();
        expect(row.read<String>('u'), 'carton');
        expect(row.read<int>('q'), 1000);
        expect(row.read<int>('b'), 24000);
        expect(await stockOf(gala), 76000);
        await booksBalance();
      },
    );

    test(
      'ten cartons bought put 240 pieces on the shelf at what a carton cost',
      () async {
        final gala = await biscuits(onHand: 0);
        await buy(
          actor,
          PurchaseDraft(
            partyId: supplier,
            lines: [
              PurchaseLineDraft(
                itemId: gala,
                itemName: 'Gala Biscuit',
                qty: Qty.units(10),
                baseQty: ItemPack(
                  unitId: unit['carton']!,
                  size: Qty.units(24),
                ).inBase(Qty.units(10)),
                unitId: unit['carton']!,
                unitCode: 'carton',
                rate: Rate.rupees(960),
              ),
            ],
          ),
        );
        expect(await stockOf(gala), 240000);
        final avg = await db
            .customSelect(
              'SELECT avg_cost_milli_paisa AS c FROM items WHERE id = ?',
              variables: [Variable<String>(gala)],
            )
            .getSingle();
        expect(Rate.raw(avg.read<int>('c')), Rate.rupees(40));
        await booksBalance();
      },
    );

    test('a bori of 50 kg sells two bori as a hundred kilos', () async {
      final atta = await item(
        'Atta Chakki',
        onHand: 500,
        packs: [ItemPack(unitId: unit['bori']!, size: Qty.units(50))],
      );
      final units = await converter();
      final base = units.convert(
        Qty.units(2),
        fromUnitId: unit['bori']!,
        toUnitId: unit['kg']!,
        itemId: atta,
      );
      await sell([
        line(atta, Qty.units(2), unitCode: 'bori', baseQty: base, rupees: 6000),
      ]);
      expect(await stockOf(atta), 400000);
    });

    test(
      'a pack taken off an item can be put back on it, at another size',
      () async {
        final gala = await biscuits();
        ItemDraft draft(List<ItemPack>? packs) => ItemDraft(
          name: 'Gala Biscuit',
          baseUnitId: unit['pcs']!,
          saleRate: Rate.rupees(50),
          packs: packs,
        );

        await catalogue.updateItem(actor, gala, draft(const []));
        expect(
          packsOf(await converter(), itemId: gala, baseUnitId: unit['pcs']!),
          isEmpty,
        );

        // Before v10 this was a UNIQUE failure: the struck-out carton held
        // the pair for ever.
        await catalogue.updateItem(
          actor,
          gala,
          draft([ItemPack(unitId: unit['carton']!, size: Qty.units(20))]),
        );
        final now = packsOf(
          await converter(),
          itemId: gala,
          baseUnitId: unit['pcs']!,
        );
        expect(now.single.size, Qty.units(20));
        expect(
          await count(
            'SELECT COUNT(*) AS n FROM unit_conversions WHERE item_id IS NOT '
            'NULL AND deleted_at_utc IS NOT NULL',
          ),
          1,
          reason: 'the old carton is kept, struck out',
        );

        // And the next carton sold is twenty.
        await sell([
          line(
            gala,
            Qty.one,
            unitCode: 'carton',
            baseQty: (await converter()).convert(
              Qty.one,
              fromUnitId: unit['carton']!,
              toUnitId: unit['pcs']!,
              itemId: gala,
            ),
            rupees: 1000,
          ),
        ]);
        expect(await stockOf(gala), 80000);
      },
    );

    test('an edit that says nothing of packs leaves them alone, and a new size '
        'is the same row', () async {
      final gala = await biscuits();
      await catalogue.updateItem(
        actor,
        gala,
        ItemDraft(
          name: 'Gala Biscuit',
          baseUnitId: unit['pcs']!,
          saleRate: Rate.rupees(55),
        ),
      );
      expect(
        packsOf(
          await converter(),
          itemId: gala,
          baseUnitId: unit['pcs']!,
        ).single.size,
        Qty.units(24),
      );

      await catalogue.updateItem(
        actor,
        gala,
        ItemDraft(
          name: 'Gala Biscuit',
          baseUnitId: unit['pcs']!,
          saleRate: Rate.rupees(55),
          packs: [ItemPack(unitId: unit['carton']!, size: Qty.units(48))],
        ),
      );
      expect(
        await count(
          'SELECT COUNT(*) AS n FROM unit_conversions WHERE item_id IS NOT '
          'NULL',
        ),
        1,
      );
      expect(
        packsOf(
          await converter(),
          itemId: gala,
          baseUnitId: unit['pcs']!,
        ).single.size,
        Qty.units(48),
      );
      final audit = await db
          .customSelect(
            'SELECT summary FROM audit_log WHERE action_code = '
            "'ITEM_PACKS_SET' ORDER BY at_utc, id",
          )
          .get();
      expect(audit.last.read<String>('summary'), contains('1 carton = 48'));
    });

    test(
      "a pack the shop already sizes, or the item's own unit, is refused",
      () async {
        await expectLater(
          item(
            'Anday',
            unitCode: 'pcs',
            packs: [ItemPack(unitId: unit['dozen']!, size: Qty.units(10))],
          ),
          throwsA(isA<ArgumentError>()),
          reason: 'a dozen of ten would be a lie on the bill',
        );
        await expectLater(
          item(
            'Anday',
            unitCode: 'pcs',
            packs: [ItemPack(unitId: unit['pcs']!, size: Qty.units(10))],
          ),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          item(
            'Anday',
            unitCode: 'pcs',
            packs: [ItemPack(unitId: unit['carton']!, size: Qty.zero)],
          ),
          throwsA(isA<ArgumentError>()),
        );
        expect(
          await count("SELECT COUNT(*) AS n FROM items WHERE name = 'Anday'"),
          0,
          reason: 'a refused pack takes the item with it',
        );
      },
    );

    test(
      'a struck-out conversion does not hold its place against a live one',
      () async {
        final gala = await biscuits();
        final held = await db
            .customSelect(
              'SELECT id FROM unit_conversions WHERE item_id = ?',
              variables: [Variable<String>(gala)],
            )
            .getSingle();
        await runner.run(actor, (tx) async {
          await tx.softDelete('unit_conversions', held.read<String>('id'));
          await tx.insert('unit_conversions', {
            'from_unit_id': unit['carton'],
            'to_unit_id': unit['pcs'],
            'factor_thousandths': 12000,
            'item_id': gala,
          });
        });
        // Two live ones are still one too many.
        await expectLater(
          runner.run(
            actor,
            (tx) => tx.insert('unit_conversions', {
              'from_unit_id': unit['carton'],
              'to_unit_id': unit['pcs'],
              'factor_thousandths': 6000,
              'item_id': gala,
            }),
          ),
          throwsA(anything),
        );
      },
    );
  });
}
