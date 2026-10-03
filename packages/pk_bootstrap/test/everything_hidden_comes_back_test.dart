import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/paper.dart';

/// Everything a shopkeeper can hide comes back (M60, completing M5).
///
/// A van sold, a recipe no longer made, an expense head no longer used, a
/// member of staff who left: each put away with one act, each listed in the
/// bin with when and by whom, each back with one tap — and, with Data Lock
/// on, none of them put away without a PIN.
void main() {
  late AppServices shop;
  late String firmId;
  late String owner;
  late String oil;
  late String masala;
  late String chilli;

  setUp(() async {
    shop = await openInMemoryServices(
      clock: FixedClock(DateTime.utc(2026, 10, 3, 9, 15)),
    );
    await shop.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    owner = shop.currentUser!.id;
    firmId = (await shop.queries.currentFirm())!.id;
    final pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs');
    Future<String> item(String name, {int stock = 50}) =>
        shop.catalogue.addItem(
          shop.actorNow(),
          ItemDraft(
            name: name,
            baseUnitId: pcs.id,
            saleRate: Rate.rupees(100),
            openingStock: Qty.units(stock),
            openingRate: Rate.rupees(60),
          ),
        );
    oil = await item('Cooking Oil 5L');
    masala = await item('Chaat Masala 100g', stock: 0);
    chilli = await item('Lal Mirch 1kg');
  });

  tearDown(() => shop.close());

  Future<void> load(String to, int pieces, {String from = 'MAIN'}) =>
      shop.catalogue.transferStock(
        shop.actorNow(),
        StockTransferDraft(
          itemId: oil,
          from: from,
          to: to,
          qty: Qty.units(pieces),
        ),
      );

  Future<String> recipe() => shop.manufacturing.saveBom(
    shop.actorNow(),
    BomDraft(
      name: 'Chaat masala',
      outputItemId: masala,
      outputQty: Qty.units(10),
      lines: [BomLineDraft(itemId: chilli, qty: Qty.units(1))],
    ),
  );

  group('the recycle bin', () {
    test('a van with goods on board is not put away; empty, it goes, says who '
        'and when, and comes back', () async {
      final vanId = await shop.vans.addVan(shop.actorNow(), name: 'Suzuki 1');
      final van = (await shop.queries.vans(firmId)).single;
      await load(van.locationCode, 5);

      await expectLater(
        shop.recycle.hideVan(vanId),
        throwsA(
          isA<VanRefused>().having(
            (e) => e.reason,
            'reason',
            contains('still has 1 item on board'),
          ),
        ),
      );

      await load('MAIN', 5, from: van.locationCode);
      await shop.recycle.hideVan(vanId);
      expect(await shop.queries.vans(firmId), isEmpty);
      final hidden = await shop.recycle.hiddenVans();
      expect(hidden.single.name, 'Suzuki 1');
      final mark = (await shop.recycle.marks())['vans/$vanId']!;
      expect(mark.by, 'Malik Sahib');
      expect(mark.atUtc, DateTime.utc(2026, 10, 3, 9, 15));

      await shop.recycle.restoreVan(vanId);
      expect((await shop.queries.vans(firmId)).single.id, vanId);
      expect(await shop.recycle.hiddenVans(), isEmpty);
    });

    test('a van a phone still sells from is not put away', () async {
      final vanId = await shop.vans.addVan(shop.actorNow(), name: 'Suzuki 1');
      final van = (await shop.queries.vans(firmId)).single;
      await shop.setCounterLocation(van.locationCode);

      await expectLater(
        shop.recycle.hideVan(vanId),
        throwsA(
          isA<VanRefused>().having(
            (e) => e.reason,
            'reason',
            contains('A phone still sells from Suzuki 1'),
          ),
        ),
      );
      expect(await shop.queries.vans(firmId), hasLength(1));
    });

    test('a recipe put away leaves the list and comes back, its batches '
        'untouched', () async {
      final bomId = await recipe();
      final made = await shop.manufacturing.assemble(shop.actorNow(), bomId, 2);

      await shop.recycle.hideRecipe(bomId);
      expect(await shop.queries.boms(firmId), isEmpty);
      expect((await shop.recycle.hiddenRecipes()).single.name, 'Chaat masala');
      expect((await shop.recycle.marks())['boms/$bomId']?.by, 'Malik Sahib');
      // What was made from it is still on the shelf.
      final shelf = await shop.queries.searchItems(firmId, query: 'Chaat');
      expect(shelf.single.stockOnHand, Qty.units(20));
      expect(made.assemblyNo, isNotEmpty);

      await shop.recycle.restoreRecipe(bomId);
      expect((await shop.queries.boms(firmId)).single.id, bomId);
      expect(await shop.recycle.hiddenRecipes(), isEmpty);

      // And put away a second time, the one setting flips again.
      await shop.recycle.hideRecipe(bomId);
      expect(await shop.queries.boms(firmId), isEmpty);
    });

    test('heads, staff, items and customers hidden each say who hid them and '
        'when', () async {
      final heads = await shop.shopMoney.expenseHeads();
      final rent = heads.firstWhere((h) => h.systemKey == 'rent');
      await shop.shopMoney.setExpenseHeadHidden(rent.accountId, true);
      await shop.shopMoney.setIncomeHeadHidden('scrap', true);
      await shop.setPin(owner, '1947');
      final bilal = await shop.addStaff(
        name: 'Bilal',
        role: Role.cashier,
        pin: '1357',
      );
      await shop.setStaffActive(bilal, active: false);
      await shop.catalogue.archiveItem(shop.actorNow(), oil);
      final rashid = await shop.catalogue.addParty(
        shop.actorNow(),
        const PartyDraft(name: 'Rashid Traders'),
      );
      await shop.catalogue.archiveParty(shop.actorNow(), rashid);

      final marks = await shop.recycle.marks();
      for (final key in [
        'accounts/${rent.accountId}',
        'settings/scrap',
        'users/$bilal',
        'items/$oil',
        'parties/$rashid',
      ]) {
        expect(marks[key]?.by, 'Malik Sahib', reason: key);
      }
      expect((await shop.recycle.switchedOffStaff()).single.name, 'Bilal');
    });

    test('with Data Lock on, every hiding asks for a PIN and bringing back '
        'does not', () async {
      final vanId = await shop.vans.addVan(shop.actorNow(), name: 'Suzuki 1');
      final bomId = await recipe();
      final rent = (await shop.shopMoney.expenseHeads()).firstWhere(
        (h) => h.systemKey == 'rent',
      );
      final photo = await shop.photos.add(
        ownerTable: 'parties',
        ownerId: await shop.catalogue.addParty(
          shop.actorNow(),
          const PartyDraft(name: 'Rashid Traders'),
        ),
        kind: EntryPhotoKind.papers,
        source: paper(1),
        fileName: 'cnic.bmp',
      );
      await shop.setPin(owner, '1947');
      final bilal = await shop.addStaff(
        name: 'Bilal',
        role: Role.cashier,
        pin: '1357',
      );
      await shop.audit.setDataLock(on: true);

      final asks = <Future<void> Function()>[
        () => shop.recycle.hideVan(vanId),
        () => shop.recycle.hideRecipe(bomId),
        () => shop.shopMoney.setExpenseHeadHidden(rent.accountId, true),
        () => shop.shopMoney.setIncomeHeadHidden('scrap', true),
        () => shop.setStaffActive(bilal, active: false),
        () => shop.catalogue.archiveItem(shop.actorNow(), oil),
        () => shop.photos.remove(photo),
      ];
      for (final (i, hide) in asks.indexed) {
        await expectLater(
          hide(),
          throwsA(
            isA<ApprovalNeeded>().having(
              (e) => e.kind,
              'kind',
              ApprovalKind.dataLock,
            ),
          ),
          reason: 'hiding #$i went through without a PIN',
        );
      }
      expect(await shop.recycle.hiddenVans(), isEmpty, reason: 'rolled back');

      final asked = <ApprovalAsk>[];
      shop.audit.prompt = (ask) async {
        asked.add(ask);
        return ApprovalAnswer(userId: owner, pin: '1947');
      };
      await shop.recycle.hideVan(vanId);
      await shop.recycle.hideRecipe(bomId);
      expect(asked, hasLength(2));

      await shop.recycle.restoreVan(vanId);
      await shop.recycle.restoreRecipe(bomId);
      expect(asked, hasLength(2), reason: 'bringing back asks nothing');
    });

    test('every act that fills the bin is one Data Lock guards', () {
      for (final code in hidingActions.keys) {
        expect(undoingActions, contains(code), reason: code);
      }
    });
  });
}
