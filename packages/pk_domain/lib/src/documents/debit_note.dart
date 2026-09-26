/// A debit note: a charge put on a customer's khata without a sale.
///
/// The bank took Rs 500 when Rashid's cheque bounced, and the shop wants it
/// back from Rashid. The transporter's fare for the cartons sent to Bilal is
/// Bilal's to pay. Neither is a sale of anything, so neither belongs in the
/// day's sales or on a bill with lines; both are owed, so both belong on the
/// khata, where a receipt settles them like any bill.
///
/// Stored as an `other_income` document with the party on it, the mirror of
/// an unpaid `expense` with a supplier on it: what the shop is owed that is
/// not a sale, beside what it owes that is not a purchase.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';

/// Why a charge cannot be put on a khata, in words.
final class DebitNoteRefused implements Exception {
  const DebitNoteRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// What the shopkeeper entered.
final class DebitNoteDraft {
  const DebitNoteDraft({
    required this.partyId,
    required this.amount,
    required this.note,
    this.partyName,
  });

  final String partyId;
  final String? partyName;
  final Money amount;

  /// What it is for. Required: a charge the customer cannot be told the
  /// reason for is a charge they will refuse to pay.
  final String note;
}

/// Everything one debit note writes.
final class DebitNotePosting {
  const DebitNotePosting({
    required this.document,
    required this.journal,
    required this.auditSummary,
  });

  final DocumentPosting document;
  final JournalEntryPosting journal;
  final String auditSummary;
}

/// Builds the rows one debit note writes.
final class DebitNoteBuilder {
  const DebitNoteBuilder();

  DebitNotePosting build({
    required ActorContext actor,
    required DebitNoteDraft draft,
    required AllocatedNumber number,
    required AllocatedNumber journalNumber,
  }) {
    if (!draft.amount.isPositive) {
      throw const DebitNoteRefused('A charge of nothing is not a charge.');
    }
    final note = draft.note.trim();
    if (note.isEmpty) {
      throw const DebitNoteRefused(
        'A charge has to say what it is for, or the customer will not pay it.',
      );
    }
    final millis = actor.epochMillis;
    final amount = draft.amount;

    //   Dr  Receivables (their khata)   the charge
    //     Cr  Other Income              the charge
    return DebitNotePosting(
      document: DocumentPosting(
        docType: 'other_income',
        docNo: number.formatted,
        docSeries: number.series,
        docSeq: number.sequence,
        fiscalYear: actor.businessDate.fiscalYear,
        docDateUtcMillis: millis,
        docDateLocal: actor.businessDate.value,
        partyId: draft.partyId,
        partyNameSnapshot: draft.partyName,
        subtotal: amount,
        lineDiscount: Money.zero,
        billDiscount: Money.zero,
        taxable: amount,
        tax: Money.zero,
        furtherTax: Money.zero,
        withholding: Money.zero,
        extraCharges: Money.zero,
        roundOff: Money.zero,
        total: amount,
        paid: Money.zero,
        balance: amount,
        cost: Money.zero,
        roundingMode: 'half_up',
        taxRuleVersion: '',
        cashThresholdBreached: false,
        notes: note,
      ),
      journal: JournalEntryPosting(
        entryNo: journalNumber.formatted,
        entryDateUtcMillis: millis,
        entryDateLocal: actor.businessDate.value,
        fiscalYear: actor.businessDate.fiscalYear,
        sourceType: 'other_income',
        totalDebit: amount,
        totalCredit: amount,
        narration: 'Debit note ${number.formatted}: $note',
        lines: [
          JournalLinePosting(
            lineNo: 1,
            accountSystemKey: 'accounts_receivable',
            debit: amount,
            credit: Money.zero,
            partyId: draft.partyId,
            narration: note,
          ),
          JournalLinePosting(
            lineNo: 2,
            accountSystemKey: 'other_income',
            debit: Money.zero,
            credit: amount,
            narration: 'Debit note ${number.formatted}',
          ),
        ],
      ),
      auditSummary:
          'Debit note ${number.formatted} of ${amount.amountOnly} to '
          '${draft.partyName ?? draft.partyId}: $note',
    );
  }
}
