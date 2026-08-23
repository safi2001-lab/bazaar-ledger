import 'dart:convert';

import 'package:pk_domain/pk_domain.dart';

import 'cart.dart';

/// The bill in progress, as a string that survives the app being killed.
///
/// Every number is an integer. Money is paisa, quantity is thousandths, a rate
/// is milli-paisa: the same units the ledger stores, so a restored cart is
/// byte-for-byte the cart that was saved and a round trip cannot introduce the
/// rounding the whole codebase exists to avoid. `jsonEncode` would happily
/// write a double here, and nothing downstream would notice until a bill was
/// out by a paisa.
///
/// The item is snapshotted rather than referenced. A restored cart needs no
/// lookup — which means it cannot fail to restore because an item was renamed,
/// archived or deleted while the app was dead — and, more importantly, the
/// rate that was *entered* survives a price change made in between. A bill
/// half-rung at yesterday's price stays at yesterday's price.
abstract final class CartDraft {
  /// Bumped when the shape changes. A draft written by an older build is
  /// dropped rather than guessed at: the cost of dropping one is that the
  /// cashier re-rings a bill, and the cost of misreading one is a wrong bill
  /// they cannot see is wrong.
  static const version = 2;

  static String encode(Cart cart) => jsonEncode({
    'v': version,
    'partyId': cart.partyId,
    'partyName': cart.partyName,
    'billDiscountPaisa': cart.billDiscount.inPaisa,
    'lines': [
      for (final line in cart.lines)
        {
          'itemId': line.item.id,
          'name': line.item.name,
          'code': line.item.code,
          'barcode': line.item.barcode,
          'category': line.item.category,
          'unitId': line.item.unitId,
          'unitCode': line.item.unitCode,
          'unitDecimals': line.item.unitDecimals,
          'saleRateMilliPaisa': line.item.saleRate.inMilliPaisa,
          'stockOnHandThousandths': line.item.stockOnHand.inThousandths,
          'minStockThousandths': line.item.minStock.inThousandths,
          'tracksStock': line.item.tracksStock,
          'qtyThousandths': line.qty.inThousandths,
          'rateMilliPaisa': line.rate.inMilliPaisa,
          'discountBp': line.discountBp,
          'explicitDiscountPaisa': line.explicitDiscount?.inPaisa,
          // The unit the line is being SOLD in, which is not always the
          // unit the item is stocked in. A restored bill that quietly
          // reverted two maunds of atta to two kilos would be a bill for
          // a fortieth of the goods.
          'sellingUnitId': line.unitId,
          'sellingUnitCode': line.unitCode,
        },
    ],
  });

  /// The cart a string describes, or null if it does not describe one.
  ///
  /// Null for anything unexpected — a truncated file, a draft from an older
  /// build, a field of the wrong type. There is no partial restore: a cart
  /// missing some of its lines looks exactly like a whole one to the cashier,
  /// and the stock that is not on it walks out of the shop.
  static Cart? decode(String source) {
    try {
      final root = jsonDecode(source);
      if (root is! Map<String, Object?>) return null;
      if (root['v'] != version) return null;

      final rawLines = root['lines'];
      if (rawLines is! List) return null;

      final lines = <CartLine>[];
      for (final raw in rawLines) {
        if (raw is! Map<String, Object?>) return null;
        final line = _line(raw);
        if (line == null) return null;
        lines.add(line);
      }

      final discount = root['billDiscountPaisa'];
      if (discount is! int) return null;

      return Cart(
        lines: lines,
        partyId: root['partyId'] as String?,
        partyName: root['partyName'] as String?,
        billDiscount: Money.paisa(discount),
      );
    } on Object {
      return null;
    }
  }

  static CartLine? _line(Map<String, Object?> raw) {
    final itemId = raw['itemId'];
    final name = raw['name'];
    final unitId = raw['unitId'];
    final unitCode = raw['unitCode'];
    final unitDecimals = raw['unitDecimals'];
    final saleRate = raw['saleRateMilliPaisa'];
    final stock = raw['stockOnHandThousandths'];
    final minStock = raw['minStockThousandths'];
    final tracksStock = raw['tracksStock'];
    final qty = raw['qtyThousandths'];
    final rate = raw['rateMilliPaisa'];
    final discountBp = raw['discountBp'];
    final explicit = raw['explicitDiscountPaisa'];
    final sellingUnitId = raw['sellingUnitId'];
    final sellingUnitCode = raw['sellingUnitCode'];

    if (itemId is! String ||
        name is! String ||
        unitId is! String ||
        unitCode is! String ||
        unitDecimals is! int ||
        saleRate is! int ||
        stock is! int ||
        minStock is! int ||
        tracksStock is! bool ||
        qty is! int ||
        rate is! int ||
        discountBp is! int ||
        (explicit != null && explicit is! int) ||
        (sellingUnitId != null && sellingUnitId is! String) ||
        (sellingUnitCode != null && sellingUnitCode is! String)) {
      return null;
    }

    return CartLine(
      item: ItemSummary(
        id: itemId,
        name: name,
        code: raw['code'] as String?,
        barcode: raw['barcode'] as String?,
        category: raw['category'] as String?,
        unitId: unitId,
        unitCode: unitCode,
        unitDecimals: unitDecimals,
        saleRate: Rate.raw(saleRate),
        stockOnHand: Qty.raw(stock),
        minStock: Qty.raw(minStock),
        tracksStock: tracksStock,
      ),
      qty: Qty.raw(qty),
      rate: Rate.raw(rate),
      discountBp: discountBp,
      explicitDiscount: explicit == null ? null : Money.paisa(explicit as int),
      unitId: sellingUnitId as String?,
      unitCode: sellingUnitCode as String?,
    );
  }
}
