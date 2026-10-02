/// Deciding which bills a payment settles.
///
/// A wholesale customer walks in with Rs 50,000 against four open bills and
/// says nothing about which. Every competing product in this market either
/// nets the payment against a single running balance or asks the cashier to
/// tick boxes, and being unable to answer *which bills did this settle* is
/// the single most-complained-about gap in their reviews. A shopkeeper who
/// cannot answer it cannot argue with a customer about it either.
///
/// Oldest first, because that is what both sides already assume: the customer
/// thinks they are clearing last month, and the shop wants the oldest debt
/// off its books. It is also what makes an ageing report mean anything — a
/// payment applied to the newest bill leaves a 90-day bucket that never
/// empties while the customer pays every month.
///
/// ## Two rules that look like details and are not
///
/// **A settled bill is skipped, never netted.** Taking the overshoot off the
/// next bill in the list would produce the right total and the wrong khata:
/// the shop's record would show a bill part-paid that the customer paid in
/// full, and the argument at the counter is unwinnable from either side.
///
/// **Money left over becomes an advance, never an allocation row.** It is
/// tempting to park the remainder on the oldest bill as a credit and let a
/// later purchase absorb it. That writes an allocation larger than the bill
/// it points at, and `findOverAllocatedPayments()` is the health check that
/// would find it — six months later, in somebody else's shop, with no way
/// left to reconstruct what was meant.
library;

import 'package:pk_money/pk_money.dart';

/// One bill a payment could be applied to.
final class OpenBill {
  const OpenBill({
    required this.documentId,
    required this.dateLocal,
    required this.sequence,
    required this.outstanding,
    this.docNo = '',
    this.docType = '',
  });

  final String documentId;

  /// The number printed on the paper, and what kind of paper it is
  /// (`sale_invoice`, `other_income`, `purchase_bill`, `expense`).
  ///
  /// Not used to allocate — the allocation is by date and sequence and
  /// nothing else. Carried for the khata, which showed a customer's open
  /// bills by their database id until M31: twenty-six characters of ULID
  /// where the shopkeeper needed "INV-2627-0042".
  final String docNo;
  final String docType;

  /// `YYYY-MM-DD`, the business date. Sorted on before [sequence] because a
  /// backdated bill entered on Sunday belongs where its date puts it, not
  /// where it was typed.
  final String dateLocal;

  /// The document's own counter within its series, which breaks ties between
  /// bills raised on the same day in the order they were actually raised.
  final int sequence;

  /// What is still owed on it. Never zero or negative in a well-formed list;
  /// [allocateFifo] skips such a bill rather than trusting it.
  final Money outstanding;
}

/// One bill, and what this payment puts against it.
final class BillAllocation {
  const BillAllocation({required this.documentId, required this.amount});

  final String documentId;
  final Money amount;

  @override
  String toString() => 'BillAllocation($documentId, $amount)';
}

/// How a payment lands: some against bills, and possibly some left over.
final class FifoAllocation {
  const FifoAllocation({required this.allocations, required this.unapplied});

  /// In the order the bills were taken — oldest first.
  final List<BillAllocation> allocations;

  /// What no open bill could absorb.
  ///
  /// A customer paying Rs 5,000 against Rs 3,000 of bills is not an error and
  /// must not be refused: they are leaving credit, which is ordinary in a
  /// shop that takes standing orders. It becomes an advance, and the one
  /// thing it must never become is an allocation row.
  final Money unapplied;

  Money get applied => allocations.fold(Money.zero, (a, b) => a + b.amount);
}

/// Applies [amount] to [bills], oldest first.
///
/// [bills] may arrive in any order and is not mutated. The result's
/// allocations plus its unapplied remainder always sum back to [amount]
/// exactly — that is the property the whole thing is for, and it holds by
/// construction because every step subtracts what it just handed out.
FifoAllocation allocateFifo(Money amount, List<OpenBill> bills) {
  if (!amount.isPositive) {
    throw ArgumentError.value(
      amount.inPaisa,
      'amount',
      'a payment of nothing, or of less than nothing, is not a payment. A '
          'refund is a payment in the other direction and has its own row.',
    );
  }

  final ordered = [...bills]
    ..sort((a, b) {
      final byDate = a.dateLocal.compareTo(b.dateLocal);
      if (byDate != 0) return byDate;
      final bySeq = a.sequence.compareTo(b.sequence);
      if (bySeq != 0) return bySeq;
      // Two bills on the same date with the same sequence should not exist,
      // but a sort that is not total gives a different answer on different
      // runs, and an allocation that is not reproducible is not evidence.
      return a.documentId.compareTo(b.documentId);
    });

  final allocations = <BillAllocation>[];
  var remaining = amount;

  for (final bill in ordered) {
    if (!remaining.isPositive) break;
    // Settled, or malformed. Either way this payment has nothing to do here,
    // and netting the overshoot onto it would record a bill as part-paid that
    // the customer paid in full.
    if (!bill.outstanding.isPositive) continue;

    final take = remaining < bill.outstanding ? remaining : bill.outstanding;
    allocations.add(BillAllocation(documentId: bill.documentId, amount: take));
    remaining -= take;
  }

  return FifoAllocation(allocations: allocations, unapplied: remaining);
}
