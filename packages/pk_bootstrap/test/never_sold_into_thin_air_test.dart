import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// One clock for both phones, a millisecond on at every look.
final class _Ticking implements Clock {
  DateTime _t = DateTime.utc(2026, 10, 3, 5);

  @override
  DateTime nowUtc() => _t = _t.add(const Duration(milliseconds: 1));
}

/// Selling below nothing, through the services the app is built on (M53):
/// the owner's rule reaching the sale path and the challan, who may change
/// it, and two counters on the shop's Wi-Fi each selling the last packet
/// while apart, over a real socket on this machine.
void main() {
  late _Ticking clock;
  late AppServices master;
  late AppServices counter;
  late String biscuit;
  late String pcs;

  setUp(() async {
    clock = _Ticking();
    master = await openInMemoryServices(clock: clock);
    await master.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Master',
    );
    final firm = (await master.queries.currentFirm())!;
    pcs = (await master.queries.units(
      firm.id,
    )).singleWhere((u) => u.code == 'pcs').id;
    biscuit = await master.catalogue.addItem(
      master.actorNow(),
      ItemDraft(
        name: 'Gala Biscuit',
        baseUnitId: pcs,
        saleRate: Rate.rupees(50),
        openingStock: Qty.one,
        openingRate: Rate.rupees(40),
        negativeStock: NegativeStock.block,
      ),
    );
    final port = await master.sync.startHosting(
      port: 0,
      address: InternetAddress.loopbackIPv4,
    );
    counter = await openInMemoryServices(clock: clock);
    await counter.sync.join(
      host: '127.0.0.1',
      port: port,
      code: master.sync.openJoining(),
      label: 'Counter 2',
    );
  });

  tearDown(() async {
    await counter.close();
    await master.close();
  });

  /// [pieces] of the biscuit for cash, at [phone]'s own till.
  Future<PostedSale> sell(AppServices phone, int pieces) async {
    final firm = (await phone.queries.currentFirm())!;
    final cash = (await phone.queries.paymentAccounts(
      firm.id,
    )).firstWhere((a) => a.modeLabel == 'cash');
    return phone.postSale(
      phone.actorNow(),
      SaleDraft(
        lines: [
          SaleLineDraft(
            itemId: biscuit,
            itemName: 'Gala Biscuit',
            qty: Qty.units(pieces),
            baseQty: Qty.units(pieces),
            unitId: pcs,
            unitCode: 'pcs',
            rate: Rate.rupees(50),
          ),
        ],
        tenders: [
          TenderDraft(
            paymentAccountId: cash.id,
            mode: 'cash',
            amount: Money.rupees(50 * pieces),
          ),
        ],
      ),
    );
  }

  Future<ItemSummary> onShelf(AppServices phone) async {
    final firm = (await phone.queries.currentFirm())!;
    return (await phone.queries.itemById(firm.id, biscuit))!;
  }

  group('selling below nothing', () {
    test('two counters apart each sell the last packet: the merge keeps both '
        'bills and the shelf reads below nothing on both phones', () async {
      expect((await onShelf(counter)).negativeStock, NegativeStock.block);

      // Apart: each sells the one packet it knows of, rightly by what it
      // knows. The rule is kept at each phone at the moment of sale.
      await sell(master, 1);
      await sell(counter, 1);

      await counter.sync.syncNow();

      for (final phone in [master, counter]) {
        final item = await onShelf(phone);
        expect(item.stockOnHand, -Qty.one);
        expect(item.isBelowNothing, isTrue);
        final firm = (await phone.queries.currentFirm())!;
        expect(
          (await phone.queries.lowStockItems(firm.id)).map((i) => i.id),
          contains(biscuit),
          reason: 'flagged where the owner looks for what to count',
        );
        final bills = await phone.database
            .customSelect(
              'SELECT COUNT(*) AS n FROM documents WHERE doc_type = '
              "'sale_invoice'",
            )
            .getSingle();
        expect(bills.read<int>('n'), 2, reason: 'a sale is never merged away');
        final health = await phone.checkHealth();
        expect(health.isHealthy, isTrue, reason: health.toString());

        // And from here neither phone sells another.
        await expectLater(sell(phone, 1), throwsA(isA<ShelfRefused>()));
      }
    });

    test(
      "the owner's rule for the shop reaches the sale path and the challan",
      () async {
        expect(await master.shelf.shopRule(), NegativeStock.warn);
        final firm = (await master.queries.currentFirm())!;
        final cheeni = await master.catalogue.addItem(
          master.actorNow(),
          ItemDraft(
            name: 'Cheeni',
            baseUnitId: pcs,
            saleRate: Rate.rupees(160),
          ),
        );
        final customer = await master.catalogue.addParty(
          master.actorNow(),
          const PartyDraft(name: 'Rashid Traders'),
        );
        SaleDraft cheeniBill() => SaleDraft(
          partyId: customer,
          partyName: 'Rashid Traders',
          lines: [
            SaleLineDraft(
              itemId: cheeni,
              itemName: 'Cheeni',
              qty: Qty.one,
              baseQty: Qty.one,
              unitId: pcs,
              unitCode: 'pcs',
              rate: Rate.rupees(160),
            ),
          ],
        );

        // A shop that never chose asks; the service lets it through.
        await master.postSale(master.actorNow(), cheeniBill());

        await master.shelf.setShopRule(NegativeStock.block);
        expect(await master.shelf.shopRule(), NegativeStock.block);
        await expectLater(
          master.postSale(master.actorNow(), cheeniBill()),
          throwsA(isA<ShelfRefused>()),
        );
        await expectLater(
          master.issueChallan(master.actorNow(), cheeniBill()),
          throwsA(isA<ShelfRefused>()),
        );
        final shelf = await master.shelf.atCounter([cheeni]);
        expect(shelf[cheeni]!.onHand, -Qty.one);
        expect(shelf[cheeni]!.rule, NegativeStock.block);

        final logged = await master.database
            .customSelect(
              'SELECT summary FROM audit_log WHERE firm_id = ? AND '
              "action_code = 'NEGATIVE_STOCK_RULE_SET'",
              variables: [Variable<String>(firm.id)],
            )
            .getSingle();
        expect(logged.read<String>('summary'), contains('block'));
      },
    );

    test("only the owner changes a rule, the shop's or an item's", () async {
      await master.setPin(master.currentUser!.id, '1947');
      final bilal = await master.addStaff(
        name: 'Bilal',
        role: Role.cashier,
        pin: '2468',
      );
      await master.lock();
      await master.signIn(bilal, '2468');

      expect(master.shelf.canSetRules, isFalse);
      await expectLater(
        master.shelf.setShopRule(NegativeStock.allow),
        throwsA(isA<PermissionDenied>()),
      );
      ItemDraft draft(NegativeStock? rule) => ItemDraft(
        name: 'Gala Biscuit',
        baseUnitId: pcs,
        saleRate: Rate.rupees(55),
        negativeStock: rule,
      );
      await expectLater(
        master.catalogue.updateItem(
          master.actorNow(),
          biscuit,
          draft(NegativeStock.allow),
        ),
        throwsA(isA<PermissionDenied>()),
        reason: 'the cashier the rule is meant to stop cannot lift it',
      );
      // The price, with the rule left as the owner set it, is his to edit.
      await master.catalogue.updateItem(
        master.actorNow(),
        biscuit,
        draft(NegativeStock.block),
      );
      expect((await onShelf(master)).saleRate, Rate.rupees(55));
    });

    test(
      'two counters that give one item a carton while apart keep selling, '
      'the second carton kept as a clash rather than stopping every sync',
      () async {
        final firm = (await master.queries.currentFirm())!;
        final carton = (await master.queries.units(
          firm.id,
        )).singleWhere((u) => u.code == 'carton').id;
        ItemDraft packed(int size) => ItemDraft(
          name: 'Gala Biscuit',
          baseUnitId: pcs,
          saleRate: Rate.rupees(50),
          negativeStock: NegativeStock.block,
          packs: [ItemPack(unitId: carton, size: Qty.units(size))],
        );
        await master.catalogue.updateItem(
          master.actorNow(),
          biscuit,
          packed(24),
        );
        await counter.catalogue.updateItem(
          counter.actorNow(),
          biscuit,
          packed(12),
        );

        final report = await counter.sync.syncNow();
        expect(report.conflicts, greaterThan(0));

        Future<List<int>> liveCartons(AppServices phone) async => [
          for (final r
              in await phone.database
                  .customSelect(
                    'SELECT factor_thousandths AS f FROM unit_conversions '
                    'WHERE item_id = ? AND deleted_at_utc IS NULL',
                    variables: [Variable<String>(biscuit)],
                  )
                  .get())
            r.read<int>('f'),
        ];
        expect(await liveCartons(master), [24000], reason: 'its own stands');
        expect(await liveCartons(counter), [12000]);

        // And the next sync goes through.
        await sell(master, 1);
        final again = await counter.sync.syncNow();
        expect(again.received.applied, greaterThan(0));
      },
    );
  });
}
