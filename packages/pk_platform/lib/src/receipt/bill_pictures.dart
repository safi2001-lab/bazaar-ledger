import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pk_domain/pk_domain.dart';

/// The two pictures a shop puts on its bills (M51): its logo, and the
/// payment QR its own bank or wallet gave it.
///
/// Both are kept inline in the books, like an item's photograph, so a backup
/// is one file and a restore never comes back without them — which is also
/// why both are kept small. Neither is the item shrinker's job, and each is
/// shrunk for what it is:
///
/// * **A logo** is very often a PNG with a transparent background. The item
///   shrinker writes JPEG, and JPEG has no transparency: every clear pixel
///   came out black, so a logo on white arrived as a black box. It is laid
///   on white first.
/// * **A QR** has to scan after it has been printed. JPEG's blocks smear the
///   edges of the modules, and the item shrinker's 512 pixels can leave a QR
///   that was a small part of a screenshot with too few dots a module. It is
///   kept larger, in grey, as PNG wherever that fits — a screenshot of a QR
///   is mostly flat white and black and compresses to almost nothing.
///
/// Nothing here makes a QR. A picture goes in and the same picture, smaller,
/// comes out.
const _logoEdge = 400;
const _qrEdge = 800;

/// [source] as the shop's logo, ready to store.
///
/// Throws [FormatException] when the bytes are not a picture this build can
/// read, which the screen says in words.
ImageAttachment prepareShopLogo(Uint8List source, {required String id}) =>
    _prepare(_decode(source), id: id, edge: _logoEdge, grey: false);

/// [source] as the shop's own payment QR, ready to store.
///
/// Throws [FormatException] when the bytes are not a picture this build can
/// read.
ImageAttachment preparePaymentQr(Uint8List source, {required String id}) =>
    _prepare(_decode(source), id: id, edge: _qrEdge, grey: true);

/// A stored picture as one-bit dots for the till roll: [widthPercent] of
/// the paper's width, centred on a full-width row so the printer and the
/// picture of the bill place it the same way.
///
/// Thresholded, never dithered. Dithering is right for a photograph and
/// wrong for a QR: it turns every module's edge into a scatter of dots a
/// scanner reads as noise. Small pictures are scaled up by whole pixels for
/// the same reason — a QR module must stay square.
///
/// Null when the bytes cannot be read: a QR that will not decode costs the
/// bill its QR, never the bill.
MonoBitmap? pictureDots(
  Uint8List encoded, {
  required int paperDots,
  int widthPercent = 60,
}) {
  final img.Image picture;
  try {
    final decoded = img.decodeImage(encoded);
    if (decoded == null) return null;
    picture = _onWhite(decoded);
  } on Object {
    return null;
  }
  final target = (paperDots * widthPercent ~/ 100).clamp(64, paperDots);
  final scaled = img.copyResize(
    picture,
    width: target,
    // Down by averaging, so thin lines survive; up by repeating pixels, so
    // edges stay hard.
    interpolation: picture.width > target
        ? img.Interpolation.average
        : img.Interpolation.nearest,
  );
  // Never taller than the paper is wide twice over: a whole phone screenshot
  // is a long strip of roll for one QR.
  final height = scaled.height > paperDots * 2 ? paperDots * 2 : scaled.height;
  final bytesPerRow = (paperDots + 7) ~/ 8;
  final bits = Uint8List(bytesPerRow * height);
  final left = (paperDots - scaled.width) ~/ 2;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < scaled.width; x++) {
      final p = scaled.getPixel(x, y);
      if (p.luminanceNormalized < 0.5) {
        final dx = left + x;
        bits[y * bytesPerRow + (dx >> 3)] |= 0x80 >> (dx & 7);
      }
    }
  }
  return MonoBitmap(width: paperDots, height: height, bits: bits);
}

img.Image _decode(Uint8List source) {
  // `decodeImage` returns null for some unreadable inputs and throws for
  // others; both mean the same thing to a shopkeeper.
  img.Image? decoded;
  try {
    decoded = img.decodeImage(source);
  } on Object {
    decoded = null;
  }
  if (decoded == null) {
    throw const FormatException(
      'That file is not a picture this app can read.',
    );
  }
  return decoded;
}

/// [picture] laid on white, so a transparent background is white on the
/// page rather than black.
img.Image _onWhite(img.Image picture) {
  if (!picture.hasAlpha) return picture;
  final flat = img.Image(width: picture.width, height: picture.height);
  img.fill(flat, color: img.ColorRgb8(255, 255, 255));
  return img.compositeImage(flat, picture);
}

ImageAttachment _prepare(
  img.Image decoded, {
  required String id,
  required int edge,
  required bool grey,
}) {
  var working = _onWhite(decoded);
  final longest = working.width > working.height
      ? working.width
      : working.height;
  if (longest > edge) {
    working = img.copyResize(
      working,
      width: working.width >= working.height ? edge : null,
      height: working.height > working.width ? edge : null,
      interpolation: img.Interpolation.average,
    );
  }
  if (grey) {
    working = img.grayscale(working).convert(numChannels: 1);
  }

  // PNG first: lossless, and small for anything flat — a logo, a QR
  // screenshot. A photograph does not fit and falls through to JPEG, which
  // gives way on quality before size, and on size by halving, so the loop
  // ends in a handful of passes whatever the picture is.
  final png = Uint8List.fromList(img.encodePng(working, level: 9));
  if (png.length <= ImageAttachment.maxBytes) {
    return ImageAttachment(
      id: id,
      bytes: png,
      mimeType: 'image/png',
      width: working.width,
      height: working.height,
    );
  }
  var quality = 90;
  var encoded = Uint8List.fromList(img.encodeJpg(working, quality: quality));
  while (encoded.length > ImageAttachment.maxBytes) {
    if (quality > 60) {
      quality -= 10;
    } else {
      working = img.copyResize(
        working,
        width: working.width ~/ 2 < 32 ? 32 : working.width ~/ 2,
        interpolation: img.Interpolation.average,
      );
    }
    encoded = Uint8List.fromList(img.encodeJpg(working, quality: quality));
  }
  return ImageAttachment(
    id: id,
    bytes: encoded,
    mimeType: 'image/jpeg',
    width: working.width,
    height: working.height,
  );
}
