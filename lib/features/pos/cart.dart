import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import 'cart_draft.dart';

/// One line as the counter has it so far.
///
/// Immutable, and compared by value, so Riverpod's `==` notification filter
/// actually cuts rebuilds instead of firing on every identical rebuild of the
/// same list.
final class CartLine {
  const CartLine({
    required this.item,
    required this.qty,
    required this.rate,
    this.discountBp = 0,
    this.explicitDiscount,
    this.unitId,
    this.unitCode,
  });

  final ItemSummary item;

  /// The quantity as the cashier typed it, in [sellingUnitCode].
  final Qty qty;

  /// The price per [sellingUnitCode], not per the item's base unit.
  ///
  /// A shop that stocks atta in kilos and sells it by the maund quotes a
  /// price per maund, and that is the number that belongs on the bill.
  final Rate rate;

  final int discountBp;
  final Money? explicitDiscount;

  /// The unit this line is being sold in, when it is not the item's own.
  ///
  /// Null means the item's base unit, which is the overwhelming case: a
  /// kiryana counter sells pieces of what it stocks in pieces. It is null
  /// rather than a copy of the base unit so that a line the cashier never
  /// touched cannot drift out of step with the item it names.
  final String? unitId;
  final String? unitCode;

  String get sellingUnitId => unitId ?? item.unitId;
  String get sellingUnitCode => unitCode ?? item.unitCode;

  /// True when this line is priced and counted in something other than what
  /// the shelf is counted in.
  bool get isConverted => unitId != null && unitId != item.unitId;

  Money get gross => rate.amountFor(qty);

  Money get discount =>
      explicitDiscount ??
      (discountBp == 0 ? Money.zero : gross.percentBp(discountBp));

  Money get net => gross - discount;

  CartLine copyWith({
    Qty? qty,
    Rate? rate,
    int? discountBp,
    Money? explicitDiscount,
    bool clearExplicitDiscount = false,
    String? unitId,
    String? unitCode,
  }) => CartLine(
    item: item,
    qty: qty ?? this.qty,
    rate: rate ?? this.rate,
    discountBp: discountBp ?? this.discountBp,
    explicitDiscount: clearExplicitDiscount
        ? null
        : explicitDiscount ?? this.explicitDiscount,
    unitId: unitId ?? this.unitId,
    unitCode: unitCode ?? this.unitCode,
  );

  /// The line as the write path wants it.
  ///
  /// [units] converts the entered quantity into the item's base unit, which
  /// is the only thing stock moves in. A line sold in the item's own unit
  /// needs no converter at all, which is why one is optional — the counter
  /// must not stop selling pieces because the conversion table failed to
  /// load.
  SaleLineDraft toDraft([UnitConverter? units]) => SaleLineDraft(
    itemId: item.id,
    itemName: item.name,
    itemCode: item.code,
    qty: qty,
    // Stock moves in the item's base unit and nothing else. A bill for
    // two maunds of atta takes eighty kilos off the shelf, and the
    // conversion is exact or the sale does not post.
    baseQty: isConverted && units != null
        ? units.convert(
            qty,
            fromUnitId: sellingUnitId,
            toUnitId: item.unitId,
            itemId: item.id,
          )
        : qty,
    unitId: sellingUnitId,
    unitCode: sellingUnitCode,
    rate: rate,
    discountBp: discountBp,
    explicitDiscount: explicitDiscount,
    tracksStock: item.tracksStock,
  );

  @override
  bool operator ==(Object other) =>
      other is CartLine &&
      other.item.id == item.id &&
      other.qty == qty &&
      other.rate == rate &&
      other.discountBp == discountBp &&
      other.explicitDiscount == explicitDiscount &&
      other.unitId == unitId;

  @override
  int get hashCode =>
      Object.hash(item.id, qty, rate, discountBp, explicitDiscount, unitId);
}

/// The bill in progress.
final class Cart {
  const Cart({
    this.lines = const [],
    this.partyId,
    this.partyName,
    this.billDiscount = Money.zero,
    this.priceTier = PriceTier.retail,
    this.partyDiscountBp = 0,
    this.sourceId,
    this.sourceNo,
  });

  final List<CartLine> lines;
  final String? partyId;
  final String? partyName;
  final Money billDiscount;

  /// The customer's prices. Retail for a walk-in.
  final PriceTier priceTier;

  /// The customer's standing discount on every line, in basis points.
  final int partyDiscountBp;

  /// The quotation this bill is being made from, and its number.
  final String? sourceId;
  final String? sourceNo;

  bool get isEmpty => lines.isEmpty;

  Money get gross => Money.sum(lines.map((l) => l.gross));

  Money get lineDiscount => Money.sum(lines.map((l) => l.discount));

  /// What the counter shows before tax. The authoritative number is always the
  /// one [SaleCalculator] produces at post time — this is the running display,
  /// and the two agree because they apply the same rules in the same order.
  Money get subtotal => gross - lineDiscount - billDiscount;

  Cart copyWith({
    List<CartLine>? lines,
    String? partyId,
    String? partyName,
    Money? billDiscount,
    PriceTier? priceTier,
    int? partyDiscountBp,
    bool clearParty = false,
  }) => Cart(
    sourceId: sourceId,
    sourceNo: sourceNo,
    lines: lines ?? this.lines,
    partyId: clearParty ? null : partyId ?? this.partyId,
    partyName: clearParty ? null : partyName ?? this.partyName,
    billDiscount: billDiscount ?? this.billDiscount,
    priceTier: priceTier ?? this.priceTier,
    partyDiscountBp: partyDiscountBp ?? this.partyDiscountBp,
  );
}

final cartProvider = NotifierProvider<CartNotifier, Cart>(CartNotifier.new);

/// Holds the bill in progress, and writes it down.
///
/// Deliberately not auto-disposed, so walking away from the counter to fetch a
/// tin of ghee leaves the bill where it was. That covers leaving the screen
/// and nothing more: an Infinix or Tecno running Phone Master will force-stop
/// a backgrounded app, and about 44% of the handsets this ships to are
/// Transsion. A cashier who checks a price in WhatsApp on a fifteen-line bill
/// and comes back to an empty cart re-scans the lot with the customer
/// standing there.
///
/// So every mutation is written to a file. Not to the books — a draft has no
/// invoice number, no journal entry and no place in the sync outbox — and not
/// through Flutter's state restoration, which rides on Android's
/// `savedInstanceState` and dies with the task record: a force-stop, a swipe
/// off Recents or a reboot all take it, leaving only the low-memory reclaim
/// covered, which is the case a shopkeeper is least likely to notice.
class CartNotifier extends Notifier<Cart> {
  @override
  Cart build() {
    // Restored synchronously. A cart that arrives a frame late shows an empty
    // bill first, and an empty bill is one the cashier starts ringing again.
    final saved = ref.read(appServicesProvider).restoredCartDraft;
    final restored = saved == null ? null : CartDraft.decode(saved);

    // `listenSelf` rather than a line in each mutator: there are eight of
    // them, and the ninth that someone adds later would be the one that is
    // not saved.
    listenSelf((_, next) => _save(next));

    return restored ?? const Cart();
  }

  void _save(Cart cart) {
    final drafts = ref.read(appServicesProvider).drafts;
    // Never awaited on the scan path. The store coalesces — a write in
    // flight holds the slot and the newest pending contents replace any older
    // pending contents — so four quick taps on the quantity stepper cost one
    // write, and it is the last one.
    unawaited(
      cart.isEmpty && cart.partyId == null
          ? drafts.clear(cartDraftSlot)
          : drafts.write(cartDraftSlot, CartDraft.encode(cart)),
    );
  }

  /// Adds an item, or bumps the quantity if it is already on the bill.
  ///
  /// Scanning the same barcode twice means two of them, which is what a
  /// cashier expects and what every till in the world does.
  void add(ItemSummary item, {Qty? qty}) {
    final step = qty ?? Qty.one;
    final index = state.lines.indexWhere((l) => l.item.id == item.id);
    final lines = [...state.lines];
    if (index >= 0) {
      lines[index] = lines[index].copyWith(qty: lines[index].qty + step);
    } else {
      lines.add(
        CartLine(
          item: item,
          qty: step,
          rate: priceFor(item, state.priceTier),
          discountBp: state.partyDiscountBp,
        ),
      );
    }
    state = state.copyWith(lines: lines);
  }

  void setQty(String itemId, Qty qty) {
    if (!qty.isPositive) {
      remove(itemId);
      return;
    }
    state = state.copyWith(
      lines: [
        for (final l in state.lines)
          l.item.id == itemId ? l.copyWith(qty: qty) : l,
      ],
    );
  }

  void setRate(String itemId, Rate rate) {
    state = state.copyWith(
      lines: [
        for (final l in state.lines)
          l.item.id == itemId ? l.copyWith(rate: rate) : l,
      ],
    );
  }

  void setLineDiscount(String itemId, Money? amount) {
    state = state.copyWith(
      lines: [
        for (final l in state.lines)
          if (l.item.id == itemId)
            l.copyWith(
              explicitDiscount: amount,
              clearExplicitDiscount: amount == null,
              discountBp: 0,
            )
          else
            l,
      ],
    );
  }

  void remove(String itemId) {
    final lines = [
      for (final l in state.lines)
        if (l.item.id != itemId) l,
    ];
    // The last line off the bill takes the customer with it.
    //
    // A named customer used to outlive the lines they were attached to, and
    // the clear-cart action is hidden once the cart is empty, so there was no
    // way to detach them. The next walk-in's bill was then written against
    // that customer's party_id — and if it was taken on udhaar, the debt
    // landed in the wrong khata for real. An empty counter is a new bill.
    state = lines.isEmpty ? const Cart() : state.copyWith(lines: lines);
  }

  /// Sells this line in a different unit, carrying the price with it.
  ///
  /// The quantity is NOT converted: a cashier who switches from pieces to
  /// dozens means "one dozen", not "one twelfth of a dozen". What has to
  /// follow is the price — a hundred rupees a piece is twelve hundred a
  /// dozen — because otherwise the bill silently charges a dozen at the
  /// price of one.
  ///
  /// Refused if the price cannot be carried exactly, which is the same rule
  /// the quantities live by: a unit price that has been rounded will not
  /// reconcile with the line total printed beside it.
  void setUnit(
    String itemId,
    UnitConverter units, {
    required String unitId,
    required String unitCode,
  }) {
    state = state.copyWith(
      lines: [
        for (final l in state.lines)
          if (l.item.id != itemId)
            l
          else
            l.copyWith(
              unitId: unitId,
              unitCode: unitCode,
              rate: units.convertRate(
                l.rate,
                fromUnitId: l.sellingUnitId,
                toUnitId: unitId,
                itemId: itemId,
              ),
            ),
      ],
    );
  }

  void setBillDiscount(Money amount) =>
      state = state.copyWith(billDiscount: amount);

  /// Sells this bill to [party], at their prices; null is a walk-in.
  ///
  /// The customer is usually picked last, at the payment sheet, after every
  /// line is rung. So the lines follow: each one still at the price the
  /// counter set moves to this customer's price and standing discount. A
  /// line whose price or discount the cashier typed is left exactly as
  /// typed — they meant it, and a price that changed under their thumb is
  /// the one they would never notice.
  ///
  /// [units] carries a price into a line sold in another unit. Without it
  /// such a line keeps its price rather than being given a wrong one.
  void setParty(PartySummary? party, {UnitConverter? units}) {
    final tier = party?.priceTier ?? PriceTier.retail;
    final bp = party?.defaultDiscountBp ?? 0;
    final lines = [for (final l in state.lines) _follow(l, tier, bp, units)];
    state = party == null
        ? state.copyWith(
            lines: lines,
            clearParty: true,
            priceTier: tier,
            partyDiscountBp: bp,
          )
        : state.copyWith(
            lines: lines,
            partyId: party.id,
            partyName: party.name,
            priceTier: tier,
            partyDiscountBp: bp,
          );
  }

  CartLine _follow(
    CartLine line,
    PriceTier tier,
    int discountBp,
    UnitConverter? units,
  ) {
    Rate? priced(PriceTier t) {
      final base = priceFor(line.item, t);
      if (!line.isConverted) return base;
      if (units == null) return null;
      try {
        return units.convertRate(
          base,
          fromUnitId: line.item.unitId,
          toUnitId: line.sellingUnitId,
          itemId: line.item.id,
        );
      } on Object {
        return null;
      }
    }

    var out = line;
    final was = priced(state.priceTier);
    final now = priced(tier);
    if (was != null && now != null && line.rate == was) {
      out = out.copyWith(rate: now);
    }
    if (line.explicitDiscount == null &&
        line.discountBp == state.partyDiscountBp) {
      out = out.copyWith(discountBp: discountBp);
    }
    return out;
  }

  void clear() => state = const Cart();

  /// Puts a quotation on the counter to be billed: its lines at the prices
  /// quoted, its customer, and a note of where it came from so the bill is
  /// linked to it. The quoted prices stand even if the shelf price has moved
  /// since; that is what a quotation is.
  void loadQuotation(
    QuotationRow quotation,
    List<(ItemSummary, QuotedLine)> lines, {
    PartySummary? party,
  }) {
    state = Cart(
      lines: [
        for (final (item, q) in lines)
          CartLine(
            item: item,
            qty: q.qty,
            rate: q.rate,
            discountBp: q.discountBp,
            explicitDiscount: q.explicitDiscount,
            unitId: q.unitId == null || q.unitId == item.unitId
                ? null
                : q.unitId,
            unitCode: q.unitId == null || q.unitId == item.unitId
                ? null
                : q.unitCode,
          ),
      ],
      partyId: quotation.partyId,
      partyName: quotation.partyName,
      priceTier: party?.priceTier ?? PriceTier.retail,
      partyDiscountBp: party?.defaultDiscountBp ?? 0,
      sourceId: quotation.id,
      sourceNo: quotation.docNo,
    );
  }
}
