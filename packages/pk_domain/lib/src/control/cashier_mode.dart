/// The salesman makes the bill; the cashier takes the money (M68).
///
/// Marg's cashier mode, as a wholesale counter in Shah Alam Market runs it:
/// three salesmen on the floor write up what each customer wants, and one
/// person at the till, the only one who touches the money, takes it and
/// hands over the paper. The shop wants two things from that: a salesman
/// who never handles cash, and a cashier who cannot let goods out without a
/// bill somebody else wrote.
///
/// ## A held bill is a proforma
///
/// The schema has carried a `proforma` document type since v1 with nothing
/// writing it: a bill made out before it is paid, which is exactly what the
/// salesman hands the cashier. It is written like a quotation (M25): its
/// lines priced by the same calculator a bill is, numbered in its own PRO
/// series, and nothing else. **No stock leaves the shelf and nothing
/// reaches the books while it waits.** No sale number is used, no journal
/// entry, nothing on anybody's khata.
///
/// The cashier takes it from the queue onto their counter and settles it as
/// any bill made from a quotation: the bill is made then, at the held
/// prices, linked `converted_from` to the held bill in its own commit. That
/// is the moment stock leaves and the books move -- one bill, dated when it
/// was paid, through every check a bill passes (the shelf, the pharmacy,
/// the discount ceiling, credit control, FBR). Decided so, rather than
/// posting the bill when the salesman makes it and the payment later:
///
///  * a customer who walks away leaves nothing to undo: no cancelled sale
///    in the invoice series for FBR or an auditor to ask about, no stock
///    to put back;
///  * a walk-in has no khata, so a bill posted unpaid has nowhere honest to
///    sit; and the drawer and the books agree at every moment;
///  * the link is the existing one, which already refuses billing the same
///    paper twice -- two cashiers cannot both take money for it.
///
/// The bill says who made it (`salesperson_id`, the held bill's maker) and
/// who took the money (`created_by`, the cashier), and the paper says both.
///
/// A held bill is a row in the books from the moment the salesman taps send,
/// committed before their counter clears, so an app killed on either phone
/// loses nothing; and it reaches the cashier's phone with the rest of the
/// books over the shop's wi-fi (M13).
library;

import 'dart:convert';

import 'package:pk_money/pk_money.dart';

import '../documents/quotation.dart';
import '../identity/actor_context.dart';
import '../sales/sale_calculator.dart';
import '../sales/sale_draft.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';

/// The settings key the mode is kept under, as JSON.
const cashierModeSetting = 'counter.cashier_mode';

/// The document type a held bill is written as.
const heldBillDocType = 'proforma';

/// Audit codes.
const cashierModeSetAction = 'CASHIER_MODE_SET';
const billHeldAction = 'BILL_HELD';
const heldBillDroppedAction = 'HELD_BILL_DROPPED';

/// Whether the shop runs that way, and who its salesmen are.
final class CashierMode {
  const CashierMode({this.on = false, this.salesmen = const {}});

  static const off = CashierMode();

  final bool on;

  /// The staff who make bills and take no money. Anybody else at a counter
  /// -- the owner, a manager, a cashier -- takes money as before.
  final Set<String> salesmen;

  /// Whether [userId] makes bills for the cashier rather than taking money.
  bool isSalesman(String? userId) =>
      on && userId != null && salesmen.contains(userId);

  String toJson() => jsonEncode({
    'on': on,
    'salesmen': [...salesmen]..sort(),
  });

  static CashierMode fromJson(String? text) {
    if (text == null || text.trim().isEmpty) return off;
    try {
      final map = jsonDecode(text);
      if (map is! Map<String, Object?>) return off;
      final list = map['salesmen'];
      return CashierMode(
        on: map['on'] == true,
        salesmen: {
          if (list is List)
            for (final id in list)
              if (id is String) id,
        },
      );
    } on FormatException {
      return off;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CashierMode && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

/// One bill waiting at the cashier.
final class HeldBill {
  const HeldBill({
    required this.id,
    required this.docNo,
    required this.madeBy,
    required this.madeByName,
    required this.madeAtUtcMillis,
    required this.total,
    required this.lineCount,
    this.partyId,
    this.partyName,
    this.billDiscount = Money.zero,
    this.paidAs,
    this.dropped = false,
  });

  final String id;
  final String docNo;

  /// The salesman, by id and by name.
  final String madeBy;
  final String madeByName;
  final int madeAtUtcMillis;
  final Money total;
  final int lineCount;
  final String? partyId;
  final String? partyName;

  /// The bill's own discount, as the salesman gave it.
  final Money billDiscount;

  /// The bill it became, once paid.
  final String? paidAs;

  /// Set aside without being paid.
  final bool dropped;

  bool get isWaiting => paidAs == null && !dropped;
}

/// Why a held bill cannot be written or paid, in words.
final class HeldBillRefused implements Exception {
  const HeldBillRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Builds the held bill for [draft], as a quotation is built (M25), but in
/// the proforma series, with the salesman named and no expiry.
QuotationPosting heldBillPosting({
  required ActorContext actor,
  required SaleDraft draft,
  required CalculatedSale calculated,
  required AllocatedNumber number,
}) {
  if (draft.lines.isEmpty) {
    throw const HeldBillRefused('A bill for the cashier needs an item.');
  }
  if (draft.tenders.isNotEmpty) {
    throw const HeldBillRefused(
      'A held bill takes no money: the cashier takes it.',
    );
  }
  if (draft.lines.any((l) => l.isLoose)) {
    // Taken back onto the cashier's counter item by item, as a quotation
    // is, and a loose line (M37) is not an item.
    throw const HeldBillRefused(
      'A loose line cannot go to the cashier: make it an item first.',
    );
  }
  final q = const QuotationBuilder().build(
    actor: actor,
    draft: draft,
    calculated: calculated,
    number: number,
  );
  final d = q.document;
  return QuotationPosting(
    document: DocumentPosting(
      docType: heldBillDocType,
      docNo: d.docNo,
      docSeries: d.docSeries,
      docSeq: d.docSeq,
      fiscalYear: d.fiscalYear,
      docDateUtcMillis: d.docDateUtcMillis,
      docDateLocal: d.docDateLocal,
      partyId: d.partyId,
      partyNameSnapshot: d.partyNameSnapshot,
      partyNtnSnapshot: d.partyNtnSnapshot,
      partyStrnSnapshot: d.partyStrnSnapshot,
      partyAddressSnapshot: d.partyAddressSnapshot,
      subtotal: d.subtotal,
      lineDiscount: d.lineDiscount,
      billDiscount: d.billDiscount,
      taxable: d.taxable,
      tax: d.tax,
      furtherTax: d.furtherTax,
      withholding: d.withholding,
      extraCharges: d.extraCharges,
      roundOff: d.roundOff,
      total: d.total,
      // Nothing paid and nothing owed while it waits.
      paid: Money.zero,
      balance: Money.zero,
      cost: Money.zero,
      roundingMode: d.roundingMode,
      taxRuleVersion: d.taxRuleVersion,
      cashThresholdBreached: false,
      salespersonId: actor.userId,
      notes: d.notes,
    ),
    lines: q.lines,
    validUntil: actor.businessDate,
    auditSummary:
        'Bill ${number.formatted} made for the cashier: '
        '${draft.partyName ?? 'a walk-in'}, ${calculated.total.amountOnly}',
  );
}
