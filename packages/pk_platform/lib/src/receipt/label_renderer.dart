import 'dart:typed_data';

import 'package:barcode/barcode.dart' as bc;
import 'package:pk_domain/pk_domain.dart';

import 'escpos.dart';

/// One shelf label: what the thing is, what it costs, and a code to scan.
///
/// Labels are what make a barcode workflow actually work. A shopkeeper who has
/// entered barcodes for three thousand items still cannot scan the loose rice,
/// the repacked masala or anything else that came out of a sack — those have
/// no manufacturer's code, and the only way they get one is if the shop prints
/// it. A product that sells barcode scanning and then charges extra to print
/// labels has sold half a feature.
final class LabelSpec {
  const LabelSpec({
    this.dots = 576,
    this.symbolHeightDots = 70,
    this.perRow = 1,
    this.showPrice = true,
  });

  /// The printable width in dots. 576 on 80 mm, 384 on 58 mm.
  final int dots;

  /// How tall the bars are.
  ///
  /// A scanner needs enough vertical run to find a clean sweep across the
  /// bars; too short and it reads on the bench and fails on a shelf at arm's
  /// length. 70 dots is about 9 mm at 203 dpi, which is the low end of what
  /// works reliably.
  final int symbolHeightDots;

  /// Labels across the paper. Two fit on 80 mm for small items.
  final int perRow;

  final bool showPrice;

  /// The full width one label may use, after the gutter between them.
  int get labelWidthDots =>
      perRow <= 1 ? dots : (dots - (perRow - 1) * _gutterDots) ~/ perRow;

  static const _gutterDots = 16;
}

/// What goes on one label.
final class LabelData {
  const LabelData({required this.name, required this.code, this.priceLabel});

  final String name;

  /// The digits under the bars. Also what a scanner will read back.
  final String code;

  /// Already formatted, already in the shopkeeper's language. This package
  /// does not know what a rupee is.
  final String? priceLabel;
}

/// Turns labels into ESC/POS.
///
/// The symbol is drawn as a bitmap and pushed through the same `GS v 0` raster
/// path the logo and the imported bank QR already use, rather than through a
/// printer's built-in barcode command (`GS k`). Two reasons, and the second is
/// the one that decides it:
///
///   * `GS k` support varies. Cheap printers accept the command, print
///     nothing, and report no error.
///   * A raster is the same bytes on every machine, so what a golden test
///     asserts is what a shopkeeper's printer receives. A built-in symbol is
///     rendered by firmware nobody can inspect.
final class LabelRenderer {
  const LabelRenderer();

  /// One sheet of `copies` identical labels.
  Uint8List toBytes(
    LabelData label, {
    int copies = 1,
    LabelSpec spec = const LabelSpec(),
  }) {
    if (copies < 1) {
      throw ArgumentError.value(copies, 'copies', 'must be at least one');
    }

    final out = EscPos()
      ..initialise()
      ..codePage(0)
      ..font(EscPosFont.a);

    for (var i = 0; i < copies; i++) {
      out
        ..align(EscPosAlign.centre)
        ..line(_fit(label.name, spec))
        ..raster(symbolFor(label.code, spec))
        ..line(label.code);
      if (spec.showPrice && label.priceLabel != null) {
        out
          ..bold()
          ..line(label.priceLabel!)
          ..bold(on: false);
      }
      out
        ..align(EscPosAlign.left)
        ..feed(2);
    }
    return out.cut().bytes;
  }

  /// The barcode itself, as dots.
  ///
  /// Code 128 rather than EAN-13. A shop printing its own labels has no
  /// GS1 prefix and no right to mint EAN-13 codes that belong to somebody
  /// else's product range — and Code 128 takes any length and any character,
  /// which is what an internal code actually looks like.
  MonoBitmap symbolFor(String code, LabelSpec spec) {
    if (code.trim().isEmpty) {
      throw ArgumentError.value(code, 'code', 'a label needs something to say');
    }

    final labelWidth = spec.labelWidthDots;
    final height = spec.symbolHeightDots;

    // Measured in a unit space first, so the module count can be recovered
    // before anything is committed to dots.
    //
    // Rendering straight at the label width was the first attempt and it
    // produced a symbol no scanner could read. The package stretches the
    // symbol to fill whatever width it is handed, so with 576 dots over 79
    // modules each module is 7.29 dots — and rounding every bar independently
    // leaves some 7 dots wide and some 8. A scanner measures bars in modules;
    // ragged ones decode as the wrong character or as nothing at all. It looks
    // completely convincing on screen.
    final unit = <(double, double)>[
      for (final element in bc.Barcode.code128().make(
        code,
        width: 1,
        height: 1,
        drawText: false,
      ))
        if (element is bc.BarcodeBar && element.black)
          (element.left, element.width),
    ];
    if (unit.isEmpty) {
      throw ArgumentError.value(code, 'code', 'produced no bars');
    }

    // The narrowest bar is one module, so its reciprocal is the module count.
    final narrowest = unit.map((b) => b.$2).reduce((a, b) => a < b ? a : b);
    final totalModules = (1 / narrowest).round();

    // Ten modules of white either side, which is what the specification asks
    // for. Without them a scanner cannot find where the symbol begins, and a
    // label butted against the edge of a sticker fails while the same code on
    // a bench succeeds.
    const quietModules = 10;
    final module = (labelWidth ~/ (totalModules + 2 * quietModules)).clamp(
      1,
      labelWidth,
    );
    if (module < 2) {
      throw ArgumentError.value(
        code,
        'code',
        'is too long for a $labelWidth-dot label: it needs '
            '${totalModules + 2 * quietModules} modules and there is room for '
            'less than two dots each, which no print head can place',
      );
    }

    final symbolWidth = totalModules * module;
    // Centred, with whatever is left over shared between the margins.
    final left = (labelWidth - symbolWidth) ~/ 2;

    final bytesPerRow = (labelWidth + 7) ~/ 8;
    final row = Uint8List(bytesPerRow);

    for (final (unitLeft, unitWidth) in unit) {
      // Snapped to module boundaries rather than to dots. Every bar is now a
      // whole number of modules wide by construction.
      final startModule = (unitLeft * totalModules).round();
      final widthModules = (unitWidth * totalModules).round();
      final start = left + startModule * module;
      final end = start + widthModules * module;
      for (var x = start; x < end && x < labelWidth; x++) {
        if (x >= 0) row[x >> 3] |= 0x80 >> (x & 7);
      }
    }

    // One row computed once and copied down. Not an optimisation: it
    // guarantees every scan line is identical, and a symbol whose rows
    // disagree by a dot reads at some angles and not others.
    final bits = Uint8List(bytesPerRow * height);
    for (var y = 0; y < height; y++) {
      bits.setRange(y * bytesPerRow, (y + 1) * bytesPerRow, row);
    }

    return MonoBitmap(width: labelWidth, height: height, bits: bits);
  }

  /// Trims a name to the columns one label has, without wrapping.
  ///
  /// A label that wraps onto two lines pushes the barcode off the sticker.
  static String _fit(String name, LabelSpec spec) {
    // Font A is 12 dots wide per character.
    final columns = spec.labelWidthDots ~/ 12;
    if (name.length <= columns) return name;
    return name.substring(0, columns);
  }
}
