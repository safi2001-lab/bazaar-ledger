/// What a khata entry looks like when it is opened (M31).
///
/// The khata's history is a list of one-line summaries, and a summary is not
/// enough to answer the questions a customer actually asks about a payment —
/// "which bill did my Rs 5,000 go on?", "who took it?" — nor to correct one.
/// These are the whole entry, read for the page that opens when it is tapped.
library;

import 'package:pk_money/pk_money.dart';

import '../corrections/payment_void.dart';
import '../time/clock.dart';

/// One bill a payment put money on.
final class SettledBill {
  const SettledBill({
    required this.documentId,
    required this.docNo,
    required this.docType,
    required this.dateLocal,
    required this.sequence,
    required this.amount,
  });

  final String documentId;
  final String docNo;
  final String docType;
  final String dateLocal;

  /// The bill's place in its series, so a list rebuilt from these sorts the
  /// way the payment writer sorts open bills.
  final int sequence;

  /// What this payment put on it.
  final Money amount;
}

/// One payment, taken or made, as its own page shows it.
final class PaymentDetail {
  const PaymentDetail({
    required this.id,
    required this.paymentNo,
    required this.direction,
    required this.amount,
    required this.mode,
    required this.paymentAccountId,
    required this.paymentAccountName,
    required this.dateLocal,
    required this.status,
    required this.enteredBy,
    required this.settled,
    this.partyId,
    this.partyName,
    this.reference,
    this.notes,
    this.chequeNo,
    this.chequeBank,
    this.chequeDue,
    this.chequeStatus,
    this.counterBillId,
    this.counterBillNo,
    this.cancelReason,
    this.cancelledBy,
    this.cancelledAt,
    this.enteredAt,
    this.replaces,
    this.replacesId,
    this.replacedBy,
    this.replacedById,
  });

  final String id;
  final String paymentNo;

  /// `in` for money taken, `out` for money paid.
  final String direction;
  final String? partyId;
  final String? partyName;
  final Money amount;

  /// `cash`, `bank_transfer`, `jazzcash`, `easypaisa`, `cheque` and so on.
  final String mode;
  final String paymentAccountId;
  final String paymentAccountName;
  final String? reference;
  final String? notes;
  final String dateLocal;

  /// `cleared`, `pending`, `bounced` or `void`.
  final String status;
  final String? chequeNo;
  final String? chequeBank;
  final BusinessDate? chequeDue;
  final String? chequeStatus;

  /// Who keyed it in, and when, as a shopkeeper reads a time: "23-08-2026
  /// 2:15 PM". The fear these answer is the one every shop with staff has —
  /// a receipt that appeared, or changed, with nobody owning it.
  final String enteredBy;
  final String? enteredAt;

  /// The bills it settled — still, or until it was cancelled.
  final List<SettledBill> settled;

  /// The bill it was taken with at the counter, when it was.
  final String? counterBillId;
  final String? counterBillNo;

  /// Why it was cancelled, by whom and when, when it was.
  final String? cancelReason;
  final String? cancelledBy;
  final String? cancelledAt;

  /// The payment this one was entered to correct, and the one that corrected
  /// this, when either happened — number and id, so the page can open the
  /// other and the whole chain of an entry corrected twice can be walked.
  final String? replaces;
  final String? replacesId;
  final String? replacedBy;
  final String? replacedById;

  bool get isReceipt => direction == 'in';
  bool get isCheque => mode == 'cheque';
  bool get isCancelled => status == 'void';

  /// What no bill absorbed: money the shop is holding for the customer.
  Money get onAccount =>
      amount - Money.sum([for (final b in settled) b.amount]);

  /// Whether it can be put right, by the same rule the books apply.
  PaymentLock get lock => paymentLockOf(
    status: status,
    mode: mode,
    chequeStatus: chequeStatus,
    takenWithBill: counterBillId != null,
  );
}

/// A charge on a khata or an expense, as its own page shows it.
final class EntryDocument {
  const EntryDocument({
    required this.id,
    required this.docType,
    required this.docNo,
    required this.dateLocal,
    required this.status,
    required this.total,
    required this.balance,
    required this.note,
    required this.enteredBy,
    required this.paidBy,
    this.partyId,
    this.partyName,
    this.head,
    this.paidFromAccountId,
  });

  final String id;

  /// `other_income` (a charge) or `expense`.
  final String docType;
  final String docNo;
  final String dateLocal;

  /// `posted` or `void`.
  final String status;
  final String? partyId;
  final String? partyName;
  final Money total;

  /// What is still owed on it.
  final Money balance;
  final String note;
  final String enteredBy;

  /// An expense's head (`rent`, `salaries`, ...), read off its debit line.
  final String? head;

  /// The payment account an expense paid at once came out of.
  final String? paidFromAccountId;

  /// Payments recorded against it since. While any stands, it cannot be
  /// cancelled or changed: the payment has to go first, or it would be
  /// left settling something that no longer exists.
  final List<String> paidBy;

  bool get isCancelled => status == 'void';
  bool get isCharge => docType == 'other_income';
}
