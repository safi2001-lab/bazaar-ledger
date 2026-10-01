import 'dart:convert';

import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

FbrSale _sale({String? hs = '1512.1900', String? ntn = '1234567-8'}) => FbrSale(
  invoiceRef: 'INV-2627-0001',
  dateUtc: DateTime.utc(2026, 9, 30, 9, 30, 5),
  sellerNtn: ntn,
  sellerStrn: '3277876123456',
  buyerNtn: '9876543-2',
  buyerName: 'Al-Rehman "Traders"',
  buyerRegistered: true,
  lines: [
    FbrLine(
      itemCode: 'SKU-9901',
      description: 'Cooking Oil 5L Can',
      hsCode: hs,
      qty: Qty.units(10),
      unit: 'Can',
      unitPrice: const Money.rupees(2500),
      value: const Money.rupees(25000),
      salesTaxBp: 1800,
      salesTax: const Money.rupees(4500),
      furtherTax: Money.zero,
      discount: const Money.rupees(500),
      total: const Money.rupees(29500),
    ),
  ],
);

void main() {
  group('fbr invoice', () {
    test('a registered sale is written as the gateway reads it', () {
      final json = jsonDecode(fbrPayload(_sale())) as Map<String, Object?>;
      expect(json['InvoiceType'], 'Sale Invoice');
      expect(json['InvoiceDate'], '2026-09-30T09:30:05Z');
      expect(json['SellerNTN'], '1234567-8');
      expect(json['BuyerType'], 'Registered');
      expect(json['BuyerName'], 'Al-Rehman "Traders"');
      final item = (json['InvoiceItems']! as List).single as Map;
      expect(item['HSCode'], '1512.1900');
      expect(item['Quantity'], 10);
      expect(item['SalesTaxRate'], 18);
      expect(item['SalesTaxAmount'], 4500);
      expect(json['TotalSalesTax'], 4500);
      expect(json['TotalInvoiceAmount'], 29500);
    });

    test('amounts go out as exact decimals, never through a float', () {
      final raw = fbrPayload(_sale());
      expect(raw, contains('"UnitPrice":2500.00'));
      expect(raw, contains('"Quantity":10.000'));
      expect(raw, contains('"SalesTaxRate":18.00'));
      expect(raw, contains('"TotalInvoiceAmount":29500.00'));
    });

    test('what FBR would refuse is said before anything is sent', () {
      expect(fbrProblems(_sale()), isEmpty);
      expect(fbrProblems(_sale(hs: null)).single, startsWith('1002'));
      expect(fbrProblems(_sale(hs: '1512')).single, startsWith('1002'));
      expect(fbrProblems(_sale(ntn: '12345')).single, startsWith('1001'));
    });

    test(
      "the gateway's answers are read for a number, a refusal or a retry",
      () {
        expect(
          readFbrResponse(200, {
            'invoiceNumber': '7000007DI1747119701593',
            'validationResponse': {'statusCode': '00', 'status': 'Valid'},
          }),
          isA<FbrPosted>().having(
            (p) => p.fbrInvoiceNo,
            'number',
            '7000007DI1747119701593',
          ),
        );
        expect(
          readFbrResponse(200, {
            'validationResponse': {
              'statusCode': '01',
              'errorCode': '1002',
              'error': 'Invalid HS Code',
            },
          }),
          isA<FbrRejected>(),
        );
        expect(
          readFbrResponse(200, {'ErrorCode': '1005', 'Message': 'Duplicate'}),
          isA<FbrRejected>().having((r) => r.code, 'code', '1005'),
        );
        expect(readFbrResponse(503, null), isA<FbrTryLater>());
        expect(readFbrResponse(200, {'ErrorCode': '5003'}), isA<FbrTryLater>());
        expect(readFbrResponse(401, null), isA<FbrRejected>());
      },
    );

    test('a credit note names the invoice it takes goods back from', () {
      final base = _sale();
      FbrSale credit(String? ref) => FbrSale(
        invoiceRef: 'RET-2627-0001',
        dateUtc: base.dateUtc,
        sellerNtn: base.sellerNtn,
        sellerStrn: base.sellerStrn,
        buyerNtn: base.buyerNtn,
        buyerName: base.buyerName,
        buyerRegistered: true,
        lines: base.lines,
        invoiceType: 'Credit Note',
        referenceFbrNo: ref,
      );
      final json = fbrPayload(credit('7000007DI0000000001'));
      expect(json, contains('"InvoiceType":"Credit Note"'));
      expect(json, contains('"ReferenceInvoiceNo":"7000007DI0000000001"'));
      expect(fbrProblems(credit('7000007DI0000000001')), isEmpty);
      expect(fbrProblems(credit(null)), hasLength(1));
      expect(fbrPayload(base), isNot(contains('ReferenceInvoiceNo')));
    });
  });
}
