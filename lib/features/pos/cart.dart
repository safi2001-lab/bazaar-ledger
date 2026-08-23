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

  void setBillDiscount(Money amount) =>
      state = state.copyWith(billDiscount: amount);

  void setParty(String? id, String? name) => state = id == null
      ? state.copyWith(clearParty: true)
      : state.copyWith(partyId: id, partyName: name);

  void clear() => state = const Cart();
}
