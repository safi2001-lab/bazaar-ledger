import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// The evening count, and the log of who did what, from the screen.
void main() {
  testWidgets('a short drawer is closed, and the books then agree with it', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _cashSale(app, rupees: 2500);

    await tapText(tester, 'Din band');
    expect(find.text('Rs 2,500.00'), findsOneWidget);
    await typeInto(tester, 'Gin kar kitna nikla', '2400');
    expect(find.text('100.00 kam hai'), findsOneWidget);
    await typeInto(tester, 'Farq ki wajah (marzi se)', 'Khula nahi tha');
    await tapButton(tester, 'Din band karein');

    expect(find.text('Din band ho gaya'), findsOneWidget);
    final firm = await app.services.queries.currentFirm();
    expect(
      await app.services.queries.cashInDrawer(firm!.id),
      const Money.rupees(2400),
    );
    final close = await app.services.queries.lastDayClose(firm.id);
    expect(close!.summary, contains('short by 100.00: Khula nahi tha'));
  });

  testWidgets('the activity log says who did what', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _cashSale(app, rupees: 2500);

    await openSettings(tester);
    await tapText(tester, 'Kaun ne kya kiya');

    expect(find.textContaining('Malik'), findsWidgets);
    expect(find.textContaining('INV-'), findsWidgets);
  });
}

Future<void> _cashSale(Harness app, {required int rupees}) async {
  final oil = await app.seedItem(name: 'Cooking Oil 5L', rupees: rupees);
  final services = app.services;
  final firm = (await services.queries.currentFirm())!;
  final item = (await services.queries.itemById(firm.id, oil))!;
  final cash = (await services.queries.paymentAccounts(
    firm.id,
  )).firstWhere((a) => a.modeLabel == 'cash');
  await services.postSale(
    services.actorNow(),
    SaleDraft(
      lines: [
        SaleLineDraft(
          itemId: oil,
          itemName: item.name,
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitId: item.unitId,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
        ),
      ],
      tenders: [
        TenderDraft(
          paymentAccountId: cash.id,
          mode: 'cash',
          amount: Money.rupees(rupees),
        ),
      ],
    ),
  );
}
