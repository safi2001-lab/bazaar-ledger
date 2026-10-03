import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pk_domain/pk_domain.dart';

/// A photograph of a paper — a parchi, a bijli bill, a deposit slip, a
/// cheque — reduced to something the shop's books can carry (M60).
///
/// Not the item shrinker, and on purpose. That one keeps 512 pixels, which
/// is plenty to recognise a packet and nowhere near enough to read a
/// handwritten "40 bags @ 3,150" on a carbon copy, which is the one thing a
/// photograph of a supplier's bill is ever looked at for. This keeps
/// [EntryPhoto.maxEdge] and fits [EntryPhoto.maxBytes].
///
/// The order of the two knobs is the item shrinker's, for the same reason:
/// quality first, because a slightly softer photograph of handwriting is
/// still legible; then size, because a smaller one that fits is better than
/// a refusal a shopkeeper standing at the counter cannot do anything about.
///
/// Colour is kept. A supplier's stamp, a cheque's printed background and a
/// correction in red ink are all things a grey copy would lose.
///
/// Pure Dart, like the item shrinker: the same everywhere and testable with
/// no phone.
ImageAttachment preparePaperPhoto(Uint8List source, {required String id}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(source);
  } on Object {
    // A truncated file, a PDF picked by mistake: the same sentence either
    // way, said in words by the screen.
    decoded = null;
  }
  if (decoded == null) {
    throw const FormatException(
      'That file is not a picture this app can read.',
    );
  }

  // A phone held upright writes a landscape picture and a note saying
  // "turn me". Resizing reads the pixels, not the note, so the turn is made
  // first — or a portrait parchi is stored on its side and read with the
  // phone held sideways.
  var working = img.bakeOrientation(decoded);
  working = _fit(working, EntryPhoto.maxEdge);

  var encoded = Uint8List.fromList(img.encodeJpg(working, quality: 80));
  var quality = 80;
  while (encoded.length > EntryPhoto.maxBytes) {
    // Down to 40 before the edge gives way: blocky round the strokes, and
    // every figure still legible, which is worth more than a sharper copy
    // of fewer pixels.
    if (quality > 40) {
      quality -= 10;
    } else {
      // Out of quality at this size: three quarters of the edge, and the
      // ladder again. Bounded, because the edge shrinks every time round,
      // and 256 pixels of anything fits the ceiling many times over.
      final longest = working.width > working.height
          ? working.width
          : working.height;
      if (longest <= 256) {
        throw StateError(
          'A ${working.width}x${working.height} photograph will not fit in '
          '${EntryPhoto.maxBytes} bytes, which should be impossible.',
        );
      }
      working = _fit(working, longest * 3 ~/ 4);
      quality = 75;
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

/// [picture] no larger than [edge] on its longest side; never enlarged.
img.Image _fit(img.Image picture, int edge) {
  final longest = picture.width > picture.height
      ? picture.width
      : picture.height;
  if (longest <= edge) return picture;
  return img.copyResize(
    picture,
    width: picture.width >= picture.height ? edge : null,
    height: picture.height > picture.width ? edge : null,
    interpolation: img.Interpolation.average,
  );
}
