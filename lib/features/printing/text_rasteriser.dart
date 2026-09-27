import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pk_bootstrap/pk_bootstrap.dart';

/// Draws a line of text as a picture, for a printer that cannot say it.
///
/// ## Why this cannot live in `pk_platform`
///
/// `pk_platform` is pure Dart on purpose: the whole receipt path is testable
/// headless and the byte stream can be asserted command by command. Shaping
/// Urdu is the one part of printing that genuinely needs the platform. Arabic
/// script is cursive — every letter has up to four contextual forms — and a
/// line mixing `\u0686\u0627\u0648\u0644` with `1,450.00` needs the bidirectional algorithm to
/// decide what order the runs come out in. Both live in the text engine
/// behind `dart:ui`, alongside the system font fallback that supplies the
/// Urdu glyphs in the first place.
///
/// Reimplementing either here would be this app guessing at Unicode. So the
/// pure package says *which* lines it cannot print, and this draws them.
///
/// ## The font is the system's, deliberately
///
/// Android ships Noto Naskh Arabic and has since Android 5, so Urdu renders
/// on every handset this targets without bundling anything. Nastaliq — the
/// style Urdu is actually set in, and what a shopkeeper would prefer — is a
/// 300 KB to 2 MB font, and Flutter's tree-shaking cannot touch a font used
/// for text composed at runtime, so all of it would ship. The release APKs
/// sit at 27 MB against a 30 MB ceiling. Naskh is legible, correct, free and
/// already on the phone; Nastaliq is a preference that costs a tenth of the
/// download. If it is ever bundled, it goes behind a setting and not into
/// the default build.
final class UiTextRasteriser {
  const UiTextRasteriser({this.fontFamily});

  /// The face to draw with. Null on a phone, which uses the system's own
  /// Urdu-capable font; set by the paper proofs to the Naskh face the app
  /// bundles, since the test engine's own font draws every letter as a box.
  final String? fontFamily;

  /// The only two values a thermal head has.
  ///
  /// Not tokens, and the exemption says so rather than leaving the next
  /// reader to wonder. A design token is a choice about how the app should
  /// look; this is the physical fact that a print head either burns a dot or
  /// does not. There is no dark mode for paper, and a token here would be a
  /// colour somebody could retheme into a blank receipt.
  static const _burn = ui.Color(
    0xFF000000,
  ); // arch_check: allow no_hardcoded_colour - ink
  static const _paper = ui.Color(
    0xFFFFFFFF,
  ); // arch_check: allow no_hardcoded_colour - bare paper

  /// A picture of [text], [widthDots] wide, at [pointSize] points.
  ///
  /// Rendered black on white and thresholded, because a thermal head has one
  /// bit per dot: it burns or it does not, and there is no grey. Antialiased
  /// edges therefore have to be decided one way or the other here rather than
  /// by the printer, which would take any non-zero byte as black and thicken
  /// every stroke.
  Future<MonoBitmap> rasterise(
    String text, {
    required int widthDots,
    double pointSize = 30,
    bool bold = false,
    bool centre = false,
  }) async {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              // Not `ui.TextDirection.rtl`, and not ltr either — the base
              // direction is whatever the first strong character says, which
              // is what a mixed line needs. `ur` gives the engine the right
              // language for glyph selection where Arabic and Urdu differ.
              textDirection: _baseDirection(text),
              // From the start of the line, which for Urdu is the right-hand
              // edge. `left` put every Urdu line hard against the wrong
              // margin, which the virtual printer showed on its first run.
              textAlign: centre ? ui.TextAlign.center : ui.TextAlign.start,
              fontFamily: fontFamily,
              fontSize: pointSize,
              // Generous, because Naskh's descenders and the nuqta below `\u067E`
              // sit well outside a Latin line box and would otherwise be
              // clipped by the next line.
              height: 1.45,
              fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: _burn,
              fontFamily: fontFamily,
              fontSize: pointSize,
              fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
              locale: const ui.Locale('ur', 'PK'),
            ),
          )
          ..addText(text);

    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: widthDots.toDouble()));

    // Rounded up to a whole dot row, and never zero: `GS v 0` with a height
    // of zero is a command the printer waits on for pixels that never come.
    final height = paragraph.height.ceil().clamp(1, 0xFFFF);

    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..drawRect(
        ui.Rect.fromLTWH(0, 0, widthDots.toDouble(), height.toDouble()),
        ui.Paint()..color = _paper,
      )
      ..drawParagraph(paragraph, ui.Offset.zero);

    final picture = recorder.endRecording();
    final image = await picture.toImage(widthDots, height);
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        throw StateError('the text engine returned no pixels for "$text"');
      }
      return _threshold(data.buffer.asUint8List(), widthDots, height);
    } finally {
      image.dispose();
    }
  }

  /// The direction the line starts in, from its first strong character.
  ///
  /// A receipt line beginning with an Urdu item name is an RTL paragraph with
  /// an LTR number in it; one beginning `Total` is the reverse. Forcing
  /// either would put the price on the wrong end of half the receipt.
  static ui.TextDirection _baseDirection(String text) {
    for (final rune in text.runes) {
      // Arabic, Arabic Supplement, Arabic Extended-A, and the presentation
      // forms. Hebrew is not in this market and is left out rather than
      // guessed at.
      if (rune >= 0x0590 && rune <= 0x08FF) return ui.TextDirection.rtl;
      if (rune >= 0xFB1D && rune <= 0xFDFF) return ui.TextDirection.rtl;
      if (rune >= 0xFE70 && rune <= 0xFEFF) return ui.TextDirection.rtl;
      if (rune >= 0x41 && rune <= 0x5A) return ui.TextDirection.ltr;
      if (rune >= 0x61 && rune <= 0x7A) return ui.TextDirection.ltr;
    }
    return ui.TextDirection.ltr;
  }

  /// RGBA down to one bit a dot, MSB first, which is what `GS v 0` reads.
  ///
  /// The threshold is on luminance at the midpoint. A lighter cut would make
  /// Naskh's hairlines disappear at 30 points on 203 dpi; a darker one closes
  /// the counters of `\u06C1` into a blob. Both were visible on paper before this
  /// number settled here.
  static MonoBitmap _threshold(Uint8List rgba, int width, int height) {
    final bytesPerRow = (width + 7) ~/ 8;
    final bits = Uint8List(bytesPerRow * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final alpha = rgba[i + 3];
        // Composited over the white rectangle already, so alpha is 255 across
        // the bitmap; kept as a guard because a zero-alpha pixel read as
        // black would print a solid rectangle.
        if (alpha == 0) continue;
        final luma =
            (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
        if (luma < 128) {
          bits[y * bytesPerRow + (x >> 3)] |= 0x80 >> (x & 7);
        }
      }
    }
    return MonoBitmap(width: width, height: height, bits: bits);
  }
}

/// Draws every line of [receipt] the printer cannot spell, as the renderer
/// will ask for them: the shop name centred and large, like its Latin
/// counterpart, and every other line from its own starting edge.
Future<Map<String, MonoBitmap>> drawUnprintableLines(
  ReceiptRenderer renderer,
  ReceiptData receipt,
  ReceiptPaper paper, {
  UiTextRasteriser rasteriser = const UiTextRasteriser(),
}) async {
  final needed = renderer.unprintableLines(receipt, paper: paper);
  if (needed.isEmpty) return const {};
  final name = receipt.shop.name.toUpperCase();
  return {
    for (final line in needed)
      line: line == name
          ? await rasteriser.rasterise(
              line,
              widthDots: paper.dots,
              pointSize: 44,
              bold: true,
              centre: true,
            )
          : await rasteriser.rasterise(line, widthDots: paper.dots),
  };
}
