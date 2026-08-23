import 'package:bazaar_ledger/features/printing/printer_setup_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Can a shopkeeper print a bill.
///
/// Not "does the byte encoder work" — that has thirty-three tests of its own,
/// and it always passed. The question here is the one the encoder's tests
/// could never answer: is any of it reachable from the app.
///
/// For two commits it was not. `PrintQueue`, `TcpPrinter`, `BluetoothPrinter`,
/// the ESC/POS encoder and both column layouts were written, tested, and
/// imported by exactly zero files under `lib/`. `pk_bootstrap` deliberately
/// withheld them, `AppServices` had no printer field, and the receipt screen
/// rendered a crossed-out printer under a string reading "Printing arrives in
/// M2." Both commits said the milestone had landed. Both described packages.
///
/// So this test drives the real widget tree by taps and typing, and asserts on
/// bytes that arrived at a transport. A test that reached into the services
/// and called `print()` directly would have passed for that whole period.
void main() {
  testWidgets('a shopkeeper sets up a printer and a bill reaches it', (
    tester,
  ) async {
    final printer = _RecordingPrinter();
    final app = await Harness.startWithShop(tester, transports: [printer]);

    // Nothing is configured, so the receipt screen must say so rather than
    // offering a button that fails at the counter.
    expect(
      await app.services.printing.settings(
        app.services.identity!.firmId,
        app.services.identity!.deviceId,
      ),
      isNull,
    );

    // Settings → Printer.
    await openSettings(tester);
    await tapText(tester, 'Printer');
    expect(find.byType(PrinterSetupScreen), findsOneWidget);

    // Choose the LAN printer and give it an address.
    await tapText(tester, 'Wi-Fi par (LAN)');
    await typeInto(tester, 'Printer ka pata', '192.168.1.50:9100');

    // The test print is the point of the screen: the shopkeeper looks at the
    // paper to find out whether the printer is 42 or 48 columns wide, because
    // ESC/POS cannot be asked.
    await tapButton(tester, 'Test print nikaalein');
    await tester.pumpAndSettle();

    expect(
      printer.jobs,
      hasLength(1),
      reason: 'the test print never reached a transport, so the one screen '
          'that can settle the column width does nothing',
    );

    // The ruler specifically, not "some line that happens to be 48 wide".
    //
    // The first version of this assertion was `lines.any((l) => l.length ==
    // 48)`, and it passed with the ruler deliberately shortened by three
    // characters — because the sample money rows are padded to exactly the
    // column width too. It asserted that the padding worked, which was never
    // in doubt.
    final ruler = _lines(printer.jobs.single).firstWhere(
      (l) => RegExp(r'^[.\d]{4,}$').hasMatch(l),
      orElse: () => '',
    );
    expect(
      ruler.length,
      48,
      reason: 'the ruler is ${ruler.length} characters, not 48. A shopkeeper '
          'holding it against their paper to decide between 42 and 48 columns '
          'is being shown the wrong answer, and every total on every receipt '
          'will wrap for as long as the setting stays wrong.',
    );

    // Save it.
    await tapButton(tester, 'Printer save karein');
    await tester.pumpAndSettle();

    final saved = await app.services.printing.settings(
      app.services.identity!.firmId,
      app.services.identity!.deviceId,
    );
    expect(saved, isNotNull, reason: 'the choice did not survive the screen');
    expect(saved!.transportKind, 'tcp');
    expect(saved.address, '192.168.1.50:9100');
    expect(saved.columns, 48);
  });

  testWidgets('the printer a shop chose is remembered by the database', (
    tester,
  ) async {
    // Not a file, and not memory. A shopkeeper is entitled to ask how many
    // times a bill was printed, and a count in a scratch file next to the till
    // is not evidence.
    final app = await Harness.startWithShop(
      tester,
      transports: [_RecordingPrinter()],
    );
    final identity = app.services.identity!;

    await app.services.printing.saveSettings(
      app.services.actorNow(),
      const PrinterSettings(
        transportKind: 'tcp',
        address: '192.168.1.50:9100',
        name: 'Counter printer',
        columns: 42,
      ),
    );

    final rows = await app.rowsOf('SELECT setting_key, firm_id FROM settings');
    expect(
      rows.map((r) => r['setting_key']),
      contains('printer.${identity.deviceId}'),
      reason: 'the settings table has been in the schema since v1 and this is '
          'the first thing ever to write to it. The key is namespaced per '
          'device because the counter and the back office have different '
          'printers.',
    );
  });

  testWidgets('a printer that cannot work here is offered, and says why', (
    tester,
  ) async {
    // Hiding an unavailable transport leaves a shopkeeper with a Bluetooth
    // printer wondering why the app has no Bluetooth. Offering it without the
    // note fails at the counter with a customer waiting.
    await Harness.startWithShop(tester, transports: [_UnavailablePrinter()]);

    await openSettings(tester);
    await tapText(tester, 'Printer');
    await tester.pumpAndSettle();

    expect(find.text('Bluetooth'), findsOneWidget);
    expect(find.text('Is phone par nahi chal sakta'), findsWidgets);
  });
}

/// The printed bytes, split into the lines a shopkeeper would see.
List<String> _lines(List<int> bytes) => String.fromCharCodes(
  bytes.where((b) => b >= 32 && b < 127 || b == 10),
).split('\n');

final class _RecordingPrinter implements PrinterTransport {
  final jobs = <List<int>>[];

  @override
  String get kind => 'tcp';

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<List<PrinterTarget>> discover({Duration? timeout}) async => const [];

  @override
  Future<void> send(PrinterTarget target, List<int> bytes) async {
    jobs.add(bytes);
  }
}

final class _UnavailablePrinter implements PrinterTransport {
  @override
  String get kind => 'bluetooth';

  @override
  Future<bool> get isAvailable async => false;

  @override
  Future<List<PrinterTarget>> discover({Duration? timeout}) async => const [];

  @override
  Future<void> send(PrinterTarget target, List<int> bytes) async =>
      throw StateError('not available');
}
