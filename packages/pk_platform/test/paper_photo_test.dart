import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

/// A photograph of a parchi, kept large enough to read and small enough to
/// back up (M60).
///
/// The item shrinker's 512 pixels recognise a packet; they do not read a
/// handwritten "40 bags" on a carbon copy, which is the only thing anybody
/// ever opens a photograph of a supplier's bill to do. These hold the
/// larger edge and the ceiling that keeps a year of parchis a backup a shop
/// can still send.
void main() {
  /// Something shaped like a photograph of paper: a light page with dark
  /// strokes across it, the way a parchi looks to a camera.
  Uint8List parchi(int width, int height) {
    final page = img.Image(width: width, height: height);
    img.fill(page, color: img.ColorRgb8(236, 230, 214));
    for (var y = 0; y < height; y += 24) {
      for (var x = 0; x < width; x++) {
        // A wavering line of "handwriting" every 24 pixels.
        final dy = (x ~/ 7) % 5;
        if (y + dy < height) page.setPixelRgb(x, y + dy, 30, 40, 120);
      }
    }
    return Uint8List.fromList(img.encodeJpg(page, quality: 95));
  }

  /// The least compressible thing a camera can hand over.
  Uint8List noise(int width, int height) {
    final image = img.Image(width: width, height: height);
    var seed = 4242;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        image.setPixelRgb(
          x,
          y,
          seed & 0xFF,
          (seed >> 8) & 0xFF,
          (seed >> 16) & 0xFF,
        );
      }
    }
    return Uint8List.fromList(img.encodePng(image));
  }

  group('a photograph of the paper', () {
    test('a camera-sized parchi comes back at a size that reads, inside the '
        'ceiling', () {
      final kept = preparePaperPhoto(parchi(1500, 2000), id: 'p');

      expect(kept.height, EntryPhoto.maxEdge, reason: 'portrait, long edge');
      expect(kept.width, 1500 * EntryPhoto.maxEdge ~/ 2000);
      expect(
        EntryPhoto.maxEdge,
        greaterThan(ImageAttachment.maxEdge),
        reason: "an item's 512 pixels do not read handwriting",
      );
      expect(kept.bytes.length, lessThanOrEqualTo(EntryPhoto.maxBytes));
      expect(kept.mimeType, 'image/jpeg');
      expect(img.decodeJpg(kept.bytes), isNotNull);
    });

    test('a photograph that will not compress is made smaller, never '
        'refused', () {
      final kept = preparePaperPhoto(noise(1400, 1400), id: 'p');

      expect(kept.bytes.length, lessThanOrEqualTo(EntryPhoto.maxBytes));
      expect(kept.width, greaterThan(256));
    });

    test('a small one is not enlarged', () {
      final kept = preparePaperPhoto(parchi(300, 200), id: 'p');
      expect((kept.width, kept.height), (300, 200));
    });

    test('a phone held upright gives an upright picture', () {
      // The camera writes the pixels landscape and a note saying "turn me";
      // a parchi stored on its side is read with the phone held sideways.
      final sideways = img.Image(width: 400, height: 200);
      img.fill(sideways, color: img.ColorRgb8(240, 240, 240));
      sideways.exif.imageIfd.orientation = 6;
      final kept = preparePaperPhoto(
        Uint8List.fromList(img.encodeJpg(sideways)),
        id: 'p',
      );

      expect((kept.width, kept.height), (200, 400));
    });

    test('something that is not a picture is refused in words', () {
      expect(
        () => preparePaperPhoto(
          Uint8List.fromList('%PDF-1.4'.codeUnits),
          id: 'p',
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('not a picture'),
          ),
        ),
      );
    });
  });
}
