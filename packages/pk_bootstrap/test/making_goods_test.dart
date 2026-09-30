import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// A production run, through the one write path and into the books.
void main() {
  late AppServices shop;
  late String chilli;
  late String salt;
  late String pack;

  setUp(() async {
    shop = await openInMemoryServices(
      clock: FixedClock(DateTime.utc(2026, 9, 30, 6)),
    );
    await shop.setUpShop(
      shopName: 'Shan Masala House',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    final firm = (await shop.queries.currentFirm())!;
    final units = await shop.queries.units(firm.id);
    final kg = units.firstWhere((u) => u.code == 'kg');
    final pcs = units.firstWhere((u) => u.code == 'pcs');
    Future<String> item(String name, String unit, int stock, int cost) =>
        shop.catalogue.addItem(
          shop.actorNow(),
          ItemDraft(
            name: name,
            baseUnitId: unit,
            saleRate: Rate.rupees(cost * 2),
            openingStock: Qty.units(stock),
            openingRate: Rate.rupees(cost),
          ),
        );
    chilli = await item('Red chilli', kg.id, 5, 800);
    salt = await item('Salt', kg.id, 10, 50);
    pack = await item('Mirch masala 100g', pcs.id, 0, 0);
  });

  tearDown(() => shop.close());

  Future<int> onHand(String itemId) async =>
      (await shop.database
              .customSelect(
                'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS q '
                'FROM stock_ledger WHERE item_id = ?',
                variables: [Variable<String>(itemId)],
              )
              .getSingle())
          .read<int>('q');

  Future<String> recipe() => shop.manufacturing.saveBom(
    shop.actorNow(),
    BomDraft(
      name: 'Mirch masala',
      outputItemId: pack,
      outputQty: Qty.units(10),
      overhead: const Money.rupees(50),
      lines: [
        BomLineDraft(itemId: chilli, qty: Qty.units(1)),
        BomLineDraft(itemId: salt, qty: Qty.raw(200)),
      ],
    ),
  );

  group('making goods', () {
    test(
      'a run moves the stock, costs the goods and keeps the books',
      () async {
        final bom = await recipe();
        final result = await shop.manufacturing.assemble(
          shop.actorNow(),
          bom,
          2,
        );
        expect(result.assemblyNo, startsWith('ASM-2627-'));

        expect(await onHand(chilli), 3000);
        expect(await onHand(salt), 9600);
        expect(await onHand(pack), 20000);

        final firm = (await shop.queries.currentFirm())!;
        final packs = (await shop.queries.searchItems(
          firm.id,
          query: 'Mirch',
        )).single;
        expect(packs.stockOnHand, Qty.units(20));
        final avg =
            (await shop.database
                    .customSelect(
                      'SELECT avg_cost_milli_paisa FROM items WHERE id = ?',
                      variables: [Variable<String>(pack)],
                    )
                    .getSingle())
                .read<int>('avg_cost_milli_paisa');
        expect(avg, Rate.rupees(86).inMilliPaisa, reason: '1,720 / 20 packs');

        final health = await shop.checkHealth();
        expect(health.isHealthy, isTrue, reason: health.toString());

        // The work, Rs 100, is carried in stock until the packs are sold.
        final work =
            (await shop.database
                    .customSelect(
                      'SELECT SUM(jl.credit_paisa) AS c FROM journal_lines jl '
                      'JOIN accounts a ON a.id = jl.account_id '
                      "WHERE a.system_key = 'production_overhead'",
                    )
                    .getSingle())
                .read<int>('c');
        expect(work, 10000);
      },
    );

    test('a run the shelf cannot cover changes nothing', () async {
      final bom = await recipe();
      await expectLater(
        shop.manufacturing.assemble(shop.actorNow(), bom, 6),
        throwsA(isA<AssemblyRefused>()),
      );
      expect(await onHand(chilli), 5000);
      expect(await onHand(pack), 0);
    });

    test('a recipe is kept, listed and changed', () async {
      final bom = await recipe();
      final firm = (await shop.queries.currentFirm())!;
      var listed = (await shop.queries.boms(firm.id)).single;
      expect(listed.id, bom);
      expect(listed.outputName, 'Mirch masala 100g');
      expect(listed.componentNames.values, ['Red chilli', 'Salt']);

      await shop.manufacturing.saveBom(
        shop.actorNow(),
        BomDraft(
          name: 'Mirch masala',
          outputItemId: pack,
          outputQty: Qty.units(12),
          lines: [BomLineDraft(itemId: chilli, qty: Qty.units(1))],
        ),
        bomId: bom,
      );
      listed = (await shop.queries.boms(firm.id)).single;
      expect(listed.draft.outputQty, Qty.units(12));
      expect(listed.draft.lines.single.itemId, chilli);
    });
  });
}
