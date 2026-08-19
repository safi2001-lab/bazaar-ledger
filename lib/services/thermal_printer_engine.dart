import 'dart:typed_data';
import 'dart:ui' as ui;

class ThermalPrinterEngine {
  /// Converts an off-screen ui.Image into ESC/POS GS v 0 raster command bytecode
  /// using Floyd-Steinberg error-diffusion 1-bit dithering for sharp Urdu Nastaliq output.
  static Future<List<int>> imageToEscPosRaster(ui.Image image) async {
    final width = image.width;
    final height = image.height;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return [];

    final pixels = byteData.buffer.asUint8List();
    final widthBytes = (width + 7) ~/ 8;

    // 1. Grayscale luminance conversion buffer
    final gray = List<int>.filled(width * height, 0);
    for (int i = 0; i < width * height; i++) {
      final r = pixels[i * 4];
      final g = pixels[i * 4 + 1];
      final b = pixels[i * 4 + 2];
      final a = pixels[i * 4 + 3];

      // Handle transparent backgrounds by blending with white
      if (a < 128) {
        gray[i] = 255;
      } else {
        gray[i] = (0.299 * r + 0.587 * g + 0.114 * b).round();
      }
    }

    // 2. Floyd-Steinberg 1-Bit Monochrome Dithering
    final monoBits = Uint8List(widthBytes * height);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = y * width + x;
        final oldPixel = gray[idx];
        final newPixel = oldPixel < 128 ? 0 : 255;
        gray[idx] = newPixel;
        final error = oldPixel - newPixel;

        // Distribute quantization error to neighboring pixels
        if (x + 1 < width) gray[idx + 1] += (error * 7) >> 4;
        if (x - 1 >= 0 && y + 1 < height) {
          gray[idx + width - 1] += (error * 3) >> 4;
        }
        if (y + 1 < height) gray[idx + width] += (error * 5) >> 4;
        if (x + 1 < width && y + 1 < height) {
          gray[idx + width + 1] += (error * 1) >> 4;
        }

        // Set bit in packed byte array (1 = Black dot, 0 = White)
        if (newPixel == 0) {
          final byteIndex = y * widthBytes + (x ~/ 8);
          final bitOffset = 7 - (x % 8);
          monoBits[byteIndex] |= (1 << bitOffset);
        }
      }
    }

    // 3. Assemble ESC/POS GS v 0 Command Header
    final List<int> bytes = [];
    // Initialize printer
    bytes.addAll([0x1B, 0x40]); // ESC @ (Initialize)

    // GS v 0 m xL xH yL yH
    bytes.addAll([0x1D, 0x76, 0x30, 0x00]); // GS v 0 m (m=0 normal mode)
    bytes.add(widthBytes & 0xFF); // xL (Number of bytes in horizontal direction)
    bytes.add((widthBytes >> 8) & 0xFF); // xH
    bytes.add(height & 0xFF); // yL (Number of dots in vertical direction)
    bytes.add((height >> 8) & 0xFF); // yH
    bytes.addAll(monoBits);

    // Line feed & paper cut
    bytes.addAll([0x1B, 0x64, 0x03]); // ESC d 3 (Feed 3 lines)
    bytes.addAll([0x1D, 0x56, 0x41, 0x00]); // GS V A 0 (Partial Cut)
    return bytes;
  }

  /// Streams ESC/POS bytecode over Bluetooth SPP or USB OTG in 512-byte chunks
  /// with a 35ms throttle to eliminate UART buffer overflows on portable thermal printers.
  static Future<void> sendThrottled(
    List<int> bytes,
    Future<void> Function(List<int> chunk) writeFunction, {
    int chunkSize = 512,
    int delayMs = 35,
  }) async {
    for (int i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      final chunk = bytes.sublist(i, end);
      await writeFunction(chunk);
      if (delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }
  }
}
