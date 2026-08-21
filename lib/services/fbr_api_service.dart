import 'dart:convert';
import 'package:crypto/crypto.dart';

class FbrInvoiceItemPayload {
  final String itemCode;
  final String itemName;
  final String pctCode; // 8-digit Pakistan Customs Tariff (HS Code)
  final double quantity;
  final double totalAmount;
  final double saleValue;
  final double taxCharged;
  final double taxRate;
  final double furtherTax;
  final int invoiceType; // 1 = Standard

  FbrInvoiceItemPayload({
    required this.itemCode,
    required this.itemName,
    required this.pctCode,
    required this.quantity,
    required this.totalAmount,
    required this.saleValue,
    required this.taxCharged,
    required this.taxRate,
    this.furtherTax = 0.0,
    this.invoiceType = 1,
  });

  Map<String, dynamic> toJson() => {
        'ItemCode': itemCode,
        'ItemName': itemName,
        'PCTCode': pctCode.replaceAll('.', '').padLeft(8, '0'),
        'Quantity': quantity,
        'TotalAmount': totalAmount,
        'SaleValue': saleValue,
        'TaxCharged': taxCharged,
        'TaxRate': taxRate,
        'FurtherTax': furtherTax,
        'InvoiceType': invoiceType,
      };
}

class FbrInvoicePayload {
  final String invoiceNumber;
  final String posId;
  final String usin;
  final DateTime dateTime;
  final String? buyerNtn;
  final String? buyerCnic;
  final String? buyerName;
  final String? buyerPhoneNumber;
  final double totalSaleValue;
  final double totalTaxCharged;
  final double totalFurtherTax;
  final double totalQuantity;
  final double discount;
  final double totalBillAmount;
  final int paymentMode; // 1=Cash, 2=Card, 3=Cheque, 4=Online, 5=Credit
  final int invoiceType; // 1=New, 2=Debit Note, 3=Credit Note
  final List<FbrInvoiceItemPayload> items;

  FbrInvoicePayload({
    required this.invoiceNumber,
    required this.posId,
    required this.usin,
    required this.dateTime,
    this.buyerNtn,
    this.buyerCnic,
    this.buyerName,
    this.buyerPhoneNumber,
    required this.totalSaleValue,
    required this.totalTaxCharged,
    this.totalFurtherTax = 0.0,
    required this.totalQuantity,
    this.discount = 0.0,
    required this.totalBillAmount,
    this.paymentMode = 1,
    this.invoiceType = 1,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'InvoiceNumber': invoiceNumber,
        'POSID': posId,
        'USIN': usin,
        'DateTime': dateTime.toIso8601String(),
        'BuyerNTN': buyerNtn ?? '',
        'BuyerCNIC': buyerCnic ?? '',
        'BuyerName': buyerName ?? 'Cash Customer',
        'BuyerPhoneNumber': buyerPhoneNumber ?? '',
        'TotalSaleValue': totalSaleValue,
        'TotalTaxCharged': totalTaxCharged,
        'FurtherTax': totalFurtherTax,
        'TotalQuantity': totalQuantity,
        'Discount': discount,
        'TotalBillAmount': totalBillAmount,
        'PaymentMode': paymentMode,
        'InvoiceType': invoiceType,
        'Items': items.map((i) => i.toJson()).toList(),
      };

  /// Generates deterministic FBR IRN for offline receipts
  String generateProvisionalIrn() {
    final datePart = '${dateTime.year}${dateTime.month.toString().padLeft(2, '0')}${dateTime.day.toString().padLeft(2, '0')}';
    final rawString = '$posId-$datePart-$usin-$totalBillAmount';
    final hash = md5.convert(utf8.encode(rawString)).toString().substring(0, 8).toUpperCase();
    return 'FBR-$posId-$datePart-$hash';
  }

  /// Generates FBR standard QR Code payload string
  String generateFbrQrPayload() {
    final irn = generateProvisionalIrn();
    return 'FBR_IRN:$irn|POS:$posId|BILL:${totalBillAmount.toStringAsFixed(2)}|TAX:${totalTaxCharged.toStringAsFixed(2)}|DATE:${dateTime.toIso8601String().split('T')[0]}';
  }
}

class FbrApiService {
  final String posId;
  final String bearerToken;
  final bool isProduction;

  FbrApiService({
    required this.posId,
    required this.bearerToken,
    this.isProduction = false,
  });

  String get baseUrl => isProduction
      ? 'https://ims.fbr.gov.pk/api/v1/Live'
      : 'https://ims.fbr.gov.pk/api/v1/Sandbox';

  /// Maps FBR response error codes to user-friendly recovery instructions
  static String mapFbrErrorCode(int code) {
    switch (code) {
      case 1001:
        return 'Invoice already registered with FBR (Duplicate). Marked as synced.';
      case 1002:
        return 'Invalid or expired FBR Bearer Token. Please re-enter in settings.';
      case 1005:
        return 'Invalid PCT / HS Code detected on one or more line items.';
      case 1010:
        return 'POS ID is inactive or not registered in FBR IMS portal.';
      default:
        return 'FBR Gateway Error (Code $code). Queued for automatic retry.';
    }
  }
}
