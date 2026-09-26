import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// The price a customer pays, at the counter.
///
/// Items have carried a wholesale price since M1, and parties a standing
/// discount, and the counter used neither: every buyer was charged the shelf
/// price unless the cashier retyped each line. The customer is picked last,
/// at the payment sheet, so the lines follow them there.
void main() {
  testWidgets('a wholesale customer is charged the wholesale price', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _oil(app);
    await _party(app, tier: PriceTier.wholesale);

    await _ringUpOil(tester);
    await _pick(tester, 'Rashid Traders');
    await _onUdhaar(tester);

    expect(await _billTotal(app), 230000);
  });

  testWidgets('a standing discount comes off every line', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _oil(app);
    await _party(app, discountBp: 500);

    await _ringUpOil(tester);
    await _pick(tester, 'Rashid Traders');
    await _onUdhaar(tester);

    expect(await _billTotal(app), 237500, reason: '2,500 less 5%');
  });

  testWidgets('a walk-in after a wholesale customer pays retail again', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _oil(app);
    await _party(app, tier: PriceTier.wholesale);

    await _ringUpOil(tester);
    await _pick(tester, 'Rashid Traders');
    await tester.tap(find.byTooltip('Band karein').last);
    await tester.pumpAndSettle();
    await typeInto(tester, 'Diye gaye', '2500');
    await tapButton(tester, 'Save karein');

    expect(await _billTotal(app), 250000);
  });

  testWidgets('a retail customer is charged the shelf price', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _oil(app);
    await _party(app);

    await _ringUpOil(tester);
    await _pick(tester, 'Rashid Traders');
    await _onUdhaar(tester);

    expect(await _billTotal(app), 250000);
  });

  testWidgets('a customer is set to wholesale from the editor', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _party(app);

    await tapText(tester, 'Gahak');
    await tapText(tester, 'Rashid Traders');
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await tapText(tester, 'Thok (wholesale)');
    await typeInto(tester, 'Har cheez par discount % (marzi se)', '2.5');
    await typeInto(tester, 'Pata', 'Shop 14, Shah Alam Market');
    await tapButton(tester, 'Save');

    final row = await app.rowsOf(
      'SELECT price_tier, default_discount_bp, address_line1 FROM parties',
    );
    expect(row.single['price_tier'], 'wholesale');
    expect(row.single['default_discount_bp'], 250);
    expect(row.single['address_line1'], 'Shop 14, Shah Alam Market');
  });

  testWidgets('editing a supplier keeps them a supplier', (tester) async {
    // The editor sent only what it showed and the writer stored the whole
    // row, so correcting a mill's phone number made it a customer and wiped
    // its NTN.
    final app = await Harness.startWithShop(tester);
    await app.services.catalogue.addParty(
      app.services.actorNow(),
      const PartyDraft(
        name: 'Faisal Flour Mills',
        partyType: 'supplier',
        ntn: '1234567-8',
      ),
    );

    await tapText(tester, 'Gahak');
    await tapText(tester, 'Faisal Flour Mills');
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();
    await typeInto(tester, 'Phone', '0300 1234567');
    await tapButton(tester, 'Save');

    final row = await app.rowsOf('SELECT party_type, ntn, phone FROM parties');
    expect(row.single['party_type'], 'supplier');
    expect(row.single['ntn'], '1234567-8');
    expect(row.single['phone'], '0300 1234567');
  });
}

Future<void> _oil(Harness app) async {
  final firm = app.services.identity!.firmId;
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');
  await app.services.catalogue.addItem(
    app.services.actorNow(),
    ItemDraft(
      name: 'Cooking Oil 5L',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(2500),
      wholesaleRate: Rate.rupees(2300),
      openingStock: Qty.units(50),
    ),
  );
}

Future<String> _party(
  Harness app, {
  PriceTier tier = PriceTier.retail,
  int discountBp = 0,
}) => app.services.catalogue.addParty(
  app.services.actorNow(),
  PartyDraft(
    name: 'Rashid Traders',
    priceTier: tier,
    defaultDiscountBp: discountBp,
  ),
);

Future<void> _ringUpOil(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Naya Bill');
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    'Cooking',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
  await tapButton(tester, 'Paisay lein');
}

Future<void> _pick(WidgetTester tester, String name) async {
  await tapText(tester, 'Aam gahak');
  await tapText(tester, name);
}

Future<void> _onUdhaar(WidgetTester tester) async {
  await tester.tap(find.byType(SwitchListTile).first);
  await tester.pumpAndSettle();
  await tapButton(tester, 'Save karein');
}

Future<int?> _billTotal(Harness app) => app.scalar<int>(
  "SELECT total_paisa FROM documents WHERE doc_type = 'sale_invoice'",
);
