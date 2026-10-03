import 'package:bazaar_ledger/design/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Everything a shopkeeper can hide comes back from one screen (M60), and
/// says when it went and by whose hand.
void main() {
  testWidgets('a van put away from its page waits in Hidden and comes back', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.services.vans.addVan(app.services.actorNow(), name: 'Suzuki 1');
    await tester.pumpAndSettle();

    await tapText(tester, 'Gaariyan (van)');
    await tester.tap(find.text('Suzuki 1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Gaari hatayein'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Haan');
    await settleReal(tester, until: find.text('Gaari hata di gayi'));

    final firm = app.services.identity!.firmId;
    expect(await app.services.queries.vans(firm), isEmpty);
    expect(find.text('Suzuki 1'), findsNothing, reason: 'off the vans list');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _openHidden(tester);
    expect(find.text('Suzuki 1'), findsOneWidget);
    expect(find.textContaining('Malik Sahib ne hataya ·'), findsOneWidget);
    await tapButton(tester, 'Wapas layein');

    expect(await app.services.queries.vans(firm), hasLength(1));
    expect(find.text('Kuch hataya nahi gaya'), findsOneWidget);
  });

  testWidgets('a recipe put away from its page comes back from Hidden', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final masala = await app.seedItem(
      name: 'Chaat Masala 100g',
      rupees: 120,
      openingStock: 0,
    );
    final chilli = await app.seedItem(name: 'Lal Mirch 1kg', rupees: 600);
    final bomId = await app.services.manufacturing.saveBom(
      app.services.actorNow(),
      BomDraft(
        name: 'Chaat masala',
        outputItemId: masala,
        outputQty: Qty.units(10),
        lines: [BomLineDraft(itemId: chilli, qty: Qty.units(1))],
      ),
    );
    await tester.pumpAndSettle();

    await tapText(tester, 'Maal');
    await tester.tap(find.byTooltip('Banana (recipe)'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Chaat masala');
    await tester.tap(find.byTooltip('Recipe hatayein'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Haan');
    await settleReal(tester, until: find.text('Recipe hata di gayi'));

    final firm = app.services.identity!.firmId;
    expect(await app.services.queries.boms(firm), isEmpty);
    expect((await app.services.recycle.hiddenRecipes()).single.id, bomId);

    // The bin lists it, with what it makes, and brings it back.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await _openHidden(tester);
    expect(find.text('Chaat masala'), findsOneWidget);
    expect(find.text('Chaat Masala 100g'), findsOneWidget);
    await tapButton(tester, 'Wapas layein');
    expect((await app.services.queries.boms(firm)).single.id, bomId);
  });

  testWidgets('an expense head hidden says who hid it and when, and comes '
      'back', (tester) async {
    final app = await Harness.startWithShop(tester);
    final rent = (await app.services.shopMoney.expenseHeads()).firstWhere(
      (h) => h.systemKey == 'rent',
    );
    await app.services.shopMoney.setExpenseHeadHidden(rent.accountId, true);
    await tester.pumpAndSettle();

    await _openHidden(tester);
    expect(find.text('Kharche ki mad'.toUpperCase()), findsOneWidget);
    expect(find.text('Dukaan ka kiraya'), findsOneWidget);
    expect(find.textContaining('Malik Sahib ne hataya ·'), findsOneWidget);
    await tapButton(tester, 'Wapas layein');

    final heads = await app.services.shopMoney.expenseHeads();
    expect(heads.firstWhere((h) => h.systemKey == 'rent').hidden, isFalse);
  });

  testWidgets('with Data Lock on, putting a van away asks for the PIN on '
      'screen', (tester) async {
    final app = await Harness.startWithShop(tester);
    final services = app.services;
    await services.setPin(services.currentUser!.id, '1947');
    await services.audit.setDataLock(on: true);
    await services.vans.addVan(services.actorNow(), name: 'Suzuki 1');
    await tester.pumpAndSettle();

    await tapText(tester, 'Gaariyan (van)');
    await tester.tap(find.text('Suzuki 1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Gaari hatayein'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Haan');
    await _frames(tester);

    expect(find.text('Data Lock: PIN chahiye'), findsOneWidget);
    final firm = services.identity!.firmId;
    expect(await services.queries.vans(firm), hasLength(1));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'PIN').last,
      '1947',
    );
    await tester.pump();
    await tester.tap(
      find
          .ancestor(
            of: find.text('Ijazat dein'),
            matching: find.byType(BlButton),
          )
          .last,
    );
    await settleReal(tester, until: find.text('Gaari hata di gayi'));

    expect(await services.queries.vans(firm), isEmpty);
    final pin = await app.rowsOf(
      "SELECT summary FROM audit_log WHERE action_code = 'DATA_LOCK_PIN_GIVEN'",
    );
    expect(pin.single['summary'], contains('Van Suzuki 1 put away'));
  });
}

Future<void> _openHidden(WidgetTester tester) async {
  await openSettings(tester);
  await tester.scrollUntilVisible(find.text('Hatayi hui cheezein'), 200);
  await tapText(tester, 'Hatayi hui cheezein');
}

/// Lets a few frames through; a prompt over a turning button never
/// settles.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
