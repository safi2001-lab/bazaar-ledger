import 'dart:io';

import 'package:bazaar_ledger/app/app.dart';
import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/design/components.dart';
import 'package:bazaar_ledger/features/pos/cart_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// A bill half-rung, on the handset, across a real reopen.
///
/// The widget test proves the cart is encoded and decoded correctly and that
/// the notifier writes on every mutation. It cannot prove the part that
/// matters on a phone: that the bytes are really in the app's own sandbox
/// directory, that the atomic rename works on the device filesystem, and that
/// a completely fresh `AppServices` — the same call `main()` makes on a cold
/// start — finds them and hands the counter back its bill.
///
/// The process cannot kill itself and keep asserting, so this stops one step
/// short of that: it tears the whole service graph down, reads the file off
/// the device by path, and builds the app again from nothing. What a
/// force-stop adds beyond this is the OS discarding memory, and every byte
/// being asserted here is already on disk before the teardown.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a bill left on the counter is there after a cold start',
      (tester) async {
    final path = await _freshDatabasePath();
    final directory = Directory(_dirOf(path));

    var services = await AppServices.open(databasePath: path);
    await services.drafts.clear(cartDraftSlot);

    await _pumpApp(tester, services);

    // Set the shop up and stock it.
    await _typeInto(tester, 'Dukan ka naam', 'Chishti Kiryana Store');
    await _typeInto(tester, 'Aap ka naam', 'Malik Sahib');
    await _typeInto(tester, 'Shehar', 'Lahore');
    await _tapButton(tester, 'Dukan shuru karein');

    await tester.tap(find.text('Maal').first);
    await tester.pumpAndSettle();
    await _addItem(tester, name: 'Cooking Oil 5L', price: '2500', stock: '20');
    await _addItem(tester, name: 'Chawal Basmati', price: '525', stock: '50');
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Ring three lines and walk away. No tender, no save: this is the bill
    // sitting on the counter while the shopkeeper checks a price in WhatsApp.
    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();
    await _addToCart(tester, 'Cooking Oil');
    await _addToCart(tester, 'Cooking Oil');
    await _addToCart(tester, 'Chawal');
    expect(find.text('Rs 5,525.00'), findsWidgets);

    // The file is on the phone, in the app's own sandbox, before anything is
    // torn down — because it is written on every mutation, not on a lifecycle
    // callback. Android sends no notification at all before a force-stop.
    await tester.pump(const Duration(milliseconds: 200));
    final onDisk = File('${directory.path}${Platform.pathSeparator}'
        'draft_cart.json');
    expect(
      onDisk.existsSync(),
      isTrue,
      reason: 'nothing was written to ${onDisk.path}',
    );
    expect(
      onDisk.lengthSync(),
      greaterThan(50),
      reason: 'the draft is there but empty',
    );

    // Nothing was posted. A draft is not a document.
    final documents = await services.database
        .customSelect('SELECT COUNT(*) c FROM documents')
        .getSingle();
    expect(documents.read<int>('c'), 0);

    // ---- The app goes away and comes back --------------------------------
    await services.close();
    services = await AppServices.open(databasePath: path);

    final recovered = services.restoredCartDraft;
    expect(
      recovered,
      isNotNull,
      reason: 'a cold start did not find the draft on the device',
    );

    final cart = CartDraft.decode(recovered!);
    expect(cart, isNotNull, reason: 'the draft on the device did not parse');
    expect(cart!.lines, hasLength(2));
    expect(cart.subtotal, const Money.rupees(5525));

    // And the counter really shows it, rather than the draft merely existing.
    await _pumpApp(tester, services);
    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();

    expect(
      find.text('Rs 5,525.00'),
      findsWidgets,
      reason: 'the bill was on disk and the counter still came up empty',
    );
    expect(find.textContaining('Cooking Oil'), findsWidgets);

    addTearDown(() async => services.close());
  });
}

String _dirOf(String path) =>
    path.substring(0, path.lastIndexOf(Platform.pathSeparator));

Future<String> _freshDatabasePath() async {
  final dir = await AppServices.booksDirectory();
  final path = '${dir.path}${Platform.pathSeparator}bazaar_ledger.sqlite';
  for (final suffix in const ['', '-wal', '-shm', '-journal']) {
    final f = File('$path$suffix');
    if (f.existsSync()) f.deleteSync();
  }
  return path;
}

Future<void> _pumpApp(WidgetTester tester, AppServices services) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: const BazaarLedgerApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapButton(WidgetTester tester, String label) async {
  final button = find
      .ancestor(
        of: find.textContaining(label),
        matching: find.byType(BlButton),
      )
      .first;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> _typeInto(
  WidgetTester tester,
  String label,
  String text,
) async {
  final field = find.widgetWithText(TextFormField, label).first;
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

Future<void> _addItem(
  WidgetTester tester, {
  required String name,
  required String price,
  required String stock,
}) async {
  final fab = find.byType(FloatingActionButton);
  if (fab.evaluate().isNotEmpty) {
    await tester.tap(fab.first);
  } else {
    await tester.tap(find.widgetWithText(BlButton, 'Naya maal').first);
  }
  await tester.pumpAndSettle();

  await _typeInto(tester, 'Naam', name);
  await _typeInto(tester, 'Farokht ki qeemat', price);
  await _typeInto(tester, 'Mojooda stock', stock);
  await _tapButton(tester, 'Save karein');
}

Future<void> _addToCart(WidgetTester tester, String query) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Talash karein').first,
    query,
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.add_circle_outline).first);
  await tester.pumpAndSettle();
}
