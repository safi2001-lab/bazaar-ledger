import 'package:pk_money/pk_money.dart';

import '../documents/delivery_challan.dart';
import '../identity/actor_context.dart';
import 'sale_calculator.dart';
import 'sale_draft.dart';
import 'sale_posting.dart';

/// A document number allocated for a posting.
final class AllocatedNumber {
  const AllocatedNumber({
    required this.formatted,
    required this.series,
    required this.sequence,
  });

  final String formatted;
  final String series;
  final int sequence;
}

/// Turns a priced sale into the exact set of rows it should produce.
///
/// Pure. Given the same draft, the same calculated totals and the same
/// allocated numbers, it produces the same posting every time — which is why
/// the whole of the double entry below can be tested without a database.
final class SalePostingBuilder {
  const SalePostingBuilder();

  SalePosting build({
    required ActorContext actor,
    required SaleDraft draft,
    required CalculatedSale calculated,
    required AllocatedNumber invoiceNumber,
    required AllocatedNumber journalNumber,
    required List<AllocatedNumber> paymentNumbers,
    required Map<String, String> ledgerAccountByPaymentAccount,
    ChallanGoods? delivered,
  }) {
    if (calculated.withholding.isPositive) {
      // Not reachable while UntaxedEngine is the only engine. Named rather
      // than silently mis-posted, because a wrong journal entry is worse than
      // a refused one.
      throw UnsupportedError(
        'Withholding on the sale side arrives with the M12 tax pack. '
        'Refusing to post an entry whose treatment is not yet defined.',
      );
    }

    final millis = actor.epochMillis;
    final localDate = actor.businessDate.value;
    final fiscalYear = actor.businessDate.fiscalYear;

    // A bill made from a delivery challan sells goods that have already
    // left. They are not taken off the shelf again, and they are costed at
    // what they left at, not at today's average.
    if (delivered != null && delivered.partyId != draft.partyId) {
      throw ChallanRefused(
        'The goods on ${delivered.docNo} went to somebody else. The bill '
        'has to be made out to the customer they went to.',
      );
    }
    final challanCost = delivered?.costOfLines(calculated.lines);
    final cost = delivered?.cost ?? calculated.cost;

    // --- Document and lines ----------------------------------------------
    final document = DocumentPosting(
      docType: 'sale_invoice',
      docNo: invoiceNumber.formatted,
      docSeries: invoiceNumber.series,
      docSeq: invoiceNumber.sequence,
      fiscalYear: fiscalYear,
      docDateUtcMillis: millis,
      docDateLocal: localDate,
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
      paid: calculated.paid,
      balance: calculated.balance,
      cost: cost,
      roundingMode: roundingModeCode(draft.roundingMode),
      taxRuleVersion: calculated.ruleVersion,
      cashThresholdBreached: calculated.cashThresholdBreached,
      salespersonId: draft.salespersonId,
      notes: draft.notes,
    );

    final lines = <DocumentLinePosting>[];
    final stock = <StockMovementPosting>[];
    for (final l in calculated.lines) {
      lines.add(documentLineFor(l, cost: challanCost?[l.lineNo]));

      if (delivered == null && l.draft.tracksStock && !l.draft.baseQty.isZero) {
        stock.add(
          StockMovementPosting(
            itemId: l.draft.itemId,
            txnType: 'sale',
            qtyDelta: -l.draft.baseQty,
            rate: l.draft.unitCost,
            valueDelta: -l.cost,
            occurredAtUtcMillis: millis,
            occurredOnLocal: localDate,
            lineNo: l.lineNo,
            lotId: l.draft.lotId,
          ),
        );
      }
    }

    // --- Tenders ----------------------------------------------------------
    //
    // The capping arithmetic is the calculator's, not repeated here. This
    // builder writes what that pure function decided, one payment row per
    // tender it decided was real, in the same order — so the caller can
    // allocate exactly `calculated.tenders.length` receipt numbers and never
    // burn one on a row that is not written.
    if (paymentNumbers.length < calculated.tenders.length) {
      throw ArgumentError(
        'Got ${paymentNumbers.length} receipt numbers for '
        '${calculated.tenders.length} payments.',
      );
    }

    final payments = <PaymentPosting>[];
    for (var i = 0; i < calculated.tenders.length; i++) {
      final settlement = calculated.tenders[i];
      final tender = settlement.draft;
      if (tender.mode == 'cheque') {
        // Said here in words. The schema refuses a cheque with no number
        // too, and the counter used to meet that as a constraint error: the
        // tender sheet offered Cheque and never asked for the number, so
        // every cheque sale failed with nothing written.
        if (tender.chequeNo?.trim().isEmpty ?? true) {
          throw ArgumentError.value(
            tender.chequeNo,
            'chequeNo',
            'a cheque with no number cannot be chased when it bounces',
          );
        }
        // A cheque that bounces reopens the bill, and a reopened bill is
        // somebody's udhaar. A walk-in has no khata to put it back on.
        if (draft.partyId == null) {
          throw ArgumentError.value(
            null,
            'partyId',
            'a cheque has to name the customer who wrote it, or a bounce '
                'leaves money nobody can be asked for',
          );
        }
      }
      final ledgerAccount =
          ledgerAccountByPaymentAccount[tender.paymentAccountId];
      if (ledgerAccount == null) {
        throw StateError(
          'Payment account ${tender.paymentAccountId} is not linked to an '
          'account in the chart, so this tender cannot be posted.',
        );
      }

      payments.add(
        PaymentPosting(
          paymentNo: paymentNumbers[i].formatted,
          direction: 'in',
          paymentAccountId: tender.paymentAccountId,
          ledgerAccountId: ledgerAccount,
          mode: tender.mode,
          amount: settlement.applied,
          tendered: settlement.offered,
          change: settlement.change,
          reference: tender.reference,
          partyId: draft.partyId,
          paymentDateUtcMillis: millis,
          paymentDateLocal: localDate,
          chequeNo: tender.chequeNo,
          chequeBank: tender.chequeBank,
          chequeDateUtcMillis: tender.chequeDateUtc?.millisecondsSinceEpoch,
        ),
      );
    }

    // --- Double entry -----------------------------------------------------
    //
    //   Dr  the account each tender landed in     what was actually paid
    //   Dr  Receivables (udhaar)                  what is still owed
    //   Dr  Discount Given                        line + bill discount
    //   Dr  Round Off                             when the bill was rounded down
    //   Dr  Cost of Goods Sold                    cost of what left the shelf
    //     Cr  Sales                               gross, before discount
    //     Cr  Output Sales Tax                    sales tax
    //     Cr  Further Tax Payable                 further tax, s.3(1A)
    //     Cr  Other Income                        extra charges
    //     Cr  Round Off                           when the bill was rounded up
    //     Cr  Inventory                           cost of what left the shelf
    //
    // Sales is credited GROSS and the discount is a contra-entry rather than
    // being netted off, because a shopkeeper who gives Rs 40,000 of riayat in
    // a month needs to be able to see that number.
    final journalLines = <JournalLinePosting>[];
    var lineNo = 1;

    void post({
      required String key,
      Money debit = Money.zero,
      Money credit = Money.zero,
      String? partyId,
      String? narration,
    }) {
      if (debit.isZero && credit.isZero) return;
      journalLines.add(
        JournalLinePosting(
          lineNo: lineNo++,
          accountSystemKey: key,
          debit: debit,
          credit: credit,
          partyId: partyId,
          narration: narration,
        ),
      );
    }

    // Tenders, grouped by the account they landed in, so a split payment
    // across two cash drawers does not produce two identical lines.
    final byAccount = <String, Money>{};
    for (final p in payments) {
      if (p.amount.isZero) continue;
      // A cheque is not money in the bank until it clears. It sits in
      // "Cheques in Hand" and moves when the PDC lifecycle says it has.
      final key = p.isCheque ? '__cheques_in_hand' : p.ledgerAccountId;
      byAccount[key] = (byAccount[key] ?? Money.zero) + p.amount;
    }
    byAccount.forEach((account, amount) {
      post(
        key: account == '__cheques_in_hand'
            ? 'cheques_in_hand'
            : _accountIdKey(account),
        debit: amount,
        narration: 'Received against ${invoiceNumber.formatted}',
      );
    });

    // An unpaid balance is somebody's khata, and nobody's khata is not a
    // khata: a receivable with no party is money the shop can never ask for,
    // sitting in a total it can never explain. Checked here rather than in the
    // calculator, because pricing a bill is a different question from who owes
    // what is left on it.
    if (calculated.balance.isPositive && draft.partyId == null) {
      throw ArgumentError.value(
        calculated.balance.amountOnly,
        'balance',
        'a bill left part-paid has to name the customer who owes the rest',
      );
    }

    post(
      key: 'accounts_receivable',
      debit: calculated.balance,
      partyId: draft.partyId,
      narration: 'Udhaar on ${invoiceNumber.formatted}',
    );

    final totalDiscount =
        calculated.lineDiscountTotal + calculated.billDiscount;
    post(key: 'discount_given', debit: totalDiscount);

    if (calculated.roundOff.isNegative) {
      post(key: 'round_off', debit: -calculated.roundOff);
    }

    post(key: 'cogs', debit: cost);

    // Gross of discount, net of any tax that was inside the price: that tax
    // is the government's, credited below, and never the shop's sales.
    post(key: 'sales', credit: calculated.subtotal - calculated.inclusiveTax);
    post(key: 'output_tax', credit: calculated.tax);
    post(key: 'further_tax_payable', credit: calculated.furtherTax);
    post(key: 'other_income', credit: calculated.extraCharges);

    if (calculated.roundOff.isPositive) {
      post(key: 'round_off', credit: calculated.roundOff);
    }

    post(
      key: delivered == null ? 'inventory' : 'goods_on_challan',
      credit: cost,
      partyId: delivered == null ? null : draft.partyId,
    );

    final totalDebit = Money.sum([for (final l in journalLines) l.debit]);
    final totalCredit = Money.sum([for (final l in journalLines) l.credit]);

    final posting = SalePosting(
      document: document,
      lines: lines,
      convertedFromId: draft.convertedFromId,
      payments: payments,
      stockMovements: stock,
      journal: JournalEntryPosting(
        entryNo: journalNumber.formatted,
        entryDateUtcMillis: millis,
        entryDateLocal: localDate,
        fiscalYear: fiscalYear,
        sourceType: 'sale',
        totalDebit: totalDebit,
        totalCredit: totalCredit,
        narration: 'Sale ${invoiceNumber.formatted}',
        lines: journalLines,
      ),
      auditSummary: _summarise(invoiceNumber.formatted, calculated, draft),
    );

    posting.assertBalanced();
    return posting;
  }

  static String _summarise(String docNo, CalculatedSale sale, SaleDraft draft) {
    final who = draft.partyName ?? 'walk-in customer';
    final items = sale.lines.length == 1
        ? '1 item'
        : '${sale.lines.length} items';
    final settled = sale.isFullyPaid
        ? 'paid in full'
        : '${sale.balance.amountOnly} on udhaar';
    return '$docNo to $who — $items, ${sale.total.amountOnly}, $settled';
  }

  /// Tender accounts are already resolved to an account id, so they are passed
  /// through with a marker the writer recognises rather than a system key.
  static String _accountIdKey(String accountId) => '#$accountId';
}

/// Whether a journal line names an account by system key or by a resolved id.
extension JournalAccountLookup on JournalLinePosting {
  bool get isResolvedAccountId => accountSystemKey.startsWith('#');

  /// The account id, when [isResolvedAccountId].
  String get accountId => accountSystemKey.substring(1);
}

/// The stored code for a rounding mode.
String roundingModeCode(RoundingMode mode) => switch (mode) {
  RoundingMode.halfUp => 'half_up',
  RoundingMode.halfEven => 'half_even',
  RoundingMode.truncate => 'truncate',
  RoundingMode.ceilAbs => 'ceil_abs',
};

/// One calculated line as the row `document_lines` stores. Shared by every
/// document priced by the sale calculator, so a quotation and the bill made
/// from it cannot store the same line two ways.
///
/// [cost] replaces the line's cost when it was settled elsewhere: goods
/// billed off a challan cost what they left at.
DocumentLinePosting documentLineFor(CalculatedLine l, {Money? cost}) =>
    DocumentLinePosting(
      lineNo: l.lineNo,
      itemId: l.draft.itemId,
      itemNameSnapshot: l.draft.itemName,
      itemCodeSnapshot: l.draft.itemCode,
      hsCodeSnapshot: l.draft.hsCode,
      description: l.draft.description,
      qty: l.draft.qty,
      baseQty: l.draft.baseQty,
      unitId: l.draft.unitId,
      unitCodeSnapshot: l.draft.unitCode,
      rate: l.draft.rate,
      mrp: l.draft.mrp,
      lotId: l.draft.lotId,
      gross: l.gross,
      discountBp: l.draft.discountBp,
      discount: l.totalDiscount,
      taxable: l.taxable,
      tax: l.tax,
      lineTotal: l.lineTotal,
      cost: cost ?? l.cost,
      isFreeItem: l.draft.isFreeItem,
      taxes: l.taxes,
    );
