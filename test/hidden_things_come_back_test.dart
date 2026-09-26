import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Hiding an item or a customer, and bringing them back.
///
/// Nothing here is ever deleted, but until this hiding was one-way: an
/// archived item could only come back as a second item with none of the
/// first one's history, and a customer could not be hidden at all.
void main() {
  testWidgets('an archived item comes back to the counter', (tester) async {
    final app = await Harness.startWithShop(tester);
    final oilId = await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await app.services.catalogue.archiveItem(app.services.actorNow(), oilId);
    await tester.pumpAndSettle();

    await _openHidden(tester);
    expect(find.text('Cooking Oil 5L'), findsOneWidget);
    await tapButton(tester, 'Wapas layein');

    expect(find.text('Kuch hataya nahi gaya'), findsOneWidget);
    final firm = app.services.identity!.firmId;
    final found = await app.services.queries.searchItems(firm, query: 'oil');
    expect(found.single.id, oilId, reason: 'the counter still cannot sell it');
    expect(
      await app.scalar<int>(
        "SELECT COUNT(*) FROM audit_log WHERE action_code = 'ITEM_RESTORED'",
      ),
      1,
    );
  });

  testWidgets('a customer can be hidden from the khata and brought back', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedParty(name: 'Rashid Traders');

    await tapText(tester, 'Gahak');
    await tapText(tester, 'Rashid Traders');
    await tester.tap(find.byTooltip('Gahak ki tafseel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Khate se hatayein'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Haan');

    // Back on the list, and they are not on it.
    expect(find.text('Rashid Traders'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _openHidden(tester);
    await tapButton(tester, 'Wapas layein');

    final firm = app.services.identity!.firmId;
    expect(
      await app.services.queries.searchParties(firm, query: 'rashid'),
      hasLength(1),
    );
  });

  testWidgets('a customer who still owes cannot be hidden, and is told why', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedParty(name: 'Rashid Traders', owedRupees: 4500);

    await tapText(tester, 'Gahak');
    await tapText(tester, 'Rashid Traders');
    await tester.tap(find.byTooltip('Gahak ki tafseel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Khate se hatayein'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Haan');

    expect(find.textContaining('still owes 4,500.00'), findsOneWidget);
    final firm = app.services.identity!.firmId;
    expect(
      await app.services.queries.searchParties(firm, query: 'rashid'),
      hasLength(1),
    );
  });

  testWidgets('a supplier the shop still owes cannot be hidden', (
    tester,
  ) async {
    // The check used to look only at what the party owed the shop, so a mill
    // with an unpaid delivery could be hidden and the debt with it.
    final app = await Harness.startWithShop(tester);
    final actor = app.services.actorNow();
    final millId = await app.services.catalogue.addParty(
      actor,
      const PartyDraft(name: 'Punjab Rice Mills', partyType: 'supplier'),
    );
    await app.services.recordExpense(
      actor,
      ExpenseDraft(
        accountSystemKey: 'freight',
        amount: const Money.rupees(800),
        note: 'Rickshaw from the mill',
        partyId: millId,
      ),
    );

    await expectLater(
      app.services.catalogue.archiveParty(app.services.actorNow(), millId),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', contains('800')),
      ),
    );
  });
}

Future<void> _openHidden(WidgetTester tester) async {
  await openSettings(tester);
  await tester.scrollUntilVisible(find.text('Hatayi hui cheezein'), 200);
  await tapText(tester, 'Hatayi hui cheezein');
}
