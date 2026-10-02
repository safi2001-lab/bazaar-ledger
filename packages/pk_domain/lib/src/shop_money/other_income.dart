/// Money the shop earned that is not a sale (M47).
///
/// The room upstairs let to a tailor, commission on a mobile load, the
/// bank's profit on the current account, the kabari's money for a month of
/// empty cartons, a deposit refunded. None of it is a sale of goods, so
/// none of it belongs in the day's sales or the margin; all of it is the
/// shop's, so all of it belongs in the profit.
///
///   Dr  Cash or Bank      what came in
///     Cr  Other Income    what came in
///
/// ## How it is kept, and how it differs from a charge
///
/// An `other_income` document, as M25's charges are, with one difference
/// that decides everything: **no party**. A charge (a debit note) is money
/// a customer owes, so it carries their party, its balance is owed, and the
/// khata reads it by that party. Shop income was received when it was
/// written, so its balance is nothing and it carries no party at all: no
/// khata query (they all read `other_income` by `party_id`) can ever find
/// it, and M31's charge cancel, which is only reached from a khata, can
/// never be pointed at it. Who it came from, when it is said, is the
/// document's `party_name_snapshot`, a name and nothing more. Being a
/// document, it has a number the shopkeeper can quote (the `INC` series the
/// charges share: both are the shop's other income in the books), a date,
/// a status a cancellation turns to `void` with its reason, and the void
/// writer's mirror — the same path M31 cancels an expense with.
///
/// The head is the `income:<key>` tag on its lines (see `heads.dart` for
/// why it is not an account of its own).
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';
import '../time/clock.dart';
import 'tags.dart';

/// Why other income could not be recorded or put right, in words.
final class OtherIncomeRefused implements Exception {
  const OtherIncomeRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// What the shopkeeper entered.
final class OtherIncomeDraft {
  const OtherIncomeDraft({
    required this.headKey,
    required this.amount,
    required this.paymentAccountId,
    required this.receivedOn,
    this.note = '',
    this.fromName,
  });

  /// Which head it came under: a shipped key or one of the shop's own.
  final String headKey;
  final Money amount;

  /// The cash drawer, a bank or a wallet it came into. Never the cheque
  /// drawer: a cheque is recorded in its own book until it clears.
  final String paymentAccountId;

  /// The day it came in. Today unless the shopkeeper says otherwise, and
  /// never a day not yet come.
  final BusinessDate receivedOn;

  /// What it was. Optional, except under "other", where the head says
  /// nothing on its own.
  final String note;

  /// Who paid it, by name, when the shopkeeper says.
  final String? fromName;
}

/// Everything one entry of other income writes.
final class OtherIncomePosting {
  const OtherIncomePosting({
    required this.document,
    required this.journal,
    required this.headKey,
    required this.auditSummary,
  });

  final DocumentPosting document;
  final JournalEntryPosting journal;
  final String headKey;
  final String auditSummary;

  /// The tag every line carries.
  String get costCentre => incomeTag(headKey);

  void assertBalanced() {
    final debit = Money.sum([for (final l in journal.lines) l.debit]);
    final credit = Money.sum([for (final l in journal.lines) l.credit]);
    if (debit != credit) {
      throw StateError(
        'Other income ${document.docNo} would post an unbalanced entry: '
        'debits ${debit.amountOnly}, credits ${credit.amountOnly}.',
      );
    }
    if (document.partyId != null || !document.balance.isZero) {
      // The line between this and a charge. One with a party would be read
      // by every khata query as money that party owes.
      throw StateError(
        'Other income ${document.docNo} carries a party or a balance, which '
        'would put it on a khata as a charge.',
      );
    }
  }
}

/// What a recorded entry of other income left behind.
final class RecordedOtherIncome {
  const RecordedOtherIncome({
    required this.documentId,
    required this.docNo,
    required this.amount,
    required this.journalEntryId,
  });

  final String documentId;
  final String docNo;
  final Money amount;
  final String journalEntryId;
}

/// Builds the rows one entry of other income writes.
final class OtherIncomeBuilder {
  const OtherIncomeBuilder();

  /// [headName] is the head as the books name it, read by the writer from
  /// the shop's heads; [ledgerAccountId] the account of the cash or bank it
  /// came into.
  OtherIncomePosting build({
    required ActorContext actor,
    required OtherIncomeDraft draft,
    required AllocatedNumber number,
    required AllocatedNumber journalNumber,
    required String ledgerAccountId,
    required String headName,
  }) {
    if (!draft.amount.isPositive) {
      throw const OtherIncomeRefused('Income of nothing is not income.');
    }
    if (draft.receivedOn.value.compareTo(actor.businessDate.value) > 0) {
      throw OtherIncomeRefused(
        'It is dated ${draft.receivedOn.value}, which has not come yet. Enter '
        'it on the day the money comes in.',
      );
    }
    final note = draft.note.trim();
    if (note.isEmpty && draft.headKey == 'other') {
      throw const OtherIncomeRefused(
        'Say what it was. "Other income" on its own is a number nobody can '
        'explain six months later.',
      );
    }
    final from = draft.fromName?.trim();
    final fromName = from == null || from.isEmpty ? null : from;
    final amount = draft.amount;
    final what = note.isEmpty ? headName : '$headName — $note';
    final date = draft.receivedOn;

    final posting = OtherIncomePosting(
      document: DocumentPosting(
        docType: 'other_income',
        docNo: number.formatted,
        docSeries: number.series,
        docSeq: number.sequence,
        fiscalYear: date.fiscalYear,
        docDateUtcMillis: actor.epochMillis,
        docDateLocal: date.value,
        partyNameSnapshot: fromName,
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
        paid: amount,
        balance: Money.zero,
        cost: Money.zero,
        roundingMode: 'half_up',
        taxRuleVersion: '',
        cashThresholdBreached: false,
        notes: note.isEmpty ? null : note,
      ),
      journal: JournalEntryPosting(
        entryNo: journalNumber.formatted,
        entryDateUtcMillis: actor.epochMillis,
        entryDateLocal: date.value,
        fiscalYear: date.fiscalYear,
        sourceType: 'other_income',
        totalDebit: amount,
        totalCredit: amount,
        narration:
            'Other income ${number.formatted}: $what'
            '${fromName == null ? '' : ', from $fromName'}',
        lines: [
          JournalLinePosting(
            lineNo: 1,
            accountSystemKey: '#$ledgerAccountId',
            debit: amount,
            credit: Money.zero,
            narration: what,
          ),
          JournalLinePosting(
            lineNo: 2,
            accountSystemKey: 'other_income',
            debit: Money.zero,
            credit: amount,
            narration: 'Other income ${number.formatted}',
          ),
        ],
      ),
      headKey: draft.headKey,
      auditSummary:
          'Other income ${number.formatted} of ${amount.amountOnly} under '
          '$headName on ${date.value}'
          '${fromName == null ? '' : ' from $fromName'}'
          '${note.isEmpty ? '' : ': $note'}',
    );
    posting.assertBalanced();
    return posting;
  }
}
