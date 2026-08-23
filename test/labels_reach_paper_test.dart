import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Shelf labels, from the item a shopkeeper is looking at.
///
/// The renderer has fourteen tests of its own that check the symbol is
/// structurally readable. These check the thing those cannot: that a
/// shopkeeper standing in front of an item can get stickers out of the
/// printer, and that an item with no code says so instead of printing blanks.
///
/// A blank sticker is worse than no sticker. It looks like it worked, it goes
/// on a shelf, and it fails at the counter.
void main() {
  testWidgets('a shopkeeper prints stickers for an item', (tester) async {
    final printer = _RecordingPrinter();
    final app = await Harness.startWithShop(tester, transports: [printer]);
    await _usePrinter(app);
    await _stock(app, name: 'Chawal Basmati', barcode: '8964000999999');

    await tester.pumpAndSettle();
    await tapText(tester, 'Maal');
    await tapText(tester, 'Chawal Basmati');
    await tester.tap(find.byTooltip('Sticker chhapein').first);
    await tester.pumpAndSettle();

    // Five stickers.
    await tapText(tester, '5');
    await tapButton(tester, 'Sticker chhapein');
    await tester.pumpAndSettle();

    expect(
      printer.jobs,
      hasLength(1),
      reason:
          'the label sheet never reached the printer, so the barcode '
          'workflow stops at whatever a manufacturer already printed',
    );

    final bytes = printer.jobs.single;
    expect(
      _countRasters(bytes),
      5,
      reason:
          'a shopkeeper asked for five stickers and got '
          '${_countRasters(bytes)}',
    );
    expect(
      _text(bytes),
      contains('8964000999999'),
      reason:
          'the code is not printed under the bars, so a sticker whose '
          'symbol will not scan leaves the cashier nothing to type',
    );
  });

  testWidgets('an item with no code says so rather than printing blanks', (
    tester,
  ) async {
    final printer = _RecordingPrinter();
    final app = await Harness.startWithShop(tester, transports: [printer]);
    await _usePrinter(app);
    await _stock(app, name: 'Loose Cheeni', barcode: null);

    await tester.pumpAndSettle();
    await tapText(tester, 'Maal');
    await tapText(tester, 'Loose Cheeni');
    await tester.tap(find.byTooltip('Sticker chhapein').first);
    await tester.pumpAndSettle();

    expect(
      find.text('Is cheez ka koi code nahi. Pehle barcode ya code likhein.'),
      findsOneWidget,
    );
    expect(
      printer.jobs,
      isEmpty,
      reason:
          'blank stickers went to the printer. They look like they '
          'worked, they go on shelves, and they fail at the counter.',
    );
  });

  testWidgets('with no printer set up, nothing is printed and it says why', (
    tester,
  ) async {
    final printer = _RecordingPrinter();
    final app = await Harness.startWithShop(tester, transports: [printer]);
    // Deliberately no printer configured.
    await _stock(app, name: 'Chawal Basmati', barcode: '8964000999999');

    await tester.pumpAndSettle();
    await tapText(tester, 'Maal');
    await tapText(tester, 'Chawal Basmati');
    await tester.tap(find.byTooltip('Sticker chhapein').first);
    await tester.pumpAndSettle();

    await tapButton(tester, 'Sticker chhapein');
    await tester.pumpAndSettle();

    expect(find.text('Pehle printer set karein.'), findsOneWidget);
    expect(printer.jobs, isEmpty);
  });
}

Future<void> _usePrinter(Harness app) => app.services.printing.saveSettings(
  app.services.actorNow(),
  const PrinterSettings(
    transportKind: 'tcp',
    address: '192.168.1.50:9100',
    name: 'Counter printer',
  ),
);

Future<void> _stock(
  Harness app, {
  required String name,
  required String? barcode,
}) async {
  final firm = app.services.identity!.firmId;
  final actor = app.services.actorNow();
  final pcs = (await app.services.queries.units(
    firm,
  )).firstWhere((u) => u.code == 'pcs');

  await app.services.catalogue.addItem(
    actor,
    ItemDraft(
      name: name,
      barcode: barcode,
      baseUnitId: pcs.id,
      saleRate: Rate.rupees(525),
      openingStock: Qty.units(50),
    ),
  );
}

/// How many `GS v 0` rasters — one per sticker.
int _countRasters(List<int> bytes) {
  var found = 0;
  for (var i = 0; i + 2 < bytes.length; i++) {
    if (bytes[i] == 0x1D && bytes[i + 1] == 0x76 && bytes[i + 2] == 0x30) {
      found++;
    }
  }
  return found;
}

/// The characters a shopkeeper would read, with escape sequences skipped.
String _text(List<int> bytes) {
  final out = StringBuffer();
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    if (b == 0x1B) {
      i += (i + 1 < bytes.length && bytes[i + 1] == 0x40) ? 2 : 3;
      continue;
    }
    if (b == 0x1D && i + 7 < bytes.length && bytes[i + 1] == 0x76) {
      final bytesPerRow = bytes[i + 4] + bytes[i + 5] * 256;
      final rows = bytes[i + 6] + bytes[i + 7] * 256;
      i += 8 + bytesPerRow * rows;
      continue;
    }
    if (b == 0x1D) {
      i += 3;
      continue;
    }
    if (b == 0x0A || (b >= 32 && b < 127)) out.writeCharCode(b);
    i++;
  }
  return out.toString();
}

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
