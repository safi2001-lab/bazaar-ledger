import 'dart:io';

import 'package:bazaar_ledger/features/printing/text_rasteriser.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:pk_platform/virtual_printer.dart';

/// The Urdu shop name on paper, drawn by the app's own rasteriser in the
/// Naskh face it bundles, sent as the app sends it, and read back by the
/// virtual printer.
///
/// The test engine's default font draws every letter as a box, which would
/// pass any check for ink. So the bundled face is loaded, and joining is
/// measured: letters that join make fewer separate marks on the paper than
/// the same letters forced apart. Boxes, or a face with no Urdu in it, make
/// the same number either way.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const face = 'ProofNaskh';
  const rasteriser = UiTextRasteriser(fontFamily: face);
  const shopName = 'الفلاح سٹور';

  setUpAll(() async {
    final bytes = File(
      'assets/fonts/NotoNaskhArabic-Regular.ttf',
    ).readAsBytesSync();
    await (FontLoader(
      face,
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  /// Separate marks of ink, eight-connected.
  int marks(MonoBitmap b) {
    bool ink(int x, int y) =>
        b.bits[y * b.bytesPerRow + (x >> 3)] & (0x80 >> (x & 7)) != 0;
    final seen = <int>{};
    var count = 0;
    for (var y = 0; y < b.height; y++) {
      for (var x = 0; x < b.width; x++) {
        if (!ink(x, y) || seen.contains(y * b.width + x)) continue;
        count++;
        final stack = [(x, y)];
        seen.add(y * b.width + x);
        while (stack.isNotEmpty) {
          final (cx, cy) = stack.removeLast();
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              final nx = cx + dx;
              final ny = cy + dy;
              if (nx < 0 || ny < 0 || nx >= b.width || ny >= b.height) continue;
              if (!ink(nx, ny) || !seen.add(ny * b.width + nx)) continue;
              stack.add((nx, ny));
            }
          }
        }
      }
    }
    return count;
  }

  test(
    'an Urdu shop name prints as joined script, not as question marks',
    () async {
      final receipt = ReceiptData(
        shop: const ReceiptShop(name: shopName, city: 'Lahore'),
        docNo: 'INV-2627-0001',
        dateTimeLabel: '27-09-2026  2:15 PM',
        cashierName: 'Malik Sahib',
        lines: const [
          ReceiptLine(
            name: 'Chawal 5 kg',
            qtyDisplay: '1',
            unitCode: 'pcs',
            rate: Rate.rupees(2450),
            amount: Money.rupees(2450),
          ),
        ],
        subtotal: const Money.rupees(2450),
        total: const Money.rupees(2450),
        tenders: const [
          ReceiptTender(label: 'Cash', amount: Money.rupees(2450)),
        ],
        paid: const Money.rupees(2450),
        balance: Money.zero,
        change: Money.zero,
      );
      for (final paper in [ReceiptPaper.mm80, ReceiptPaper.mm58]) {
        const renderer = ThermalReceiptRenderer();
        // The app's own drawing step, not a copy of it.
        final drawn = await drawUnprintableLines(
          renderer,
          receipt,
          paper,
          rasteriser: rasteriser,
        );
        expect(drawn.keys, contains(shopName));

        final out = VirtualPrinter(
          dots: paper.dots,
        ).print(renderer.toThermalBytes(receipt, paper: paper, drawn: drawn));
        if (Platform.environment['PAPER_OUT'] case final dir?) {
          File('$dir/urdu_${paper.dots}.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync(out.toPng());
        }

        // Nothing was spelled that the printer cannot spell.
        expect(out.texts.where((t) => t.text.contains('?')), isEmpty);
        final name = out.rasters.first;
        expect(
          name.hasInk,
          isTrue,
          reason: 'the name printed as a blank strip',
        );
        expect(name.bitmap.width, paper.dots);
        // Centred, as the Latin name is: ink on both sides of the middle, and
        // the margins within a few dots of each other.
        var left = paper.dots;
        var right = 0;
        for (var row = 0; row < name.bitmap.height; row++) {
          for (var x = 0; x < paper.dots; x++) {
            if (!name.ink(x, row)) continue;
            if (x < left) left = x;
            if (x > right) right = x;
          }
        }
        expect(
          (left - (paper.dots - 1 - right)).abs(),
          lessThan(24),
          reason:
              'the name sits $left dots from the left, '
              '${paper.dots - 1 - right} from the right',
        );
        expect(out.cuts.single, greaterThan(out.lastInk));

        // Joined: forced apart with zero-width non-joiners, the same letters
        // make more separate marks.
        final apart = await rasteriser.rasterise(
          shopName.split('').join('\u200C'),
          widthDots: paper.dots,
          pointSize: 44,
          bold: true,
          centre: true,
        );
        expect(
          marks(name.bitmap),
          lessThan(marks(apart)),
          reason: 'the letters did not join: no shaping, or no Urdu face',
        );
      }
    },
  );
}
