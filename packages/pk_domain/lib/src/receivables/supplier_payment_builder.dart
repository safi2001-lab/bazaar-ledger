/// Paying a supplier, described in full before any of it is written.
///
/// The mirror of a receipt. The shop hands the rice mill Rs 30,000 against
/// three deliveries it has not finished paying for, and the same question
/// comes back the other way: which deliveries did that settle? A supplier
/// who says "you still owe on the June bill" is either right or wrong, and
/// only a record of which bills each payment cleared can say which.
///
/// Oldest first, through [allocateFifo] — the same function the customer
/// side runs, for the same reasons.
///
/// ## Why paying more than is owed is refused, not held as an advance
///
/// A customer who overpays leaves credit, and the shop records it as a
/// liability because it is holding their money. The shop overpaying a
/// supplier is the opposite: money the shop is owed back, which is an ASSET,
/// and the chart has no advances-to-suppliers account to put it in. Crediting
/// it to Accounts Payable would show the supplier owing the shop inside a
/// liability, where no balance sheet can see it — the exact netting the
/// receipt side was built to avoid. So it is refused in words until that
/// account exists.
///
/// ## Why a cheque is refused
///
/// A cheque the shop writes is a post-dated liability with a lifecycle of its
/// own — issued, presented, cleared, bounced — and paying from the Cheque
/// account would credit Cheques in Hand, which is paper customers gave the
/// shop. Both are M6's to record properly.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';
import 'fifo_allocator.dart';
import 'receipt_posting.dart';

/// Why a supplier payment cannot be recorded, in words a shopkeeper can act
/// on.
final class SupplierPaymentRefused implements Exception {
  const SupplierPaymentRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// What the shopkeeper entered.
final class SupplierPaymentDraft {
  const SupplierPaymentDraft({
    required this.partyId,
    required this.amount,
    required this.mode,
    required this.paymentAccountId,
    this.reference,
  });

  /// Always a party. Money going out to nobody in particular is an expense,
  /// and that screen already exists.
  final String partyId;

  final Money amount;

  /// `cash`, `bank_transfer`, `jazzcash`, `easypaisa`, `raast`, `card`. A
  /// label on a ledger row, never an integration.
  final String mode;

  final String paymentAccountId;

  /// A bank slip number, a JazzCash TID, nothing at all.
  final String? reference;
}

/// Builds the rows one payment to a supplier writes.
final class SupplierPaymentBuilder {
  const SupplierPaymentBuilder();

  /// [openBills] is what the shop still owes this supplier, in any order:
  /// purchase bills and unpaid expenses with a balance left on them.
  ReceiptPosting build({
    required ActorContext actor,
    required SupplierPaymentDraft draft,
    required List<OpenBill> openBills,
    required AllocatedNumber paymentNumber,
    required AllocatedNumber journalNumber,
    required String ledgerAccountId,
  }) {
    if (!draft.amount.isPositive) {
      throw const SupplierPaymentRefused(
        'A payment of nothing is not a payment.',
      );
    }
    if (draft.mode == 'cheque') {
      throw const SupplierPaymentRefused(
        'A cheque the shop writes is recorded with post-dated cheques, not '
        'here. Pay by cash, bank or wallet, or wait for the cheque book.',
      );
    }

    final owed = Money.sum([
      for (final b in openBills)
        if (b.outstanding.isPositive) b.outstanding,
    ]);
    if (!owed.isPositive) {
      throw const SupplierPaymentRefused(
        'Nothing is owed to this supplier, so there is nothing to pay.',
      );
    }
    if (draft.amount > owed) {
      throw SupplierPaymentRefused(
        'Only ${owed.amountOnly} is owed. Money paid beyond that is an '
        'advance the supplier owes back, and this shop has no account to '
        'hold it in yet.',
      );
    }

    final allocation = allocateFifo(draft.amount, openBills);
    // Refused above, so this is a proof rather than a branch: nothing is
    // left over, and every rupee landed on a bill.
    if (allocation.unapplied.isPositive) {
      throw StateError(
        'Payment ${paymentNumber.formatted} left '
        '${allocation.unapplied.amountOnly} unapplied after the amount was '
        'checked against what is owed.',
      );
    }

    final outstandingById = {
      for (final bill in openBills) bill.documentId: bill.outstanding,
    };

    final allocations = <AllocationPosting>[
      for (final applied in allocation.allocations)
        AllocationPosting(
          documentId: applied.documentId,
          amount: applied.amount,
          mode: 'fifo',
        ),
    ];
    // New totals, not deltas: the same rule the receipt side follows, so two
    // tills paying against one delivery cannot lose an update.
    final settlements = <BillSettlement>[
      for (final applied in allocation.allocations)
        BillSettlement(
          documentId: applied.documentId,
          paid: applied.amount,
          balance: outstandingById[applied.documentId]! - applied.amount,
        ),
    ];

    final journalLines = <JournalLinePosting>[
      // What the shop owes this supplier comes down, and the line names them.
      // Without the party a Trial Balance still balances and no report can
      // say whose payable moved.
      JournalLinePosting(
        lineNo: 1,
        accountSystemKey: 'accounts_payable',
        debit: draft.amount,
        credit: Money.zero,
        partyId: draft.partyId,
        narration: 'Against ${allocations.length} bill(s)',
      ),
      // And the money leaves the account it was paid from, resolved by id so
      // renaming "Golak" cannot break a payment.
      JournalLinePosting(
        lineNo: 2,
        accountSystemKey: '#$ledgerAccountId',
        debit: Money.zero,
        credit: draft.amount,
        narration: 'Payment ${paymentNumber.formatted}',
      ),
    ];

    final posting = ReceiptPosting(
      payment: PaymentPosting(
        paymentNo: paymentNumber.formatted,
        direction: 'out',
        paymentAccountId: draft.paymentAccountId,
        ledgerAccountId: ledgerAccountId,
        mode: draft.mode,
        amount: draft.amount,
        change: Money.zero,
        partyId: draft.partyId,
        reference: draft.reference,
        paymentDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        paymentDateLocal: actor.businessDate.value,
      ),
      allocations: allocations,
      settlements: settlements,
      unapplied: Money.zero,
      journal: JournalEntryPosting(
        entryNo: journalNumber.formatted,
        entryDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        entryDateLocal: actor.businessDate.value,
        fiscalYear: actor.businessDate.fiscalYear,
        sourceType: 'payment',
        totalDebit: draft.amount,
        totalCredit: draft.amount,
        narration: 'Payment ${paymentNumber.formatted}',
        lines: journalLines,
      ),
      auditSummary:
          'Payment ${paymentNumber.formatted} of ${draft.amount.amountOnly} '
          'by ${draft.mode} to a supplier, against '
          '${allocations.length} bill(s)',
    );

    posting.assertBalanced();
    return posting;
  }
}
