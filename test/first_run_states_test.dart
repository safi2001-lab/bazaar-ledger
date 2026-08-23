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
    expect(find.byType(BlEmpty), findsOneWidget);
    expect(find.text('Aaj abhi koi bill nahi bana'), findsOneWidget);
    expect(find.text('Rs 0.00'), findsWidgets, reason: 'the day starts at nil');
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
    expect(
      find.widgetWithText(BlButton, 'Naya maal'),
      findsOneWidget,
      reason: 'an empty state offers the action that fixes it',
    );
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
  });
}
