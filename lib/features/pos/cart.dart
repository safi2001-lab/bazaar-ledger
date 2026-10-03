import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_domain/pk_domain.dart';

import '../../app/providers.dart';
import '../pharmacy/pharmacy_counter.dart';
import '../pharmacy/pharmacy_providers.dart';
import 'cart_draft.dart';
import 'scheme_book.dart';

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
    this.lotIds = const [],
    this.lotLabels = const [],
    this.isLoose = false,
    this.countedInUnitId, // M54
  });

  /// M54: the unit this line was counted in on the screen when it was sold
  /// in it and then moved to the item's own unit — a line sold by the dozen
  /// that a piece was added to. Three dozen and four is forty pieces at the
  /// piece price, exactly (M45), and still reads "3 doz + 4 pcs" to the
  /// cashier who rang it by the dozen. On the screen only: the books get
  /// the forty pieces. Null for every other line; a unit the cashier picks
  /// for the line clears it.
  final String? countedInUnitId;

  /// A loose line (M37): something sold by what the cashier calls it and
  /// what it comes to, with no item in the catalogue behind it.
  ///
  /// Built by [CartLine.loose], whose [item] is a stand-in that exists only
  /// on this bill: its id keys the line on the counter (so two loose lines
  /// can be told apart, stepped and removed like any other) and is never
  /// written anywhere. [toDraft] hands the write path no item at all.
  final bool isLoose;

  /// A loose line: [name] at [rate] a unit, [qty] of them, optionally in one
  /// of the shop's units. [key] tells it apart from the bill's other lines.
  ///
  /// Three decimals, whatever the unit: what was typed is a figure on a
  /// bill, not a count of anything on a shelf, and 0.750 kg of onions is a
  /// thing a kiryana sells all day.
  factory CartLine.loose({
    required String key,
    required String name,
    required Qty qty,
    required Rate rate,
    String? unitId,
    String? unitCode,
  }) => CartLine(
    item: ItemSummary(
      id: key,
      name: name,
      unitId: unitId ?? '',
      unitCode: unitCode ?? '',
      unitDecimals: 3,
      saleRate: rate,
      stockOnHand: Qty.zero,
      tracksStock: false,
    ),
    qty: qty,
    rate: rate,
    isLoose: true,
  );

  final ItemSummary item;

  /// The pieces on this line by serial number, for an item sold by serial:
  /// one lot per piece, [qty] of them.
  final List<String> lotIds;

  /// The serial numbers of [lotIds], for the screen.
  final List<String> lotLabels;

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
    List<String>? lotIds,
    List<String>? lotLabels,
    String? countedInUnitId, // M54
    bool clearCountedIn = false,
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
    lotIds: lotIds ?? this.lotIds,
    lotLabels: lotLabels ?? this.lotLabels,
    isLoose: isLoose,
    countedInUnitId: clearCountedIn
        ? null
        : countedInUnitId ?? this.countedInUnitId, // M54
  );

  /// The line as the write path wants it: one line per serial number when
  /// the pieces were scanned one by one, so each leaves its own lot.
  List<SaleLineDraft> toDrafts([UnitConverter? units]) {
    if (lotIds.isEmpty) return [toDraft(units)];
    final discounts = explicitDiscount?.split(lotIds.length);
    return [
      for (var i = 0; i < lotIds.length; i++)
        SaleLineDraft(
          itemId: item.id,
          itemName: item.name,
          itemCode: item.code,
          hsCode: item.hsCode,
          description: lotLabels.length > i ? 'Serial ${lotLabels[i]}' : null,
          qty: Qty.one,
          baseQty: Qty.one,
          unitId: item.unitId,
          unitCode: item.unitCode,
          rate: rate,
          discountBp: discountBp,
          explicitDiscount: discounts?[i],
          tracksStock: item.tracksStock,
          lotId: lotIds[i],
          // M59: taxed on the printed price, or by the province.
          mrp: item.mrp,
          isThirdSchedule: item.isThirdSchedule,
          isService: item.isService,
        ),
    ];
  }

  /// The line as the write path wants it.
  ///
  /// [units] converts the entered quantity into the item's base unit, which
  /// is the only thing stock moves in. A line sold in the item's own unit
  /// needs no converter at all, which is why one is optional — the counter
  /// must not stop selling pieces because the conversion table failed to
  /// load.
  SaleLineDraft toDraft([UnitConverter? units]) =>
      isLoose ? _looseDraft() : _itemDraft(units);

  SaleLineDraft _itemDraft(UnitConverter? units) => SaleLineDraft(
    itemId: item.id,
    itemName: item.name,
    itemCode: item.code,
    // On the bill line, so a registered shop's invoice carries it to FBR.
    hsCode: item.hsCode,
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
    // M59: taxed on the printed price, or by the province.
    mrp: item.mrp,
    isThirdSchedule: item.isThirdSchedule,
    isService: item.isService,
  );

  /// A loose line goes to the books with no item, no stock to move and no
  /// cost (M37): what it is called, what was typed, and the shop's unit if
  /// one was picked.
  SaleLineDraft _looseDraft() => SaleLineDraft(
    itemId: null,
    itemName: item.name,
    qty: qty,
    baseQty: qty,
    unitId: item.unitId.isEmpty ? null : item.unitId,
    unitCode: item.unitCode,
    rate: rate,
    discountBp: discountBp,
    explicitDiscount: explicitDiscount,
    tracksStock: false,
  );

  @override
  bool operator ==(Object other) =>
      other is CartLine &&
      other.item.id == item.id &&
      other.qty == qty &&
      other.rate == rate &&
      other.discountBp == discountBp &&
      other.explicitDiscount == explicitDiscount &&
      other.unitId == unitId &&
      other.countedInUnitId == countedInUnitId; // M54

  @override
  int get hashCode => Object.hash(
    item.id,
    qty,
    rate,
    discountBp,
    explicitDiscount,
    unitId,
    countedInUnitId, // M54
  );
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
    this.sourceType, // M54
    this.alsoSourceIds = const [],
    this.replacesId,
    this.replacesNo,
    this.paidBefore,
    this.copiedFromNo,
    this.copyNote,
    this.bonusWaived = const {},
    this.slabWaived = false,
    this.recurring, // M63
    this.sentBonus, // M54
    this.partyPrices, // M66
    this.loyalty, // M66
  });

  // M66 -------------------------------------------------------------------

  /// The named customer's own prices (party_prices.dart), read when they
  /// were picked; null for a walk-in, or while they are being read. The
  /// counter prices a line from it before their tier and the item's slabs.
  final PartyPrices? partyPrices;

  /// The customer's points used on this bill, chosen on the payment sheet:
  /// part of the bill's discount ([forBooks]), checked against their points
  /// and kept in the bill's own commit. A different customer takes it off.
  final LoyaltyRedemption? loyalty;

  /// [line]'s customer's own price carried into the unit it is sold in, or
  /// null when they have none for it, or it does not carry exactly.
  Rate? ownRateFor(CartLine line, UnitConverter? units) {
    if (line.isLoose) return null;
    final own = partyPrices?.rateFor(line.item.id);
    if (own == null || !line.isConverted) return own;
    if (units == null) return null;
    try {
      return units.convertRate(
        own,
        fromUnitId: line.item.unitId,
        toUnitId: line.sellingUnitId,
        itemId: line.item.id,
      );
    } on Object {
      return null;
    }
  }

  /// Whether [line] is at its customer's own price: "Haji Sahib ka rate".
  bool atOwnRate(CartLine line, UnitConverter? units) {
    final own = ownRateFor(line, units);
    return own != null && own == line.rate;
  }

  /// M54: the bonus the challans on the counter sent with their goods, as
  /// they sent it — null for every other bill.
  ///
  /// A challan's goods have gone, free ones included, and the bill made
  /// from it must be for exactly what went (M25), so the shop's schemes are
  /// not worked out again for it: a scheme changed between the challan and
  /// the bill used to give a different bonus here, and the bill was refused
  /// in the challan's words. Now the challan's free lines stand, as its
  /// paid lines and their prices do; the cashier sees them under the lines
  /// and cannot take them off, because they are already at the customer's.
  final List<SaleLineDraft>? sentBonus;

  /// M63: the repeating bill this one is, and the day it is for. The sale
  /// moves the template on in its own commit (recurring_services.dart). A
  /// different customer named on the counter makes it an ordinary bill.
  final RecurringMark? recurring;

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

  /// M54: what [sourceId] is — `quotation`, `delivery_challan` or
  /// `sale_order` — so the payment sheet can offer what that paper may
  /// become. Null for a bill made from nothing, and for a draft written
  /// before M54, which the sheet reads as it read every loaded paper then.
  final String? sourceType;

  /// M54: a sale order (M41) on the counter. It may be billed, or sent
  /// ahead of the bill on a challan that takes its advance with it.
  bool get fromSaleOrder => sourceType == 'sale_order';

  /// More challans billed on this one bill with [sourceId] (M25).
  final List<String> alsoSourceIds;

  /// The cancelled bill this one puts right (M36), and its number. The
  /// sale links the two when it posts.
  final String? replacesId;
  final String? replacesNo;

  /// What the customer had paid on [replacesId] at the counter, which the
  /// payment sheet starts from (M36). Null for every other bill.
  final PaidBefore? paidBefore;

  /// The bill this one was copied from (M36), and what of it did not come
  /// onto the counter, in words — shown at the head of the lines until the
  /// cashier waves it away. On screen only: not kept in the draft, because
  /// it is news about the moment of copying, not part of the bill.
  final String? copiedFromNo;
  final String? copyNote;

  // M43 -------------------------------------------------------------------
  //
  // The shop's schemes on this bill (schemes.dart). The bonus and the bill
  // slab are never lines or figures the cart holds: they are worked out
  // from the lines every time, so they cannot fall out of step with what
  // was rung — ten soaps earn the free one, nine take it back off. All the
  // cart keeps is what the cashier took off.

  /// The items whose bonus the cashier took off this bill. Taking a bonus
  /// off gives less away, so any cashier may.
  final Set<String> bonusWaived;

  /// Whether the cashier took the shop's bill-value discount off this bill.
  final bool slabWaived;

  /// The bill as it goes to the books: every line rung, the bonus each
  /// item's scheme gives under the last line of that item, and the bill
  /// discount — the one typed, or else the shop's slab for a bill this big.
  ///
  /// M66: with [points], the customer's points chosen on the payment sheet
  /// are added to the bill discount. A quotation or a challan kept from the
  /// payment sheet is not given them: points are spent on a bill.
  ({List<SaleLineDraft> lines, Money billDiscount, BillSlab? slab}) forBooks(
    UnitConverter? units,
    SchemeBook book, {
    bool points = true, // M66
  }) {
    final rung = [for (final l in lines) ...l.toDrafts(units)];
    // M54: a bill made from challans gives the bonus they sent, as sent.
    final bonus = sentBonus == null
        ? bonusOn(rung, book)
        : const <BonusGrant>[];
    final out = <SaleLineDraft>[];
    if (sentBonus case final sent?) {
      final last = <String, int>{
        for (var i = 0; i < rung.length; i++) ?rung[i].itemId: i,
      };
      for (var i = 0; i < rung.length; i++) {
        out.add(rung[i]);
        for (final f in sent) {
          if (last[f.itemId] == i) out.add(f);
        }
      }
      // A free item none of the bill's paid lines are of, at the foot.
      out.addAll(sent.where((f) => !last.containsKey(f.itemId)));
    } else if (bonus.isEmpty) {
      out.addAll(rung);
    } else {
      final last = <String, int>{
        for (var i = 0; i < rung.length; i++) ?rung[i].itemId: i,
      };
      for (var i = 0; i < rung.length; i++) {
        out.add(rung[i]);
        for (final g in bonus) {
          if (last[g.forItemId] == i) out.add(g.toLine());
        }
      }
    }
    // M66: the customer's points, on top of whatever else came off.
    final spent = points ? pointsOff : Money.zero;
    if (billDiscount.isPositive || slabWaived) {
      return (lines: out, billDiscount: billDiscount + spent, slab: null);
    }
    final hit = book.billSlabFor(SchemeBook.billValueOf(rung));
    return (
      lines: out,
      billDiscount: (hit?.discount ?? billDiscount) + spent,
      slab: hit?.slab,
    );
  }

  /// M66: what the points chosen take off, for this bill's customer only.
  Money get pointsOff => switch (loyalty) {
    final l? when partyId != null && l.partyId == partyId => l.value,
    _ => Money.zero,
  };

  /// The bonus [rung] earns, less what the cashier took off.
  List<BonusGrant> bonusOn(List<SaleLineDraft> rung, SchemeBook book) => [
    for (final g in book.bonusFor(SchemeBook.paidBaseOf(rung)))
      if (!bonusWaived.contains(g.forItemId)) g,
  ];

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
    bool clearCopyNote = false,
    Set<String>? bonusWaived,
    bool? slabWaived,
    PartyPrices? partyPrices, // M66
    LoyaltyRedemption? loyalty,
    bool clearLoyalty = false,
  }) => Cart(
    sourceId: sourceId,
    sourceNo: sourceNo,
    sourceType: sourceType, // M54
    alsoSourceIds: alsoSourceIds,
    replacesId: replacesId,
    replacesNo: replacesNo,
    paidBefore: paidBefore,
    copiedFromNo: clearCopyNote ? null : copiedFromNo,
    copyNote: clearCopyNote ? null : copyNote,
    lines: lines ?? this.lines,
    partyId: clearParty ? null : partyId ?? this.partyId,
    partyName: clearParty ? null : partyName ?? this.partyName,
    billDiscount: billDiscount ?? this.billDiscount,
    priceTier: priceTier ?? this.priceTier,
    partyDiscountBp: partyDiscountBp ?? this.partyDiscountBp,
    bonusWaived: bonusWaived ?? this.bonusWaived,
    slabWaived: slabWaived ?? this.slabWaived,
    recurring: clearParty || (partyId != null && partyId != this.partyId)
        ? null
        : recurring, // M63
    sentBonus: sentBonus, // M54
    // M66: a customer's prices and points are theirs alone; another
    // customer, or none, takes both off the bill.
    partyPrices: clearParty || (partyId != null && partyId != this.partyId)
        ? partyPrices
        : partyPrices ?? this.partyPrices,
    loyalty:
        clearLoyalty ||
            clearParty ||
            (partyId != null && partyId != this.partyId)
        ? loyalty
        : loyalty ?? this.loyalty,
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
    // M49: a pharmacy's standing "% off MRP", loaded before the first line
    // goes on, so the first line is priced like the rest.
    ref.listen(pharmacyRulesProvider, (_, _) {});

    // M43: a scheme read or changed while lines are on the counter moves
    // the lines still at the counter's own price to the new one.
    ref.listen<AsyncValue<SchemeBook>>(schemeBookProvider, (was, now) {
      final before = was?.valueOrNull ?? SchemeBook.empty;
      final after = now.valueOrNull;
      // M54: not on a bill made from challans, whose prices are as sent.
      if (after != null &&
          !identical(before, after) &&
          state.sentBonus == null) {
        _schemesChanged(before, after);
      }
    });

    // M66: a bill brought back with a customer on it reads their own prices
    // again, for the lines rung from now; the lines already rung keep theirs.
    if (restored?.partyId case final id?) {
      unawaited(Future<void>(() => _readOwnPrices(id, reprice: false)));
    }

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
      final was = lines[index];
      lines[index] = _repriced(was, was.copyWith(qty: was.qty + step)); // M43
    } else {
      // M43: the customer's price, or the item's slab for this many. M66:
      // their own price before either, with no standing discount on it.
      final priced = _priceOf(item, step);
      lines.add(
        CartLine(
          item: item,
          qty: step,
          rate: priced.rate,
          discountBp: priced.source == PriceSource.party
              ? 0
              : state.partyDiscountBp,
        ),
      );
      if (priced.source != PriceSource.party) {
        lines.last = _offMrp(lines.last); // M49
      }
    }
    state = state.copyWith(lines: lines);
  }

  // M49: a new line of an item with a printed price, at the shop's "% off
  // MRP" when it is a pharmacy that has one (pharmacy_counter.dart).
  CartLine _offMrp(CartLine line) =>
      offMrpDefault(line, ref.read(pharmacyRulesProvider).valueOrNull);

  // M49: "% off MRP" typed on one line: a percentage, not an amount.
  void setDiscountBp(String itemId, int bp) {
    state = state.copyWith(
      lines: [
        for (final l in state.lines)
          if (l.item.id == itemId)
            l.copyWith(discountBp: bp, clearExplicitDiscount: true)
          else
            l,
      ],
    );
  }

  /// Puts a loose line on the bill (M37): [name] at [rate], [qty] of it.
  ///
  /// The same thing at the same price in the same unit again is more of it,
  /// as a second scan of a barcode is — two kilos of onions rung as one and
  /// one are one line of two. It also keeps a return honest: a loose line is
  /// known on its way back by its name, price and unit, and two lines alike
  /// in all three could not be told apart.
  ///
  /// It takes no standing discount: the customer's discount is off the
  /// shop's own prices, and this price is the one the cashier just typed.
  void addLoose({
    required String name,
    required Qty qty,
    required Rate rate,
    String? unitId,
    String? unitCode,
  }) {
    final lines = [...state.lines];
    final index = lines.indexWhere(
      (l) =>
          l.isLoose &&
          l.item.name == name &&
          l.item.unitId == (unitId ?? '') &&
          l.rate == rate,
    );
    if (index >= 0) {
      lines[index] = lines[index].copyWith(qty: lines[index].qty + qty);
    } else {
      // A key no other line on this bill has. Counted up from the highest
      // in use rather than from how many there are, so removing the first
      // loose line and adding another never gives two lines one key.
      var next = 1;
      for (final l in lines) {
        if (!l.isLoose || !l.item.id.startsWith(_looseKey)) continue;
        final n = int.tryParse(l.item.id.substring(_looseKey.length)) ?? 0;
        if (n >= next) next = n + 1;
      }
      lines.add(
        CartLine.loose(
          key: '$_looseKey$next',
          name: name,
          qty: qty,
          rate: rate,
          unitId: unitId,
          unitCode: unitCode,
        ),
      );
    }
    state = state.copyWith(lines: lines);
  }

  static const _looseKey = 'loose-';

  void setQty(String itemId, Qty qty) {
    if (!qty.isPositive) {
      remove(itemId);
      return;
    }
    state = state.copyWith(
      lines: [
        for (final l in state.lines)
          l.item.id != itemId
              ? l
              : l.lotIds.isEmpty
              ? _repriced(l, l.copyWith(qty: qty)) // M43
              // A line of scanned pieces only shrinks, dropping the last
              // scanned; more pieces are more scans.
              : () {
                  final keep = qty.inThousandths ~/ 1000;
                  if (keep >= l.lotIds.length) return l;
                  return l.copyWith(
                    qty: Qty.units(keep),
                    lotIds: l.lotIds.sublist(0, keep),
                    lotLabels: l.lotLabels.take(keep).toList(),
                  );
                }(),
      ],
    );
  }

  /// Adds one piece of [item] by its serial number. Returns false when that
  /// piece is already on the bill.
  bool addSerial(
    ItemSummary item, {
    required String lotId,
    required String serial,
  }) {
    final index = state.lines.indexWhere((l) => l.item.id == item.id);
    final lines = [...state.lines];
    if (index >= 0) {
      final line = lines[index];
      if (line.lotIds.contains(lotId)) return false;
      lines[index] = _repriced(
        line,
        line.copyWith(
          qty: Qty.units(line.lotIds.length + 1),
          lotIds: [...line.lotIds, lotId],
          lotLabels: [...line.lotLabels, serial],
        ),
      ); // M43
    } else {
      final priced = _priceOf(item, Qty.one); // M43, M66
      lines.add(
        CartLine(
          item: item,
          qty: Qty.one,
          rate: priced.rate,
          discountBp: priced.source == PriceSource.party
              ? 0
              : state.partyDiscountBp,
          lotIds: [lotId],
          lotLabels: [serial],
        ),
      );
      if (priced.source != PriceSource.party) {
        lines.last = _offMrp(lines.last); // M49
      }
    }
    state = state.copyWith(lines: lines);
    return true;
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

  // M45: the line as the cashier counted it ("2 ctn 5" on a carton line),
  // remade in counted_line.dart: in pieces, its price carried there.
  void setCounted(CartLine line) => state = state.copyWith(
    lines: [for (final l in state.lines) l.item.id == line.item.id ? line : l],
  );

  // M53: the line put back as it last stood within the shelf, or taken off
  // when it never did — what the counter does when the shelf says no
  // (shelf_guard.dart).
  void putBack(String itemId, CartLine? before) {
    final lines = [
      for (final l in state.lines)
        if (l.item.id != itemId) l else ?before,
    ];
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
            _repriced(
              l,
              l.copyWith(
                unitId: unitId,
                unitCode: unitCode,
                clearCountedIn: true, // M54: the unit picked is the count
                rate: units.convertRate(
                  l.rate,
                  fromUnitId: l.sellingUnitId,
                  toUnitId: unitId,
                  itemId: itemId,
                ),
              ),
              units: units,
            ), // M43
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
    // M66: the same customer keeps their own prices; another's are read
    // below, and the lines move to them once they are.
    final same = party != null && party.id == state.partyId;
    final own = same ? state.partyPrices : null;
    final lines = [
      for (final l in state.lines) _follow(l, tier, bp, units, own),
    ];
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
    if (party != null && !same) {
      unawaited(_readOwnPrices(party.id, units: units)); // M66
    }
  }

  CartLine _follow(
    CartLine line,
    PriceTier tier,
    int discountBp,
    UnitConverter? units,
    PartyPrices? own, // M66
  ) {
    // A loose line (M37) is at the price the cashier typed, which is not on
    // any price list to move along.
    if (line.isLoose) return line;
    // M43: the tier's price, or the item's slab where that is lower. M66:
    // the customer's own price before both, as it stands before and after.
    final was = _counterRate(
      line,
      tier: state.priceTier,
      units: units,
      own: state.partyPrices,
    );
    final now = _counterRate(line, tier: tier, units: units, own: own);

    var out = line;
    final moves = was != null && now != null && line.rate == was;
    if (moves) out = out.copyWith(rate: now);
    // M66: a line at its customer's own price carries no standing discount,
    // so the discount that follows is the one the line's price wants.
    final wasOwn = state.partyPrices?.rateFor(line.item.id) != null && moves;
    final nowOwn = own?.rateFor(line.item.id) != null && moves;
    final standingWas = wasOwn ? 0 : state.partyDiscountBp;
    if (line.explicitDiscount == null && line.discountBp == standingWas) {
      out = out.copyWith(discountBp: nowOwn ? 0 : discountBp);
    }
    return out;
  }

  // M66 -------------------------------------------------------------------

  /// What a new line of [item], [baseQty] of it, is priced at, and why.
  ({Rate rate, PriceSource source}) _priceOf(ItemSummary item, Qty baseQty) =>
      counterPrice(
        item,
        tier: state.priceTier,
        baseQty: baseQty,
        book: schemesNow(ref),
        own: state.partyPrices,
      );

  /// Reads [partyId]'s own prices and, while they are still the bill's
  /// customer, moves each line still at the counter's price to them. With
  /// [reprice] false (a quotation or a bill read back, whose prices stand)
  /// only the next lines rung take them.
  Future<void> _readOwnPrices(
    String partyId, {
    UnitConverter? units,
    bool reprice = true,
  }) async {
    final PartyPrices prices;
    try {
      prices = await ref.read(appServicesProvider).loyalty.pricesOf(partyId);
    } on Object {
      // Not read is no own prices: the tier and the slabs price the bill,
      // as they did before M66.
      return;
    }
    if (state.partyId != partyId) return;
    if (!reprice) {
      state = state.copyWith(partyPrices: prices);
      return;
    }
    ownPricesChanged(prices, units: units);
  }

  /// The customer's own prices are now [prices]: read, or one set from the
  /// counter. Each line still at the counter's price moves to the new one,
  /// its standing discount following (none on their own price).
  void ownPricesChanged(PartyPrices prices, {UnitConverter? units}) {
    if (state.partyId != prices.partyId) return;
    final before = state.partyPrices;
    final lines = [
      for (final l in state.lines)
        if (l.isLoose)
          l
        else
          () {
            final was = _counterRate(l, units: units, own: before);
            final now = _counterRate(l, units: units, own: prices);
            if (was == null || now == null || l.rate != was || now == was) {
              return l;
            }
            final wasOwn = before?.rateFor(l.item.id) != null;
            final nowOwn = prices.rateFor(l.item.id) != null;
            var out = l.copyWith(rate: now);
            if (l.explicitDiscount == null) {
              if (!wasOwn && nowOwn && l.discountBp == state.partyDiscountBp) {
                out = out.copyWith(discountBp: 0);
              } else if (wasOwn && !nowOwn && l.discountBp == 0) {
                out = out.copyWith(discountBp: state.partyDiscountBp);
              }
            }
            return out;
          }(),
    ];
    state = state.copyWith(lines: lines, partyPrices: prices);
  }

  /// The customer's points used on this bill, or none.
  void setLoyalty(LoyaltyRedemption? redeem) => state = redeem == null
      ? state.copyWith(clearLoyalty: true)
      : state.copyWith(loyalty: redeem);

  // M43 -------------------------------------------------------------------

  /// What the counter charges for [line] as it stands, in the unit it is
  /// sold in: the customer's tier price, or the item's quantity slab for
  /// what the line takes off the shelf where that is lower. Null when the
  /// price cannot be carried into the line's unit exactly.
  Rate? _counterRate(
    CartLine line, {
    PriceTier? tier,
    SchemeBook? book,
    UnitConverter? units,
    PartyPrices? own, // M66: the customer's own prices, when they have any
  }) {
    final converter = units ?? ref.read(unitConverterProvider).valueOrNull;
    final Qty base;
    if (!line.isConverted) {
      base = line.qty;
    } else {
      if (converter == null) return null;
      try {
        base = converter.convert(
          line.qty,
          fromUnitId: line.sellingUnitId,
          toUnitId: line.item.unitId,
          itemId: line.item.id,
        );
      } on Object {
        return null;
      }
    }
    final perBase = counterPrice(
      line.item,
      tier: tier ?? state.priceTier,
      baseQty: base,
      book: book ?? schemesNow(ref),
      own: own, // M66
    ).rate;
    if (!line.isConverted) return perBase;
    try {
      return converter!.convertRate(
        perBase,
        fromUnitId: line.item.unitId,
        toUnitId: line.sellingUnitId,
        itemId: line.item.id,
      );
    } on Object {
      return null;
    }
  }

  /// [after] is [before] with more or less of it, or in another unit. When
  /// [before] was at the counter's own price, [after] moves to the
  /// counter's price for what it now is — twelve pieces reach the dozen
  /// slab, eleven go back above it. A price the cashier typed is left as
  /// typed, as the customer's tier leaves it (setParty). An item with no
  /// slab is never touched, so a shop without schemes rings exactly as it
  /// did.
  CartLine _repriced(CartLine before, CartLine after, {UnitConverter? units}) {
    if (before.isLoose) return after;
    if (!schemesNow(ref).slabs.containsKey(before.item.id)) return after;
    final own = state.partyPrices; // M66
    final was = _counterRate(before, units: units, own: own);
    if (was == null || before.rate != was) return after;
    final now = _counterRate(after, units: units, own: own);
    return now == null ? after : after.copyWith(rate: now);
  }

  void _schemesChanged(SchemeBook before, SchemeBook after) {
    var moved = false;
    final lines = [
      for (final l in state.lines)
        if (l.isLoose ||
            (!before.slabs.containsKey(l.item.id) &&
                !after.slabs.containsKey(l.item.id)))
          l
        else
          () {
            final was = _counterRate(
              l,
              book: before,
              own: state.partyPrices, // M66
            );
            final now = _counterRate(l, book: after, own: state.partyPrices);
            if (was == null || now == null || l.rate != was || now == was) {
              return l;
            }
            moved = true;
            return l.copyWith(rate: now);
          }(),
    ];
    if (moved) state = state.copyWith(lines: lines);
  }

  /// Takes [itemId]'s bonus off this bill, or puts it back.
  void setBonusWaived(String itemId, {required bool waived}) =>
      state = state.copyWith(
        bonusWaived: waived
            ? {...state.bonusWaived, itemId}
            : ({...state.bonusWaived}..remove(itemId)),
      );

  /// Takes the shop's bill-value discount off this bill, or puts it back.
  void setSlabWaived({required bool waived}) =>
      state = state.copyWith(slabWaived: waived);

  void clear() => state = const Cart();

  /// Puts a quotation on the counter to be billed: its lines at the prices
  /// quoted, its customer, and a note of where it came from so the bill is
  /// linked to it. The quoted prices stand even if the shelf price has moved
  /// since; that is what a quotation is.
  void loadQuotation(
    QuotationRow quotation,
    List<(ItemSummary, QuotedLine)> lines, {
    PartySummary? party,
    List<QuotationRow> alsoFrom = const [],
    List<SaleLineDraft>? sentBonus, // M54
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
      sourceNo: [quotation.docNo, for (final q in alsoFrom) q.docNo].join(', '),
      sourceType: quotation.docType, // M54
      alsoSourceIds: [for (final q in alsoFrom) q.id],
      // M54: a challan's bonus as it went; none for any other paper, whose
      // bonus the counter works out from the shop's schemes as for any bill.
      sentBonus: quotation.isChallan ? (sentBonus ?? const []) : null,
    );
    // M66: the quoted prices stand; a line added takes their own price.
    if (quotation.partyId case final id?) {
      unawaited(_readOwnPrices(id, reprice: false));
    }
  }

  /// Puts a bill read back on the counter as a new bill (M36): its lines,
  /// already priced the way the cashier chose, and its customer at their
  /// prices today.
  ///
  /// [replacesId] and [paidBefore] are for a bill being put right: the
  /// cancelled bill it replaces, and the money the customer had already
  /// handed over for it, which the payment sheet starts from. Both survive
  /// the app being killed (the draft is v5 for them).
  void loadCopy(
    List<CartLine> lines, {
    PartySummary? party,
    Money billDiscount = Money.zero,
    String? replacesId,
    String? replacesNo,
    PaidBefore? paidBefore,
    String? copiedFromNo,
    String? copyNote,
    RecurringMark? recurring, // M63
  }) {
    state = Cart(
      lines: lines,
      partyId: party?.id,
      partyName: party?.name,
      billDiscount: billDiscount,
      priceTier: party?.priceTier ?? PriceTier.retail,
      partyDiscountBp: party?.defaultDiscountBp ?? 0,
      replacesId: replacesId,
      replacesNo: replacesNo,
      paidBefore: replacesId == null ? null : paidBefore,
      copiedFromNo: copiedFromNo,
      copyNote: copyNote,
      recurring: party == null ? null : recurring, // M63
    );
    // M66: the bill's prices stand; a line added takes their own price.
    if (party != null) unawaited(_readOwnPrices(party.id, reprice: false));
  }

  /// Waves away the note about where the bill was copied from (M36).
  void dismissCopyNote() => state = state.copyWith(clearCopyNote: true);
}
