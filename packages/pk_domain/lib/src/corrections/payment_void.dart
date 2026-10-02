/// Cancelling money that was taken or paid (M31).
///
/// Until this, a receipt keyed in wrong stayed wrong. The khata showed it,
/// the bills it settled read as paid, and the only advice the app had —
/// "undo those first", in the refusal to cancel a bill — pointed at a button
/// that did not exist.
///
/// A payment is undone the way a bill is: never by editing it, always by
/// writing the opposite and pointing at what it undid.
///
///  * its journal entry is mirrored, dated today, side for side (see
///    `reversal.dart` — never a minus sign);
///  * the bills it settled are owed again, for exactly what it put on each;
///  * its allocations are released, so no report or reprinted bill still
///    counts the money against those bills;
///  * the payment row is marked `void`, and nothing else on it changes —
///    the receipt the customer is holding still matches what the shop has.
///
/// ## What is refused, and why
///
/// Money taken at the counter with a bill is part of that bill: its debit
/// sits inside the sale's own entry, and cancelling it on its own would
/// leave a bill reading paid with no money behind it. It goes with the bill.
///
/// A cheque is the other case. Cancelling a cheque the shop is still holding
/// (or one it wrote that nobody has presented) is the paper going back, and
/// is allowed. Once it is at the bank, or the bank has paid or returned it,
/// the bank's record and the shop's would disagree: cancelling would say the
/// shop never had a cheque the bank is clearing, or that money it has in
/// the bank never came. Those are refused, in words, and the cheque is moved
/// on through its own lifecycle instead (M6).
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../receivables/receipt_posting.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';
import 'reversal.dart';

/// Why a payment cannot be cancelled or edited, when it cannot.
enum PaymentLock {
  /// It can be put right.
  none,

  /// It already has been.
  cancelled,

  /// Taken at the counter with a bill, and goes with that bill.
  takenWithBill,

  /// A cheque at the bank, waiting to clear.
  chequeAtBank,

  /// A cheque the bank has paid.
  chequeCleared,

  /// A cheque the bank sent back.
  chequeBounced,
}

/// Whether a payment can be put right, decided in one place.
///
/// The payment's page uses this to decide which buttons to offer and the
/// builder uses it to decide what to refuse, so the screen can never offer a
/// Cancel that the books then turn down.
PaymentLock paymentLockOf({
  required String status,
  required String mode,
  required String? chequeStatus,
  required bool takenWithBill,
}) {
  if (status == 'void') return PaymentLock.cancelled;
  if (takenWithBill) return PaymentLock.takenWithBill;
  if (status == 'bounced') return PaymentLock.chequeBounced;
  if (mode == 'cheque') {
    if (chequeStatus == 'deposited') return PaymentLock.chequeAtBank;
    if (chequeStatus == 'cleared' || status == 'cleared') {
      return PaymentLock.chequeCleared;
    }
  }
  return PaymentLock.none;
}

/// One bill a payment put money on, and where that bill stands now.
final class PaymentAllocationSnapshot {
  const PaymentAllocationSnapshot({
    required this.allocationId,
    required this.documentId,
    required this.docNo,
    required this.amount,
    required this.mode,
    required this.billPaid,
    required this.billBalance,
  });

  final String allocationId;
  final String documentId;
  final String docNo;

  /// What this payment put on the bill.
  final Money amount;

  /// `fifo`, `manual` or `exact`. `exact` is a tender the sale wrote for
  /// itself at the counter, which is what makes a payment part of its bill.
  final String mode;

  /// The bill's `paid_paisa` and `balance_paisa` as they are now, read inside
  /// the transaction, so the reopened totals are computed from the truth and
  /// not from what a screen showed a minute ago.
  final Money billPaid;
  final Money billBalance;
}

/// A payment as it was written, read back so cancelling it is the exact
/// mirror of what happened rather than of what a builder would do today.
final class PostedPaymentSnapshot {
  const PostedPaymentSnapshot({
    required this.paymentId,
    required this.paymentNo,
    required this.direction,
    required this.amount,
    required this.mode,
    required this.status,
    required this.allocations,
    this.partyId,
    this.chequeNo,
    this.chequeStatus,
    this.entryId,
    this.entry,
  });

  final String paymentId;
  final String paymentNo;

  /// `in` for money taken, `out` for money paid.
  final String direction;
  final String? partyId;
  final Money amount;
  final String mode;

  /// `cleared`, `pending`, `bounced` or `void`.
  final String status;
  final String? chequeNo;

  /// `issued`, `deposited`, `cleared`, `bounced` or `returned`; null for
  /// anything that is not a cheque.
  final String? chequeStatus;

  /// The entry that put the payment on the books, or null when none can be
  /// found — which is refused rather than guessed at.
  final String? entryId;
  final JournalEntryPosting? entry;

  /// The bills it put money on, released when it is cancelled.
  final List<PaymentAllocationSnapshot> allocations;

  bool get isCheque => mode == 'cheque';
  bool get isReceipt => direction == 'in';
}

/// Everything cancelling one payment writes.
final class PaymentVoidPosting {
  const PaymentVoidPosting({
    required this.paymentId,
    required this.paymentNo,
    required this.direction,
    required this.amount,
    required this.reason,
    required this.journal,
    required this.reversesEntryId,
    required this.reopened,
    required this.releasedAllocationIds,
    required this.auditSummary,
  });

  final String paymentId;
  final String paymentNo;
  final String direction;
  final Money amount;
  final String reason;

  /// The mirror of the payment's entry, dated today.
  final JournalEntryPosting journal;
  final String reversesEntryId;

  /// Each bill the payment settled, with its new `paid` and `balance` — the
  /// answer, not a delta, the same as everywhere else money lands on a bill.
  final List<BillSettlement> reopened;

  /// The allocation rows that stop counting. Struck out, never destroyed:
  /// the tombstone is the record of what the payment once settled.
  final List<String> releasedAllocationIds;

  final String auditSummary;

  void assertBalanced() {
    final debit = Money.sum([for (final l in journal.lines) l.debit]);
    final credit = Money.sum([for (final l in journal.lines) l.credit]);
    if (debit != credit) {
      throw StateError(
        'Cancelling $paymentNo would post an unbalanced entry: debits '
        '${debit.amountOnly}, credits ${credit.amountOnly}.',
      );
    }
    for (final line in journal.lines) {
      if (line.debit.isNegative || line.credit.isNegative) {
        throw StateError(
          'Cancelling $paymentNo line ${line.lineNo} carries a negative '
          'amount. A reversal swaps the sides; it never negates.',
        );
      }
    }
  }
}

/// What cancelling a payment left behind.
final class VoidedPayment {
  const VoidedPayment({
    required this.paymentId,
    required this.paymentNo,
    required this.amount,
    required this.reversingEntryId,
    required this.reason,
    required this.reopenedDocumentIds,
  });

  final String paymentId;
  final String paymentNo;
  final Money amount;
  final String reversingEntryId;
  final String reason;

  /// The bills that are owed again because of it.
  final List<String> reopenedDocumentIds;
}

/// Builds the cancellation of a payment, or refuses it in words.
final class PaymentVoidBuilder {
  const PaymentVoidBuilder();

  PaymentVoidPosting build({
    required ActorContext actor,
    required PostedPaymentSnapshot payment,
    required String reason,
    required AllocatedNumber journalNumber,
  }) {
    final why = reason.trim();
    final no = payment.paymentNo;
    if (why.isEmpty) {
      // The same rule as a bill: a cancellation nobody can explain six
      // months later is the first thing an auditor asks about.
      throw const VoidRefused('A cancellation has to say why.');
    }
    // Taken at the counter with a bill. Its money is a line inside the
    // sale's entry, not an entry of its own, so there is nothing of its own
    // to mirror — and the bill would read paid with no money behind it.
    final counterBill = payment.allocations
        .where((a) => a.mode == 'exact')
        .map((a) => a.docNo)
        .firstOrNull;
    final cheque = payment.chequeNo ?? no;
    switch (paymentLockOf(
      status: payment.status,
      mode: payment.mode,
      chequeStatus: payment.chequeStatus,
      takenWithBill: counterBill != null,
    )) {
      case PaymentLock.none:
        break;
      case PaymentLock.cancelled:
        throw VoidRefused('$no is already cancelled.');
      case PaymentLock.takenWithBill:
        throw VoidRefused(
          '$no was taken at the counter with bill $counterBill, and goes '
          'with it. Open that bill and return or cancel it instead.',
        );
      case PaymentLock.chequeBounced:
        throw VoidRefused(
          'Cheque $cheque already came back from the bank, and what it paid '
          'is already owed again. There is nothing left to cancel.',
        );
      case PaymentLock.chequeAtBank:
        throw VoidRefused(
          'Cheque $cheque is at the bank. Cancelling it now would say the '
          'shop never had a cheque the bank is clearing: wait, and mark it '
          'cleared or bounced on the Cheques screen.',
        );
      case PaymentLock.chequeCleared:
        throw VoidRefused(
          payment.isReceipt
              ? 'Cheque $cheque has cleared: the money is in the bank. '
                    'Cancelling the receipt would say it never arrived.'
              : 'Cheque $cheque has been paid by the bank: the money has '
                    'left the account. Cancelling the payment would say it '
                    'never went.',
        );
    }

    final entry = payment.entry;
    final entryId = payment.entryId;
    if (entry == null || entryId == null) {
      // A payment with no entry never reached the books. Appending a
      // reversal of nothing would burn a journal number on an entry with no
      // lines, so it is refused and named instead.
      throw VoidRefused(
        '$no has no journal entry, so there is nothing to undo. The books '
        'need checking before it is cancelled.',
      );
    }

    final applied = Money.sum([for (final a in payment.allocations) a.amount]);
    if (applied > payment.amount) {
      throw StateError(
        '$no is allocated ${applied.amountOnly} against bills, more than the '
        '${payment.amount.amountOnly} it was for.',
      );
    }

    final reopened = <BillSettlement>[
      for (final a in payment.allocations)
        () {
          final paid = a.billPaid - a.amount;
          if (paid.isNegative) {
            throw StateError(
              '${a.docNo} reads ${a.billPaid.amountOnly} paid, less than the '
              '${a.amount.amountOnly} $no put on it.',
            );
          }
          // What it was paid, less what this payment put on it; what it
          // owes, plus the same. The bounce does exactly this (M6).
          return BillSettlement(
            documentId: a.documentId,
            paid: paid,
            balance: a.billBalance + a.amount,
          );
        }(),
    ];

    final kind = payment.isReceipt ? 'receipt' : 'payment';
    final posting = PaymentVoidPosting(
      paymentId: payment.paymentId,
      paymentNo: no,
      direction: payment.direction,
      amount: payment.amount,
      reason: why,
      journal: reverseEntry(
        entry,
        actor: actor,
        number: journalNumber,
        // The payment's number as well as the reason, for the same reason a
        // bill's reversal carries the bill's: nobody at a counter looks a
        // payment up by its journal number.
        reason: '$no — $why',
      ),
      reversesEntryId: entryId,
      reopened: reopened,
      releasedAllocationIds: [
        for (final a in payment.allocations) a.allocationId,
      ],
      auditSummary:
          'Cancelled $kind $no of ${payment.amount.amountOnly}'
          '${reopened.isEmpty ? '' : ', ${reopened.length} bill(s) owed again'}'
          ': $why',
    );
    posting.assertBalanced();
    return posting;
  }
}
