/// Turning "the customer handed over Rs 5,000" into rows.
///
/// Pure. Given a draft, the bills that are open and the numbers already
/// allocated, it produces every row the receipt writes and proves the entry
/// balances — all without a database, which is what lets the awkward cases be
/// asserted directly instead of being discovered in a shop.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';
import 'fifo_allocator.dart';
import 'receipt_posting.dart';

/// What the cashier entered.
final class ReceiptDraft {
  const ReceiptDraft({
    required this.partyId,
    required this.amount,
    required this.mode,
    required this.paymentAccountId,
    this.reference,
    this.notes,
    this.chequeNo,
    this.chequeBank,
    this.chequeDateUtcMillis,
    this.allocationMode = 'fifo',
    this.holdAsAdvance = false,
  });

  /// Always a party. A walk-in customer has nothing to settle: they paid at
  /// the counter and the sale recorded it. Money arriving later belongs to
  /// somebody whose name is in the khata, or there is nothing to apply it to.
  final String partyId;

  final Money amount;

  /// `cash`, `bank_transfer`, `jazzcash`, `easypaisa`, `raast`, `card`,
  /// `cheque`, `adjustment` — a label on a ledger row, never an integration.
  /// If EasyPaisa disappeared tomorrow the button would still work.
  final String mode;

  final String paymentAccountId;

  /// Whatever the shopkeeper wants to write down: a JazzCash TID, the last
  /// four of a card slip, nothing at all. Never verified, because there is
  /// nothing to verify it against.
  final String? reference;

  final String? notes;
  final String? chequeNo;
  final String? chequeBank;
  final int? chequeDateUtcMillis;
  final String allocationMode;

  /// Held for the customer whole, against nothing they already owe (M41):
  /// an advance paid down on a sale order, kept for the bill the order
  /// becomes rather than swallowed by last month's udhaar. The khata's
  /// balance is the same either way; which bill reads paid is not.
  final bool holdAsAdvance;
}

/// Builds the rows one receipt writes.
final class ReceiptBuilder {
  const ReceiptBuilder();

  /// [openBills] is what the party still owes, in any order.
  ///
  /// [ledgerAccountId] is the chart account the tender lands in, resolved
  /// from the payment account so that renaming "Golak" never breaks a
  /// receipt.
  ReceiptPosting build({
    required ActorContext actor,
    required ReceiptDraft draft,
    required List<OpenBill> openBills,
    required AllocatedNumber paymentNumber,
    required AllocatedNumber journalNumber,
    required String ledgerAccountId,
  }) {
    if (!draft.amount.isPositive) {
      throw ArgumentError.value(
        draft.amount.inPaisa,
        'amount',
        'a receipt of nothing is not a receipt',
      );
    }
    if (draft.mode == 'cheque' && (draft.chequeNo?.trim().isEmpty ?? true)) {
      // The schema refuses this too. Caught here so the shopkeeper is told
      // which field is missing rather than shown a constraint name.
      throw ArgumentError.value(
        draft.chequeNo,
        'chequeNo',
        'a cheque with no number cannot be chased when it bounces',
      );
    }

    final allocation = allocateFifo(draft.amount, openBills);
    final outstandingById = {
      for (final bill in openBills) bill.documentId: bill.outstanding,
    };

    final allocations = <AllocationPosting>[];
    final settlements = <BillSettlement>[];
    for (final applied in allocation.allocations) {
      allocations.add(
        AllocationPosting(
          documentId: applied.documentId,
          amount: applied.amount,
          mode: draft.allocationMode,
        ),
      );
      // The bill's new totals, not deltas. A writer handed a delta has to
      // read the row, add and write it back, and two tills doing that against
      // one bill is a lost update; a writer handed the answer cannot.
      final before = outstandingById[applied.documentId]!;
      settlements.add(
        BillSettlement(
          documentId: applied.documentId,
          paid: applied.amount,
          balance: before - applied.amount,
        ),
      );
    }

    final journalLines = <JournalLinePosting>[];
    var lineNo = 1;

    // Money in: the tender account is debited by the whole amount, whatever
    // the payment turns out to settle.
    //
    // A cheque is not money in the bank until it clears. It sits in Cheques
    // in Hand and moves when the PDC lifecycle says it has — the same rule
    // the sale path already follows, and getting it wrong here would let a
    // shop's bank balance include a cheque that later bounces.
    //
    // Anything else names its resolved account id with the `#` prefix the
    // journal uses for exactly that, so renaming "Golak" cannot break a
    // receipt and deleting it cannot orphan the line.
    journalLines.add(
      JournalLinePosting(
        lineNo: lineNo++,
        accountSystemKey: draft.mode == 'cheque'
            ? 'cheques_in_hand'
            : '#$ledgerAccountId',
        debit: draft.amount,
        credit: Money.zero,
        narration: 'Receipt ${paymentNumber.formatted}',
      ),
    );

    final applied = allocation.applied;
    if (applied.isPositive) {
      // Receivables comes down by what was actually applied, and the party is
      // stamped on the line. Without it a Trial Balance still balances and no
      // report can say whose udhaar moved.
      journalLines.add(
        JournalLinePosting(
          lineNo: lineNo++,
          accountSystemKey: 'accounts_receivable',
          debit: Money.zero,
          credit: applied,
          partyId: draft.partyId,
          narration: 'Against ${allocations.length} bill(s)',
        ),
      );
    }

    if (allocation.unapplied.isPositive) {
      // A liability, not a negative receivable. The shop is holding the
      // customer's money, and netting it against udhaar would hide a real
      // obligation inside an asset — where a balance sheet cannot show it and
      // an ageing report cannot find it.
      journalLines.add(
        JournalLinePosting(
          lineNo: lineNo++,
          accountSystemKey: 'customer_advances',
          debit: Money.zero,
          credit: allocation.unapplied,
          partyId: draft.partyId,
          narration: 'Paid on account',
        ),
      );
    }

    final total = Money.sum([for (final l in journalLines) l.debit]);
    final posting = ReceiptPosting(
      payment: PaymentPosting(
        paymentNo: paymentNumber.formatted,
        direction: 'in',
        paymentAccountId: draft.paymentAccountId,
        ledgerAccountId: ledgerAccountId,
        mode: draft.mode,
        amount: draft.amount,
        change: Money.zero,
        partyId: draft.partyId,
        reference: draft.reference,
        chequeNo: draft.chequeNo,
        chequeBank: draft.chequeBank,
        chequeDateUtcMillis: draft.chequeDateUtcMillis,
        paymentDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        paymentDateLocal: actor.businessDate.value,
        // M55: the draft's words reach the payment row. They were dropped
        // here, so a receipt's note was asked for and never kept; a round's
        // receipt names its recovery man in it.
        notes: draft.notes,
      ),
      allocations: allocations,
      settlements: settlements,
      unapplied: allocation.unapplied,
      journal: JournalEntryPosting(
        entryNo: journalNumber.formatted,
        entryDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        entryDateLocal: actor.businessDate.value,
        fiscalYear: actor.businessDate.fiscalYear,
        sourceType: 'payment',
        totalDebit: total,
        totalCredit: total,
        narration: 'Receipt ${paymentNumber.formatted}',
        lines: journalLines,
      ),
      auditSummary:
          'Receipt ${paymentNumber.formatted} for '
          '${draft.amount.amountOnly} by ${draft.mode}, applied to '
          '${allocations.length} bill(s)'
          '${allocation.unapplied.isPositive ? ', '
                    '${allocation.unapplied.amountOnly} on account' : ''}',
    );

    posting.assertBalanced();
    return posting;
  }
}
