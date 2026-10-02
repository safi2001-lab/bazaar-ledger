/// "Baqi chhor do": udhaar let go, as a settlement discount or a bad debt,
/// with the reason kept (M44).
///
/// Two things happen at a Pakistani counter that the khata had no words for.
/// A customer owing Rs 10,000 hands over Rs 9,500 and the shopkeeper says
/// "chalo, paanch sau chhor diye" — the bills are settled in full and the
/// Rs 500 is the shop's cost of being paid today. And a customer who moved
/// away, or died, or will not pay, has a balance the shop stops expecting:
/// it is written off as a bad debt, and the shop wants to know why when the
/// name comes up again.
///
/// ## Modelled as an allowance: money that did not come
///
/// Both are written as a payment *in* of mode `adjustment` — the mode the
/// schema has carried since M0 for exactly this — allocated to the
/// customer's bills the way a receipt is, oldest first (or, for a write-off,
/// to the bills the shopkeeper picks). The difference from a receipt is the
/// debit: not the drawer or the bank, but an expense — Settlement Discount
/// or Bad Debts — so the receivable comes down, the profit and loss shows
/// the cost, and no cash figure moves. Vyapar does the first as "discount
/// during payment" and calls it a write-off; myBillBook has a payment-in
/// discount; Zoho writes off with a reason and can undo it. This does all
/// three, in one shape.
///
/// That shape is what makes it reversible for free: M31's cancel already
/// mirrors a payment's entry, reopens the bills it settled and strikes its
/// allocations, so cancelling a write-off puts the udhaar back exactly. An
/// *edit* is refused (cancel and write off again), because the edit path
/// would re-take it as a receipt.
///
/// Each kind has its own number series (`SD-`, `WO-`), so the khata, a
/// reprinted bill and the activity log say which it was without a column of
/// its own — no schema change was open to this milestone.
library;

import 'package:pk_money/pk_money.dart';

import '../entitlement/roles.dart';
import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';
import 'fifo_allocator.dart';
import 'receipt_posting.dart';

/// What is let go.
enum AllowanceKind {
  /// Forgiven to settle: "Rs 500 chhor diye".
  settlementDiscount(
    docType: 'settlement_discount',
    prefix: 'SD',
    accountKey: 'settlement_discount',
    narration: 'Settlement discount',
    auditAction: 'SETTLEMENT_DISCOUNT_GIVEN',
  ),

  /// Given up on: a bad debt.
  writeOff(
    docType: 'write_off',
    prefix: 'WO',
    accountKey: 'bad_debts',
    narration: 'Written off',
    auditAction: 'BAD_DEBT_WRITTEN_OFF',
  );

  const AllowanceKind({
    required this.docType,
    required this.prefix,
    required this.accountKey,
    required this.narration,
    required this.auditAction,
  });

  /// The number series it is counted in.
  final String docType;

  /// The series' prefix: `SD-2627-0001`, `WO-2627-0001`.
  final String prefix;

  /// The expense account it is posted to, by system key.
  final String accountKey;

  /// How its journal entry begins: "Written off WO-2627-0001". The cancel
  /// path (M31) finds the entry by it.
  final String narration;
  final String auditAction;

  /// The kind [paymentNo] was numbered as, or null for an ordinary payment.
  static AllowanceKind? ofPaymentNo(String paymentNo) {
    for (final k in values) {
      if (paymentNo.startsWith('${k.prefix}-')) return k;
    }
    return null;
  }
}

/// What the shopkeeper decided.
final class AllowanceDraft {
  const AllowanceDraft({
    required this.partyId,
    required this.kind,
    required this.amount,
    required this.reason,
    this.documentIds,
  });

  final String partyId;
  final AllowanceKind kind;
  final Money amount;

  /// Why. Required for a write-off; a settlement discount says one for
  /// itself when none is given.
  final String reason;

  /// The bills to let go, each in full, when the shopkeeper picked them;
  /// null to go oldest first across everything owed.
  final List<String>? documentIds;
}

/// Why letting udhaar go was refused, in words.
final class AllowanceRefused implements Exception {
  const AllowanceRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Builds the rows one allowance writes, in the shape of a receipt so the
/// payment writer that writes receipts writes it.
final class AllowanceBuilder {
  const AllowanceBuilder();

  ReceiptPosting build({
    required ActorContext actor,
    required AllowanceDraft draft,
    required List<OpenBill> openBills,
    required Money owed,
    required AllocatedNumber paymentNumber,
    required AllocatedNumber journalNumber,
    required String ledgerAccountId,
    required String paymentAccountId,
  }) {
    final no = paymentNumber.formatted;
    final why = draft.reason.trim();
    if (draft.kind == AllowanceKind.writeOff && why.isEmpty) {
      // The first question anybody asks of a write-off, a year later.
      throw const AllowanceRefused('A write-off has to say why.');
    }
    if (!draft.amount.isPositive) {
      throw const AllowanceRefused('There is nothing to let go.');
    }
    if (draft.amount > owed) {
      // Letting go more than is owed would leave the shop owing the
      // customer money that never changed hands.
      throw AllowanceRefused(
        'Only Rs ${owed.amountOnly} is owed; Rs ${draft.amount.amountOnly} '
        'cannot be let go.',
      );
    }

    final FifoAllocation allocation;
    final picked = draft.documentIds;
    if (picked != null) {
      final byId = {for (final b in openBills) b.documentId: b};
      final chosen = <OpenBill>[];
      for (final id in picked) {
        final bill = byId[id];
        if (bill == null) {
          throw const AllowanceRefused(
            'One of the bills picked is no longer open.',
          );
        }
        chosen.add(bill);
      }
      final total = Money.sum([for (final b in chosen) b.outstanding]);
      if (total != draft.amount) {
        throw AllowanceRefused(
          'The bills picked come to Rs ${total.amountOnly}, not '
          'Rs ${draft.amount.amountOnly}.',
        );
      }
      allocation = allocateFifo(draft.amount, chosen);
    } else {
      allocation = allocateFifo(draft.amount, openBills);
    }

    final outstanding = {
      for (final b in openBills) b.documentId: b.outstanding,
    };
    final allocations = [
      for (final a in allocation.allocations)
        AllocationPosting(
          documentId: a.documentId,
          amount: a.amount,
          mode: picked == null ? 'fifo' : 'manual',
        ),
    ];
    final settlements = [
      for (final a in allocation.allocations)
        BillSettlement(
          documentId: a.documentId,
          paid: a.amount,
          balance: outstanding[a.documentId]! - a.amount,
        ),
    ];

    final narration = '${draft.kind.narration} $no';
    var lineNo = 1;
    final lines = <JournalLinePosting>[
      // The cost: Settlement Discount or Bad Debts, never the drawer.
      JournalLinePosting(
        lineNo: lineNo++,
        accountSystemKey: '#$ledgerAccountId',
        debit: draft.amount,
        credit: Money.zero,
        partyId: draft.partyId,
        narration: narration,
      ),
      if (allocation.applied.isPositive)
        JournalLinePosting(
          lineNo: lineNo++,
          accountSystemKey: 'accounts_receivable',
          debit: Money.zero,
          credit: allocation.applied,
          partyId: draft.partyId,
          narration: 'Against ${allocations.length} bill(s)',
        ),
      // What no bill absorbed is the opening balance they started with: it
      // sits against the receivable the opening posted, and is cleared the
      // way a receipt against it is, on the customer's advances.
      if (allocation.unapplied.isPositive)
        JournalLinePosting(
          lineNo: lineNo++,
          accountSystemKey: 'customer_advances',
          debit: Money.zero,
          credit: allocation.unapplied,
          partyId: draft.partyId,
          narration: 'Off the opening balance',
        ),
    ];

    final reason = why.isEmpty ? draft.kind.narration : why;
    final posting = ReceiptPosting(
      payment: PaymentPosting(
        paymentNo: no,
        direction: 'in',
        paymentAccountId: paymentAccountId,
        ledgerAccountId: ledgerAccountId,
        mode: 'adjustment',
        amount: draft.amount,
        change: Money.zero,
        partyId: draft.partyId,
        notes: reason,
        paymentDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        paymentDateLocal: actor.businessDate.value,
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
        totalDebit: draft.amount,
        totalCredit: draft.amount,
        narration: narration,
        lines: lines,
      ),
      auditSummary:
          '${draft.kind.narration} $no of ${draft.amount.amountOnly} on '
          '${allocations.length} bill(s): $reason',
      auditAction: draft.kind.auditAction,
    );
    posting.assertBalanced();
    return posting;
  }
}

/// Whether [role] may write a customer's udhaar off: whoever may put the
/// books right (M31's `correctEntries`). A write-off is the books saying
/// money will not come, which is the owner's or the munshi's call, never
/// the counter's.
bool mayWriteOff(Role role) => role.can(Permission.correctEntries);

/// Whether [role] may let [discount] go to settle [settled] (the money
/// taken and the discount together) on its own say-so.
///
/// Within the role's discount ceiling, as at the counter (M22): a cashier
/// may let Rs 500 go on Rs 10,000, five per cent, and no more. Whoever may
/// write a balance off altogether may let any part of it go.
bool settlementDiscountAllowed({
  required Role role,
  required Money settled,
  required Money discount,
}) =>
    mayWriteOff(role) ||
    discountAllowed(role: role, subtotal: settled, discount: discount);
