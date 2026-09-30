import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

final class _FakeFbr implements FbrGateway {
  int sent = 0;

  @override
  Future<FbrOutcome> post(String payloadJson) async {
    sent++;
    return const FbrPosted('7000007DI0000000009');
  }
}

void main() {
  testWidgets('a registered shop turns FBR on and a bill comes back numbered', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final fbr = _FakeFbr();
    app.services.fbr.gatewayFor = (_) => fbr;
    await app.services.updateFirm({
      'is_sales_tax_registered': 1,
      'ntn': '1234567-8',
    });
    final firm = app.services.identity!.firmId;
    final pcs = (await app.services.queries.units(
      firm,
    )).firstWhere((u) => u.code == 'pcs');
    await app.services.catalogue.addItem(
      app.services.actorNow(),
      ItemDraft(
        name: 'Ghee 1kg',
        baseUnitId: pcs.id,
        saleRate: Rate.rupees(1000),
        hsCode: '1517.1000',
        openingStock: Qty.units(20),
      ),
    );

    await openSettings(tester);
    await tapText(tester, 'Tax');
    await tapText(tester, 'FBR digital invoicing');
    await tapText(tester, 'Har bill FBR ko bhejein');
    await typeInto(tester, 'PRAL ka token', 'pral-token');
    await tapButton(tester, 'Save karein');
    expect(find.text('FBR ki setting save ho gayi'), findsOneWidget);
    expect((await app.services.fbr.settings()).enabled, isTrue);

    for (var i = 0; i < 3; i++) {
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await tapText(tester, 'Naya Bill');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Talash karein').first,
      'Ghee',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ghee 1kg').first);
    await tester.pumpAndSettle();
    await tapButton(tester, 'Paisay lein');
    await typeInto(tester, 'Diye gaye', '1180');
    await tapButton(tester, 'Save karein');

    expect(fbr.sent, 1);
    final status = await app.scalar<String>(
      "SELECT fbr_invoice_no FROM documents WHERE doc_type = 'sale_invoice'",
    );
    expect(status, '7000007DI0000000009');
    await tester.pumpWidget(const SizedBox());
  });
}
