import 'package:pk_money/pk_money.dart';

import 'receipt.dart';

/// The shop, as the app needs it on screen.
final class FirmProfile {
  const FirmProfile({
    required this.id,
    required this.name,
    required this.province,
    required this.isSalesTaxRegistered,
    required this.roundInvoiceToRupee,
    this.city,
    this.addressLine1,
    this.phone,
    this.ntn,
    this.strn,
    this.raastAlias,
    this.bankName,
    this.bankAccountTitle,
    this.bankIban,
  });

  final String id;
  final String name;
  final String? city;
  final String? addressLine1;
  final String? phone;
  final String province;
  final String? ntn;
  final String? strn;
  final bool isSalesTaxRegistered;
  final bool roundInvoiceToRupee;
  final String? raastAlias;
  final String? bankName;
  final String? bankAccountTitle;
  final String? bankIban;

  ReceiptShop toReceiptShop() => ReceiptShop(
        name: name,
        addressLine1: addressLine1,
        city: city,
        phone: phone,
        ntn: ntn,
        strn: strn,
        raastAlias: raastAlias,
        bankName: bankName,
        bankAccountTitle: bankAccountTitle,
        bankIban: bankIban,
      );
}

/// One row of the item list, and one tap away from a cart line.
final class ItemSummary {
  const ItemSummary({
    required this.id,
    required this.name,
    required this.unitId,
    required this.unitCode,
    required this.unitDecimals,
    required this.saleRate,
    required this.stockOnHand,
    required this.tracksStock,
    this.code,
    this.barcode,
    this.category,
    this.minStock = Qty.zero,
  });

  final String id;
  final String name;
  final String? code;
  final String? barcode;
  final String? category;

  final String unitId;
  final String unitCode;

  /// How many decimals the counter offers for this unit. Pieces get none, so
  /// a cashier cannot sell 2.5 shampoo bottles by mistyping.
  final int unitDecimals;

  final Rate saleRate;
  final Qty stockOnHand;
  final Qty minStock;
  final bool tracksStock;

  bool get isLowOnStock =>
      tracksStock && !minStock.isZero && stockOnHand <= minStock;
}

/// One row of the sales list.
final class SaleListRow {
  const SaleListRow({
    required this.id,
    required this.docNo,
    required this.dateLocal,
    required this.timeLabel,
    required this.total,
    required this.balance,
    required this.lineCount,
    required this.status,
    this.partyName,
  });

  final String id;
  final String docNo;
  final String dateLocal;
  final String timeLabel;
  final String? partyName;
  final Money total;
  final Money balance;
  final int lineCount;
  final String status;

  bool get isPaid => balance.isZero;
  bool get isVoid => status == 'void';
}

/// What one day of trading came to.
final class DayTotals {
  const DayTotals({
    required this.dateLocal,
    required this.billCount,
    required this.sales,
    required this.received,
    required this.onUdhaar,
  });

  final String dateLocal;
  final int billCount;
  final Money sales;
  final Money received;
  final Money onUdhaar;

  static const DayTotals empty = DayTotals(
    dateLocal: '',
    billCount: 0,
    sales: Money.zero,
    received: Money.zero,
    onUdhaar: Money.zero,
  );
}

/// A tender destination the counter can offer.
final class PaymentAccountSummary {
  const PaymentAccountSummary({
    required this.id,
    required this.name,
    required this.kind,
    required this.modeLabel,
    required this.isDefault,
  });

  final String id;
  final String name;
  final String kind;
  final String modeLabel;
  final bool isDefault;
}

/// A customer, as the counter needs them.
final class PartySummary {
  const PartySummary({
    required this.id,
    required this.name,
    required this.partyType,
    required this.balance,
    this.phone,
    this.creditLimit,
  });

  final String id;
  final String name;
  final String? phone;
  final String partyType;

  /// Positive means they owe the shop.
  final Money balance;
  final Money? creditLimit;

  bool get isOverCreditLimit =>
      creditLimit != null && balance > creditLimit!;
}

/// Everything the app reads.
///
/// Declared here so the UI can be written against domain types and never has
/// to see a row, a companion or a transaction. `lib/` does not list the data
/// package in its pubspec at all, so a widget that reaches for drift is a
/// resolution error rather than a review comment.
abstract interface class AppQueries {
  /// The firm this device belongs to, or null before first run.
  Future<FirmProfile?> currentFirm();

  /// The signed-in user's display name.
  Future<String> userName(String userId);

  Future<List<PaymentAccountSummary>> paymentAccounts(String firmId);

  /// Item search for the counter: name, code or barcode, keyset-paginated.
  ///
  /// [afterId] is the last id of the previous page. Offset pagination on a
  /// 20,000-SKU catalogue is the crash cluster that shows up in every
  /// competitor's reviews.
  Future<List<ItemSummary>> searchItems(
    String firmId, {
    String query = '',
    String? afterId,
    int limit = 40,
  });

  Future<ItemSummary?> itemByBarcode(String firmId, String barcode);

  Future<ItemSummary?> itemById(String firmId, String itemId);

  Future<List<PartySummary>> searchParties(
    String firmId, {
    String query = '',
    int limit = 40,
  });

  Future<List<SaleListRow>> recentSales(
    String firmId, {
    String? afterId,
    int limit = 40,
    String? onDateLocal,
  });

  Future<DayTotals> dayTotals(String firmId, String dateLocal);

  /// Everything needed to draw or print one receipt.
  Future<ReceiptData?> receiptFor(String firmId, String documentId);

  /// The units a firm has, for the item editor.
  Future<List<({String id, String code, String name, int decimals})>> units(
    String firmId,
  );
}
