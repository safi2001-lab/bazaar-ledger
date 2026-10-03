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
  ///
  /// v4 (M37) marks a loose line, which has no item behind it. A build
  /// before v4 would read one as an item whose id names nothing in the
  /// shop, and the bill would fail at the till; so a v4 draft is not one it
  /// may read. Everything a v3 draft says, a v4 one says the same way.
  ///
  /// v5 (M36) carries a bill being put right: the cancelled bill it
  /// replaces, and what the customer had paid on it. A v4 build would read
  /// such a draft as an ordinary bill and post it unlinked, with the payment
  /// sheet starting at nothing — the customer's money forgotten — so it is
  /// not one it may read either.
  ///
  /// v6 (M54) keeps, beside a line, the unit it was counted in on the
  /// screen when it was rung by the dozen and then moved to pieces
  /// (`countedIn`), what the paper on the counter is (`sourceType`), and
  /// the bonus a challan on it sent (`sentBonus`). The first two are words
  /// on the screen. The third is the bill: a v5 build reading it would work
  /// the challan's bonus out again from today's schemes, and a scheme
  /// changed since would have the bill refused at the till for not being
  /// what the challan sent — so a v6 draft is not one it may read. Every
  /// older shape is still read here: a v5 draft is a v6 one counted in no
  /// dozen, holding no paper of known kind, and carrying no challan bonus.
  static const version = 6;

  /// A v2 draft is a v3 one with no price tier: every v2 cart was priced
  /// retail, so it is read as exactly that rather than thrown away. A v3
  /// draft is a v4 one with no loose lines, and a v4 one a v5 one putting
  /// nothing right.
  static const _readable = {2, 3, 4, 5, 6};

  static String encode(Cart cart) => jsonEncode({
    'v': version,
    'partyId': cart.partyId,
    'partyName': cart.partyName,
    'billDiscountPaisa': cart.billDiscount.inPaisa,
    'priceTier': cart.priceTier.code,
    'partyDiscountBp': cart.partyDiscountBp,
    'sourceId': cart.sourceId,
    'sourceNo': cart.sourceNo,
    // M54: what the paper on the counter is, so a sale order brought back
    // after the app was killed may still go out on a challan.
    'sourceType': ?cart.sourceType,
    'alsoSourceIds': cart.alsoSourceIds,
    // A bill being put right (M36), and the money already taken for it.
    if (cart.replacesId != null) 'replacesId': cart.replacesId,
    if (cart.replacesNo != null) 'replacesNo': cart.replacesNo,
    if (cart.paidBefore case final paid?)
      'paidBefore': {
        'amountPaisa': paid.amount.inPaisa,
        'mode': paid.mode,
        'reference': paid.reference,
        'chequeNo': paid.chequeNo,
        'chequeBank': paid.chequeBank,
        'chequeDateUtcMillis': paid.chequeDateUtcMillis,
      },
    // M43: what the cashier took off of the shop's schemes. Optional, and
    // not a new version: a draft without them is a bill with every scheme
    // on, which is what a build before M43 would make of it, and the
    // cashier sees a bonus put back on the counter before the bill goes.
    if (cart.bonusWaived.isNotEmpty) 'bonusWaived': cart.bonusWaived.toList(),
    if (cart.slabWaived) 'slabWaived': true,
    // M63: the repeating bill this is. Optional, not a new version: a build
    // before M63 posts it as an ordinary bill and the template stays due.
    if (cart.recurring case final r?) 'recurring': r.toJson(),
    // M54: the bonus the challans on the counter sent, billed as it went.
    // Absent for every other bill, whose bonus is worked out at the counter.
    if (cart.sentBonus case final sent?)
      'sentBonus': [
        for (final f in sent)
          {
            'itemId': f.itemId,
            'name': f.itemName,
            'code': f.itemCode,
            'hsCode': f.hsCode,
            'qtyThousandths': f.qty.inThousandths,
            'baseThousandths': f.baseQty.inThousandths,
            'unitId': f.unitId,
            'unitCode': f.unitCode,
            'tracksStock': f.tracksStock,
          },
      ],
    'lines': [
      for (final line in cart.lines)
        {
          'itemId': line.item.id,
          'name': line.item.name,
          'code': line.item.code,
          'barcode': line.item.barcode,
          'category': line.item.category,
          'hsCode': line.item.hsCode,
          'unitId': line.item.unitId,
          'unitCode': line.item.unitCode,
          'unitDecimals': line.item.unitDecimals,
          'saleRateMilliPaisa': line.item.saleRate.inMilliPaisa,
          'wholesaleRateMilliPaisa': line.item.wholesaleRate?.inMilliPaisa,
          'vipRateMilliPaisa': line.item.vipRate?.inMilliPaisa,
          'stockOnHandThousandths': line.item.stockOnHand.inThousandths,
          'minStockThousandths': line.item.minStock.inThousandths,
          'tracksStock': line.item.tracksStock,
          'qtyThousandths': line.qty.inThousandths,
          'rateMilliPaisa': line.rate.inMilliPaisa,
          'discountBp': line.discountBp,
          'explicitDiscountPaisa': line.explicitDiscount?.inPaisa,
          if (line.lotIds.isNotEmpty) 'lotIds': line.lotIds,
          // A loose line (M37). Its "item" is the stand-in the cart made
          // for it, and it is restored as one, never looked up.
          if (line.isLoose) 'loose': true,
          if (line.lotLabels.isNotEmpty) 'lotLabels': line.lotLabels,
          // The unit the line is being SOLD in, which is not always the
          // unit the item is stocked in. A restored bill that quietly
          // reverted two maunds of atta to two kilos would be a bill for
          // a fortieth of the goods.
          'sellingUnitId': line.unitId,
          'sellingUnitCode': line.unitCode,
          // M54: the dozen a line moved to pieces is still counted in.
          'countedIn': ?line.countedInUnitId,
          // M59: how the line is taxed. Optional keys, so a v5 draft
          // written before them reads as goods with no MRP, as it was.
          if (line.item.mrp case final mrp?) 'mrpPaisa': mrp.inPaisa,
          if (line.item.isThirdSchedule) 'thirdSchedule': true,
          if (line.item.isService) 'service': true,
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
      if (!_readable.contains(root['v'])) return null;

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
      final partyDiscountBp = root['partyDiscountBp'] ?? 0;
      if (partyDiscountBp is! int) return null;

      final rawPaid = root['paidBefore'];
      PaidBefore? paidBefore;
      if (rawPaid != null) {
        if (rawPaid is! Map<String, Object?>) return null;
        final amount = rawPaid['amountPaisa'];
        if (amount is! int) return null;
        paidBefore = PaidBefore(
          amount: Money.paisa(amount),
          mode: rawPaid['mode'] as String?,
          reference: rawPaid['reference'] as String?,
          chequeNo: rawPaid['chequeNo'] as String?,
          chequeBank: rawPaid['chequeBank'] as String?,
          chequeDateUtcMillis: rawPaid['chequeDateUtcMillis'] as int?,
        );
      }

      return Cart(
        lines: lines,
        partyId: root['partyId'] as String?,
        partyName: root['partyName'] as String?,
        billDiscount: Money.paisa(discount),
        priceTier: PriceTier.parse(root['priceTier'] as String?),
        partyDiscountBp: partyDiscountBp,
        sourceId: root['sourceId'] as String?,
        sourceNo: root['sourceNo'] as String?,
        sourceType: root['sourceType'] as String?, // M54
        alsoSourceIds: [
          for (final id
              in (root['alsoSourceIds'] as List<Object?>?) ?? const [])
            if (id is String) id,
        ],
        replacesId: root['replacesId'] as String?,
        replacesNo: root['replacesNo'] as String?,
        paidBefore: paidBefore,
        // M43.
        bonusWaived: {
          for (final id in (root['bonusWaived'] as List<Object?>?) ?? const [])
            if (id is String) id,
        },
        slabWaived: root['slabWaived'] == true,
        recurring: RecurringMark.fromJson(root['recurring']), // M63
        sentBonus: _sentBonus(root['sentBonus']), // M54
      );
    } on Object {
      return null;
    }
  }

  /// M54: a challan's bonus as the draft keeps it; null when it keeps none.
  /// A malformed entry throws, and the draft is not read (see [decode]).
  static List<SaleLineDraft>? _sentBonus(Object? raw) {
    if (raw == null) return null;
    return [
      for (final f in raw as List<Object?>)
        if (f case final Map<String, Object?> m)
          SaleLineDraft(
            itemId: m['itemId']! as String,
            itemName: m['name']! as String,
            itemCode: m['code'] as String?,
            hsCode: m['hsCode'] as String?,
            qty: Qty.raw(m['qtyThousandths']! as int),
            baseQty: Qty.raw(m['baseThousandths']! as int),
            unitId: m['unitId'] as String?,
            unitCode: m['unitCode']! as String,
            rate: Rate.zero,
            isFreeItem: true,
            tracksStock: m['tracksStock'] != false,
          )
        else
          throw const FormatException('sentBonus'),
    ];
  }

  static CartLine? _line(Map<String, Object?> raw) {
    final itemId = raw['itemId'];
    final name = raw['name'];
    final unitId = raw['unitId'];
    final unitCode = raw['unitCode'];
    final unitDecimals = raw['unitDecimals'];
    final saleRate = raw['saleRateMilliPaisa'];
    final wholesaleRate = raw['wholesaleRateMilliPaisa'];
    final vipRate = raw['vipRateMilliPaisa'];
    final stock = raw['stockOnHandThousandths'];
    final minStock = raw['minStockThousandths'];
    final tracksStock = raw['tracksStock'];
    final qty = raw['qtyThousandths'];
    final rate = raw['rateMilliPaisa'];
    final discountBp = raw['discountBp'];
    final explicit = raw['explicitDiscountPaisa'];
    final sellingUnitId = raw['sellingUnitId'];
    final sellingUnitCode = raw['sellingUnitCode'];
    final loose = raw['loose'] ?? false;
    final countedIn = raw['countedIn']; // M54

    if (itemId is! String ||
        name is! String ||
        unitId is! String ||
        unitCode is! String ||
        unitDecimals is! int ||
        saleRate is! int ||
        (wholesaleRate != null && wholesaleRate is! int) ||
        (vipRate != null && vipRate is! int) ||
        stock is! int ||
        minStock is! int ||
        tracksStock is! bool ||
        qty is! int ||
        rate is! int ||
        discountBp is! int ||
        (explicit != null && explicit is! int) ||
        (sellingUnitId != null && sellingUnitId is! String) ||
        (sellingUnitCode != null && sellingUnitCode is! String) ||
        (countedIn != null && countedIn is! String) ||
        loose is! bool) {
      return null;
    }

    return CartLine(
      item: ItemSummary(
        id: itemId,
        name: name,
        code: raw['code'] as String?,
        barcode: raw['barcode'] as String?,
        category: raw['category'] as String?,
        hsCode: raw['hsCode'] as String?,
        unitId: unitId,
        unitCode: unitCode,
        unitDecimals: unitDecimals,
        saleRate: Rate.raw(saleRate),
        wholesaleRate: wholesaleRate == null
            ? null
            : Rate.raw(wholesaleRate as int),
        vipRate: vipRate == null ? null : Rate.raw(vipRate as int),
        stockOnHand: Qty.raw(stock),
        minStock: Qty.raw(minStock),
        tracksStock: tracksStock,
        // M59.
        mrp: switch (raw['mrpPaisa']) {
          final int paisa => Money.paisa(paisa),
          _ => null,
        },
        isThirdSchedule: raw['thirdSchedule'] == true,
        isService: raw['service'] == true,
      ),
      qty: Qty.raw(qty),
      rate: Rate.raw(rate),
      discountBp: discountBp,
      explicitDiscount: explicit == null ? null : Money.paisa(explicit as int),
      unitId: sellingUnitId as String?,
      unitCode: sellingUnitCode as String?,
      lotIds: [
        for (final id in (raw['lotIds'] as List<Object?>?) ?? const [])
          if (id is String) id,
      ],
      lotLabels: [
        for (final l in (raw['lotLabels'] as List<Object?>?) ?? const [])
          if (l is String) l,
      ],
      isLoose: loose,
      countedInUnitId: countedIn as String?, // M54
    );
  }
}
