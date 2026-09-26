import 'package:pk_money/pk_money.dart';

/// One line as the counter entered it, before any calculation.
final class SaleLineDraft {
  const SaleLineDraft({
    required this.itemId,
    required this.itemName,
    required this.qty,
    required this.baseQty,
    required this.unitCode,
    required this.rate,
    this.unitId,
    this.itemCode,
    this.hsCode,
    this.description,
    this.discountBp = 0,
    this.explicitDiscount,
    this.unitCost = Rate.zero,
    this.mrp,
    this.isThirdSchedule = false,
    this.taxRuleId,
    this.lotId,
    this.isFreeItem = false,
    this.tracksStock = true,
  });

  final String itemId;
  final String itemName;
  final String? itemCode;
  final String? hsCode;
  final String? description;

  /// What the cashier typed, in the unit they typed it in.
  final Qty qty;

  /// The same quantity in the item's base unit. Stock moves on this.
  final Qty baseQty;

  final String? unitId;
  final String unitCode;

  /// Milli-paisa per [unitCode].
  final Rate rate;

  /// A percentage discount in basis points.
  final int discountBp;

  /// A discount typed as an amount, which wins over [discountBp] when both are
  /// present — a shopkeeper who says "make it 500" means 500, not 500 rounded
  /// through a percentage.
  final Money? explicitDiscount;

  /// Weighted-average cost per base unit, captured at post time so bill-wise
  /// profit reads what it cost then and not what it costs today.
  final Rate unitCost;

  final Money? mrp;
  final bool isThirdSchedule;
  final String? taxRuleId;
  final String? lotId;

  /// A free item still moves stock and still costs money; it just carries no
  /// revenue.
  final bool isFreeItem;

  final bool tracksStock;

  /// This line, costed at [cost] per base unit.
  SaleLineDraft withUnitCost(Rate cost) => SaleLineDraft(
    itemId: itemId,
    itemName: itemName,
    itemCode: itemCode,
    hsCode: hsCode,
    description: description,
    qty: qty,
    baseQty: baseQty,
    unitId: unitId,
    unitCode: unitCode,
    rate: rate,
    discountBp: discountBp,
    explicitDiscount: explicitDiscount,
    unitCost: cost,
    mrp: mrp,
    isThirdSchedule: isThirdSchedule,
    taxRuleId: taxRuleId,
    lotId: lotId,
    isFreeItem: isFreeItem,
    tracksStock: tracksStock,
  );
}

/// One tender against a sale. A label and an amount, and nothing more.
///
/// There is no payment integration anywhere in this product. The customer pays
/// however they pay — cash in hand, EasyPaisa from their own phone, a card on
/// the bank's own machine — and the money never touches this app. The
/// shopkeeper taps the mode, types the amount and an optional reference, and
/// we post it, exactly as a paper cash book records a mode in a column.
final class TenderDraft {
  const TenderDraft({
    required this.paymentAccountId,
    required this.mode,
    required this.amount,
    this.tendered,
    this.reference,
    this.chequeNo,
    this.chequeBank,
    this.chequeDateUtc,
  });

  final String paymentAccountId;

  /// One of the closed set the schema allows: cash, bank_transfer, jazzcash,
  /// easypaisa, raast, card, cheque, adjustment.
  final String mode;

  final Money amount;

  /// What the customer handed over, when it was cash. Change is the difference.
  final Money? tendered;

  /// Whatever the shopkeeper wants written down — a JazzCash TID, the last
  /// four digits of a card slip, nothing at all. Never verified against
  /// anything, because there is nothing to verify it against.
  final String? reference;

  final String? chequeNo;
  final String? chequeBank;
  final DateTime? chequeDateUtc;

  bool get isCash => mode == 'cash';

  /// Whether this tender went through a banking or digital channel.
  ///
  /// Feeds the s.21(s) check: since the Finance Act 2025, 50% of an
  /// expenditure is disallowed where a single invoice above Rs 200,000 is
  /// settled otherwise than through such a channel.
  bool get isBankingChannel => !isCash && mode != 'adjustment';
}

/// A whole sale as entered, before posting.
final class SaleDraft {
  const SaleDraft({
    required this.lines,
    this.partyId,
    this.partyName,
    this.partyNtn,
    this.partyStrn,
    this.partyAddress,
    this.tenders = const [],
    this.billDiscount = Money.zero,
    this.extraCharges = Money.zero,
    this.roundToRupee = true,
    this.roundingMode = RoundingMode.halfUp,
    this.notes,
    this.salespersonId,
    this.convertedFromId,
  });

  final List<SaleLineDraft> lines;

  /// The quotation (or order) this bill was made from, if any.
  final String? convertedFromId;

  /// A walk-in has no party row at all. That is the common case at a kiryana
  /// counter and must never be an obstacle to billing.
  final String? partyId;
  final String? partyName;
  final String? partyNtn;
  final String? partyStrn;
  final String? partyAddress;

  final List<TenderDraft> tenders;

  /// A discount on the whole bill, apportioned back across the lines.
  final Money billDiscount;

  final Money extraCharges;

  final bool roundToRupee;
  final RoundingMode roundingMode;

  final String? notes;
  final String? salespersonId;

  /// The same draft with [lines] in place of its own.
  SaleDraft withLines(List<SaleLineDraft> lines) => SaleDraft(
    lines: lines,
    partyId: partyId,
    partyName: partyName,
    partyNtn: partyNtn,
    partyStrn: partyStrn,
    partyAddress: partyAddress,
    tenders: tenders,
    billDiscount: billDiscount,
    extraCharges: extraCharges,
    roundToRupee: roundToRupee,
    roundingMode: roundingMode,
    notes: notes,
    salespersonId: salespersonId,
    convertedFromId: convertedFromId,
  );
}
