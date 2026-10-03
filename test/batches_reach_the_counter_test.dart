import 'package:bazaar_ledger/design/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Batches, expiry and serial numbers, from the screen: the pharmacy and
/// the mobile shop.
void main() {
  testWidgets('a pack scanned past its date is stopped at the counter', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(
      name: 'Panadol strip',
      rupees: 40,
      barcode: '8960123456789',
    );

    await tapText(tester, 'Naya Bill');
    await tester.pumpAndSettle();
    await _scan(tester, '01089601234567891726083110OLD7');

    expect(
      find.text(
        'Batch OLD7 ki expiry 2026-08-31 guzar chuki hai. Yeh na bechein.',
      ),
      findsOneWidget,
    );
    expect(find.text('Panadol strip'), findsNothing);
  });

  testWidgets('a pack in date is scanned onto the bill by its GS1 code', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(
      name: 'Panadol strip',
      rupees: 40,
      barcode: '8960123456789',
    );

    await tapText(tester, 'Naya Bill');
    await tester.pumpAndSettle();
    await _scan(tester, '01089601234567891728123110NEW1');

    expect(find.text('Panadol strip'), findsOneWidget);
  });

  testWidgets('a phone is sold by its IMEI, and only once', (tester) async {
    final app = await Harness.startWithShop(tester);
    final services = app.services;
    final firm = (await services.queries.currentFirm())!;
    final pcs = (await services.queries.units(
      firm.id,
    )).firstWhere((u) => u.code == 'pcs');
    final phone = await services.catalogue.addItem(
      services.actorNow(),
      ItemDraft(
        name: 'Tecno Spark',
        baseUnitId: pcs.id,
        saleRate: Rate.rupees(30000),
        tracksSerial: true,
      ),
    );
    final supplier = await services.catalogue.addParty(
      services.actorNow(),
      const PartyDraft(name: 'Mobile Wholesale', partyType: 'supplier'),
    );
    await services.recordPurchase(
      services.actorNow(),
      PurchaseDraft(
        partyId: supplier,
        lines: [
          PurchaseLineDraft(
            itemId: phone,
            itemName: 'Tecno Spark',
            qty: Qty.units(1),
            baseQty: Qty.units(1),
            unitId: pcs.id,
            unitCode: 'pcs',
            rate: Rate.rupees(25000),
            serials: const ['356938035643809'],
          ),
        ],
      ),
    );

    await tapText(tester, 'Naya Bill');
    await tester.pumpAndSettle();
    await _scan(tester, '356938035643809');
    expect(find.text('Tecno Spark'), findsOneWidget);
    await _scan(tester, '356938035643809');
    expect(find.text('356938035643809 pehle se bill par hai'), findsOneWidget);

    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '30000');
    await tapButton(tester, 'Save karein');

    expect(
      await services.queries.serialOnHand(firm.id, '356938035643809'),
      isNull,
      reason: 'that phone has been sold',
    );
  });

  testWidgets('a delivery keeps the batch and expiry the pack says', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final services = app.services;
    final firm = (await services.queries.currentFirm())!;
    final pcs = (await services.queries.units(
      firm.id,
    )).firstWhere((u) => u.code == 'pcs');
    await services.catalogue.addItem(
      services.actorNow(),
      ItemDraft(
        name: 'Panadol strip',
        baseUnitId: pcs.id,
        saleRate: Rate.rupees(40),
        tracksBatch: true,
      ),
    );
    await services.catalogue.addParty(
      services.actorNow(),
      const PartyDraft(name: 'Medi Distributors', partyType: 'supplier'),
    );

    await tapText(tester, 'Kharidari');
    await tapText(tester, 'Nayi kharidari');
    await tapText(tester, 'Supplier chunein');
    await tapText(tester, 'Medi Distributors');
    await tapText(tester, 'Cheez shamil karein');
    await typeInto(tester, 'Talash karein', 'Panadol');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tapText(tester, 'Panadol strip');
    await typeInto(tester, 'Tadaad (pcs)', '100');
    await typeInto(tester, 'Kharid qeemat', '3000');
    // The pack's own code, scanned into the batch field.
    await typeInto(tester, 'Batch no.', '01089601234567891727063010B42');
    await tester.tap(
      find
          .ancestor(
            of: find.text('Cheez shamil karein'),
            matching: find.byType(BlButton),
          )
          .last,
    );
    await tester.pumpAndSettle();
    await tapText(tester, 'Kharidari save karein');

    final lots = await services.queries.lotsOnHand(firm.id);
    expect(lots.single.lotNo, 'B42');
    expect(lots.single.expiry, const BusinessDate('2027-06-30'));
    expect(lots.single.qty, Qty.units(100));
  });

  testWidgets('goods are moved to the godown from the item', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Chawal Basmati', rupees: 525, openingStock: 50);

    await tapText(tester, 'Maal');
    await tapText(tester, 'Chawal Basmati');
    await tester.tap(find.byTooltip('Maal kahan hai'));
    await tester.pumpAndSettle();
    await typeInto(tester, 'Tadaad (pcs)', '30');
    await tapButton(tester, 'Bhej dein');

    expect(find.text('Maal bhej diya'), findsOneWidget);
    expect(find.text('GODOWN'), findsWidgets);
    expect(find.text('20 pcs'), findsOneWidget);
    expect(find.text('30 pcs'), findsOneWidget);
  });
}

Future<void> _scan(WidgetTester tester, String code) async {
  final field = find.widgetWithText(TextFormField, 'Talash karein').first;
  await tester.enterText(field, code);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}
