/// "Das kilo ghee de diya, rate baad mein" (M55).
///
/// In a mandi, and in a kiryana that keeps households on a salary-day khata,
/// goods go out on the word: ten kilos of ghee, a bori of atta, the price to
/// be settled when the customer comes to settle. DigiKhata's users asked for
/// a khata line with a quantity and no amount, priced at settlement.
///
/// ## Why this is a delivery challan, and not a new kind of line
///
/// The books already had a document for exactly this: the delivery challan
/// (M25). Goods leave the shelf on it and wait in Goods on Challan at what
/// they cost — still the shop's asset, owed by nobody — and the bill made
/// from it later moves them to Cost of Goods Sold without moving any stock a
/// second time, carrying the cost across to the paisa. Several challans to
/// one customer are billed together on one bill. The only thing a challan
/// had that this does not is a price, and a challan line priced at nothing
/// is precisely "rate baad mein".
///
/// So goods given rate-later are a challan whose lines carry no rate, and
/// nothing else is invented: no column, no new document type, no second
/// path from the shelf to the khata. A challan line at no rate that is not
/// a free item is goods given with the rate still to be agreed. It owes
/// nothing — a challan's balance is nothing, so no khata query can read it
/// as udhaar — and the khata shows it apart, by its quantities, until the
/// rate is put on it. Putting the rate on is billing the challan, through
/// the counter, at the prices agreed then (M25's path, unchanged).
///
/// A challan the counter priced is goods given with the bill still to come;
/// the khata lists it beside these, with its value, because a customer
/// holding forty cartons on a challan is told about them the same way.
library;

import 'package:pk_money/pk_money.dart';

import '../sales/sale_draft.dart';

/// One line of goods handed over: what, how much, and at what rate if any.
final class GoodsGivenLine {
  const GoodsGivenLine({
    required this.itemId,
    required this.itemName,
    required this.qty,
    required this.unitCode,
    required this.rate,
    this.unitId,
    this.isFree = false,
    this.discountBp = 0,
    this.discount = Money.zero,
  });

  final String itemId;
  final String itemName;

  /// As given, in the unit it was given in.
  final Qty qty;
  final String? unitId;
  final String unitCode;

  /// Per [unitCode]. Nothing on a line given rate-later.
  final Rate rate;

  /// A free item carries no rate on purpose, and is not waiting for one.
  final bool isFree;

  /// The line's own discount, kept so a priced challan billed again keeps it.
  final int discountBp;
  final Money discount;

  /// Given with the rate still to be agreed.
  bool get isUnpriced => rate.isZero && !isFree;

  /// What the line comes to at its own rate; nothing while unpriced.
  Money get amount => isFree ? Money.zero : rate.amountFor(qty) - discount;
}

/// One challan to a customer not yet billed: goods on the khata, not money.
final class GoodsGiven {
  const GoodsGiven({
    required this.challanId,
    required this.docNo,
    required this.dateLocal,
    required this.lines,
    this.partyId,
    this.partyName,
    this.notes,
  });

  final String challanId;
  final String docNo;

  /// The shop's own day the goods left, `YYYY-MM-DD`.
  final String dateLocal;

  final String? partyId;
  final String? partyName;
  final String? notes;
  final List<GoodsGivenLine> lines;

  /// Lines still waiting for a rate.
  int get unpricedCount => lines.where((l) => l.isUnpriced).length;

  /// Whether any line on it is waiting for a rate.
  bool get waitsForRate => unpricedCount > 0;

  /// What the priced lines come to. Not owed: a challan owes nothing until
  /// it is billed.
  Money get pricedValue => Money.sum([for (final l in lines) l.amount]);
}

/// A customer with goods given and no rate on them yet, for the chase list.
final class UnpricedParty {
  const UnpricedParty({
    required this.partyId,
    required this.partyName,
    required this.lines,
    required this.challans,
    required this.oldestLocal,
  });

  final String partyId;
  final String partyName;

  /// Lines given rate-later, across every challan of theirs not yet billed.
  final int lines;
  final int challans;

  /// The day the oldest of them went.
  final String oldestLocal;
}

/// [draft] as goods handed over with no price: every line at no rate and no
/// discount, the bill's discount and charges dropped.
///
/// The quantities, the units, the items and where they leave from are
/// untouched, because those are what the challan is a record of; the price
/// is what is not known yet. A free item stays free.
SaleDraft rateLater(SaleDraft draft) => SaleDraft(
  lines: [
    for (final l in draft.lines)
      SaleLineDraft(
        itemId: l.itemId,
        itemName: l.itemName,
        itemCode: l.itemCode,
        hsCode: l.hsCode,
        description: l.description,
        qty: l.qty,
        baseQty: l.baseQty,
        unitId: l.unitId,
        unitCode: l.unitCode,
        rate: Rate.zero,
        unitCost: l.unitCost,
        mrp: l.mrp,
        isThirdSchedule: l.isThirdSchedule,
        taxRuleId: l.taxRuleId,
        lotId: l.lotId,
        isFreeItem: l.isFreeItem,
        tracksStock: l.tracksStock,
      ),
  ],
  partyId: draft.partyId,
  partyName: draft.partyName,
  partyNtn: draft.partyNtn,
  partyStrn: draft.partyStrn,
  partyAddress: draft.partyAddress,
  roundToRupee: draft.roundToRupee,
  roundingMode: draft.roundingMode,
  notes: draft.notes,
  salespersonId: draft.salespersonId,
  locationCode: draft.locationCode,
);
