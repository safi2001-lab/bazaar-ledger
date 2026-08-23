import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pk_domain/pk_domain.dart';

/// Reduces a phone photograph to something a shop's database can carry.
///
/// The picture that comes off a camera is four thousand pixels wide and eight
/// megabytes. The picture a cashier needs is one they can recognise on a
/// 720x1600 screen at arm's length. Storing the first to serve the second is
/// how a shop's backup stops being a file anybody can send over WhatsApp — and
/// this product deliberately stores images inline, so the database IS the
/// backup.
///
/// Pure Dart, on purpose. `package:image` decodes and re-encodes without a
/// platform channel, which means the whole path is testable headless and
/// behaves the same on every ROM. The alternative — a native downscale — would
/// be faster and would be one more thing that only fails on a handset.
final class DartImageShrinker implements ImageShrinker {
  const DartImageShrinker();

  @override
  Future<ImageAttachment> shrink(Uint8List source, {required String id}) async {
    // `decodeImage` returns null for some unreadable inputs and THROWS for
    // others — a truncated header, an empty file, a PDF. Both mean the same
    // thing to a shopkeeper, so both come out as the same sentence.
    img.Image? probed;
    try {
      probed = img.decodeImage(source);
    } on Object {
      probed = null;
    }

    final decoded = probed;
    if (decoded == null) {
      // A PDF someone picked by mistake, a corrupt download, a format this
      // build cannot read. Worth saying plainly: "that file is not a picture"
      // is something a shopkeeper can act on, and a silent failure leaves them
      // tapping the same button again.
      throw const FormatException(
        'That file is not a picture this app can read.',
      );
    }

    final longest = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;

    // Only ever downwards. Enlarging a small picture to hit a target makes the
    // file bigger and the picture no better.
    final resized = longest <= ImageAttachment.maxEdge
        ? decoded
        : img.copyResize(
            decoded,
            width: decoded.width >= decoded.height
                ? ImageAttachment.maxEdge
                : null,
            height: decoded.height > decoded.width
                ? ImageAttachment.maxEdge
                : null,
            interpolation: img.Interpolation.average,
          );

    // JPEG, not PNG. A photograph of a tin of oil in PNG is four times the
    // size for no visible gain, and size is the whole constraint here.
    //
    // Two knobs, tried in that order, and the order matters. Quality first,
    // because a slightly softer picture of a packet is still a recognisable
    // picture of that packet. Then size, because at some point more pixels of
    // a busy shelf stop helping a cashier and start costing the backup.
    //
    // It never gives up. Refusing a photograph a shopkeeper just took is a
    // dead end they cannot act on -- "try a plainer photograph" is not advice
    // anybody can follow while standing in front of a shelf. The loop is
    // bounded by the edge halving, so it terminates in a handful of passes
    // even on pure noise, which is the least compressible thing a camera can
    // produce and nothing like a real photograph.
    var working = resized;
    var encoded = Uint8List.fromList(img.encodeJpg(working, quality: 82));

    for (var quality = 70; ; quality -= 15) {
      if (encoded.length <= ImageAttachment.maxBytes) break;

      if (quality >= 40) {
        encoded = Uint8List.fromList(img.encodeJpg(working, quality: quality));
        continue;
      }

      // Out of quality. Halve the edge and start again -- a 256px picture of
      // a packet is still a picture of that packet, and the alternative is
      // telling a shopkeeper their photograph is not allowed.
      final longestNow = working.width > working.height
          ? working.width
          : working.height;
      if (longestNow <= 64) {
        // Sixty-four pixels of anything fits inside the ceiling. Reaching here
        // would mean the encoder is not doing what it says.
        throw StateError(
          'A ${working.width}x${working.height} picture will not fit in '
          '${ImageAttachment.maxBytes} bytes, which should be impossible.',
        );
      }
      working = img.copyResize(
        working,
        width: working.width >= working.height ? longestNow ~/ 2 : null,
        height: working.height > working.width ? longestNow ~/ 2 : null,
        interpolation: img.Interpolation.average,
      );
      encoded = Uint8List.fromList(img.encodeJpg(working, quality: 70));
      quality = 85; // restart the quality ladder at the new size
    }

    return ImageAttachment(
      id: id,
      bytes: encoded,
      mimeType: 'image/jpeg',
      width: working.width,
      height: working.height,
    );
  }
}
