import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// M45 against a real database: a bill read back for printing says how
/// many cartons a line of pieces is, from the item's own packs, and a line
/// sold by the carton counts in the carton it was sold at.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late DriftAppQueries queries;
  late DriftCatalogueWriter catalogue;
  late PostSaleUseCase postSale;
  late RecordPurchaseUseCase buy;
  late ActorContext actor;
  late Map<String, String> unit;

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
    final runner = TxRunner(database: db, ids: ids, hlc: hlc);
    queries = DriftAppQueries(db);
    catalogue = DriftCatalogueWriter(runner);
    postSale = PostSaleUseCase(
      writer: DriftSaleWriter(runner: runner),
      shelf: DriftShelfReader(db),
    );
    buy = RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: runner));
    unit = {
      for (final r in await db.customSelect('SELECT id, code FROM units').get())
        r.read<String>('code'): r.read<String>('id'),
    };
  });

  tearDown(() async => db.close());

  Future<String> item(String name, String unitCode, {List<ItemPack>? packs}) =>
      catalogue.addItem(
        actor,
        ItemDraft(
          name: name,
          baseUnitId: unit[unitCode]!,
          saleRate: Rate.rupees(40),
          openingStock: Qty.units(500),
          openingRate: Rate.rupees(30),
          packs: packs,
        ),
      );

  SaleLineDraft line(
    String itemId,
    Qty qty,
    String unitCode, {
    Qty? baseQty,
    required Rate rate,
  }) => SaleLineDraft(
    itemId: itemId,
    itemName: 'Item',
    qty: qty,
    baseQty: baseQty ?? qty,
    unitId: unit[unitCode],
    unitCode: unitCode,
    rate: rate,
  );

  group('counted on paper', () {
    test('a bill read for printing counts a line of pieces in its cartons, '
        'and leaves a carton line and a weight as they were sold', () async {
      final gala = await item(
        'Gala Biscuit',
        'pcs',
        packs: [ItemPack(unitId: unit['carton']!, size: Qty.units(24))],
      );
      final cheeni = await item('Cheeni', 'kg');
      final oil = await item('Cooking Oil 5L', 'pcs');

      final customer = await catalogue.addParty(
        actor,
        const PartyDraft(name: 'Rashid Traders'),
      );
      final sale = await postSale(
        actor,
        SaleDraft(
          partyId: customer,
          partyName: 'Rashid Traders',
          lines: [
            line(gala, Qty.units(53), 'pcs', rate: Rate.rupees(40)),
            line(
              gala,
              Qty.units(2),
              'carton',
              baseQty: Qty.units(48),
              rate: Rate.rupees(960),
            ),
            line(cheeni, Qty.parse('1.5'), 'kg', rate: Rate.rupees(160)),
            line(oil, Qty.units(2), 'pcs', rate: Rate.rupees(2500)),
          ],
          roundToRupee: false,
        ),
      );
      // 53 x 40 + 2 x 960 + 1.5 x 160 + 2 x 2,500, to the paisa.
      expect(sale.total, Money.rupees(2120 + 1920 + 240 + 5000));

      final paper = (await queries.receiptFor(firm.firmId, sale.documentId))!;
      final lines = paper.lines;
      expect(lines[0].qtyDisplay, '53');
      expect(lines[0].qtyWords, '2 ctn 5 pc');
      expect(lines[1].qtyWords, isNull, reason: '"2 carton" says it already');
      expect(
        lines[2].qtyWords,
        isNull,
        reason: 'a weight keeps "1.5 kg x rate" on paper, as M56 left it',
      );
      expect(lines[3].qtyWords, isNull);
    });

    test('a delivery of loose pieces reads back in cartons too', () async {
      final gala = await item(
        'Gala Biscuit',
        'pcs',
        packs: [ItemPack(unitId: unit['carton']!, size: Qty.units(24))],
      );
      final supplier = await catalogue.addParty(
        actor,
        const PartyDraft(name: 'Peek Freans Depot', partyType: 'supplier'),
      );
      final posted = await buy(
        actor,
        PurchaseDraft(
          partyId: supplier,
          lines: [
            PurchaseLineDraft(
              itemId: gala,
              itemName: 'Gala Biscuit',
              qty: Qty.units(245),
              baseQty: Qty.units(245),
              unitId: unit['pcs']!,
              unitCode: 'pcs',
              rate: Rate.rupees(40),
            ),
          ],
        ),
      );
      final paper = (await queries.receiptFor(firm.firmId, posted.documentId))!;
      expect(paper.lines.single.qtyWords, '10 ctn 5 pc');
    });
  });
}
