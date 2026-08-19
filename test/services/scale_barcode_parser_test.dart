import 'package:flutter_test/flutter_test.dart';
import 'package:pakistan_sme_billing/services/scale_barcode_parser.dart';

void main() {
  group('ScaleBarcodeParser Tests', () {
    test('Correctly parses weight-embedded scale barcode (Prefix 20)', () {
      // Barcode: 20 00125 01500 4 (PLU: 00125, Weight: 1500g / 1.500kg)
      const rawCode = '2000125015004';
      final item = ScaleBarcodeParser.parse(rawCode);

      expect(item, isNotNull);
      expect(item!.prefix, '20');
      expect(item.plu, '00125');
      expect(item.isWeightEmbedded, true);
      expect(item.weightInGrams, 1500.0);
      expect(item.weightInKg, 1.5);
      expect(item.priceInRupees, isNull);
    });

    test('Correctly parses price-embedded scale barcode (Prefix 22)', () {
      // Barcode: 22 00450 05000 7 (PLU: 00450, Price: Rs. 50.00 / 5000 paisas)
      const rawCode = '2200450050007';
      final item = ScaleBarcodeParser.parse(rawCode);

      expect(item, isNotNull);
      expect(item!.prefix, '22');
      expect(item.plu, '00450');
      expect(item.isWeightEmbedded, false);
      expect(item.priceInRupees, 50.0);
      expect(item.weightInKg, isNull);
    });

    test('Returns null for standard non-scale barcodes (e.g. standard FMCG EAN-13 896)', () {
      const fmcgBarcode = '8964000123456';
      final item = ScaleBarcodeParser.parse(fmcgBarcode);
      expect(item, isNull);
    });
  });
}
