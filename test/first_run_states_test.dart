import 'package:bazaar_ledger/design/add_offer.dart';
import 'package:bazaar_ledger/design/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// What a shopkeeper sees before there is anything to see.
///
/// Every one of these is a state a real person hits on their first morning
/// with the app, and every one of them is a state that has crashed at least
/// once. An empty state rendered inside a list is not an edge case: it is the
/// only thing on the home screen until the first bill exists.
void main() {
  testWidgets('the home screen renders on a shop with no sales at all',
      (tester) async {
    await Harness.startWithShop(tester);

    // BlEmpty is a direct child of the home screen's ListView, which gives it
    // no height at all. An unconditional SingleChildScrollView there throws
    // "Vertical viewport was given unbounded height" and red-screens the very
    // first thing a new user ever sees.
    expect(tester.takeException(), isNull);
    expect(find.text('Rs 0.00'), findsWidgets, reason: 'the day starts at nil');
    // Below the tiles, which grew past one screen with Quotations and
    // Cheques; the list builds it only once it is scrolled to.
    await tester.scrollUntilVisible(
      find.byType(BlEmpty),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(BlEmpty), findsOneWidget);
    expect(find.text('Aaj abhi koi bill nahi bana'), findsOneWidget);
  });

  testWidgets('every empty state renders in the list it lives in',
      (tester) async {
    final app = await Harness.startWithShop(tester);

    for (final (label, empty) in const [
      ('Maal', 'Abhi koi maal nahi'),
      ('Gahak', 'Abhi koi gahak nahi'),
      ('Farokht', 'Abhi koi bill nahi bana'),
    ]) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$label crashed');
      expect(find.text(empty), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    // Nothing was written by looking at empty screens.
    expect(await app.countIn('documents'), 0);
    expect(await app.countIn('items'), 0);
  });

  testWidgets('the counter is usable with an empty catalogue', (tester) async {
    await Harness.startWithShop(tester);
    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Bill abhi khali hai'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Talash karein').first,
      'anything',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Kuch nahi mila'), findsOneWidget);
    // Since M32 the fix is made right here: what was typed becomes the item,
    // and it goes on the bill.
    expect(
      find.widgetWithText(BlAddOffer, "'anything' ko naya maal banayein"),
      findsOneWidget,
      reason: 'an empty state offers the action that fixes it',
    );
  });

  testWidgets('a validation error clears when the field is corrected',
      (tester) async {
    await Harness.start(tester);

    // Save with the owner's name empty, so the field is marked invalid.
    await typeInto(tester, 'Dukan ka naam', 'Chishti Kiryana Store');
    await tapButton(tester, 'Dukan shuru karein');
    expect(find.text('Yeh khana zaroori hai'), findsWidgets);

    // Now fill it in. Found by hand on an Android 16 handset: the field kept
    // its red border and its message while holding "Malik Sahib", because
    // errors only refresh on the next `validate()` call. For an audience
    // where 60% national and 52% rural literacy is the design constraint, an
    // error that will not go away is a dead end.
    await typeInto(tester, 'Aap ka naam', 'Malik Sahib');
    await tester.pumpAndSettle();

    expect(
      find.text('Yeh khana zaroori hai'),
      findsNothing,
      reason: 'the field is filled in and still says it is required',
    );
  });

  testWidgets('leaving a search screen clears the filter with the box',
      (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L', rupees: 2500);
    await app.seedItem(name: 'Chawal Basmati', rupees: 525);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Maal').first);
    await tester.pumpAndSettle();

    await typeInto(tester, 'Talash karein', 'Chawal');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cooking Oil'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maal').first);
    await tester.pumpAndSettle();

    // The query lived in a plain global provider while the search field's
    // controller lived on the State, so coming back gave an empty box over a
    // filtered list: the catalogue looked as though it had shrunk to one row,
    // with nothing on screen to explain why. On the counter it was worse —
    // the cart is only drawn when the query is empty, so a half-built bill
    // simply was not there.
    expect(
      find.textContaining('Cooking Oil'),
      findsOneWidget,
      reason: 'the filter outlived the screen and the search box did not',
    );
    expect(find.textContaining('Chawal'), findsOneWidget);
  });

  testWidgets('text at 200% does not clip a list row', (tester) async {
    final app = await Harness.startWithShop(tester);
    await app.seedItem(name: 'Cooking Oil 5L Extra Long Name', rupees: 2500);

    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpAndSettle();
    await tester.tap(find.text('Maal').first);
    await tester.pumpAndSettle();

    // The app clamps the scaler to 2.0, and the row extent scales with it.
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Cooking Oil'), findsOneWidget);
  });

  testWidgets('first run puts the bootstrap rows in the sync outbox',
      (tester) async {
    final app = await Harness.startWithShop(tester);

    // The firm, the owner and this device are written with raw SQL, because at
    // that instant there is no actor for the write path to demand. They still
    // have to reach the outbox by hand: a counter joining over LAN in M13 that
    // never receives them would sync rows whose foreign keys point at nothing.
    final outbox = await app.rowsOf(
      '''
      SELECT entity_table, op, seq FROM change_log
      WHERE entity_table IN ('firms', 'devices', 'users')
      ORDER BY seq
      ''',
    );
    expect(
      outbox.map((r) => r['entity_table']),
      ['firms', 'devices', 'users'],
    );
    expect(outbox.map((r) => r['op']), everyElement('insert'));
    expect(outbox.map((r) => r['seq']), [1, 2, 3]);

    // And the device's counter agrees, so the next write does not reuse a
    // sequence number.
    final seq = await app.scalar<int>(
      'SELECT change_seq FROM devices WHERE is_this_device = 1',
    );
    expect(
      seq,
      greaterThanOrEqualTo(3),
      reason: 'a reused seq silently drops a row from every peer',
    );

    // Sequence numbers are unique per device, always.
    final duplicates = await app.rowsOf(
      '''
      SELECT seq, COUNT(*) c FROM change_log
      GROUP BY origin_device_id, seq HAVING c > 1
      ''',
    );
    expect(duplicates, isEmpty);

    // Each row carries its own timestamp. Sharing one across the three left
    // three outbox entries byte-identical in `entity_hlc`, which is a tie no
    // merge rule can break.
    final stamps = await app.rowsOf(
      '''
      SELECT DISTINCT entity_hlc FROM change_log
      WHERE entity_table IN ('firms', 'devices', 'users')
      ''',
    );
    expect(stamps, hasLength(3));

    // And the payload a peer would replay is a complete row, not just the
    // business columns: every envelope column is NOT NULL, so a partial
    // payload is one the receiving counter cannot insert.
    final payload = await app.rowsOf(
      '''
      SELECT payload_json FROM change_log
      WHERE entity_table = 'firms'
      ''',
    );
    for (final column in const [
      'id',
      'firm_id',
      'created_at_utc',
      'updated_at_utc',
      'created_by',
      'updated_by',
      'origin_device_id',
      'hlc',
      'rev',
    ]) {
      expect(
        payload.single['payload_json'],
        contains('"$column"'),
        reason: 'a peer cannot build the row without $column',
      );
    }
  });
}
