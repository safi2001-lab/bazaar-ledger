import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pk_bootstrap/pk_bootstrap.dart';

/// A bill as a picture, for the shops that send a photo of the bill (M30).
///
/// A great many shops do not send a PDF at all. They print the bill, lay it
/// on the counter and photograph it, because a picture opens inside the chat
/// on any phone and a PDF is a file the customer has to open in something
/// else. This makes that picture without the printer and without the camera.
///
/// ## The same paper, not a second layout
///
/// What is drawn is the 48-column layout the printer receives and the receipt
/// screen previews, line for line, then the bank's QR and FBR's as the
/// printer puts them under it. A "nicer" picture of the bill would be a third
/// layout of the same numbers, and the first anybody heard of it drifting
/// would be a customer holding a picture that disagrees with their paper.
///
/// ## Why not a picture of the PDF
///
/// Rasterising the PDF needs a PDF renderer, which this build does not carry:
/// the `printing` plugin would be a new native dependency through the release
/// gates for one button, and its raster path cannot run in a host test, so
/// the picture a customer receives would be the one part of sending a bill
/// nothing here could check. An A5 page shrunk into a chat bubble also reads
/// worse than a till roll, which is tall and narrow like a phone. Flutter's
/// own text engine is already here, draws Urdu with the phone's fonts as the
/// thermal path does, and encodes PNG itself. Nothing is added to the build.
final class ReceiptPicture {
  const ReceiptPicture({this.fontFamily, this.fontSize = 30});

  /// The monospaced face to draw with. Null on a phone, which uses its own;
  /// a test may name one it has loaded.
  final String? fontFamily;

  /// Points per character row. Thirty makes an 80 mm bill about a thousand
  /// pixels wide: sharp on a phone, and small enough that WhatsApp sends it
  /// without squeezing the figures into mush.
  final double fontSize;

  /// The page, and the ink on it.
  ///
  /// Not tokens, deliberately: this is a picture of paper, and it has to be
  /// black on white whatever theme the phone is in. A dark-mode bill sent to
  /// a customer would arrive white on black and print as a black rectangle.
  static const _ink = ui.Color(
    0xFF000000,
  ); // arch_check: allow no_hardcoded_colour - ink on a picture of paper
  static const _paper = ui.Color(
    0xFFFFFFFF,
  ); // arch_check: allow no_hardcoded_colour - the paper itself

  /// [receipt] as a PNG, laid out as [renderer] lays it out for [paper].
  Future<Uint8List> png(
    ReceiptRenderer renderer,
    ReceiptData receipt, {
    ReceiptPaper paper = ReceiptPaper.mm80,
  }) async {
    final lines = renderer.toPreview(receipt, paper: paper);
    final text = _paragraph(lines);

    // Laid out unconstrained first to find the widest line, then at exactly
    // that width: a bill is as wide as its paper, not as wide as the screen.
    text.layout(const ui.ParagraphConstraints(width: 100000));
    final textWidth = text.maxIntrinsicWidth.ceilToDouble();
    text.layout(ui.ParagraphConstraints(width: textWidth));

    // Pictures under the text, as the printer puts them: the QR the shop's
    // own bank issued, then FBR's number as a QR (M19). Each is scaled from
    // paper dots to the width the text came out at, so a QR keeps its place
    // on the bill whatever size the font is.
    final bitmaps = [
      ?receipt.bankQr,
      if (receipt.fbrInvoiceNo case final fbrNo?)
        fbrQrBitmap(fbrNo, widthDots: paper.dots),
    ];
    final scale = textWidth / paper.dots;

    final margin = fontSize;
    final pictureHeight = bitmaps.fold<double>(
      0,
      (sum, b) => sum + b.height * scale + margin / 2,
    );
    final width = (textWidth + margin * 2).ceil();
    final height = (text.height + pictureHeight + margin * 2).ceil();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawRect(
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..color = _paper,
      )
      ..drawParagraph(text, ui.Offset(margin, margin));

    var top = margin + text.height;
    // Hard edges: antialiased runs at a fractional scale leave grey seams
    // between the rows of a QR, and a scanner reads seams as modules.
    final ink = ui.Paint()
      ..color = _ink
      ..isAntiAlias = false;
    for (final bitmap in bitmaps) {
      top += margin / 2;
      final left = margin + (textWidth - bitmap.width * scale) / 2;
      _drawBits(canvas, bitmap, left: left, top: top, scale: scale, ink: ink);
      top += bitmap.height * scale;
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('the text engine returned no picture of the bill');
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }

  /// Every line in one paragraph, the shop's name in bold as the printer
  /// prints it large.
  ///
  /// One paragraph rather than a paragraph a line, so the text engine decides
  /// the order of an Urdu run inside a Latin line once per line, exactly as
  /// the on-screen preview does with the same string.
  ui.Paragraph _paragraph(List<String> lines) {
    ui.TextStyle style({bool bold = false}) => ui.TextStyle(
      color: _ink,
      fontFamily: fontFamily ?? 'monospace',
      fontFamilyFallback: const ['Courier New', 'Roboto Mono'],
      fontSize: fontSize,
      fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
      height: 1.35,
    );

    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textDirection: ui.TextDirection.ltr,
        fontFamily: fontFamily ?? 'monospace',
        fontSize: fontSize,
        height: 1.35,
      ),
    );
    if (lines.isNotEmpty) {
      builder
        ..pushStyle(style(bold: true))
        ..addText(lines.first)
        ..pop();
    }
    if (lines.length > 1) {
      builder
        ..pushStyle(style())
        ..addText('\n${lines.skip(1).join('\n')}')
        ..pop();
    }
    return builder.build();
  }

  /// A one-bit bitmap as runs of ink, a rectangle per run rather than per
  /// dot: a QR is tens of thousands of dots and a few thousand runs.
  static void _drawBits(
    ui.Canvas canvas,
    MonoBitmap bitmap, {
    required double left,
    required double top,
    required double scale,
    required ui.Paint ink,
  }) {
    final path = ui.Path();
    for (var y = 0; y < bitmap.height; y++) {
      int? runStart;
      for (var x = 0; x <= bitmap.width; x++) {
        final set =
            x < bitmap.width &&
            (bitmap.bits[y * bitmap.bytesPerRow + (x >> 3)] &
                    (0x80 >> (x & 7))) !=
                0;
        if (set) {
          runStart ??= x;
        } else if (runStart != null) {
          path.addRect(
            ui.Rect.fromLTWH(
              left + runStart * scale,
              top + y * scale,
              (x - runStart) * scale,
              scale,
            ),
          );
          runStart = null;
        }
      }
    }
    canvas.drawPath(path, ink);
  }
}
