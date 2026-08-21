import 'package:flutter_test/flutter_test.dart';
import 'package:pakistan_sme_billing/services/fbr_api_service.dart';

void main() {
  test('FbrInvoicePayload generates compliant FBR JSON structure', () {
    final payload = FbrInvoicePayload(
      invoiceNumber: 'INV-2026-001',
      posId: '100245',
      usin: 'USIN-001',
      dateTime: DateTime(2026, 8, 21, 14, 30),
      buyerNtn: '1234567-8',
      buyerName: 'Lahore Traders',
      totalSaleValue: 10000.0,
      totalTaxCharged: 1800.0, // 18% standard
      totalFurtherTax: 300.0,  // 3% Further Tax
      totalQuantity: 10.0,
      totalBillAmount: 12100.0,
      paymentMode: 1, // Cash
      items: [
        FbrInvoiceItemPayload(
          itemCode: 'ITEM-01',
          itemName: 'Industrial Lubricant',
          pctCode: '2710.19',
          quantity: 10.0,
          totalAmount: 12100.0,
          saleValue: 10000.0,
          taxCharged: 1800.0,
          taxRate: 18.0,
          furtherTax: 300.0,
        ),
      ],
    );

    final json = payload.toJson();
    expect(json['POSID'], '100245');
    expect(json['BuyerNTN'], '1234567-8');
    expect(json['TotalTaxCharged'], 1800.0);
    expect(json['FurtherTax'], 300.0);
    expect((json['Items'] as List).length, 1);
    expect((json['Items'] as List).first['PCTCode'], '002710.19');
  });

  test('FbrInvoicePayload produces deterministic offline provisional IRN', () {
    final payload = FbrInvoicePayload(
      invoiceNumber: 'INV-001',
      posId: '100245',
      usin: 'USIN-001',
      dateTime: DateTime(2026, 8, 21, 12, 0),
      totalSaleValue: 5000.0,
      totalTaxCharged: 900.0,
      totalQuantity: 5.0,
      totalBillAmount: 5900.0,
      items: [],
    );

    final irn1 = payload.generateProvisionalIrn();
    final irn2 = payload.generateProvisionalIrn();
    expect(irn1, startsWith('FBR-100245-20260821-'));
    expect(irn1, equals(irn2)); // Deterministic
  });

  test('FbrApiService maps FBR error codes accurately', () {
    expect(FbrApiService.mapFbrErrorCode(1001), contains('Duplicate'));
    expect(FbrApiService.mapFbrErrorCode(1002), contains('Bearer Token'));
    expect(FbrApiService.mapFbrErrorCode(1010), contains('POS ID'));
  });
}
