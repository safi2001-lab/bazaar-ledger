import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// A van's day: loaded, sold from, settled.
void main() {
  late AppServices shop;
  late String firmId;
  late String oil;

  setUp(() async {
    shop = await openInMemoryServices(
      clock: FixedClock(DateTime.utc(2026, 9, 30, 6)),
    );
    await shop.setUpShop(
      shopName: 'Rashid Traders',
      ownerName: 'Rashid',
      deviceLabel: 'Office',
    );
    firmId = (await shop.queries.currentFirm())!.id;
    final pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs');
    oil = await shop.catalogue.addItem(
      shop.actorNow(),
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: pcs.id,
        saleRate: Rate.rupees(2500),
        openingStock: Qty.units(50),
        openingRate: Rate.rupees(2000),
      ),
    );
  });

  tearDown(() => shop.close());

  Future<int> at(String location) async =>
      (await shop.database
              .customSelect(
                'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS q '
                'FROM stock_ledger WHERE item_id = ? AND location_code = ?',
                variables: [Variable<String>(oil), Variable<String>(location)],
              )
              .getSingle())
          .read<int>('q');

  Future<void> sell(String location, int pieces) async {
    final cash = (await shop.queries.paymentAccounts(
      firmId,
    )).firstWhere((a) => a.modeLabel == 'cash');
    final pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs');
    await shop.postSale(
      shop.actorNow(),
      SaleDraft(
        locationCode: location,
        lines: [
          SaleLineDraft(
            itemId: oil,
            itemName: 'Cooking Oil 5L',
            qty: Qty.units(pieces),
            baseQty: Qty.units(pieces),
            unitId: pcs.id,
            unitCode: 'pcs',
            rate: Rate.rupees(2500),
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: cash.id,
            mode: 'cash',
            amount: Money.rupees(2500 * pieces),
          ),
        ],
      ),
    );
  }

  group('van sales', () {
    test('a van is loaded, sells, and settles short', () async {
      final vanId = await shop.vans.addVan(shop.actorNow(), name: 'Suzuki 1');
      final van = (await shop.queries.vans(firmId)).single;
      expect(van.locationCode, 'VAN-SUZUKI1');

      await shop.catalogue.transferStock(
        shop.actorNow(),
        StockTransferDraft(
          itemId: oil,
          from: 'MAIN',
          to: van.locationCode,
          qty: Qty.units(10),
        ),
      );
      await sell(van.locationCode, 3);
      await sell('MAIN', 1);

      final today = BusinessDate.now(shop.clock);
      final day = await shop.queries.vanDay(firmId, vanId, today);
      expect(day.salesCount, 1, reason: 'the shop-floor sale is not the van');
      expect(day.expectedCash, const Money.rupees(7500));
      expect(day.stock.single.qty, Qty.units(7));

      final settled = await shop.vans.settle(
        shop.actorNow(),
        vanId,
        counted: const Money.rupees(7300),
      );
      expect(settled.difference, const Money.rupees(-200));
      expect(settled.linesReturned, 1);

      expect(await at(van.locationCode), 0);
      expect(await at('MAIN'), 46000, reason: '50 - 10 + 7 back - 1 sold');

      final short =
          (await shop.database
                  .customSelect(
                    'SELECT SUM(jl.debit_paisa) AS d FROM journal_lines jl '
                    'JOIN accounts a ON a.id = jl.account_id '
                    "WHERE a.system_key = 'cash_short_over'",
                  )
                  .getSingle())
              .read<int>('d');
      expect(short, 20000);
      final health = await shop.checkHealth();
      expect(health.isHealthy, isTrue, reason: health.toString());

      expect(
        (await shop.queries.vanDay(firmId, vanId, today)).settled?.counted,
        const Money.rupees(7300),
      );
    });

    test('a day is settled once', () async {
      final vanId = await shop.vans.addVan(shop.actorNow(), name: 'Suzuki 1');
      await shop.vans.settle(shop.actorNow(), vanId, counted: Money.zero);
      await expectLater(
        shop.vans.settle(shop.actorNow(), vanId, counted: Money.zero),
        throwsA(isA<VanRefused>()),
      );
    });

    test('a phone set to a van sells from the van', () async {
      await shop.vans.addVan(shop.actorNow(), name: 'Suzuki 1');
      expect(await shop.counterLocation(), 'MAIN');
      await shop.setCounterLocation('VAN-SUZUKI1');
      expect(await shop.counterLocation(), 'VAN-SUZUKI1');
    });
  });
}
