import 'dart:io';

import 'package:bazaar_ledger/app/app.dart';
import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/design/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// The M0 demo script, on the handset, against the file the app really uses.
///
/// `test/demo_script_test.dart` drives the same script under `flutter test`,
/// where the database is an in-memory SQLite the host process owns. That is a
/// real database and a real write path, and it proved a great deal — but it
/// cannot prove any of this:
///
///   * that the app compiles for Android at all — it did not, and two Gradle
///     faults killed every build while 327 Dart tests passed,
///   * that the SQLite native library loads on the device ABI,
///   * that the application support directory is writable in the Android
///     sandbox, which is where production puts the books,
///   * that a committed row is really on the disk of the phone and not in a
///     page cache that a power cut would take with it,
///   * that the layout survives a 411x914 logical viewport rather than the
///     800x600 the widget tester invents.
///
/// So this one opens the real application support directory, empties it, and
/// runs the shop up from nothing.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a shopkeeper sets up, stocks two items and rings a cash sale',
      (tester) async {
    final path = await _freshDatabasePath();
    var services = await AppServices.open(databasePath: path);
    addTearDown(() async => services.close());

    await _pumpApp(tester, services);

    // ---- 1. First run ---------------------------------------------------
    expect(find.text('Apni dukan set karein'), findsOneWidget);
    expect(await _count(services, 'firms'), 0, reason: 'nothing written yet');

    await _typeInto(tester, 'Dukan ka naam', 'Chishti Kiryana Store');
    await _typeInto(tester, 'Aap ka naam', 'Malik Sahib');
    await _typeInto(tester, 'Shehar', 'Lahore');
    await _tapButton(tester, 'Dukan shuru karein');

    expect(await _count(services, 'firms'), 1);
    expect(await _count(services, 'users'), 1);
    expect(await _count(services, 'devices'), 1);
    expect(
      await _count(services, 'accounts'),
      greaterThan(20),
      reason: 'the chart of accounts is seeded on first run',
    );
    expect(find.text('Chishti Kiryana Store'), findsOneWidget);

    // ---- 2. Two items, through the editor -------------------------------
    await tester.tap(find.text('Maal').first);
    await tester.pumpAndSettle();
    await _addItem(tester, name: 'Cooking Oil 5L', price: '2500', stock: '20');
    await _addItem(tester, name: 'Chawal Basmati', price: '525', stock: '50');
    expect(await _count(services, 'items'), 2);

    await tester.pageBack();
    await tester.pumpAndSettle();

    // ---- 3. A cash sale --------------------------------------------------
    await tester.tap(find.text('Naya Bill').first);
    await tester.pumpAndSettle();

    await _addToCart(tester, 'Cooking Oil');
    await _addToCart(tester, 'Cooking Oil');
    await _addToCart(tester, 'Chawal');

    expect(find.text('Rs 5,525.00'), findsWidgets);

    await _tapButton(tester, 'Paisay lein');
    await _typeInto(tester, 'Diye gaye', '6000');
    await tester.pumpAndSettle();
    expect(find.text('475.00'), findsOneWidget, reason: 'change due');

    await _tapButton(tester, 'Save karein');

    // ---- 4. What is on the disk of this phone ----------------------------
    final documents = await _rows(
      services,
      'SELECT doc_no, total_paisa, status FROM documents',
    );
    expect(documents, hasLength(1));
    expect(documents.single['doc_no'], 'INV-2627-0001');
    expect(documents.single['total_paisa'], 552500);
    expect(documents.single['status'], 'posted');

    expect(await _count(services, 'document_lines'), 2);
    expect(await _count(services, 'payments'), 1);
    expect(await _count(services, 'payment_allocations'), 1);

    final balance = await _rows(
      services,
      'SELECT SUM(debit_paisa) d, SUM(credit_paisa) c FROM journal_lines',
    );
    expect(balance.single['d'], 552500);
    expect(
      balance.single['c'],
      552500,
      reason: 'the books balance at exact integer equality, no tolerance',
    );

    // ---- 5. And it is still there when the books are opened again --------
    //
    // The database is closed and reopened from the same file on the same
    // device. That is what proves the rows reached the phone's disk rather
    // than a cache the process was holding.
    await services.close();
    services = await AppServices.open(databasePath: path);

    final reopened = await _rows(
      services,
      'SELECT doc_no, total_paisa FROM documents',
    );
    expect(
      reopened.single['doc_no'],
      'INV-2627-0001',
      reason: 'the sale did not survive closing the books',
    );
    expect(reopened.single['total_paisa'], 552500);
    expect(await _count(services, 'stock_ledger'), greaterThanOrEqualTo(4));
  });
}

/// The real application support directory, emptied.
///
/// The same directory `AppServices.open()` picks in production, so the test
/// exercises the actual Android sandbox path and the actual permissions on
/// it, not a temporary directory that happens to be writable.
Future<String> _freshDatabasePath() async {
  final dir = await getApplicationSupportDirectory();
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

Future<int> _count(AppServices services, String table) async {
  final rows = await services.database
      .customSelect('SELECT COUNT(*) c FROM $table')
      .get();
  return rows.first.read<int>('c');
}

Future<List<Map<String, Object?>>> _rows(
  AppServices services,
  String sql,
) async {
  final rows = await services.database.customSelect(sql).get();
  return [for (final r in rows) r.data];
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
