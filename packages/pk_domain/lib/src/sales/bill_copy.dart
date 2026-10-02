/// A bill read back so the counter can ring it again (M36).
///
/// A wholesaler's customer sends the same list every Thursday, and a bill
/// with one wrong price on it is thirty lines that were right. Neither should
/// be typed twice. This is the bill as the counter needs it to start again:
/// what was sold, in the unit it was sold in, at what, to whom, and — for a
/// bill being put right — what money the customer had already handed over.
///
/// It is a read, never a write. Ringing a bill again makes a NEW bill with a
/// new number through the ordinary sale path, with every check the counter
/// makes; nothing here touches the bill it was read from, which stays exactly
/// as it was printed.
library;

import 'package:pk_money/pk_money.dart';

import '../tax/tax_charge.dart';
import 'sale_calculator.dart';
import 'sale_draft.dart';

/// One sale bill, as the counter needs it to ring it again.
final class BillCopy {
  const BillCopy({
    required this.documentId,
    required this.docNo,
    required this.isVoid,
    required this.lines,
    this.partyId,
    this.partyName,
    this.billDiscount = Money.zero,
    this.roundingMode = RoundingMode.halfUp,
    this.tenders = const [],
  });

  final String documentId;
  final String docNo;

  /// Cancelled. A cancelled bill can be copied too — myBillBook and Swipe
  /// both allow it, and "the bill I cancelled by mistake" is exactly the one
  /// a shopkeeper wants back.
  final bool isVoid;

  final String? partyId;
  final String? partyName;

  /// In the order they were printed.
  final List<BillCopyLine> lines;

  /// The discount typed on the whole bill, as the bill stored it.
  final Money billDiscount;

  /// How the bill rounded, stamped on it when it was posted.
  final RoundingMode roundingMode;

  /// The money taken at the counter with the bill, still standing: the
  /// tenders the sale wrote for itself, never a receipt taken later against
  /// the khata (a bill with one of those cannot be cancelled at all).
  final List<BillCopyTender> tenders;

  /// What the customer had paid on this bill at the counter.
  PaidBefore get paidBefore => PaidBefore.of(tenders);
}

/// One printed line.
final class BillCopyLine {
  const BillCopyLine({
    required this.itemId,
    required this.name,
    required this.qty,
    required this.unitCode,
    required this.rate,
    this.unitId,
    this.discountBp = 0,
    this.discount = Money.zero,
    this.lotId,
    this.lotNo,
    this.isFree = false,
    this.itemGone = false,
  });

  /// The item sold, or null for khula maal (M37), which comes back as what
  /// the cashier called it and what it came to.
  final String? itemId;

  /// What the line said on the bill.
  final String name;

  /// As billed, in the unit billed: two maunds is two, not eighty kilos.
  final Qty qty;
  final String? unitId;
  final String unitCode;

  /// Per [unitCode].
  final Rate rate;

  /// The line's discount as a percentage, when it was one.
  final int discountBp;

  /// Everything that came off this line as the bill STORED it: its own
  /// discount and its share of the bill's (M57's "what the bill stored").
  /// [discountsAsBilled] takes the two apart again.
  final Money discount;

  /// The piece sold, for an item sold by serial number, and its number.
  final String? lotId;
  final String? lotNo;

  /// A line given free. The counter has no free lines, so it is not rung
  /// again; the shopkeeper is told so.
  final bool isFree;

  /// The item has been archived or deleted since. The counter would not
  /// offer it, so a copy does not slip it back on a bill.
  final bool itemGone;

  bool get isLoose => itemId == null;
}

/// One tender the bill took at the counter.
final class BillCopyTender {
  const BillCopyTender({
    required this.mode,
    required this.amount,
    this.reference,
    this.chequeNo,
    this.chequeBank,
    this.chequeDateUtcMillis,
  });

  /// `cash`, `jazzcash`, `cheque` and the rest of the closed set.
  final String mode;

  /// What the shop KEPT of it — for cash, the bill's share, not the note
  /// that was handed over. The change went straight back.
  final Money amount;

  final String? reference;
  final String? chequeNo;
  final String? chequeBank;
  final int? chequeDateUtcMillis;
}

/// What a customer had already paid on a bill being put right, as the one
/// tender the counter takes (M36).
///
/// Cancelling the bill takes its own tenders off the books with it — the
/// shopkeeper is, in the books' eyes, handing the money back. Putting it
/// right then rings the corrected bill, and the money the customer handed
/// over the first time is the money that pays it: so the corrected bill's
/// tender starts at exactly this, never at nothing (which would leave the
/// customer owing what they had paid) and never at the bill's own total
/// (which would take money twice when the corrected bill is dearer).
final class PaidBefore {
  const PaidBefore({
    required this.amount,
    this.mode,
    this.reference,
    this.chequeNo,
    this.chequeBank,
    this.chequeDateUtcMillis,
  });

  /// Nothing at all: the whole bill was on udhaar.
  static const nothing = PaidBefore(amount: Money.zero);

  /// What the shop kept. Zero when the bill was all on udhaar.
  final Money amount;

  /// How it came; null when nothing did.
  final String? mode;

  final String? reference;
  final String? chequeNo;
  final String? chequeBank;
  final int? chequeDateUtcMillis;

  bool get onUdhaar => amount.isZero;

  /// The tenders as one. The counter only ever writes one tender per bill,
  /// so this is that tender; anything else (a bill from an older build, or
  /// from somewhere other than the counter) is put as its largest tender's
  /// mode, its total kept whole, because the total is what must not be lost
  /// and the counter cannot take two modes.
  static PaidBefore of(List<BillCopyTender> tenders) {
    if (tenders.isEmpty) return nothing;
    var largest = tenders.first;
    for (final t in tenders.skip(1)) {
      if (t.amount > largest.amount) largest = t;
    }
    final total = Money.sum([for (final t in tenders) t.amount]);
    if (total.isZero) return nothing;
    final cheque = largest.mode == 'cheque';
    return PaidBefore(
      amount: total,
      mode: largest.mode,
      reference: largest.reference,
      chequeNo: cheque ? largest.chequeNo : null,
      chequeBank: cheque ? largest.chequeBank : null,
      chequeDateUtcMillis: cheque ? largest.chequeDateUtcMillis : null,
    );
  }
}

/// One line's discount as the counter holds it.
typedef CopiedDiscount = ({int discountBp, Money? explicitDiscount});

/// The discounts of [lines] as the cashier typed them, and the bill's own
/// (M36).
///
/// A bill stores each line's discount with its share of the bill discount
/// folded in, because that is what a return has to give back (M57). The
/// counter holds them apart: a line's percentage, a line's typed rupees, and
/// one figure off the whole bill. Taken apart here, then CHECKED by pricing
/// the result through the very calculator that priced the bill: if every
/// line comes to what was stored, the copy is the bill as it was rung.
///
/// When it does not — a typed rupee discount on a line AND a discount on
/// the whole bill, which cannot be told apart from what is stored — each
/// line instead carries everything that came off it as rupees, and the bill
/// none. Every line, its tax and the total then come to exactly what was
/// billed; only the paper says "discount" on the line rather than at the
/// foot. Exact money beats a nicer-looking guess.
({List<CopiedDiscount> lines, Money billDiscount}) discountsAsBilled(
  List<BillCopyLine> lines, {
  required Money billDiscount,
  RoundingMode roundingMode = RoundingMode.halfUp,
}) {
  CopiedDiscount own(BillCopyLine l, {required bool billHasDiscount}) {
    if (l.discountBp > 0) {
      return (discountBp: l.discountBp, explicitDiscount: null);
    }
    if (billHasDiscount || l.discount.isZero) {
      return (discountBp: 0, explicitDiscount: null);
    }
    return (discountBp: 0, explicitDiscount: l.discount);
  }

  final asTyped = [
    for (final l in lines) own(l, billHasDiscount: billDiscount.isPositive),
  ];
  if (lines.isEmpty) return (lines: asTyped, billDiscount: billDiscount);

  if (_pricesTo(lines, asTyped, billDiscount, roundingMode)) {
    return (lines: asTyped, billDiscount: billDiscount);
  }
  return (
    lines: [
      for (final l in lines)
        (
          discountBp: 0,
          explicitDiscount: l.discount.isZero ? null : l.discount,
        ),
    ],
    billDiscount: Money.zero,
  );
}

/// Whether [discounts] and [billDiscount] price [lines] to the discounts
/// each line stored.
bool _pricesTo(
  List<BillCopyLine> lines,
  List<CopiedDiscount> discounts,
  Money billDiscount,
  RoundingMode roundingMode,
) {
  try {
    final calculated = const SaleCalculator().calculate(
      SaleDraft(
        lines: [
          for (var i = 0; i < lines.length; i++)
            SaleLineDraft(
              itemId: lines[i].itemId,
              itemName: lines[i].name.trim().isEmpty ? '-' : lines[i].name,
              qty: lines[i].qty,
              baseQty: lines[i].qty,
              unitId: lines[i].unitId,
              unitCode: lines[i].unitCode,
              rate: lines[i].rate,
              discountBp: discounts[i].discountBp,
              explicitDiscount: discounts[i].explicitDiscount,
              isFreeItem: lines[i].isFree && !lines[i].isLoose,
              tracksStock: false,
            ),
        ],
        billDiscount: billDiscount,
        roundToRupee: false,
        roundingMode: roundingMode,
      ),
      // Tax plays no part in a discount; the untaxed engine charges none.
      const TaxContext(
        isSellerRegistered: false,
        buyerIsRegistered: false,
        buyerIsOnAtl: null,
        province: 'punjab',
        pricesIncludeTax: false,
        ruleVersion: 'copy',
      ),
    );
    for (var i = 0; i < lines.length; i++) {
      if (calculated.lines[i].totalDiscount != lines[i].discount) return false;
    }
    return true;
  } on Object {
    // A bill the calculator would not price as typed is never copied as
    // typed: the rupees each line stored are exact whatever happened.
    return false;
  }
}

/// A bill named from another: the one it replaced or was replaced by, or a
/// customer's last.
final class LinkedBill {
  const LinkedBill({
    required this.id,
    required this.docNo,
    this.isVoid = false,
  });

  final String id;
  final String docNo;

  /// Cancelled since — a corrected bill can itself be put right again.
  final bool isVoid;
}

/// Which bill one replaced, and which replaced it (M36).
///
/// Both sides of the one `revises` link: the corrected bill says "Replaces
/// INV-…", the cancelled one "Replaced by INV-…", each a tap from the other.
final class BillLinks {
  const BillLinks({this.replaces, this.replacedBy});

  static const none = BillLinks();

  /// The cancelled bill this one put right.
  final LinkedBill? replaces;

  /// The newest bill that put this one right.
  final LinkedBill? replacedBy;

  bool get isEmpty => replaces == null && replacedBy == null;
}
