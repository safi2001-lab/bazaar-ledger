import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// The discount each role may give on its own, at the counter (M22).
void main() {
  late AppServices shop;
  late String firmId;
  late String oil;
  late String pcs;
  late String cash;

  setUp(() async {
    shop = await openInMemoryServices();
    await shop.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    firmId = (await shop.queries.currentFirm())!.id;
    pcs = (await shop.queries.units(
      firmId,
    )).firstWhere((u) => u.code == 'pcs').id;
    cash = (await shop.queries.paymentAccounts(
      firmId,
    )).firstWhere((a) => a.modeLabel == 'cash').id;
    oil = await shop.catalogue.addItem(
      shop.actorNow(),
      ItemDraft(
        name: 'Cooking Oil 5L',
        baseUnitId: pcs,
        saleRate: Rate.rupees(1000),
        openingStock: Qty.units(50),
      ),
    );
  });

  tearDown(() => shop.close());

  Future<PostedSale> sell({Money off = Money.zero, String? partyId}) {
    final total = const Money.rupees(1000) - off;
    return shop.postSale(
      shop.actorNow(),
      SaleDraft(
        partyId: partyId,
        lines: [
          SaleLineDraft(
            itemId: oil,
            itemName: 'Cooking Oil 5L',
            qty: Qty.units(1),
            baseQty: Qty.units(1),
            unitId: pcs,
            unitCode: 'pcs',
            rate: Rate.rupees(1000),
            explicitDiscount: off,
          ),
        ],
        tenders: [
          TenderDraft(paymentAccountId: cash, mode: 'cash', amount: total),
        ],
      ),
    );
  }

  Future<void> signInCashier() async {
    await shop.setPin(shop.currentUser!.id, '9999');
    final bilal = await shop.addStaff(
      name: 'Bilal',
      role: Role.cashier,
      pin: '2468',
    );
    expect(await shop.signIn(bilal, '2468'), isTrue);
  }

  group('discount ceiling', () {
    test('the rule: up to the ceiling, or the party\'s own discount', () {
      bool ok(int offRupees, {Role role = Role.cashier, int standing = 0}) =>
          discountAllowed(
            role: role,
            subtotal: const Money.rupees(1000),
            discount: Money.rupees(offRupees),
            standingBp: standing,
          );
      expect(ok(50), isTrue, reason: 'exactly 5%');
      expect(ok(51), isFalse);
      expect(ok(100, standing: 1000), isTrue);
      expect(ok(200, role: Role.manager), isTrue);
      expect(ok(201, role: Role.manager), isFalse);
      expect(ok(1000, role: Role.owner), isTrue);
      expect(ok(1, role: Role.accountant), isFalse);
      expect(ok(0, role: Role.accountant), isTrue);
    });

    test('a cashier\'s 5% goes through; 8% is refused and nothing is '
        'written', () async {
      await signInCashier();
      await sell(off: const Money.rupees(50));
      await expectLater(
        sell(off: const Money.rupees(80)),
        throwsA(isA<PermissionDenied>()),
      );
      final bills = await shop.database
          .customSelect(
            "SELECT COUNT(*) AS n FROM documents WHERE doc_type = 'sale_invoice'",
          )
          .getSingle();
      expect(bills.read<int>('n'), 1);
    });

    test(
      'a customer the owner gave 10% off is rung at 10% by a cashier',
      () async {
        final rashid = await shop.catalogue.addParty(
          shop.actorNow(),
          const PartyDraft(name: 'Rashid', defaultDiscountBp: 1000),
        );
        await signInCashier();
        await sell(off: const Money.rupees(100), partyId: rashid);
        await expectLater(
          sell(off: const Money.rupees(150), partyId: rashid),
          throwsA(isA<PermissionDenied>()),
        );
      },
    );

    test('the owner gives what they like', () async {
      await sell(off: const Money.rupees(400));
    });
  });
}
