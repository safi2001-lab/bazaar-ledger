import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:pk_platform/virtual_printer.dart';
import 'package:test/test.dart';

import 'receipt_test.dart' show receipt;

ReceiptData _withFbr(ReceiptData d, {String? no, bool pending = false}) =>
    ReceiptData(
      shop: d.shop,
      docNo: d.docNo,
      dateTimeLabel: d.dateTimeLabel,
      lines: d.lines,
      subtotal: d.subtotal,
      total: d.total,
      tenders: d.tenders,
      paid: d.paid,
      balance: d.balance,
      change: d.change,
      cashierName: d.cashierName,
      tax: const Money.rupees(4500),
      fbrInvoiceNo: no,
      fbrPending: pending,
    );

void main() {
  group('fbr receipt', () {
    test("FBR's number is printed with a QR of it", () {
      final bytes = const ThermalReceiptRenderer().toThermalBytes(
        _withFbr(receipt(), no: '7000007DI1747119701593'),
      );
      final paper = VirtualPrinter(dots: 576).print(bytes);
      expect(paper.line('FBR Invoice No'), isNotNull);
      expect(paper.line('7000007DI1747119701593'), isNotNull);
      final qr = paper.rasters.last;
      expect(qr.hasInk, isTrue);
      // A QR's three finder patterns: a solid 7x7-module square with a
      // one-module light ring and a 3x3 dark core, at three corners.
      int? firstInk(int row) {
        for (var x = 0; x < qr.bitmap.width; x++) {
          if (qr.ink(x, row)) return x;
        }
        return null;
      }

      final top = [
        for (var y = 0; y < qr.bitmap.height; y++)
          if (firstInk(y) != null) y,
      ].first;
      final left = firstInk(top)!;
      const m = 4;
      bool dark(int mx, int my) => qr.ink(left + mx * m + 1, top + my * m + 1);
      for (final (mx, my) in [(0, 0), (6, 0), (0, 6), (6, 6), (3, 3)]) {
        expect(dark(mx, my), isTrue, reason: 'finder dark at $mx,$my');
      }
      for (final (mx, my) in [(1, 1), (5, 1), (1, 5), (5, 5)]) {
        expect(dark(mx, my), isFalse, reason: 'finder light ring at $mx,$my');
      }
      expect(paper.cuts.single, greaterThan(paper.lastInk));
    });

    test('a bill FBR has not answered yet says so, with no QR', () {
      final bytes = const ThermalReceiptRenderer().toThermalBytes(
        _withFbr(receipt(), pending: true),
      );
      final paper = VirtualPrinter(dots: 576).print(bytes);
      // Rule 150XC (M59): "FBR: pending" became the offline-mode mark.
      expect(paper.line('OFFLINE INVOICE'), isNotNull);
      expect(paper.line('Issued in offline mode'), isNotNull);
      expect(paper.line('FBR invoice no. to follow'), isNotNull);
      expect(paper.rasters, isEmpty);
    });
  });
}
