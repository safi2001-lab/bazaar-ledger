/// Money going out that is not stock.
///
/// Rent, bijli, the boy who carries sacks, the tea. A shop that records only
/// what it sells and what it buys has a P&L that is fiction: the cash book
/// will not reconcile, the margin will look like profit, and the shopkeeper
/// will believe they made more than they did every single month.
///
/// The chart has carried rent, salaries, utilities, bad debts and misc since
/// M0. Nothing has ever posted to them.
///
/// ## Where the expense head lives
///
/// On the journal line, as `account_id`. Not on a column of its own.
///
/// A denormalised `expense_head` on `documents` would be a second answer to a
/// question the ledger already holds, and the two would disagree the first
/// time one was written by a path that forgot the other — which is exactly
/// how a shop ends up with a Trial Balance and an expense report that do not
/// match. Reading it back is a join through `journal_entries.document_id`,
/// which is what that column is for.
library;

import 'package:pk_money/pk_money.dart';

import '../identity/actor_context.dart';
import '../sales/sale_posting.dart';
import '../sales/sale_posting_builder.dart';

/// Why an expense cannot be recorded.
final class ExpenseRefused implements Exception {
  const ExpenseRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// What the shopkeeper entered.
final class ExpenseDraft {
  const ExpenseDraft({
    required this.accountSystemKey,
    required this.amount,
    required this.note,
    this.paymentAccountId,
    this.partyId,
  });

  /// Which head it goes under: `rent`, `salaries`, `utilities`, `misc`.
  /// A key rather than an id, so renaming "Bijli" cannot break a posting.
  final String accountSystemKey;

  final Money amount;

  /// What it was for, in the shopkeeper's own words. Required, because
  /// "Misc — Rs 4,000" six months later is a number nobody can defend, and
  /// misc is where every unlabelled expense ends up.
  final String note;

  /// Where the money came from. Null means it is owed rather than paid.
  final String? paymentAccountId;

  /// Who it is owed to, when it is not paid now.
  final String? partyId;

  bool get isPaidNow => paymentAccountId != null;
}

/// Everything one expense writes.
final class ExpensePosting {
  const ExpensePosting({
    required this.document,
    required this.journal,
    required this.headSystemKey,
    required this.auditSummary,
  });

  final DocumentPosting document;
  final JournalEntryPosting journal;

  /// Kept on the posting for the audit line only. The stored answer is the
  /// journal line's account, and nothing reads this back from a column.
  final String headSystemKey;

  final String auditSummary;

  void assertBalanced() {
    final debit = Money.sum([for (final l in journal.lines) l.debit]);
    final credit = Money.sum([for (final l in journal.lines) l.credit]);
    if (debit != credit) {
      throw StateError(
        'Expense ${document.docNo} would post an unbalanced entry: debits '
        '${debit.amountOnly}, credits ${credit.amountOnly}.',
      );
    }
    for (final line in journal.lines) {
      if (line.debit.isNegative || line.credit.isNegative) {
        throw StateError(
          'Expense ${document.docNo} line ${line.lineNo} carries a negative '
          'amount. Money coming back is a refund, not a negative expense.',
        );
      }
    }
  }
}

/// The heads a shop can put an expense under.
///
/// A closed list, because the point of an expense report is that a
/// shopkeeper can compare this month with last. Free-text heads produce
/// "Bijli", "bijli", "Electricity" and "Light bill" as four separate lines
/// that add up to nothing anybody can read.
const expenseHeads = <String>[
  'rent',
  'salaries',
  'utilities',
  'freight',
  'misc',
];

/// Builds the rows one expense writes.
final class ExpenseBuilder {
  const ExpenseBuilder();

  ExpensePosting build({
    required ActorContext actor,
    required ExpenseDraft draft,
    required AllocatedNumber expenseNumber,
    required AllocatedNumber journalNumber,
    String? ledgerAccountId,
  }) {
    if (!draft.amount.isPositive) {
      throw const ExpenseRefused('An expense of nothing is not an expense.');
    }
    if (!expenseHeads.contains(draft.accountSystemKey)) {
      throw ExpenseRefused(
        '"${draft.accountSystemKey}" is not an expense head this shop keeps.',
      );
    }
    if (draft.note.trim().isEmpty) {
      throw const ExpenseRefused(
        'An expense has to say what it was for. Six months later the amount '
        'on its own is a number nobody can defend.',
      );
    }
    if (draft.isPaidNow && ledgerAccountId == null) {
      throw const ExpenseRefused(
        'Money was paid and there is no account it came out of.',
      );
    }
    if (!draft.isPaidNow && draft.partyId == null) {
      // An unpaid expense with nobody to pay is money the shop can never
      // settle, sitting in a total it can never explain. The mirror of the
      // rule that a bill left part-paid has to name a customer.
      throw const ExpenseRefused(
        'An expense that has not been paid has to say who it is owed to.',
      );
    }

    final journalLines = <JournalLinePosting>[
      JournalLinePosting(
        lineNo: 1,
        accountSystemKey: draft.accountSystemKey,
        debit: draft.amount,
        credit: Money.zero,
        narration: draft.note.trim(),
      ),
      JournalLinePosting(
        lineNo: 2,
        accountSystemKey: draft.isPaidNow
            ? '#$ledgerAccountId'
            : 'accounts_payable',
        debit: Money.zero,
        credit: draft.amount,
        partyId: draft.isPaidNow ? null : draft.partyId,
        narration: 'Expense ${expenseNumber.formatted}',
      ),
    ];

    final posting = ExpensePosting(
      document: DocumentPosting(
        docType: 'expense',
        docNo: expenseNumber.formatted,
        docSeries: expenseNumber.series,
        docSeq: expenseNumber.sequence,
        fiscalYear: actor.businessDate.fiscalYear,
        docDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        docDateLocal: actor.businessDate.value,
        subtotal: draft.amount,
        lineDiscount: Money.zero,
        billDiscount: Money.zero,
        taxable: draft.amount,
        tax: Money.zero,
        furtherTax: Money.zero,
        withholding: Money.zero,
        extraCharges: Money.zero,
        roundOff: Money.zero,
        total: draft.amount,
        paid: draft.isPaidNow ? draft.amount : Money.zero,
        balance: draft.isPaidNow ? Money.zero : draft.amount,
        cost: Money.zero,
        roundingMode: 'half_up',
        taxRuleVersion: '',
        cashThresholdBreached: false,
        partyId: draft.partyId,
        notes: draft.note.trim(),
      ),
      journal: JournalEntryPosting(
        entryNo: journalNumber.formatted,
        entryDateUtcMillis: actor.startedAtUtc.millisecondsSinceEpoch,
        entryDateLocal: actor.businessDate.value,
        fiscalYear: actor.businessDate.fiscalYear,
        sourceType: 'expense',
        totalDebit: draft.amount,
        totalCredit: draft.amount,
        narration: 'Expense ${expenseNumber.formatted}: ${draft.note.trim()}',
        lines: journalLines,
      ),
      headSystemKey: draft.accountSystemKey,
      auditSummary:
          'Expense ${expenseNumber.formatted} of ${draft.amount.amountOnly} '
          'under ${draft.accountSystemKey}: ${draft.note.trim()}',
    );

    posting.assertBalanced();
    return posting;
  }
}
