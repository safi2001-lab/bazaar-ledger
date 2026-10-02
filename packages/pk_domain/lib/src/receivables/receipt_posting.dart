/// Taking money against udhaar, described before any of it is written.
///
/// The same shape as a sale posting and for the same reason: the rows are a
/// value, the entry is proved to balance while it is still a value, and the
/// write either commits all of it or none of it. A use case that wrote
/// nothing then has nothing to return.
library;

import 'package:pk_money/pk_money.dart';

import '../sales/sale_posting.dart';

/// One row for `payment_allocations`: this much of the payment against that
/// bill.
final class AllocationPosting {
  const AllocationPosting({
    required this.documentId,
    required this.amount,
    required this.mode,
  });

  final String documentId;
  final Money amount;

  /// `fifo`, `manual` or `exact`. Recorded rather than assumed, because a
  /// cashier who overrode the default and a cashier who accepted it are
  /// answering a customer's question differently six months later.
  final String mode;
}

/// What one bill's balance becomes once this payment lands on it.
///
/// Stated rather than left to the writer to compute, so the arithmetic is in
/// the pure layer where it can be asserted, and so the writer's job is to
/// apply numbers rather than to invent them.
final class BillSettlement {
  const BillSettlement({
    required this.documentId,
    required this.paid,
    required this.balance,
  });

  final String documentId;

  /// The bill's new `paid_paisa` and `balance_paisa`, not the deltas.
  final Money paid;
  final Money balance;
}

/// Everything one receipt writes.
final class ReceiptPosting {
  const ReceiptPosting({
    required this.payment,
    required this.allocations,
    required this.settlements,
    required this.unapplied,
    required this.journal,
    required this.auditSummary,
    this.auditAction,
  });

  final PaymentPosting payment;
  final List<AllocationPosting> allocations;
  final List<BillSettlement> settlements;

  /// What no open bill absorbed. Credited to `customer_advances`, and it is
  /// the reason this can balance without a matching allocation row.
  final Money unapplied;

  final JournalEntryPosting journal;
  final String auditSummary;

  /// The audit action, when it is not a plain receipt or payment: a
  /// settlement discount or a write-off (M44) is written by the same writer
  /// and said in the activity log as what it is.
  final String? auditAction;

  /// Asserts the entry balances, before anyone tries to write it.
  ///
  /// The database has a CHECK for this and `Tx` re-checks before commit.
  /// Three layers, because silent accounting wrongness is invisible for six
  /// months and then nothing balances and nobody can say when it started.
  void assertBalanced() {
    final debit = Money.sum([for (final l in journal.lines) l.debit]);
    final credit = Money.sum([for (final l in journal.lines) l.credit]);
    if (debit != credit) {
      throw StateError(
        'Receipt ${payment.paymentNo} would post an unbalanced entry: '
        'debits ${debit.amountOnly}, credits ${credit.amountOnly}, out by '
        '${(debit - credit).amountOnly}.',
      );
    }
    if (debit != journal.totalDebit || credit != journal.totalCredit) {
      throw StateError(
        'Receipt ${payment.paymentNo} declares totals that its own lines do '
        'not add up to.',
      );
    }
    for (final line in journal.lines) {
      // A negative debit is a credit wearing the wrong hat. The sums above
      // still match, so the equality passes, and the schema's own
      // `CHECK (debit_paisa >= 0)` refuses the write three layers later as a
      // constraint error with nothing in it a shopkeeper could act on.
      if (line.debit.isNegative || line.credit.isNegative) {
        throw StateError(
          'Receipt ${payment.paymentNo} line ${line.lineNo} carries a '
          'negative amount. A reversal swaps the sides; it never negates.',
        );
      }
    }

    // The allocations and the advance together are the payment. If they are
    // not, the shop's cash and its khata disagree by an amount nobody can
    // account for — and the journal above would still balance, because both
    // halves come from the same wrong total.
    final allocated = Money.sum([for (final a in allocations) a.amount]);
    if (allocated + unapplied != payment.amount) {
      throw StateError(
        'Receipt ${payment.paymentNo} allocates ${allocated.amountOnly} and '
        'holds ${unapplied.amountOnly} on account, which is not the '
        '${payment.amount.amountOnly} that was handed over.',
      );
    }
  }
}
