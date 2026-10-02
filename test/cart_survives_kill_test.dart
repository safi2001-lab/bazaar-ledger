import 'package:bazaar_ledger/features/pos/cart.dart';
import 'package:bazaar_ledger/features/pos/cart_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_domain/pk_domain.dart';

import 'support/harness.dart';

/// A bill half-rung when the ROM takes the app away.
///
/// This is not a hypothetical. Transsion — Infinix, Tecno, itel — is about 44%
/// of the Pakistani market at the bottom end, and its ROMs ship Phone Master
/// with a Boost button that force-stops backgrounded apps. A cashier who has
/// fifteen lines on a bill, switches to WhatsApp to check a price, and comes
/// back to an empty cart re-scans the lot with the customer standing there.
///
/// Flutter's own state restoration does not cover it. It rides on Android's
/// `savedInstanceState`, which is tied to the task record, and a force-stop
/// takes the task record with it — as does swiping the app off Recents, and as
/// does a reboot. It survives a low-memory reclaim and nothing else, which is
/// the case a shopkeeper is least likely to notice.
void main() {
  group('the cart round trip', () {
    ItemSummary oil({int rupees = 2500}) => ItemSummary(
      id: 'item-oil',
      name: 'Cooking Oil 5L',
      code: 'OIL5',
      unitId: 'unit-pcs',
      unitCode: 'pcs',
      unitDecimals: 0,
      saleRate: Rate.rupees(rupees),
      stockOnHand: Qty.units(20),
      tracksStock: true,
    );

    test('every paisa and every thousandth survives it', () {
      final cart = Cart(
        lines: [
          CartLine(
            item: oil(),
            // 0.750 of something, to prove the fraction is not rounded away —
            // the previous build rendered `quantity.toInt()` and showed a
            // cashier a zero for 750 grams of mutton.
            qty: Qty.parse('0.750'),
            rate: const Rate.rupees(2500),
            discountBp: 250,
          ),
        ],
        partyId: 'party-1',
        partyName: 'Bilal General Store',
        billDiscount: const Money.rupees(15, 37),
      );

      final restored = CartDraft.decode(CartDraft.encode(cart))!;

      expect(restored.lines.single.qty.inThousandths, 750);
      expect(
        restored.lines.single.rate.inMilliPaisa,
        const Rate.rupees(2500).inMilliPaisa,
      );
      expect(restored.lines.single.discountBp, 250);
      expect(restored.billDiscount.inPaisa, 1537);
      expect(restored.partyId, 'party-1');
      expect(restored.partyName, 'Bilal General Store');
      expect(restored.subtotal, cart.subtotal, reason: 'the total moved');
    });

    test('a draft from another build is dropped, not guessed at', () {
      final encoded = CartDraft.encode(const Cart());
      expect(
        CartDraft.decode(
          encoded.replaceFirst('"v":${CartDraft.version}', '"v":99'),
        ),
        isNull,
      );
    });

    test('the customer prices survive it', () {
      const cart = Cart(
        partyId: 'party-1',
        partyName: 'Bilal General Store',
        priceTier: PriceTier.wholesale,
        partyDiscountBp: 250,
      );
      final restored = CartDraft.decode(CartDraft.encode(cart))!;
      expect(restored.priceTier, PriceTier.wholesale);
      expect(restored.partyDiscountBp, 250);
    });

    test('a draft from the build before price tiers is read as retail', () {
      // Every v2 cart was priced retail, so that is what it is read as.
      final v2 = CartDraft.encode(
        const Cart(partyId: 'party-1', partyName: 'Bilal General Store'),
      ).replaceFirst('"v":${CartDraft.version}', '"v":2');
      final restored = CartDraft.decode(v2)!;
      expect(restored.priceTier, PriceTier.retail);
      expect(restored.partyId, 'party-1');
    });

    test('a draft from the build before loose lines is read as it was', () {
      // M37 bumped the draft to v4 for loose lines. A v3 draft is a v4 one
      // without any, so the bill half-rung before the update survives it.
      final v3 = CartDraft.encode(
        Cart(
          lines: [
            CartLine(
              item: oil(),
              qty: Qty.units(2),
              rate: const Rate.rupees(2500),
            ),
          ],
        ),
      ).replaceFirst('"v":${CartDraft.version}', '"v":3');
      final restored = CartDraft.decode(v3)!;
      expect(restored.lines.single.isLoose, isFalse);
      expect(restored.subtotal, const Money.rupees(5000));
    });

    test('a loose line comes back loose, never as an item', () {
      // Its "item" is the cart's own stand-in. Read back as an ordinary
      // line, it would post an item id that names nothing in the shop.
      final cart = Cart(
        lines: [
          CartLine.loose(
            key: 'loose-1',
            name: 'Pyaz',
            qty: Qty.parse('2.5'),
            rate: const Rate.rupees(120),
            unitId: 'unit-kg',
            unitCode: 'kg',
          ),
        ],
      );
      final line = CartDraft.decode(CartDraft.encode(cart))!.lines.single;
      expect(line.isLoose, isTrue);
      expect(line.item.name, 'Pyaz');
      expect(line.sellingUnitCode, 'kg');
      final draft = line.toDraft();
      expect(draft.itemId, isNull);
      expect(draft.unitId, 'unit-kg');
      expect(draft.tracksStock, isFalse);
      expect(draft.rate.amountFor(draft.qty), const Money.rupees(300));
    });

    test('the unit the line is sold in survives too', () {
      // A restored bill that quietly reverted two maunds of atta to two kilos
      // would be a bill for a fortieth of the goods.
      final cart = Cart(
        lines: [
          CartLine(
            item: oil(),
            qty: Qty.units(2),
            rate: const Rate.rupees(30000),
            unitId: 'unit-maund',
            unitCode: 'maund',
          ),
        ],
      );
      final restored = CartDraft.decode(CartDraft.encode(cart))!;
      expect(restored.lines.single.sellingUnitCode, 'maund');
      expect(restored.lines.single.sellingUnitId, 'unit-maund');
      expect(restored.lines.single.isConverted, isTrue);
    });

    test('the entered rate survives a price change made in between', () {
      // The item is snapshotted, not looked up. A bill half-rung at
      // yesterday's price stays at yesterday's price, and a restore cannot
      // fail because the item was renamed or archived while the app was dead.
      final cart = Cart(
        lines: [
          CartLine(item: oil(), qty: Qty.one, rate: const Rate.rupees(2400)),
        ],
      );
      final restored = CartDraft.decode(CartDraft.encode(cart))!;
      expect(
        restored.lines.single.rate.inMilliPaisa,
        const Rate.rupees(2400).inMilliPaisa,
      );
    });
  });

  testWidgets('a killed app comes back with the bill still on the counter', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await app.seedItem(name: 'Chawal Basmati', rupees: 525);

    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    await _addToCart(tester, 'Cooking Oil');
    await _addToCart(tester, 'Cooking Oil');
    await _addToCart(tester, 'Chawal');

    expect(find.text('Rs 5,525.00'), findsWidgets);

    // The draft is on disk before anything is killed, because it is written on
    // every mutation rather than on a lifecycle callback. Android gives no
    // notification at all before a force-stop, so save-on-pause is a
    // nice-to-have and never the mechanism.
    await tester.pump(const Duration(milliseconds: 50));
    final saved = await app.services.drafts.read(cartDraftSlot);
    expect(saved, isNotNull, reason: 'nothing was written down');

    final restored = CartDraft.decode(saved!)!;
    expect(restored.lines, hasLength(2));
    expect(restored.subtotal, const Money.rupees(5525));
    expect(
      restored.lines.firstWhere((l) => l.item.name.startsWith('Cooking')).qty,
      Qty.units(2),
      reason: 'the rescan was a second tin, and it has to still be two',
    );
  });

  testWidgets('posting the sale takes the draft with it', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);

    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    await _addToCart(tester, 'Cooking Oil');
    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '3000');
    await tapButton(tester, 'Save karein');
    await tester.pump(const Duration(milliseconds: 50));

    expect(await app.countIn('documents'), 1, reason: 'the sale posted');
    expect(
      await app.services.drafts.read(cartDraftSlot),
      isNull,
      reason: 'a draft outliving its own sale is a bill rung twice',
    );
  });
}

Future<void> _addToCart(WidgetTester tester, String query) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    query,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
}
