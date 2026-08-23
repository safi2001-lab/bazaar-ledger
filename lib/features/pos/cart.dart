import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

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
  });

  final ItemSummary item;
  final Qty qty;
  final Rate rate;
  final int discountBp;
  final Money? explicitDiscount;

  Money get gross => rate.amountFor(qty);

  Money get discount =>
      explicitDiscount ?? (discountBp == 0 ? Money.zero : gross.percentBp(discountBp));

  Money get net => gross - discount;

  CartLine copyWith({
    Qty? qty,
    Rate? rate,
    int? discountBp,
    Money? explicitDiscount,
    bool clearExplicitDiscount = false,
  }) =>
      CartLine(
        item: item,
        qty: qty ?? this.qty,
        rate: rate ?? this.rate,
        discountBp: discountBp ?? this.discountBp,
        explicitDiscount:
            clearExplicitDiscount ? null : explicitDiscount ?? this.explicitDiscount,
      );

  SaleLineDraft toDraft() => SaleLineDraft(
        itemId: item.id,
        itemName: item.name,
        itemCode: item.code,
        // M0 sells in the item's own base unit, so the entered quantity and
        // the stock movement are the same number. Multi-unit selling arrives
        // in M1 with the conversion table, and only `baseQty` changes.
        qty: qty,
        baseQty: qty,
        unitId: item.unitId,
        unitCode: item.unitCode,
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
      other.explicitDiscount == explicitDiscount;

  @override
  int get hashCode =>
      Object.hash(item.id, qty, rate, discountBp, explicitDiscount);
}

/// The bill in progress.
final class Cart {
  const Cart({
    this.lines = const [],
    this.partyId,
    this.partyName,
    this.billDiscount = Money.zero,
  });

  final List<CartLine> lines;
  final String? partyId;
  final String? partyName;
  final Money billDiscount;

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
    bool clearParty = false,
  }) =>
      Cart(
        lines: lines ?? this.lines,
        partyId: clearParty ? null : partyId ?? this.partyId,
        partyName: clearParty ? null : partyName ?? this.partyName,
        billDiscount: billDiscount ?? this.billDiscount,
      );
}

final cartProvider = NotifierProvider<CartNotifier, Cart>(CartNotifier.new);

/// Holds the bill in progress.
///
/// Deliberately not auto-disposed. Android Go ROMs kill aggressively and a
/// shopkeeper who walks away mid-bill to fetch a tin of ghee must find the
/// cart exactly as they left it when they come back to the screen.
class CartNotifier extends Notifier<Cart> {
  @override
  Cart build() => const Cart();

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
      lines.add(CartLine(item: item, qty: step, rate: item.saleRate));
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
    state = state.copyWith(
      lines: [
        for (final l in state.lines)
          if (l.item.id != itemId) l,
      ],
    );
  }

  void setBillDiscount(Money amount) =>
      state = state.copyWith(billDiscount: amount);

  void setParty(String? id, String? name) => state = id == null
      ? state.copyWith(clearParty: true)
      : state.copyWith(partyId: id, partyName: name);

  void clear() => state = const Cart();
}
