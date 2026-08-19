/// Offline EMVCo-compliant QR Code Generator for SBP Raast, JazzCash, EasyPaisa, and Pakistani Bank Accounts.
/// Operates 100% locally with zero external network or banking API calls.
class OfflineQrEngine {
  /// Formats an EMVCo TLV (Tag-Length-Value) element
  static String formatTag(String tag, String value) {
    final len = value.length.toString().padLeft(2, '0');
    return '$tag$len$value';
  }

  /// Generates a complete EMVCo Merchant-Presented QR payload with CRC-16 checksum
  static String generateMerchantQr({
    required String merchantIdentifier, // Raast Alias / IBAN / JazzCash Till / EasyPaisa Number
    required String merchantName,
    required String merchantCity,
    double? amount,
    String? invoiceNumber,
    String currencyCode = '586', // PKR
    String countryCode = 'PK',
  }) {
    final sb = StringBuffer();
    // Tag 00: Payload Format Indicator
    sb.write(formatTag('00', '01'));
    // Tag 01: Point of Initiation Method ('11' for Static, '12' for Dynamic with Amount)
    sb.write(formatTag('01', amount != null ? '12' : '11'));
    // Tag 26: Merchant Account Information
    sb.write(formatTag('26', formatTag('00', 'pk.raast') + formatTag('01', merchantIdentifier)));
    // Tag 52: Merchant Category Code (5411 = Grocery/Retail)
    sb.write(formatTag('52', '5411'));
    // Tag 53: Transaction Currency (586 = PKR)
    sb.write(formatTag('53', currencyCode));
    // Tag 54: Transaction Amount (if specified)
    if (amount != null && amount > 0) {
      sb.write(formatTag('54', amount.toStringAsFixed(2)));
    }
    // Tag 58: Country Code
    sb.write(formatTag('58', countryCode));
    // Tag 59: Merchant Name
    sb.write(formatTag('59', merchantName.toUpperCase()));
    // Tag 60: Merchant City
    sb.write(formatTag('60', merchantCity.toUpperCase()));
    // Tag 62: Additional Data Field (Invoice Reference)
    if (invoiceNumber != null && invoiceNumber.isNotEmpty) {
      sb.write(formatTag('62', formatTag('01', invoiceNumber)));
    }

    // Tag 63: CRC-16 Checksum placeholder
    sb.write('6304');
    final rawPayload = sb.toString();
    final crc = calculateCRC16CCITT(rawPayload);
    final crcHex = crc.toRadixString(16).toUpperCase().padLeft(4, '0');
    return '$rawPayload$crcHex';
  }

  /// Computes CRC-16 CCITT-FALSE (Polynomial 0x1021, Initial value 0xFFFF)
  static int calculateCRC16CCITT(String data) {
    int crc = 0xFFFF;
    const int polynomial = 0x1021;

    for (int i = 0; i < data.length; i++) {
      int byte = data.codeUnitAt(i);
      for (int j = 0; j < 8; j++) {
        bool bit = ((byte >> (7 - j)) & 1) == 1;
        bool c15 = ((crc >> 15) & 1) == 1;
        crc = (crc << 1) & 0xFFFF;
        if (c15 ^ bit) {
          crc ^= polynomial;
        }
      }
    }
    return crc & 0xFFFF;
  }
}
