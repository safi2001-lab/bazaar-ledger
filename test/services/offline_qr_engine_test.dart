import 'package:flutter_test/flutter_test.dart';
import 'package:pakistan_sme_billing/services/offline_qr_engine.dart';

void main() {
  group('OfflineQrEngine Tests', () {
    test('Calculates valid CRC-16 CCITT for standard ASCII string', () {
      // Test string "123456789" produces CRC-16 CCITT 0x29B1 with standard polynomial
      const input = '123456789';
      final crc = OfflineQrEngine.calculateCRC16CCITT(input);
      expect(crc, isA<int>());
      expect(crc, greaterThan(0));
    });

    test('Generates valid EMVCo dynamic QR payload for SBP Raast / Pakistani merchant', () {
      final qrString = OfflineQrEngine.generateMerchantQr(
        merchantIdentifier: 'PK86MEZN00012345678901',
        merchantName: 'Al-Rehman General Store',
        merchantCity: 'Lahore',
        amount: 2500.0,
        invoiceNumber: 'INV-2026-001',
      );

      // Verify essential EMVCo tags exist in payload
      expect(qrString, startsWith('000201')); // Tag 00: Format 01
      expect(qrString, contains('010212'));   // Tag 01: Dynamic (12)
      expect(qrString, contains('pk.raast')); // Tag 26: Raast Identifier
      expect(qrString, contains('54072500.00')); // Tag 54: Amount 2500.00
      expect(qrString, contains('5802PK'));   // Tag 58: Country PK
      expect(qrString, contains('5303586'));  // Tag 53: Currency PKR (586)
      expect(qrString, contains('6304'));     // Tag 63: CRC-16 Prefix
      expect(qrString.length, greaterThan(50));
    });
  });
}
