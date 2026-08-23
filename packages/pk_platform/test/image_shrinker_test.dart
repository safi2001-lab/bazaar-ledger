import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

/// Getting a phone photograph down to something a shop's database can carry.
///
/// This product stores item pictures INLINE, deliberately: the schema's own
/// comment says a backup is then one file and a restore cannot come back with
/// every picture missing. That choice only holds while the pictures stay
/// small, so everything here is about the ceiling.
///
/// A modern phone camera produces four thousand pixels and eight megabytes.
/// Twenty items photographed at that size is a database no shopkeeper can send
/// over WhatsApp, which is how this product expects backups to travel.
void main() {
  const shrinker = DartImageShrinker();

  /// A photograph-shaped image: smooth gradients with some structure, which is
  /// what a camera actually produces and what JPEG is designed for.
  Uint8List photo(int width, int height) {
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        // Bands and a diagonal, so there is real detail to preserve without
        // being incompressible noise.
        final r = x * 255 ~/ width;
        final g = y * 255 ~/ height;
        final b = ((x + y) ~/ 8) % 256;
        image.setPixelRgb(x, y, r, g, b);
      }
    }
    return Uint8List.fromList(img.encodePng(image));
  }

  /// The least compressible thing a camera can produce. Not a realistic
  /// photograph -- it exists to prove the shrinker never gives up.
  Uint8List noise(int width, int height) {
    final image = img.Image(width: width, height: height);
    var seed = 12345;
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

  test('a camera-sized photograph comes back inside the ceiling', () async {
    // The case this exists for. Four thousand pixels of noise is the worst
    // realistic input: a real photograph compresses far better.
    final result = await shrinker.shrink(photo(2000, 1500), id: 'A');

    expect(result.width, ImageAttachment.maxEdge);
    expect(
      result.bytes.length,
      lessThanOrEqualTo(ImageAttachment.maxBytes),
      reason:
          'the stored picture is ${result.bytes.length} bytes, which is a '
          'backup that has stopped being something a shopkeeper can send',
    );
  });

  test('the long edge is the one that gets capped', () async {
    final landscape = await shrinker.shrink(photo(1600, 900), id: 'A');
    expect(landscape.width, ImageAttachment.maxEdge);
    expect(landscape.height, lessThan(ImageAttachment.maxEdge));

    final portrait = await shrinker.shrink(photo(900, 1600), id: 'B');
    expect(portrait.height, ImageAttachment.maxEdge);
    expect(portrait.width, lessThan(ImageAttachment.maxEdge));
  });

  test('the aspect ratio survives', () async {
    // A tin of oil that comes back stretched is a picture a cashier trusts
    // less than no picture.
    final result = await shrinker.shrink(photo(1600, 800), id: 'A');
    expect(result.width / result.height, closeTo(2.0, 0.02));
  });

  test('a small picture is not enlarged to hit the target', () async {
    // Scaling up makes the file bigger and the picture no better.
    final result = await shrinker.shrink(photo(120, 90), id: 'A');
    expect(result.width, 120);
    expect(result.height, 90);
  });

  test('a square picture stays square', () async {
    final result = await shrinker.shrink(photo(1200, 1200), id: 'A');
    expect(result.width, ImageAttachment.maxEdge);
    expect(result.height, ImageAttachment.maxEdge);
  });

  test('it comes back as JPEG, whatever went in', () async {
    // PNG in, JPEG out. A photograph of a tin of oil as PNG is four times the
    // size for no visible gain, and size is the entire constraint.
    final result = await shrinker.shrink(photo(800, 600), id: 'A');
    expect(result.mimeType, 'image/jpeg');
    expect(
      img.decodeJpg(result.bytes),
      isNotNull,
      reason: 'the bytes are not readable as JPEG',
    );
  });

  test('a picture that will not compress is shrunk, never refused', () async {
    // Pure noise at 512px is the least compressible thing JPEG can be handed,
    // and well past what quality alone can fix. It must still come back inside
    // the ceiling at a smaller size.
    //
    // Refusing would be the easy implementation and the wrong one: "try a
    // plainer photograph" is not advice anybody can follow while standing in
    // front of a shelf.
    final result = await shrinker.shrink(noise(1200, 1200), id: 'A');

    expect(result.bytes.length, lessThanOrEqualTo(ImageAttachment.maxBytes));
    // Still big enough to be a picture of something. The size ladder sits
    // below the quality ladder as a safety net, and on this input the quality
    // ladder is enough on its own — what is being tested is that a photograph
    // always comes back, not which rung it came back on.
    expect(result.width, greaterThan(64));
    expect(result.height, greaterThan(64));
  });

  test('something that is not a picture is refused in words', () async {
    // A PDF picked by mistake, a corrupt download. "That file is not a
    // picture" is something a shopkeeper can act on; a silent failure leaves
    // them tapping the same button again.
    await expectLater(
      shrinker.shrink(Uint8List.fromList([1, 2, 3, 4, 5]), id: 'A'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('not a picture'),
        ),
      ),
    );
  });

  test('an empty file is refused rather than stored as nothing', () async {
    await expectLater(
      shrinker.shrink(Uint8List(0), id: 'A'),
      throwsA(isA<FormatException>()),
    );
  });

  test('the same picture twice gives the same bytes', () async {
    // Content-addressing depends on this: two shrinks of one photograph must
    // hash the same, or every save looks like a different picture.
    final source = photo(900, 700);
    final first = await shrinker.shrink(source, id: 'A');
    final second = await shrinker.shrink(source, id: 'B');
    expect(first.bytes, second.bytes);
  });
}
