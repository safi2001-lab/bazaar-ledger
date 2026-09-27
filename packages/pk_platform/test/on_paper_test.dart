import 'dart:io';
import 'dart:typed_data';

import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:pk_platform/virtual_printer.dart';
import 'package:test/test.dart';

import 'receipt_test.dart' show receipt;

/// Receipts and labels put on paper by the virtual printer: the byte stream
/// the app sends, read back the way a controller reads it.
///
/// Set PAPER_OUT to a directory to get each strip as a picture.
void main() {
  void keep(String name, PrintedPaper paper) {
    final dir = Platform.environment['PAPER_OUT'];
    if (dir == null) return;
    File('$dir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(paper.toPng());
  }

  group('on paper', () {
    for (final (paper, mm) in [
      (ReceiptPaper.mm80, 80),
      (ReceiptPaper.mm58, 58),
    ]) {
      test(
        'a bill printed on an ${mm}mm machine is readable and cut below the total',
        () {
          final bytes = const ThermalReceiptRenderer().toThermalBytes(
            receipt(),
            paper: paper,
          );
          final printer = VirtualPrinter(dots: paper.dots);
          final out = printer.print(bytes);
          keep('bill_${mm}mm', out);

          expect(out.initialised, isTrue, reason: 'ESC @ first');
          expect(out.font, 0, reason: 'Font A, which the layout counts in');
          expect(
            out.wrapped,
            isEmpty,
            reason: 'a wrapped line is a broken row',
          );
          for (final t in out.texts) {
            expect(
              t.text.length * t.widthMul,
              lessThanOrEqualTo(printer.columns),
              reason: '"${t.text}" is wider than the paper',
            );
          }
          final total = out.line('TOTAL');
          expect(total.text, endsWith('Rs 5,525.00'));
          expect(total.text.length, printer.columns, reason: 'flush right');
          expect(out.cuts, hasLength(1));
          expect(
            out.cuts.single,
            greaterThan(out.lastInk),
            reason: 'the blade must land below the last printed line',
          );
          expect(out.cuts.single, greaterThan(total.y + total.height));
        },
      );
    }

    test('a bare cut after the same feed would go through the bill', () {
      // Why the renderer sends GS V 66 and not GS V 0: the blade sits above
      // the head, and three lines of feed do not reach it.
      final bytes =
          (EscPos()
                ..initialise()
                ..line('TOTAL                    Rs 5,525.00')
                ..feed(3)
                ..partialCut())
              .bytes;
      final out = VirtualPrinter(dots: 576).print(bytes);
      expect(out.cuts.single, lessThan(out.lastInk));
    });

    for (final (spec, name) in [
      (const LabelSpec(), '80mm'),
      (const LabelSpec(dots: 384), '58mm'),
      (const LabelSpec(perRow: 2), '80mm two across'),
    ]) {
      test(
        'a Code128 label printed at the declared width scans back to its code ($name)',
        () {
          // Two across leaves 280 dots a label: room for short shop codes.
          for (final code
              in spec.perRow == 1
                  ? ['8964000123456', 'BL-00042', 'CHAWAL5KG', '7']
                  : ['7', '1234', 'CH5']) {
            final bytes = const LabelRenderer().toBytes(
              LabelData(
                name: 'Chawal 5 kg',
                code: code,
                priceLabel: 'Rs 2,450',
              ),
              spec: spec,
            );
            final out = VirtualPrinter(dots: spec.dots).print(bytes);
            keep('label_${name.replaceAll(' ', '_')}_$code', out);
            final symbol = out.rasters.single;
            expect(symbol.bitmap.width, spec.labelWidthDots);
            expect(symbol.bitmap.height, spec.symbolHeightDots);
            // Every sweep across the bars reads the same.
            for (final row in [
              0,
              symbol.bitmap.height ~/ 2,
              symbol.bitmap.height - 1,
            ]) {
              expect(readCode128(symbol, row: row), code, reason: 'row $row');
            }
            expect(out.cuts.single, greaterThan(out.lastInk));
          }
        },
      );
    }

    test('a code too long for its label is refused, not printed ragged', () {
      expect(
        () => const LabelRenderer().toBytes(
          const LabelData(name: 'x', code: '8964000123456'),
          spec: const LabelSpec(perRow: 2),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a label that does not decode is caught', () {
      final bitmap = const LabelRenderer().symbolFor(
        'BL-00042',
        const LabelSpec(),
      );
      final damaged = Uint8List.fromList(bitmap.bits);
      // Knock one bar out of the middle of every row.
      final mid = bitmap.bytesPerRow ~/ 2;
      for (var y = 0; y < bitmap.height; y++) {
        damaged[y * bitmap.bytesPerRow + mid] ^= 0xFF;
      }
      final out = VirtualPrinter(dots: 576).print(
        (EscPos()..raster(
              MonoBitmap(
                width: bitmap.width,
                height: bitmap.height,
                bits: damaged,
              ),
            ))
            .bytes,
      );
      expect(readCode128(out.rasters.single), isNull);
    });

    test('what a real printer would choke on is a fault here', () {
      final printer = VirtualPrinter(dots: 576);
      expect(
        () => printer.print(
          Uint8List.fromList([0x1D, 0x76, 0x30, 0, 72, 0, 10, 0, 1, 2]),
        ),
        throwsA(isA<PrinterFault>()),
        reason: 'a raster short of its header eats the rest of the job',
      );
      expect(
        () => printer.print(Uint8List.fromList([0xE2, 0x80, 0x94])),
        throwsA(isA<PrinterFault>()),
      );
      expect(
        () => printer.print(Uint8List.fromList([0x1B, 0x99])),
        throwsA(isA<PrinterFault>()),
      );
    });
  });
}
