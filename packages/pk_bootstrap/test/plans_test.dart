import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:pk_data/pk_data.dart' show madeWithLine;

import 'support/play_test_key.dart';

/// The subscription plans (M21): what each one unlocks, what a free shop
/// is refused, and that only a purchase Google Play signed changes it.
void main() {
  late FixedClock clock;
  late AppServices shop;
  late String firmId;
  late String pcs;

  setUp(() async {
    clock = FixedClock(DateTime.utc(2026, 10, 1, 6));
    shop = await openInMemoryServices(clock: clock);
    await shop.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    firmId = (await shop.queries.currentFirm())!.id;
    pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs').id;
    shop.plans
      ..publicKey = testPlayPublicKey
      ..allowTestPlans = false
      ..pinForTests(null);
  });

  tearDown(() => shop.close());

  ({String json, String signature}) purchase(
    Plan plan, {
    int state = 0,
    String package = 'pk.bazaarledger',
  }) {
    final json = jsonEncode({
      'orderId': 'GPA.0000-${plan.name}',
      'packageName': package,
      'productId': plan.productId,
      'purchaseTime': 1790000000000,
      'purchaseState': state,
      'purchaseToken': 'token-${plan.name}',
      'autoRenewing': true,
    });
    return (json: json, signature: signLikePlay(json));
  }

  ItemDraft oilDraft({
    String name = 'Cooking Oil 5L',
    Rate? wholesale,
    Rate? vip,
    bool batch = false,
  }) => ItemDraft(
    name: name,
    baseUnitId: pcs,
    saleRate: Rate.rupees(2500),
    wholesaleRate: wholesale,
    vipRate: vip,
    tracksBatch: batch,
  );

  Future<String> item({Rate? wholesale, Rate? vip, bool batch = false}) =>
      shop.catalogue.addItem(
        shop.actorNow(),
        oilDraft(wholesale: wholesale, vip: vip, batch: batch),
      );

  Matcher needs(Plan plan) =>
      throwsA(isA<PlanRequired>().having((e) => e.needed, 'needed', plan));

  group('plans', () {
    test('a phone with no purchase is on free, and its bills say what made '
        'them', () async {
      expect(shop.plans.plan, Plan.free);
      final oil = await item();
      final cash = (await shop.queries.paymentAccounts(
        firmId,
      )).firstWhere((a) => a.modeLabel == 'cash');
      final sale = await shop.postSale(
        shop.actorNow(),
        SaleDraft(
          lines: [
            SaleLineDraft(
              itemId: oil,
              itemName: 'Cooking Oil 5L',
              qty: Qty.units(1),
              baseQty: Qty.units(1),
              unitId: pcs,
              unitCode: 'pcs',
              rate: Rate.rupees(2500),
            ),
          ],
          tenders: [
            TenderDraft(
              paymentAccountId: cash.id,
              mode: 'cash',
              amount: const Money.rupees(2500),
            ),
          ],
        ),
      );
      final receipt = await shop.queries.receiptFor(firmId, sale.documentId);
      expect(receipt!.footerLines, contains(madeWithLine));

      shop.plans.pinForTests(Plan.silver);
      final paid = await shop.queries.receiptFor(firmId, sale.documentId);
      expect(paid!.footerLines, isNot(contains(madeWithLine)));
    });

    test('every paid feature is refused on free, naming the plan that has '
        'it', () async {
      final oil = await shop.catalogue.addItem(
        shop.actorNow(),
        ItemDraft(
          name: 'Ghee 1kg',
          baseUnitId: pcs,
          saleRate: Rate.rupees(600),
          openingStock: Qty.units(10),
        ),
      );
      await expectLater(
        shop.catalogue.addParty(
          shop.actorNow(),
          const PartyDraft(name: 'Rashid', priceTier: PriceTier.wholesale),
        ),
        needs(Plan.silver),
      );
      await expectLater(item(wholesale: Rate.rupees(2400)), needs(Plan.silver));
      await expectLater(item(batch: true), needs(Plan.gold));
      await expectLater(
        shop.catalogue.transferStock(
          shop.actorNow(),
          StockTransferDraft(
            itemId: oil,
            qty: Qty.units(1),
            from: 'MAIN',
            to: 'GODOWN',
          ),
        ),
        needs(Plan.gold),
      );
      final rashid = await shop.catalogue.addParty(
        shop.actorNow(),
        const PartyDraft(name: 'Rashid', openingBalance: Money.rupees(5000)),
      );
      final cheque = (await shop.queries.paymentAccounts(
        firmId,
      )).firstWhere((a) => a.modeLabel == 'cheque');
      await expectLater(
        shop.recordReceipt(
          shop.actorNow(),
          ReceiptDraft(
            partyId: rashid,
            amount: const Money.rupees(5000),
            mode: 'cheque',
            paymentAccountId: cheque.id,
            chequeNo: '000123',
            chequeBank: 'Meezan',
            chequeDateUtcMillis: DateTime.utc(
              2026,
              10,
              20,
            ).millisecondsSinceEpoch,
          ),
        ),
        needs(Plan.silver),
      );
      await expectLater(
        shop.setScaleFormat(ScaleFormat.standard),
        needs(Plan.gold),
      );
      await expectLater(shop.sync.startHosting(port: 0), needs(Plan.gold));
      expect(() => shop.manufacturing, needs(Plan.platinum));
      expect(() => shop.vans, needs(Plan.platinum));
      await expectLater(shop.drive.turnOn('chishti-1987'), needs(Plan.silver));
      await shop.updateFirm({'is_sales_tax_registered': 1, 'ntn': '1234567-8'});
      await expectLater(
        shop.fbr.save(const FbrSettings(enabled: true, token: 't')),
        needs(Plan.platinum),
      );
      await expectLater(
        shop.addFirm(shopName: 'Second Shop', ownerName: 'Malik'),
        needs(Plan.silver),
      );

      // Nothing refused left anything behind.
      final parties = await shop.queries.searchParties(firmId, query: '');
      expect(parties.map((p) => p.name), ['Rashid']);
    });

    test('a plan includes every plan below it', () {
      for (final f in PlanFeature.values) {
        for (final p in Plan.values) {
          shop.plans.pinForTests(p);
          expect(shop.plans.has(f), p.index >= f.plan.index, reason: '$f $p');
        }
      }
      expect(Plan.free.firms, 1);
      expect(Plan.silver.firms, 3);
      expect(Plan.platinum.firms, isNull);
      expect(Plan.silver.users, 1);
      expect(Plan.gold.users, 5);
      expect(Plan.platinum.users, isNull);
    });

    test(
      'a purchase Play signed unlocks its plan; edited, it unlocks nothing',
      () async {
        final gold = purchase(Plan.gold);
        expect(await shop.plans.bought(gold.json, gold.signature), Plan.gold);
        expect(shop.plans.plan, Plan.gold);
        expect(shop.plans.has(PlanFeature.lanSync), isTrue);
        expect(shop.plans.has(PlanFeature.vans), isFalse);

        final forged = gold.json.replaceFirst('plan_gold', 'plan_platinum');
        expect(await shop.plans.bought(forged, gold.signature), Plan.gold);

        final elsewhere = purchase(Plan.platinum, package: 'com.someone.else');
        expect(
          await shop.plans.bought(elsewhere.json, elsewhere.signature),
          Plan.gold,
        );
        final pending = purchase(Plan.platinum, state: 2);
        expect(
          await shop.plans.bought(pending.json, pending.signature),
          Plan.gold,
        );
      },
    );

    test('the plan is kept on the phone, checked again when the app opens, '
        'and lapses when Play stops confirming it', () async {
      final silver = purchase(Plan.silver);
      await shop.plans.confirm([silver]);
      expect(shop.plans.plan, Plan.silver);

      // The stored purchase edited on the phone: free on the next open.
      final stored = (await shop.drafts.read('plan.purchase'))!;
      await shop.drafts.write(
        'plan.purchase',
        stored.replaceFirst('plan_silver', 'plan_platinum'),
      );
      await shop.plans.load();
      expect(shop.plans.plan, Plan.free);

      await shop.plans.confirm([silver]);
      clock.advance(planOfflineGrace - const Duration(days: 1));
      await shop.plans.load();
      expect(shop.plans.plan, Plan.silver, reason: 'a month without signal');
      clock.advance(const Duration(days: 2));
      await shop.plans.load();
      expect(shop.plans.plan, Plan.free);

      await shop.plans.confirm([silver]);
      expect(shop.plans.plan, Plan.silver);
      await shop.plans.confirm(const []);
      expect(shop.plans.plan, Plan.free, reason: 'Play says it has ended');
    });

    test(
      'with no key in the build, nothing verifies: it never falls open',
      () async {
        shop.plans.publicKey = '';
        final platinum = purchase(Plan.platinum);
        expect(
          await shop.plans.bought(platinum.json, platinum.signature),
          Plan.free,
        );
      },
    );

    test('losing a plan locks nothing already made', () async {
      shop.plans.pinForTests(Plan.silver);
      final oil = await item(wholesale: Rate.rupees(2400));
      final rashid = await shop.catalogue.addParty(
        shop.actorNow(),
        const PartyDraft(name: 'Rashid', priceTier: PriceTier.wholesale),
      );
      shop.plans.pinForTests(Plan.free);

      await shop.catalogue.updateItem(
        shop.actorNow(),
        oil,
        oilDraft(name: 'Cooking Oil 5 litre', wholesale: Rate.rupees(2400)),
      );
      await shop.catalogue.updateParty(
        shop.actorNow(),
        rashid,
        const PartyDraft(name: 'Rashid Bhai', priceTier: PriceTier.wholesale),
      );
      await expectLater(
        shop.catalogue.updateItem(
          shop.actorNow(),
          oil,
          oilDraft(wholesale: Rate.rupees(2400), vip: Rate.rupees(2300)),
        ),
        needs(Plan.silver),
      );
    });

    test('staff need Gold, and Gold has five people', () async {
      await shop.setPin(shop.currentUser!.id, '4321');
      await expectLater(
        shop.addStaff(name: 'Bilal', role: Role.cashier, pin: '1111'),
        needs(Plan.gold),
      );
      shop.plans.pinForTests(Plan.gold);
      for (final name in ['Bilal', 'Asif', 'Kamran', 'Tariq']) {
        await shop.addStaff(name: name, role: Role.cashier, pin: '1111');
      }
      await expectLater(
        shop.addStaff(name: 'Imran', role: Role.cashier, pin: '1111'),
        needs(Plan.platinum),
      );
    });

    test(
      'a plan can be picked by hand on a test build, never on a release',
      () async {
        await expectLater(
          shop.plans.setTestPlan(Plan.platinum),
          throwsStateError,
        );
        shop.plans.allowTestPlans = true;
        await shop.plans.setTestPlan(Plan.platinum);
        expect(shop.plans.plan, Plan.platinum);
        expect(shop.plans.purchased, Plan.free);
        shop.plans.allowTestPlans = false;
        expect(shop.plans.plan, Plan.free);
      },
    );
  });
}
