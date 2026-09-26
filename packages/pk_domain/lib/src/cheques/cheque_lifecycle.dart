/// What happens to a cheque after it is taken.
///
/// A cheque sits in Cheques in Hand from the moment it is handed over. It is
/// not money yet: the bills it paid are shown as paid because the customer
/// has done their part, but the shop does not have the money until the bank
/// says so. Three things can happen next, and each is recorded here:
///
///  * **Deposited** — taken to the bank. No money moves; the shop just knows
///    it is in clearing rather than in the drawer.
///  * **Cleared** — the bank has it. Dr the bank account, Cr Cheques in Hand.
///  * **Bounced** — the bank returned it. The money never came, so everything
///    the cheque settled is unsettled: the bills it paid are reopened for
///    exactly what it put on them, the udhaar comes back onto the khata, and
///    any advance it left is taken back off. Cr Cheques in Hand, Dr
///    Receivables and Customer Advances, by name.
///
/// ## Section 489-F
///
/// Issuing a cheque that bounces is an offence under s.489-F of the Pakistan
/// Penal Code, and the payee's case rests on having served notice promptly
/// after the dishonour. The shop is told the date by which to send it —
/// thirty days from the bounce — on the day it is recorded, because that is
/// the one deadline in this whole lifecycle that costs money to miss.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../receivables/receipt_posting.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';
import '../time/clock.dart';
import 'cheque_dates.dart';

/// How many days after a bounce the 489-F notice has to go by.
const noticeDaysAfterBounce = 30;

/// Why a cheque cannot be moved on, in words.
final class ChequeRefused implements Exception {
  const ChequeRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// A cheque the shop is holding.
final class ChequeInHand {
  const ChequeInHand({
    required this.paymentId,
    required this.paymentNo,
    required this.partyId,
    required this.partyName,
    required this.amount,
    required this.chequeNo,
    required this.receivedOn,
    required this.deposited,
    this.bank,
    this.due,
  });

  final String paymentId;
  final String paymentNo;
  final String partyId;
  final String partyName;
  final Money amount;
  final String chequeNo;
  final String? bank;

  /// The day it can be banked. Null only for a cheque taken before M6, which
  /// asked for no date.
  final BusinessDate? due;

  final BusinessDate receivedOn;

  /// Taken to the bank and waiting to clear.
  final bool deposited;

  /// Whether the bank will take it yet. A cheque with no date is treated as
  /// due, because refusing to clear a cheque over a date nobody recorded
  /// would strand it in hand for ever.
  bool isDueBy(BusinessDate today) =>
      due == null || daysUntil(today, due!) <= 0;
}

/// One bill a cheque put money on, and how much.
final class ChequeAllocation {
  const ChequeAllocation({required this.documentId, required this.amount});

  final String documentId;
  final Money amount;
}

/// Everything one step in a cheque's life writes.
final class ChequeStepPosting {
  const ChequeStepPosting({
    required this.paymentId,
    required this.chequeStatus,
    required this.paymentStatus,
    required this.journal,
    required this.reopened,
    required this.auditAction,
    required this.auditSummary,
  });

  final String paymentId;

  /// `deposited`, `cleared` or `bounced`.
  final String chequeStatus;

  /// `pending`, `cleared` or `bounced`.
  final String paymentStatus;

  /// Null for a deposit, which moves no money.
  final JournalEntryPosting? journal;

  /// Bills a bounce puts back, each with its new `paid` and `balance` — the
  /// answer, not a delta, so the writer has no arithmetic to get wrong.
  final List<BillSettlement> reopened;

  final String auditAction;
  final String auditSummary;

  void assertBalanced() {
    final entry = journal;
    if (entry == null) return;
    final debit = Money.sum([for (final l in entry.lines) l.debit]);
    final credit = Money.sum([for (final l in entry.lines) l.credit]);
    if (debit != credit) {
      throw StateError(
        'Cheque step on $paymentId would post an unbalanced entry: debits '
        '${debit.amountOnly}, credits ${credit.amountOnly}.',
      );
    }
    for (final line in entry.lines) {
      if (line.debit.isNegative || line.credit.isNegative) {
        throw StateError('Cheque step on $paymentId carries a negative line.');
      }
    }
  }
}

/// Builds each step in a cheque's life.
final class ChequeLifecycle {
  const ChequeLifecycle();

  /// Taken to the bank. Refused before its date: a bank will not take a
  /// post-dated cheque early, and recording it as deposited would put it in
  /// clearing on paper while it is still in the drawer.
  ChequeStepPosting deposit({
    required ActorContext actor,
    required ChequeInHand cheque,
  }) {
    _refuseIfEarly(actor, cheque, 'deposited');
    if (cheque.deposited) {
      throw ChequeRefused('Cheque ${cheque.chequeNo} is already at the bank.');
    }
    return ChequeStepPosting(
      paymentId: cheque.paymentId,
      chequeStatus: 'deposited',
      paymentStatus: 'pending',
      journal: null,
      reopened: const [],
      auditAction: 'CHEQUE_DEPOSITED',
      auditSummary:
          'Cheque ${cheque.chequeNo} from ${cheque.partyName} for '
          '${cheque.amount.amountOnly} taken to the bank',
    );
  }

  /// The bank has the money.
  ChequeStepPosting clear({
    required ActorContext actor,
    required ChequeInHand cheque,
    required String bankLedgerAccountId,
    required AllocatedNumber journalNumber,
  }) {
    _refuseIfEarly(actor, cheque, 'cleared');
    return ChequeStepPosting(
      paymentId: cheque.paymentId,
      chequeStatus: 'cleared',
      paymentStatus: 'cleared',
      journal: JournalEntryPosting(
        entryNo: journalNumber.formatted,
        entryDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        entryDateLocal: actor.businessDate.value,
        fiscalYear: actor.businessDate.fiscalYear,
        sourceType: 'payment',
        totalDebit: cheque.amount,
        totalCredit: cheque.amount,
        narration: 'Cheque ${cheque.chequeNo} cleared',
        lines: [
          JournalLinePosting(
            lineNo: 1,
            accountSystemKey: '#$bankLedgerAccountId',
            debit: cheque.amount,
            credit: Money.zero,
            narration: 'Cheque ${cheque.chequeNo} from ${cheque.partyName}',
          ),
          JournalLinePosting(
            lineNo: 2,
            accountSystemKey: 'cheques_in_hand',
            debit: Money.zero,
            credit: cheque.amount,
            partyId: cheque.partyId,
            narration: 'Cheque ${cheque.chequeNo} cleared',
          ),
        ],
      ),
      reopened: const [],
      auditAction: 'CHEQUE_CLEARED',
      auditSummary:
          'Cheque ${cheque.chequeNo} from ${cheque.partyName} for '
          '${cheque.amount.amountOnly} cleared into the bank',
    );
  }

  /// The bank returned it. [allocations] are the bills this cheque paid, as
  /// recorded when it was taken; [outstanding] is what each of those bills
  /// owes now, keyed by document id.
  ChequeStepPosting bounce({
    required ActorContext actor,
    required ChequeInHand cheque,
    required List<ChequeAllocation> allocations,
    required Map<String, ({Money paid, Money balance})> bills,
    required AllocatedNumber journalNumber,
    required String reason,
  }) {
    final applied = Money.sum([for (final a in allocations) a.amount]);
    if (applied > cheque.amount) {
      throw StateError(
        'Cheque ${cheque.chequeNo} is allocated ${applied.amountOnly} against '
        'bills, more than the ${cheque.amount.amountOnly} it was for.',
      );
    }
    final advance = cheque.amount - applied;

    final reopened = <BillSettlement>[
      for (final a in allocations)
        () {
          final bill = bills[a.documentId];
          if (bill == null) {
            throw StateError(
              'Bill ${a.documentId} was paid by cheque ${cheque.chequeNo} '
              'and cannot be found to reopen.',
            );
          }
          // The bill's new totals, as everywhere else: what it was paid,
          // less what this cheque put on it; what it owes, plus the same.
          return BillSettlement(
            documentId: a.documentId,
            paid: bill.paid - a.amount,
            balance: bill.balance + a.amount,
          );
        }(),
    ];

    final bouncedOn = actor.businessDate;
    final noticeBy = bouncedOn.addDays(noticeDaysAfterBounce);
    final why = reason.trim();

    final lines = <JournalLinePosting>[
      // The udhaar comes back, by name. What the cheque paid off bills is
      // owed again.
      if (applied.isPositive)
        JournalLinePosting(
          lineNo: 1,
          accountSystemKey: 'accounts_receivable',
          debit: applied,
          credit: Money.zero,
          partyId: cheque.partyId,
          narration: 'Cheque ${cheque.chequeNo} bounced',
        ),
      // An advance the cheque left is taken back: the shop is not holding
      // money that never arrived.
      if (advance.isPositive)
        JournalLinePosting(
          lineNo: applied.isPositive ? 2 : 1,
          accountSystemKey: 'customer_advances',
          debit: advance,
          credit: Money.zero,
          partyId: cheque.partyId,
          narration: 'Advance on cheque ${cheque.chequeNo} withdrawn',
        ),
      JournalLinePosting(
        lineNo: (applied.isPositive ? 1 : 0) + (advance.isPositive ? 1 : 0) + 1,
        accountSystemKey: 'cheques_in_hand',
        debit: Money.zero,
        credit: cheque.amount,
        partyId: cheque.partyId,
        narration: 'Cheque ${cheque.chequeNo} returned by the bank',
      ),
    ];

    return ChequeStepPosting(
      paymentId: cheque.paymentId,
      chequeStatus: 'bounced',
      paymentStatus: 'bounced',
      journal: JournalEntryPosting(
        entryNo: journalNumber.formatted,
        entryDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        entryDateLocal: bouncedOn.value,
        fiscalYear: bouncedOn.fiscalYear,
        sourceType: 'reversal',
        totalDebit: cheque.amount,
        totalCredit: cheque.amount,
        narration:
            'Cheque ${cheque.chequeNo} bounced'
            '${why.isEmpty ? '' : ': $why'}',
        lines: lines,
      ),
      reopened: reopened,
      auditAction: 'CHEQUE_BOUNCED',
      auditSummary:
          'Cheque ${cheque.chequeNo} from ${cheque.partyName} for '
          '${cheque.amount.amountOnly} bounced on ${bouncedOn.value}'
          '${why.isEmpty ? '' : ' ($why)'}; 489-F notice by ${noticeBy.value}',
    );
  }

  static void _refuseIfEarly(
    ActorContext actor,
    ChequeInHand cheque,
    String step,
  ) {
    if (!cheque.isDueBy(actor.businessDate)) {
      throw ChequeRefused(
        'Cheque ${cheque.chequeNo} is dated ${cheque.due!.value}. A bank will '
        'not take it before then, so it cannot be $step yet.',
      );
    }
  }
}
