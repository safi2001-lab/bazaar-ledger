import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Who to chase today.
///
/// The khata answers "what does Rashid owe". This answers the question a
/// shopkeeper actually opens the book for in the evening, which is "who do I
/// call", and the answer is not the biggest balance — it is the oldest one.
void main() {
  testWidgets('the collections view is reachable from the khata list', (
    tester,
  ) async {
    await Harness.startWithShop(tester);

    await tester.pumpAndSettle();
    await tapText(tester, 'Gahak');
    await tester.pumpAndSettle();

    expect(find.byTooltip('Udhaar wasooli'), findsOneWidget);
  });

  testWidgets('a shop that is owed nothing says so', (tester) async {
    await Harness.startWithShop(tester);
    await _openChase(tester);

    expect(find.text('Kisi ka udhaar baqi nahi'), findsOneWidget);
  });

  testWidgets('the oldest debt is listed first, not the largest', (
    tester,
  ) async {
    // A list sorted by amount puts Rs 40,000 from last week ahead of Rs 3,000
    // from March, every time. They are different conversations and the second
    // is the urgent one.
    final app = await Harness.startWithShop(tester);
    await _owed(app, name: 'Big Recent', rupees: 40000, onDate: '2026-08-18');
    await _owed(app, name: 'Small Old', rupees: 3000, onDate: '2026-03-01');

    await _openChase(tester);

    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where((d) => d == 'Big Recent' || d == 'Small Old')
        .toList();
    expect(names, ['Small Old', 'Big Recent']);
  });

  testWidgets('it shows the total and what is overdue separately', (
    tester,
  ) async {
    // Overdue deliberately excludes the current bucket. A kiryana shop's
    // cycle is a fortnight, and counting this week's udhaar as overdue makes
    // every shop look like it is in trouble every day.
    final app = await Harness.startWithShop(tester);
    await _owed(app, name: 'Recent', rupees: 9000, onDate: '2026-08-20');
    await _owed(app, name: 'Old', rupees: 1000, onDate: '2026-03-01');

    await _openChase(tester);

    expect(find.text('Kul udhaar'), findsOneWidget);
    expect(find.text('Der se baqi'), findsOneWidget);
    expect(find.text('Rs 10,000.00'), findsOneWidget);
    expect(find.text('1,000.00'), findsWidgets);
  });

  testWidgets('a bucket can be tapped to see only those customers', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await _owed(app, name: 'Recent', rupees: 9000, onDate: '2026-08-20');
    await _owed(app, name: 'Old', rupees: 1000, onDate: '2026-03-01');

    await _openChase(tester);
    await tapText(tester, '90+   1,000.00');
    await tester.pumpAndSettle();

    expect(find.text('Old'), findsOneWidget);
    expect(find.text('Recent'), findsNothing);
  });

  testWidgets('tapping a customer opens their khata', (tester) async {
    // The point of the list is what happens next: take money, or send the
    // reminder. Both live on the khata.
    final app = await Harness.startWithShop(tester);
    await _owed(
      app,
      name: 'Rashid Traders',
      rupees: 3000,
      onDate: '2026-03-01',
    );

    await _openChase(tester);
    await tapText(tester, 'Rashid Traders');
    await tester.pumpAndSettle();

    expect(find.text('Kitna lena hai'), findsOneWidget);
    expect(find.text('Paisay wasool karein'), findsWidgets);
  });
}

Future<void> _openChase(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Gahak');
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Udhaar wasooli'));
  await tester.pumpAndSettle();
}

/// A customer with one unpaid bill of [rupees], dated [onDate].
Future<void> _owed(
  Harness app, {
  required String name,
  required int rupees,
  required String onDate,
}) async {
  final firm = app.services.identity!.firmId;
  final actor = app.services.actorNow();
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');

  final partyId = await app.services.catalogue.addParty(
    actor,
    PartyDraft(name: name, partyType: 'customer'),
  );
  final itemId = await app.services.catalogue.addItem(
    actor,
    ItemDraft(
      name: 'Item $name',
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(rupees),
      openingStock: Qty.units(10),
    ),
  );

  final parts = onDate.split('-').map(int.parse).toList();
  await app.services.postSale(
    ActorContext(
      firmId: firm,
      userId: app.services.identity!.userId,
      deviceId: app.services.identity!.deviceId,
      startedAtUtc: DateTime.utc(parts[0], parts[1], parts[2], 9),
    ),
    SaleDraft(
      partyId: partyId,
      lines: [
        SaleLineDraft(
          itemId: itemId,
          itemName: 'Item $name',
          qty: Qty.units(1),
          baseQty: Qty.units(1),
          unitId: pcs.id,
          unitCode: 'pcs',
          rate: Rate.rupees(rupees),
        ),
      ],
      tenders: const [],
    ),
  );
}
