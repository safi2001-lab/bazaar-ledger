import 'dart:typed_data';

import 'package:bazaar_ledger/features/printing/printing_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:pk_platform/virtual_printer.dart';

/// The test print, on the virtual printer: the ruler for the right width
/// fits on one line, and the ruler for the wrong one visibly wraps — which
/// is how a shopkeeper finds out which setting their machine needs.
void main() {
  PrinterSettings width(int columns) => PrinterSettings(
    transportKind: 'tcp',
    address: '192.168.1.50:9100',
    name: 'Counter printer',
    columns: columns,
  );

  test('the column count is read off a printed ruler, not assumed', () {
    for (final columns in [48, 42, 32]) {
      final out = VirtualPrinter(
        dots: columns * VirtualPrinter.cellWidth,
      ).print(Uint8List.fromList(testPrintBytes(width(columns))));
      expect(out.wrapped, isEmpty, reason: '$columns-column ruler wrapped');
      final ruler = out.texts.firstWhere(
        (t) => t.text.startsWith('.........1'),
      );
      expect(ruler.text.length, columns);
      expect(out.line('TOTAL').text.length, columns);
      expect(out.cuts.single, greaterThan(out.lastInk));
    }

    // A 48-column setting on a machine that holds 42 wraps its ruler, and
    // every money row with it: exactly what the test print is there to show.
    final wrong = VirtualPrinter(
      dots: 42 * VirtualPrinter.cellWidth,
    ).print(Uint8List.fromList(testPrintBytes(width(48))));
    expect(wrong.wrapped, isNotEmpty);
  });
}
