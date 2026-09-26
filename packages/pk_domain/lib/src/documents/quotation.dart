/// A quotation: what the goods would cost, written down and numbered.
///
/// A wholesaler's customer rings for a price on forty cartons before
/// committing, and gets it on paper or on WhatsApp. That paper is a promise
/// of a price and nothing else: no stock leaves, no money is owed, nothing
/// reaches the books. It is priced by the same calculator as a bill, so the
/// bill made from it later says the same thing to the paisa.
library;

import 'package:pk_money/pk_money.dart';

import '../cheques/cheque_dates.dart';
import '../identity/actor_context.dart';
import '../sales/sale_calculator.dart';
import '../sales/sale_draft.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';
import '../time/clock.dart';

/// How long a quotation holds its prices unless the shop says otherwise.
const quotationValidDays = 15;

/// Why a quotation cannot be written, in words.
final class QuotationRefused implements Exception {
  const QuotationRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Everything one quotation writes.
final class QuotationPosting {
  const QuotationPosting({
    required this.document,
    required this.lines,
    required this.validUntil,
    required this.auditSummary,
  });

  final DocumentPosting document;
  final List<DocumentLinePosting> lines;

  /// The last day the prices hold.
  final BusinessDate validUntil;
  final String auditSummary;
}

/// Builds a quotation from a priced cart.
final class QuotationBuilder {
  const QuotationBuilder();

  QuotationPosting build({
    required ActorContext actor,
    required SaleDraft draft,
    required CalculatedSale calculated,
    required AllocatedNumber number,
    int validDays = quotationValidDays,
  }) {
    if (draft.lines.isEmpty) {
      throw const QuotationRefused('A quotation needs at least one item.');
    }
    if (draft.tenders.isNotEmpty) {
      // Money taken against a quotation is an advance against an order, and
      // that is a receipt, not a line on a price list.
      throw const QuotationRefused(
        'A quotation takes no money. Record an advance as a receipt.',
      );
    }
    final validUntil = actor.businessDate.addDays(validDays);

    return QuotationPosting(
      document: DocumentPosting(
        docType: 'quotation',
        docNo: number.formatted,
        docSeries: number.series,
        docSeq: number.sequence,
        fiscalYear: actor.businessDate.fiscalYear,
        docDateUtcMillis: actor.epochMillis,
        docDateLocal: actor.businessDate.value,
        partyId: draft.partyId,
        partyNameSnapshot: draft.partyName,
        partyNtnSnapshot: draft.partyNtn,
        partyStrnSnapshot: draft.partyStrn,
        partyAddressSnapshot: draft.partyAddress,
        subtotal: calculated.subtotal,
        lineDiscount: calculated.lineDiscountTotal,
        billDiscount: calculated.billDiscount,
        taxable: calculated.taxable,
        tax: calculated.tax,
        furtherTax: calculated.furtherTax,
        withholding: calculated.withholding,
        extraCharges: calculated.extraCharges,
        roundOff: calculated.roundOff,
        total: calculated.total,
        // Nothing is paid and nothing is owed on a quotation: a balance here
        // would be udhaar on a sale that has not happened.
        paid: Money.zero,
        balance: Money.zero,
        cost: Money.zero,
        roundingMode: roundingModeCode(draft.roundingMode),
        taxRuleVersion: calculated.ruleVersion,
        cashThresholdBreached: false,
        salespersonId: draft.salespersonId,
        notes: draft.notes,
        terms: 'Prices valid until ${validUntil.value}',
      ),
      lines: [for (final l in calculated.lines) documentLineFor(l)],
      validUntil: validUntil,
      auditSummary:
          'Quotation ${number.formatted} for '
          '${draft.partyName ?? 'a walk-in'}, ${calculated.total.amountOnly}, '
          'valid until ${validUntil.value}',
    );
  }
}

/// One quotation, as the list shows it.
final class QuotationRow {
  const QuotationRow({
    required this.id,
    required this.docNo,
    required this.date,
    required this.total,
    this.partyId,
    this.partyName,
    this.validUntil,
    this.billedAs,
  });

  final String id;
  final String docNo;
  final BusinessDate date;
  final Money total;
  final String? partyId;
  final String? partyName;

  /// The last day its prices hold, if it says.
  final BusinessDate? validUntil;

  /// The bill it became, if it has.
  final String? billedAs;

  bool get isBilled => billedAs != null;

  bool isExpiredOn(BusinessDate today) =>
      validUntil != null && daysUntil(today, validUntil!) < 0;
}

/// One line of a quotation, as quoted.
final class QuotedLine {
  const QuotedLine({
    required this.itemId,
    required this.qty,
    required this.unitCode,
    required this.rate,
    this.unitId,
    this.discountBp = 0,
    this.explicitDiscount,
  });

  final String itemId;
  final Qty qty;
  final String? unitId;
  final String unitCode;
  final Rate rate;
  final int discountBp;
  final Money? explicitDiscount;
}
