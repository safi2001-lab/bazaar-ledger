import 'dart:typed_data';

import 'package:barcode/barcode.dart' as bc;
import 'package:pk_domain/pk_domain.dart';

/// FBR's invoice number as a QR code, for the foot of a registered bill
/// (M19). It carries the number and nothing else: this is not a payment QR,
/// and no payment scheme's payload is ever built here.
///
/// Every module is a whole number of dots, as the Code 128 on a label is,
/// so the code prints square and scans.
MonoBitmap fbrQrBitmap(
  String fbrInvoiceNo, {
  required int widthDots,
  int moduleDots = 4,
}) {
  // Drawn in a unit space first, so the module count can be read off.
  final unit = [
    for (final e in bc.Barcode.qrCode().make(
      fbrInvoiceNo,
      width: 1,
      height: 1,
      drawText: false,
    ))
      if (e is bc.BarcodeBar && e.black) e,
  ];
  final narrowest = unit.map((b) => b.width).reduce((a, b) => a < b ? a : b);
  final modules = (1 / narrowest).round();
  const quiet = 4;
  final size = (modules + 2 * quiet) * moduleDots;
  final width = size > widthDots ? widthDots : size;
  final left = (widthDots - size) ~/ 2;
  final bytesPerRow = (widthDots + 7) ~/ 8;
  final bits = Uint8List(bytesPerRow * size);
  for (final bar in unit) {
    final x0 = (bar.left * modules).round();
    final y0 = (bar.top * modules).round();
    final w = (bar.width * modules).round();
    final h = (bar.height * modules).round();
    for (var my = y0; my < y0 + h; my++) {
      for (var mx = x0; mx < x0 + w; mx++) {
        for (var dy = 0; dy < moduleDots; dy++) {
          final y = (quiet + my) * moduleDots + dy;
          for (var dx = 0; dx < moduleDots; dx++) {
            final x = left + (quiet + mx) * moduleDots + dx;
            if (x < 0 || x >= widthDots || y >= size) continue;
            bits[y * bytesPerRow + (x >> 3)] |= 0x80 >> (x & 7);
          }
        }
      }
    }
  }
  assert(width > 0);
  return MonoBitmap(width: widthDots, height: size, bits: bits);
}
