import 'dart:io';

import 'package:bazaar_ledger/app/app.dart';
import 'package:bazaar_ledger/app/providers.dart';
import 'package:bazaar_ledger/design/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// A running app on a real, empty database.
///
/// Not a mock. The whole reason this codebase exists is that the previous
/// build's suite passed while the app wrote nothing at all — two of its test
/// files imported no project code whatsoever. Every test here drives the real
/// widget tree by taps and typing, against the real write path, and then reads
/// the rows back out of a real SQLite database. A test that cannot fail when
/// the feature is deleted is not a test.
final class Harness {
  Harness._(this.services);

  final AppServices services;

  /// Opens an app with no shop yet, so the wizard is the first screen.
  ///
  /// [overrides] stand in for the platform — a file picker, a restart — and
  /// never for the books.
  static Future<Harness> start(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    _stubPlatformChannels();
    final services = await openInMemoryServices();
    addTearDown(services.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(services),
          ...overrides,
        ],
        child: const BazaarLedgerApp(),
      ),
    );
    await tester.pumpAndSettle();
    return Harness._(services);
  }

  /// Opens an app whose shop already exists, for tests about everything else.
  static Future<Harness> startWithShop(
    WidgetTester tester, {
    String shopName = 'Chishti Kiryana Store',
    List<PrinterTransport>? transports,
    List<Override> overrides = const [],
  }) async {
    _stubPlatformChannels();
    final services = await openInMemoryServices(transports: transports);
    addTearDown(services.close);

    await services.setUpShop(
      shopName: shopName,
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      city: 'Lahore',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(services),
          ...overrides,
        ],
        child: const BazaarLedgerApp(),
      ),
    );
    await tester.pumpAndSettle();
    return Harness._(services);
  }

  /// Puts an item on the shelves without going through the editor, for tests
  /// whose subject is something else.
  Future<String> seedItem({
    required String name,
    required int rupees,
    int openingStock = 100,
    String? barcode,
    String unitCode = 'pcs',
  }) async {
    final firm = await services.queries.currentFirm();
    final units = await services.queries.units(firm!.id);
    final pieces = units.firstWhere(
      (u) => u.code == unitCode,
      orElse: () => units.first,
    );
    return services.catalogue.addItem(
      services.actorNow(),
      ItemDraft(
        name: name,
        baseUnitId: pieces.id,
        saleRate: Rate.rupees(rupees),
        barcode: barcode,
        openingStock: Qty.units(openingStock),
        openingRate: Rate.rupees((rupees * 0.6).round()),
      ),
    );
  }

  /// Puts a customer in the khata, optionally already owing something.
  ///
  /// The opening balance is what they owed before the shop started keeping
  /// books here, which is how every real khata begins.
  Future<String> seedParty({
    required String name,
    int owedRupees = 0,
    String? phone,
  }) =>
      services.catalogue.addParty(
        services.actorNow(),
        PartyDraft(
          name: name,
          phone: phone,
          openingBalance: Money.rupees(owedRupees),
        ),
      );

  /// How many rows a table holds right now.
  Future<int> countIn(String table) async {
    final rows =
        await services.database.customSelect('SELECT COUNT(*) c FROM $table').get();
    return rows.first.read<int>('c');
  }

  /// One scalar out of the database, for the assertions the demo script makes.
  Future<T?> scalar<T extends Object>(String sql) async {
    final rows = await services.database.customSelect(sql).get();
    if (rows.isEmpty) return null;
    return rows.first.data.values.first as T?;
  }

  Future<List<Map<String, Object?>>> rowsOf(String sql) async {
    final rows = await services.database.customSelect(sql).get();
    return [for (final r in rows) r.data];
  }
}

/// Lets work that needs a real clock and a real disk finish.
///
/// A widget test's clock is fake, so file IO and an isolate sealing a backup
/// never complete under `pump` alone; and a spinner is a continuous animation,
/// so `pumpAndSettle` never returns while one is showing. This alternates the
/// two until [until] appears or [done] says so, or gives up after [rounds].
Future<void> settleReal(
  WidgetTester tester, {
  Finder? until,
  bool Function()? done,
  int rounds = 200,
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (until != null && until.evaluate().isNotEmpty) break;
    if (done != null && done()) break;
  }
  await tester.pump();
}

/// Taps a button by its label, scrolling it into view first.
///
/// The default test viewport is 800x600 and several of these forms are longer
/// than that, so a plain `tap` lands on empty space and silently does nothing
/// — which looks exactly like a button that is wired up wrong.
Future<void> tapButton(WidgetTester tester, String label) async {
  // Matched on a substring, because several buttons carry a count alongside
  // the verb — "Paisay lein · 2 cheezein".
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

/// Taps anything carrying [text], scrolling it into view first.
///
/// For rows and cards rather than buttons — a settings row is a tappable card
/// with a label, not a BlButton.
Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Opens Settings from the home screen's app bar.
Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_outlined).first);
  await tester.pumpAndSettle();
}

/// Types into a field found by its label, scrolling it into view first.
Future<void> typeInto(
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

var _stubbed = false;

/// Answers the platform channels a widget test has no operating system for.
///
/// Only `path_provider`, and only so saving a language preference writes to a
/// temporary directory instead of throwing. Nothing about the books is stubbed.
void _stubPlatformChannels() {
  if (_stubbed) return;
  _stubbed = true;
  final temp = Directory.systemTemp.createTempSync('bazaar_ledger_test').path;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => temp,
  );
}
