import 'package:bazaar_ledger/design/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/real_font.dart';

/// Customers in groups by area, route or kind, and a note about each that
/// the counter sees (M40).
///
/// A wholesaler keeps his khata by route: Route 3 on Tuesday, the hotels on
/// the canal road, the retailers in Mohalla Gulberg. Vyapar files parties
/// in groups and reports by them; the schema here had a column for it since
/// v1 that nothing wrote and nothing read. And the note a shop writes about
/// a customer — "Sirf cash, cheque bounce ho chuka" — was nowhere the
/// cashier would see it before giving credit.
///
/// Every test drives the real screens against a real database and reads the
/// rows back.
void main() {
  testWidgets('a group set on a customer filters the list with the right '
      'totals', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedParty(name: 'Bilal General Store', owedRupees: 5000);
    await app.seedParty(name: 'Ali Kiryana', owedRupees: 3000);
    await app.seedParty(name: 'Canal View Hotel', owedRupees: 9000);
    await tester.pumpAndSettle();
    await tapText(tester, 'Gahak');

    // Nobody is in a group yet, so there is nothing to narrow by.
    expect(find.text('Baghair group'), findsNothing);

    // Bilal's route typed on his details...
    await _openDetails(tester, 'Bilal General Store');
    await typeInto(tester, 'Group (marzi se)', 'Route 3');
    await tapButton(tester, 'Save karein');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // ...and Ali's picked from the routes the shop already has.
    await _openDetails(tester, 'Ali Kiryana');
    await tapText(tester, 'Route 3');
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Group (marzi se)'),
          )
          .controller!
          .text,
      'Route 3',
    );
    await tapButton(tester, 'Save karein');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(
      await app.rowsOf('SELECT name, party_group FROM parties ORDER BY name'),
      [
        {'name': 'Ali Kiryana', 'party_group': 'Route 3'},
        {'name': 'Bilal General Store', 'party_group': 'Route 3'},
        {'name': 'Canal View Hotel', 'party_group': null},
      ],
    );

    // Narrowed to the route: its two, with its totals at the top.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Route 3'));
    await tester.pumpAndSettle();
    expect(find.text('Bilal General Store'), findsOneWidget);
    expect(find.text('Ali Kiryana'), findsOneWidget);
    expect(find.text('Canal View Hotel'), findsNothing);
    expect(find.text('2 log'), findsOneWidget);
    expect(find.text('Lene hain'), findsOneWidget);
    expect(
      find.text('8,000.00'),
      findsOneWidget,
      reason: 'the route owes Rs 5,000 and Rs 3,000',
    );

    // And the straggler, under no group.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Baghair group'));
    await tester.pumpAndSettle();
    expect(find.text('Canal View Hotel'), findsOneWidget);
    expect(find.text('Bilal General Store'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Sab'));
    await tester.pumpAndSettle();
    expect(find.text('Canal View Hotel'), findsOneWidget);
    expect(find.text('Bilal General Store'), findsOneWidget);
  });

  testWidgets('the list is put in order of who owes most', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedParty(name: 'Aamir Chhota', owedRupees: 200);
    await app.seedParty(name: 'Bilal Bara', owedRupees: 90000);
    await app.seedParty(name: 'Chaudhry Darmiyana', owedRupees: 4000);
    await tester.pumpAndSettle();
    await tapText(tester, 'Gahak');

    await tester.tap(find.byTooltip('Tarteeb'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        CheckedPopupMenuItem<PartySort>,
        'Zyada udhaar pehle',
      ),
    );
    await tester.pumpAndSettle();

    double top(String name) => tester.getTopLeft(find.text(name)).dy;
    expect(top('Bilal Bara'), lessThan(top('Chaudhry Darmiyana')));
    expect(top('Chaudhry Darmiyana'), lessThan(top('Aamir Chhota')));
  });

  testWidgets('renaming a group moves every member in one go', (tester) async {
    final app = await Harness.startWithShop(tester);
    final route = [
      await _party(app, 'Bilal General Store', group: 'Route 3', owed: 5000),
      await _party(app, 'Ali Kiryana', group: 'Route 3', owed: 3000),
      await _party(app, 'Hamid Traders', group: 'Route 3'),
    ];
    final hotel = await _party(app, 'Canal View Hotel', group: 'Hotels');
    await tester.pumpAndSettle();
    await tapText(tester, 'Gahak');

    await tester.tap(find.byTooltip('Group'));
    await tester.pumpAndSettle();
    expect(find.text('Hotels'), findsOneWidget);
    await tapText(tester, 'Route 3');
    expect(find.text('3 log'), findsOneWidget);
    expect(find.text('Hamid Traders'), findsOneWidget);

    await tester.tap(find.byTooltip('Naam badlein'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Naya naam'),
      'Route 3 Gulberg',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save karein'));
    await tester.pumpAndSettle();

    // The page follows its members to the new name.
    expect(find.text('Route 3 Gulberg'), findsWidgets);
    expect(find.text('Hamid Traders'), findsOneWidget);

    for (final id in route) {
      expect(await _groupOf(app, id), 'Route 3 Gulberg');
    }
    expect(await _groupOf(app, hotel), 'Hotels');

    // Each member its own change for the other counters, all stamped by
    // the one transaction that moved them, and one line in the activity
    // log saying so.
    final moves = await app.rowsOf(
      'SELECT entity_id, at_utc FROM change_log '
      "WHERE entity_table = 'parties' AND op = 'update'",
    );
    expect(moves.map((m) => m['entity_id']).toSet(), route.toSet());
    expect(moves.map((m) => m['at_utc']).toSet(), hasLength(1));
    expect(
      await app.scalar<String>(
        'SELECT summary FROM audit_log '
        "WHERE action_code = 'PARTY_GROUP_RENAMED'",
      ),
      'Route 3 renamed to Route 3 Gulberg: 3 moved',
    );
  });

  testWidgets('a rename onto another group says so, and the two become one', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final a = await _party(app, 'Bilal General Store', group: 'Rt 3');
    final b = await _party(app, 'Ali Kiryana', group: 'Route 3');
    await tester.pumpAndSettle();
    await tapText(tester, 'Gahak');
    await tester.tap(find.byTooltip('Group'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Rt 3');

    await tester.tap(find.byTooltip('Naam badlein'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Naya naam'),
      'route 3',
    );
    await tester.pumpAndSettle();
    expect(
      find.text("'Route 3' pehle se hai — dono group ek ho jayenge"),
      findsOneWidget,
    );
    await tester.tap(find.text('Save karein'));
    await tester.pumpAndSettle();

    expect(await _groupOf(app, a), 'Route 3', reason: "the shop's spelling");
    expect(await _groupOf(app, b), 'Route 3');
    expect(find.text('2 log'), findsOneWidget);
  });

  testWidgets('a group is merged into another from its page', (tester) async {
    final app = await Harness.startWithShop(tester);
    final a = await _party(app, 'Bilal General Store', group: 'Rt 3');
    final b = await _party(app, 'Ali Kiryana', group: 'Rt 3');
    final c = await _party(app, 'Hamid Traders', group: 'Route 3');
    await tester.pumpAndSettle();
    await tapText(tester, 'Gahak');
    await tester.tap(find.byTooltip('Group'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Rt 3');

    await tester.tap(find.byTooltip('Doosre group mein milayein'));
    await tester.pumpAndSettle();
    expect(find.text('Kis group mein milana hai?'), findsOneWidget);
    await tester.tap(find.text('Route 3').last);
    await tester.pumpAndSettle();
    expect(
      find.text(
        "'Rt 3' ke sab log 'Route 3' mein chale jayenge, aur 'Rt 3' khatam "
        'ho jayega.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Haan'));
    await tester.pumpAndSettle();

    for (final id in [a, b, c]) {
      expect(await _groupOf(app, id), 'Route 3');
    }
    expect(find.text('3 log'), findsOneWidget);
    expect(
      await app.scalar<String>(
        'SELECT summary FROM audit_log '
        "WHERE action_code = 'PARTY_GROUPS_MERGED'",
      ),
      'Rt 3 merged into Route 3: 2 moved',
    );
  });

  testWidgets('several customers are picked and given a group at once', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    final bilal = await app.seedParty(name: 'Bilal General Store');
    final hotel = await app.seedParty(name: 'Canal View Hotel');
    final ali = await app.seedParty(name: 'Ali Kiryana');
    await tester.pumpAndSettle();
    await tapText(tester, 'Gahak');

    await tester.tap(find.byTooltip('Kai gahak chunein'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Canal View Hotel'));
    await tester.pumpAndSettle();
    // A long press is the other way in, and ticks as it goes; here it is
    // already picking, so a tap ticks.
    await tester.tap(find.text('Bilal General Store'));
    await tester.pumpAndSettle();
    expect(find.text('2 chune'), findsOneWidget);

    await tester.tap(find.byTooltip('Group lagayein'));
    await tester.pumpAndSettle();
    expect(find.text('2 gahak ka group'), findsOneWidget);
    await typeInto(tester, 'Group (marzi se)', 'Hotels');
    await tapButton(tester, 'Group lagayein');

    expect(await _groupOf(app, hotel), 'Hotels');
    expect(await _groupOf(app, bilal), 'Hotels');
    expect(await _groupOf(app, ali), isNull, reason: 'not picked');

    // Back to the list, which now narrows by the new group.
    expect(find.byTooltip('Kai gahak chunein'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Hotels'));
    await tester.pumpAndSettle();
    expect(find.text('Ali Kiryana'), findsNothing);
    expect(find.text('2 log'), findsOneWidget);
  });

  testWidgets('the counter shows the remarks', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await app.seedParty(name: 'Rashid Traders', owedRupees: 1200);
    await app.seedParty(name: 'Ali Kiryana');
    await tester.pumpAndSettle();

    // Written on Rashid's details by whoever keeps the khata.
    await tapText(tester, 'Gahak');
    await _openDetails(tester, 'Rashid Traders');
    await typeInto(
      tester,
      'Counter ke liye note',
      'Sirf cash — cheque bounce ho chuka',
    );
    await tapButton(tester, 'Save karein');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(
      await app.scalar<String>(
        'SELECT setting_value FROM settings '
        "WHERE setting_key LIKE 'party.remarks.%'",
      ),
      'Sirf cash — cheque bounce ho chuka',
    );

    // At the counter, the cashier sees it the moment Rashid is chosen.
    await _ringUpAndPay(tester);
    expect(find.text('Sirf cash — cheque bounce ho chuka'), findsNothing);
    await _choose(tester, 'Rashid Traders');
    expect(find.text('Rashid Traders'), findsOneWidget);
    expect(
      find.text('Sirf cash — cheque bounce ho chuka'),
      findsOneWidget,
      reason: 'the note is written for the person about to give credit',
    );
    // Read-only there: nothing on the sheet edits it.
    expect(
      find.widgetWithText(TextFormField, 'Counter ke liye note'),
      findsNothing,
    );

    // A customer without a note leaves the sheet as it was.
    await tester.tap(find.byTooltip('Band karein').last);
    await tester.pumpAndSettle();
    await _choose(tester, 'Ali Kiryana');
    expect(find.text('Ali Kiryana'), findsOneWidget);
    expect(find.text('Sirf cash — cheque bounce ho chuka'), findsNothing);
  });

  testWidgets('the picker at the counter narrows to a group and labels each '
      'name with it', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await _party(app, 'Bilal General Store', group: 'Route 3');
    await _party(app, 'Canal View Hotel', group: 'Hotels');
    await tester.pumpAndSettle();

    await _ringUpAndPay(tester);
    await tapText(tester, 'Aam gahak');
    // The route as a small label beside the name, and as a chip.
    expect(find.widgetWithText(ChoiceChip, 'Route 3'), findsOneWidget);
    expect(find.text('Route 3'), findsNWidgets(2));
    expect(find.text('Canal View Hotel'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Route 3'));
    await tester.pumpAndSettle();
    expect(find.text('Bilal General Store'), findsOneWidget);
    expect(find.text('Canal View Hotel'), findsNothing);

    // A new retailer met on the route is filed on it.
    await _typeOnTop(tester, 'Talash karein', 'Naya Retailer');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tapText(tester, "'Naya Retailer' ko naya gahak banayein");
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Group (marzi se)').last,
          )
          .controller!
          .text,
      'Route 3',
    );
    await _tapOnTop(tester, 'Save karein');
    expect(find.text('Naya Retailer'), findsOneWidget);
    expect(
      await app.scalar<String>(
        "SELECT party_group FROM parties WHERE name = 'Naya Retailer'",
      ),
      'Route 3',
    );
  });

  group('at 200% on a small phone', () {
    setUpAll(loadRealFont);

    testWidgets('the customers list, its groups and picking fit', (
      tester,
    ) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      await _party(
        app,
        'Chaudhry Muhammad Aslam Traders',
        group: 'Mohalla Gulberg Block C',
        owed: 125000,
        phone: '0300 4471203',
      );
      await _party(app, 'Bilal General Store', group: 'Route 3', owed: 900);
      await tester.pumpAndSettle();
      await tapText(tester, 'Gahak');
      _expectNothingPaintsOffScreen(tester);

      await tester.tap(
        find.widgetWithText(ChoiceChip, 'Mohalla Gulberg Block C'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Lene hain'), findsOneWidget);
      _expectNothingPaintsOffScreen(tester);

      await tester.tap(find.byTooltip('Kai gahak chunein'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chaudhry Muhammad Aslam Traders'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
      await tester.tap(find.byTooltip('Group lagayein'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
    });

    testWidgets('the customer form with its group and note fits', (
      tester,
    ) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      await _party(app, 'Bilal', group: 'Mohalla Gulberg Block C');
      await _party(app, 'Ali', group: 'Hotels on the Canal Road');
      await tester.pumpAndSettle();
      await tapText(tester, 'Gahak');
      await tester.tap(find.text('Naya gahak').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(TextFormField, 'Counter ke liye note'),
      );
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
    });

    testWidgets('the groups page and a group fit', (tester) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      await _party(
        app,
        'Chaudhry Muhammad Aslam Traders',
        group: 'Mohalla Gulberg Block C',
        owed: 1250000,
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Gahak');
      await tester.tap(find.byTooltip('Group'));
      await tester.pumpAndSettle();
      _expectNothingPaintsOffScreen(tester);
      await tapText(tester, 'Mohalla Gulberg Block C');
      _expectNothingPaintsOffScreen(tester);
    });

    testWidgets('the payment sheet with a long note fits', (tester) async {
      _useASmallPhone(tester);
      final app = await Harness.startWithShop(tester);
      await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
      await _party(
        app,
        'Chaudhry Muhammad Aslam Traders',
        group: 'Mohalla Gulberg Block C',
        remarks:
            'Sirf cash — cheque bounce ho chuka. Delivery sirf shaam '
            'paanch baje ke baad, aur bill par munshi ke dastakhat.',
      );
      await tester.pumpAndSettle();

      await _ringUpAndPay(tester);
      await tapText(tester, 'Aam gahak');
      _expectNothingPaintsOffScreen(tester);
      await tapText(tester, 'Chaudhry Muhammad Aslam Traders');
      expect(find.textContaining('Sirf cash'), findsOneWidget);
      _expectNothingPaintsOffScreen(tester);
    });
  });
}

// ---------------------------------------------------------------------------

/// A party with a group and a note, written through the catalogue as the
/// forms write them.
Future<String> _party(
  Harness app,
  String name, {
  String? group,
  int owed = 0,
  String? remarks,
  String? phone,
}) => app.services.catalogue.addParty(
  app.services.actorNow(),
  PartyDraft(
    name: name,
    phone: phone,
    group: group,
    remarks: remarks,
    openingBalance: Money.rupees(owed),
  ),
);

Future<String?> _groupOf(Harness app, String partyId) async {
  final rows = await app.rowsOf(
    "SELECT party_group FROM parties WHERE id = '$partyId'",
  );
  return rows.single['party_group'] as String?;
}

/// From the customers list: a name opens its khata, and the khata's
/// details button opens the form.
Future<void> _openDetails(WidgetTester tester, String name) async {
  await tapText(tester, name);
  await tester.tap(find.byTooltip('Gahak ki tafseel'));
  await tester.pumpAndSettle();
}

/// Rings up a tin of oil and opens the payment sheet.
Future<void> _ringUpAndPay(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tapText(tester, 'Naya Bill');
  await tester.pumpAndSettle();
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

/// From the payment sheet: the customer picker, and [name] in it.
Future<void> _choose(WidgetTester tester, String name) async {
  await tester.tap(find.text('Aam gahak'));
  await tester.pumpAndSettle();
  await tapText(tester, name);
}

/// Types into a field on the topmost sheet: the counter's own search is
/// also "Talash karein", and a later route is later in the tree.
Future<void> _typeOnTop(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextFormField, label).last;
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

/// Taps the topmost button with [label]: the payment sheet's own Save is
/// still underneath.
Future<void> _tapOnTop(WidgetTester tester, String label) async {
  final button = find
      .ancestor(of: find.text(label), matching: find.byType(BlButton))
      .last;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// 360x800 dp — an Infinix Smart at its 720x1600 native resolution — with
/// the font at 200%, as `large_text_test.dart` lays the app out.
void _useASmallPhone(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(720, 1600)
    ..devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// Every rendered piece of text still inside the screen it was drawn on,
/// checked through the transform as `large_text_test.dart` does.
///
/// Except what sits in a sideways-scrolling row, which is off the edge by
/// design and a swipe away: the group chips, as the bill finder's filter
/// chips are.
void _expectNothingPaintsOffScreen(WidgetTester tester) {
  expect(tester.takeException(), isNull);
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  for (final element in find.byType(Text).evaluate()) {
    final inSidewaysRow =
        element
            .findAncestorWidgetOfExactType<SingleChildScrollView>()
            ?.scrollDirection ==
        Axis.horizontal;
    if (inSidewaysRow) continue;
    final box = element.renderObject! as RenderBox;
    if (!box.hasSize || box.size.isEmpty) continue;
    final left = box.localToGlobal(Offset.zero).dx;
    final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
    expect(
      right,
      lessThanOrEqualTo(width + 0.5),
      reason:
          '"${(element.widget as Text).data}" is painted from $left to '
          '$right on a $width dp screen',
    );
    expect(left, greaterThanOrEqualTo(-0.5), reason: 'painted off the left');
  }
}

