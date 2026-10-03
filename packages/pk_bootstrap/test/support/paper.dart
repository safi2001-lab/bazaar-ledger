import 'dart:typed_data';

/// A picture as a phone's gallery might hand one over (M60): an
/// uncompressed bitmap of a ruled page, [shade] making each one different,
/// so the store can tell them apart by their hash.
///
/// Written out by hand rather than encoded, because this package does not
/// carry an image library of its own and should not take one on for its
/// tests; the paper preparer reads a bitmap like any other picture.
Uint8List paper(int shade, {int width = 120, int height = 160}) {
  final row = (width * 3 + 3) & ~3;
  final size = 54 + row * height;
  final b = ByteData(size)
    ..setUint8(0, 0x42)
    ..setUint8(1, 0x4D)
    ..setUint32(2, size, Endian.little)
    ..setUint32(10, 54, Endian.little)
    ..setUint32(14, 40, Endian.little)
    ..setInt32(18, width, Endian.little)
    ..setInt32(22, height, Endian.little)
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, 24, Endian.little)
    ..setUint32(34, row * height, Endian.little);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final ink = y % 12 < 2 && (x ~/ 5) % 3 != 0;
      final o = 54 + y * row + x * 3;
      b
        ..setUint8(o, ink ? 120 : (200 + shade * 7) % 256)
        ..setUint8(o + 1, ink ? 40 : 230)
        ..setUint8(o + 2, ink ? 30 : (236 - shade * 3) % 256);
    }
  }
  return b.buffer.asUint8List();
}
