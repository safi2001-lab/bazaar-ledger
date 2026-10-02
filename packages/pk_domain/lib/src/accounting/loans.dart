/// Loans the shop has taken, their repayments, and a statement for each
/// (M48).
///
/// A shop borrows. Rs 5 lakh from the bank against the stock for Eid, the
/// committee (BC) it drew first this year, Rs 50,000 from a brother-in-law,
/// a supplier who let the shop owe for a freezer and charges a little on it.
/// Every month some of it goes back, part of it off the loan and part of it
/// interest, and the shopkeeper wants three things answered: how much is
/// still owed, how much the borrowing has cost, and a paper that says both
/// to hand the lender or the accountant.
///
/// ## Nothing new in the database
///
/// A loan is an account of the chart: a liability, under a Loans group,
/// numbered after the last liability the way the shop's own accounts are
/// (M26). What it is still owed is that account's balance, so the balance
/// sheet shows it with nothing taught to read it, and the trial balance
/// cannot disagree with the loans screen. Interest, the processing fee and
/// charges are three indirect expense accounts, so the profit and loss
/// shows them where Vyapar does, under expenses below gross profit.
///
/// What the chart cannot hold about a loan (who lent it, on what rate, for
/// how long, what the instalment is) is kept in one `settings` row per loan,
/// under `loan.<account id>`, written once when the loan is taken. The
/// books never read it: a rate there decides what interest the repayment
/// screen suggests, and nothing else.
///
/// Every line of every entry a loan writes carries `loan:<account id>` in
/// the ledger's `cost_centre`, its free sub-ledger dimension. A month in
/// which only interest was paid never touches the loan's own account (none
/// of it came off the loan), and without the tag it would fall off the
/// loan's statement while still costing the shop money.
///
/// ## Corrections
///
/// A loan or a repayment entered wrong is cancelled, never edited: the
/// opposite entry, dated the day it is cancelled, pointing at what it
/// undid. A loan cannot be cancelled while repayments against it stand,
/// because the books would then read as the shop having paid back money it
/// never borrowed.
library;

import 'dart:convert';

import 'package:pk_money/pk_money.dart';

import '../receivables/aging.dart' show daysBetween;
import '../sales/sale_posting.dart'
    show JournalEntryPosting, JournalLinePosting;
import '../time/clock.dart';

/// The group every loan account sits under, by its stable key.
const loansGroupKey = 'loans';

/// What borrowing costs, as the profit and loss names it.
const loanInterestKey = 'loan_interest';
const loanFeeKey = 'loan_processing_fee';
const loanChargesKey = 'loan_charges';

/// The settings row a loan's terms are kept in.
String loanSettingKey(String loanId) => 'loan.$loanId';

/// What every line of a loan's entries carries in `cost_centre`.
String loanTag(String loanId) => 'loan:$loanId';

/// Why a loan, a repayment or a cancellation was refused, in words.
final class LoanRefused implements Exception {
  const LoanRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// What the shop knows about a loan that the chart cannot hold.
final class LoanTerms {
  const LoanTerms({
    required this.lender,
    required this.amount,
    required this.takenOn,
    required this.receiptEntryId,
    this.fee = Money.zero,
    this.rateBp,
    this.termMonths,
    this.instalment,
    this.notes,
  });

  /// The bank, the committee, the relative or the supplier.
  final String lender;

  /// What the shop owes for it, before anything was paid back.
  final Money amount;

  /// The processing fee taken out of it on the day.
  final Money fee;

  final BusinessDate takenOn;

  /// The entry that brought it into the books; cancelling that entry is
  /// cancelling the loan.
  final String receiptEntryId;

  /// The yearly rate in basis points: 1650 is 16.5% a year. Null for a loan
  /// that carries none, as most from family and every committee do.
  final int? rateBp;

  final int? termMonths;

  /// The monthly instalment (EMI) the lender asked for, when there is one.
  final Money? instalment;

  final String? notes;

  String toJson() => jsonEncode({
    'lender': lender,
    'amount': amount.inPaisa,
    'fee': fee.inPaisa,
    'takenOn': takenOn.value,
    'receiptEntryId': receiptEntryId,
    if (rateBp != null) 'rateBp': rateBp,
    if (termMonths != null) 'termMonths': termMonths,
    if (instalment != null) 'instalment': instalment!.inPaisa,
    if (notes != null) 'notes': notes,
  });

  /// Reads what [toJson] wrote. A row nobody can read is a loan with no
  /// terms, never a crash on the loans screen.
  static LoanTerms? fromJson(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) return null;
    final lender = decoded['lender'];
    final amount = decoded['amount'];
    final takenOn = decoded['takenOn'];
    final entry = decoded['receiptEntryId'];
    if (lender is! String ||
        amount is! int ||
        takenOn is! String ||
        entry is! String) {
      return null;
    }
    final date = BusinessDate.tryParse(takenOn);
    if (date == null) return null;
    final fee = decoded['fee'];
    final rate = decoded['rateBp'];
    final term = decoded['termMonths'];
    final instalment = decoded['instalment'];
    final notes = decoded['notes'];
    return LoanTerms(
      lender: lender,
      amount: Money.paisa(amount),
      fee: fee is int ? Money.paisa(fee) : Money.zero,
      takenOn: date,
      receiptEntryId: entry,
      rateBp: rate is int ? rate : null,
      termMonths: term is int ? term : null,
      instalment: instalment is int ? Money.paisa(instalment) : null,
      notes: notes is String ? notes : null,
    );
  }
}

/// A loan as the shopkeeper enters it.
final class LoanDraft {
  const LoanDraft({
    required this.lender,
    required this.amount,
    required this.intoPaymentAccountId,
    required this.takenOn,
    this.fee = Money.zero,
    this.rateBp,
    this.termMonths,
    this.instalment,
    this.notes,
  });

  final String lender;

  /// What the shop owes for it: the amount the lender sanctioned.
  final Money amount;

  /// The cash drawer or the bank it came into.
  final String intoPaymentAccountId;

  final BusinessDate takenOn;

  /// A processing fee, taken out of what came in. The loan is owed in full,
  /// what reaches the cash or the bank is the amount less the fee, and the
  /// fee is an expense of the day. Whether the bank kept it back or it was
  /// paid out of the same account that afternoon, the books end the same;
  /// one entry keeps the two together, so cancelling the loan cancels its
  /// fee. A fee paid from somewhere else is an expense of its own.
  final Money fee;

  final int? rateBp;
  final int? termMonths;
  final Money? instalment;
  final String? notes;

  /// What actually reached the cash or the bank.
  Money get received => amount - fee;
}

/// One repayment as the shopkeeper enters it: what went out, and how much of
/// it was interest and charges. The rest came off the loan.
final class RepaymentDraft {
  const RepaymentDraft({
    required this.loanId,
    required this.paid,
    required this.fromPaymentAccountId,
    required this.paidOn,
    this.interest = Money.zero,
    this.charges = Money.zero,
    this.note,
  });

  final String loanId;

  /// Everything that left the cash or the bank.
  final Money paid;

  final Money interest;

  /// A late-payment penalty, a bank's charge for the instalment.
  final Money charges;

  final String fromPaymentAccountId;
  final BusinessDate paidOn;
  final String? note;

  /// What came off the loan.
  Money get principal => paid - interest - charges;
}

/// The entry a loan comes into the books with: the cash or the bank up by
/// what reached it, the fee as an expense, and the loan owed in full.
///
/// Every account is an id the writer has already resolved. Refuses, in
/// words, a loan with no lender, no amount, a fee as large as the loan, a
/// rate nobody charges, or a date not yet come.
JournalEntryPosting loanTakenEntry({
  required LoanDraft draft,
  required BusinessDate today,
  required String loanName,
  required String entryNo,
  required int recordedAtUtcMillis,
  required String loanAccountId,
  required String intoAccountId,
  String? feeAccountId,
}) {
  checkLoanDraft(draft, today: today);
  if (draft.fee.isPositive && feeAccountId == null) {
    throw StateError('A fee was taken and there is no account for it.');
  }
  final lines = <JournalLinePosting>[
    JournalLinePosting(
      lineNo: 1,
      accountSystemKey: '#$intoAccountId',
      debit: draft.received,
      credit: Money.zero,
      narration: loanName,
    ),
    if (draft.fee.isPositive)
      JournalLinePosting(
        lineNo: 2,
        accountSystemKey: '#$feeAccountId',
        debit: draft.fee,
        credit: Money.zero,
        narration: 'Processing fee, $loanName',
      ),
    JournalLinePosting(
      lineNo: draft.fee.isPositive ? 3 : 2,
      accountSystemKey: '#$loanAccountId',
      debit: Money.zero,
      credit: draft.amount,
      narration: loanName,
    ),
  ];
  return JournalEntryPosting(
    entryNo: entryNo,
    entryDateUtcMillis: recordedAtUtcMillis,
    entryDateLocal: draft.takenOn.value,
    fiscalYear: draft.takenOn.fiscalYear,
    sourceType: 'manual',
    totalDebit: draft.amount,
    totalCredit: draft.amount,
    narration: '$loanName received',
    lines: lines,
  );
}

/// Refuses a loan that cannot be right, before anything is written.
void checkLoanDraft(LoanDraft draft, {required BusinessDate today}) {
  if (draft.lender.trim().isEmpty) {
    throw const LoanRefused(
      'Who lent it? A bank, a committee, a relative or a supplier: a loan '
      'with no lender is a number nobody can chase or repay.',
    );
  }
  if (!draft.amount.isPositive) {
    throw const LoanRefused('A loan of nothing is not a loan.');
  }
  if (draft.fee.isNegative) {
    throw const LoanRefused('A fee cannot be less than nothing.');
  }
  if (draft.fee >= draft.amount) {
    throw LoanRefused(
      'A fee of Rs ${draft.fee.amountOnly} leaves nothing of a loan of '
      'Rs ${draft.amount.amountOnly}. Check the two amounts.',
    );
  }
  final rate = draft.rateBp;
  if (rate != null && (rate < 0 || rate > 10000)) {
    throw const LoanRefused(
      'A rate is between 0% and 100% a year. Check the rate.',
    );
  }
  final term = draft.termMonths;
  if (term != null && (term < 1 || term > 600)) {
    throw const LoanRefused('A loan runs for 1 to 600 months.');
  }
  final instalment = draft.instalment;
  if (instalment != null && !instalment.isPositive) {
    throw const LoanRefused('An instalment of nothing is not an instalment.');
  }
  if (draft.takenOn.value.compareTo(today.value) > 0) {
    throw LoanRefused(
      'The loan is dated ${draft.takenOn.value}, which has not come yet. '
      'Enter it on the day the money arrives.',
    );
  }
}

/// The entry one repayment writes: the loan down by what came off it,
/// interest and charges as expenses, and the cash or the bank down by all
/// of it.
///
/// [owed] is what the loan stands at before it. A repayment that takes more
/// off the loan than is owed is refused in words: it is nearly always
/// interest typed as principal, or a zero too many.
JournalEntryPosting repaymentEntry({
  required RepaymentDraft draft,
  required String loanName,
  required Money owed,
  required BusinessDate takenOn,
  required BusinessDate today,
  required String entryNo,
  required int recordedAtUtcMillis,
  required String loanAccountId,
  required String fromAccountId,
  String? interestAccountId,
  String? chargesAccountId,
}) {
  if (!draft.paid.isPositive) {
    throw const LoanRefused('A repayment of nothing is not a repayment.');
  }
  if (draft.interest.isNegative || draft.charges.isNegative) {
    throw const LoanRefused(
      'Interest and charges cannot be less than nothing.',
    );
  }
  final principal = draft.principal;
  if (principal.isNegative) {
    throw LoanRefused(
      'Interest and charges come to '
      'Rs ${(draft.interest + draft.charges).amountOnly}, more than the '
      'Rs ${draft.paid.amountOnly} paid. Check the amounts.',
    );
  }
  if (principal > owed) {
    throw LoanRefused(
      'Rs ${principal.amountOnly} off the loan is more than the '
      'Rs ${owed.amountOnly} still owed on it. Put the rest down as '
      'interest or charges, or check the amount paid.',
    );
  }
  if (draft.paidOn.value.compareTo(takenOn.value) < 0) {
    throw LoanRefused(
      'The loan was taken on ${takenOn.value}. A repayment cannot be dated '
      'before it.',
    );
  }
  if (draft.paidOn.value.compareTo(today.value) > 0) {
    throw LoanRefused(
      'The repayment is dated ${draft.paidOn.value}, which has not come '
      'yet. Enter it on the day it is paid.',
    );
  }
  if (draft.interest.isPositive && interestAccountId == null) {
    throw StateError('Interest was paid and there is no account for it.');
  }
  if (draft.charges.isPositive && chargesAccountId == null) {
    throw StateError('Charges were paid and there is no account for them.');
  }

  final note = draft.note?.trim() ?? '';
  final said = note.isEmpty
      ? 'Repayment, $loanName'
      : 'Repayment, $loanName: $note';
  final lines = <JournalLinePosting>[];
  void add(String accountId, Money debit, Money credit, String narration) =>
      lines.add(
        JournalLinePosting(
          lineNo: lines.length + 1,
          accountSystemKey: '#$accountId',
          debit: debit,
          credit: credit,
          narration: narration,
        ),
      );
  if (principal.isPositive) {
    add(loanAccountId, principal, Money.zero, said);
  }
  if (draft.interest.isPositive) {
    add(interestAccountId!, draft.interest, Money.zero, 'Interest, $loanName');
  }
  if (draft.charges.isPositive) {
    add(chargesAccountId!, draft.charges, Money.zero, 'Charges, $loanName');
  }
  add(fromAccountId, Money.zero, draft.paid, said);

  return JournalEntryPosting(
    entryNo: entryNo,
    entryDateUtcMillis: recordedAtUtcMillis,
    entryDateLocal: draft.paidOn.value,
    fiscalYear: draft.paidOn.fiscalYear,
    sourceType: 'manual',
    totalDebit: draft.paid,
    totalCredit: draft.paid,
    narration: said,
    lines: lines,
  );
}

/// The interest a repayment on [on] most likely carries: simple interest on
/// what is still [owed], at the yearly [rateBp], for the days since the
/// loan was last paid against (or taken), on a 365-day year, to the paisa.
///
/// A suggestion the shopkeeper overwrites with what the bank's slip says.
/// Banks round, count days differently and charge on the instalment
/// schedule rather than the calendar; the figure only has to be close
/// enough that typing the real one is a correction, not a calculation.
Money suggestedInterest({
  required Money owed,
  required int rateBp,
  required BusinessDate since,
  required BusinessDate on,
}) {
  if (!owed.isPositive || rateBp <= 0) return Money.zero;
  final days = daysBetween(since.value, on.value);
  if (days <= 0) return Money.zero;
  return Money.paisa(
    divideRounded(
      owed.inPaisa * rateBp * days,
      10000 * 365,
      RoundingMode.halfUp,
    ),
  );
}

/// When interest started running for a repayment on [on]: the last day the
/// loan was taken or paid against on or before it, cancelled entries and
/// cancellations left out. Null when nothing stands before [on].
BusinessDate? interestRunsFrom(List<LoanPosting> postings, BusinessDate on) {
  BusinessDate? last;
  for (final p in postings) {
    if (p.isReversal || p.reversed) continue;
    if (p.date.value.compareTo(on.value) > 0) continue;
    if (last == null || p.date.value.compareTo(last.value) > 0) last = p.date;
  }
  return last;
}

/// Refuses a cancellation that cannot be right.
///
/// [owedNow] is what the loan stands at today. Cancelling the loan's own
/// entry while repayments against it stand would leave it paid back more
/// than it was lent, so those go first.
void checkLoanCancel({
  required LoanPosting entry,
  required Money owedNow,
  required String reason,
}) {
  if (reason.trim().isEmpty) {
    throw const LoanRefused(
      'A cancellation has to say why. An entry undone for no reason is the '
      'first thing an accountant asks about.',
    );
  }
  if (entry.isReversal) {
    throw const LoanRefused(
      'That line is itself a cancellation. Enter the loan or the repayment '
      'again if it was right after all.',
    );
  }
  if (entry.reversed) {
    throw LoanRefused('${entry.entryNo} was cancelled already.');
  }
  if ((owedNow - entry.owedChange).isNegative) {
    throw const LoanRefused(
      'Repayments stand against this loan. Cancel them first, or the books '
      'read as the shop having paid back money it never borrowed.',
    );
  }
}

/// A loan, as the loans screen lists it.
final class LoanView {
  const LoanView({
    required this.id,
    required this.code,
    required this.name,
    required this.owed,
    this.terms,
    this.cancelled = false,
  });

  /// The loan's account in the chart.
  final String id;
  final String code;
  final String name;

  /// What is still owed on it: the account's balance.
  final Money owed;

  /// Null when the terms row could not be read.
  final LoanTerms? terms;

  /// Its own entry has been cancelled: it was entered by mistake.
  final bool cancelled;
}

/// One journal entry that moved a loan, as the books hold it.
final class LoanPosting {
  const LoanPosting({
    required this.entryId,
    required this.entryNo,
    required this.date,
    required this.narration,
    required this.loanDebit,
    required this.loanCredit,
    this.interest = Money.zero,
    this.charges = Money.zero,
    this.reversesEntryId,
    this.reversed = false,
  });

  final String entryId;
  final String entryNo;
  final BusinessDate date;
  final String narration;

  /// What it put on each side of the loan's own account.
  final Money loanDebit;
  final Money loanCredit;

  /// Debits less credits on Loan Interest in the same entry.
  final Money interest;

  /// Debits less credits on the processing fee and Loan Charges.
  final Money charges;

  /// The entry this one cancels, when it is a cancellation.
  final String? reversesEntryId;

  /// A later entry cancelled this one.
  final bool reversed;

  bool get isReversal => reversesEntryId != null;

  /// What it did to what is owed: up for money borrowed.
  Money get owedChange => loanCredit - loanDebit;
}

/// What a statement line was.
enum LoanLineKind { received, repaid, cancelled }

/// One line of a loan's statement.
final class LoanStatementLine {
  const LoanStatementLine({
    required this.entryId,
    required this.entryNo,
    required this.date,
    required this.kind,
    required this.narration,
    required this.borrowed,
    required this.repaid,
    required this.interest,
    required this.charges,
    required this.owedAfter,
    required this.reversed,
  });

  final String entryId;
  final String entryNo;
  final BusinessDate date;
  final LoanLineKind kind;
  final String narration;

  /// Money borrowed. A cancelled loan shows it again as a minus, in the
  /// same column, so the column still adds up to what was borrowed.
  final Money borrowed;

  /// What came off the loan; a cancelled repayment, a minus.
  final Money repaid;

  final Money interest;

  /// The processing fee and charges.
  final Money charges;

  /// What was owed once it was done.
  final Money owedAfter;

  /// A later entry cancelled it.
  final bool reversed;
}

/// A loan's statement for a period: what was owed when it began, every
/// receipt and repayment in it with principal and interest apart and what
/// was owed after each, and what is owed at the end.
final class LoanStatement {
  const LoanStatement({
    required this.name,
    required this.from,
    required this.to,
    required this.opening,
    required this.lines,
  });

  final String name;
  final BusinessDate from;
  final BusinessDate to;

  /// What was owed before [from].
  final Money opening;
  final List<LoanStatementLine> lines;

  /// What is owed at the end of [to]. The loan account's balance on that
  /// day, by construction: both are every posting to it added up.
  Money get closing => lines.isEmpty ? opening : lines.last.owedAfter;

  Money get borrowed => Money.sum(lines.map((l) => l.borrowed));
  Money get repaid => Money.sum(lines.map((l) => l.repaid));
  Money get interest => Money.sum(lines.map((l) => l.interest));
  Money get charges => Money.sum(lines.map((l) => l.charges));
}

/// Builds a loan's statement from every entry that moved it, in the order
/// the books hold them (date, then the order they were written).
///
/// Pure, so the reports pack can build the same statement from the same
/// postings: a Loan Statement in the reports and the one on the loan's own
/// screen cannot disagree.
LoanStatement buildLoanStatement({
  required String name,
  required List<LoanPosting> postings,
  required BusinessDate from,
  required BusinessDate to,
}) {
  var owed = Money.zero;
  Money? opening;
  final lines = <LoanStatementLine>[];
  for (final p in postings) {
    if (p.date.value.compareTo(to.value) > 0) continue;
    if (p.date.value.compareTo(from.value) < 0) {
      owed = owed + p.owedChange;
      continue;
    }
    opening ??= owed;
    owed = owed + p.owedChange;
    // A cancellation reads in the columns of what it undid: a cancelled
    // repayment is a minus in the repaid column, not money borrowed.
    final undoesReceipt = p.isReversal && p.owedChange.isNegative;
    final isReceipt = !p.isReversal && p.owedChange.isPositive;
    final borrowedColumn = isReceipt || undoesReceipt;
    lines.add(
      LoanStatementLine(
        entryId: p.entryId,
        entryNo: p.entryNo,
        date: p.date,
        kind: p.isReversal
            ? LoanLineKind.cancelled
            : (isReceipt ? LoanLineKind.received : LoanLineKind.repaid),
        narration: p.narration,
        borrowed: borrowedColumn ? p.owedChange : Money.zero,
        repaid: borrowedColumn ? Money.zero : -p.owedChange,
        interest: p.interest,
        charges: p.charges,
        owedAfter: owed,
        reversed: p.reversed,
      ),
    );
  }
  return LoanStatement(
    name: name,
    from: from,
    to: to,
    opening: opening ?? owed,
    lines: lines,
  );
}
