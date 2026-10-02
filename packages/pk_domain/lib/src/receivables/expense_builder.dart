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
///
/// ## The shop's money and the home's (M47)
///
/// A shopkeeper pays the shop's bijli and his children's school fees out of
/// the same drawer, and writes both in the same book. The school fees are
/// not a cost of running the shop: counted as one, they make every month's
/// profit look smaller than it was, and the owner stops believing the
/// report. So an expense marked [ExpenseDraft.forHome] — "ghar ka kharcha" —
/// is posted to Owner's Drawings, an equity account the profit and loss
/// never reads: the drawer goes down, the owner's share of the shop goes
/// down with it, and the profit stays what the shop actually made. It is
/// still an `expense` document, so it sits in the same list, opens the same
/// way and is cancelled by the same M31 path as the shop's own.
///
/// ## The shop's own heads (M47)
///
/// [expenseHeads] is the shipped list. A shop that pays a generator's diesel
/// every week adds a head of its own: an expense account in the chart, with
/// no system key, named by the shop. It is handed to the builder as
/// `#<account id>`, the resolved form every posting already understands, and
/// the writer checks the account really is one of the shop's expense heads
/// before anything is written.
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
    this.forHome = false,
    this.tag,
  });

  /// Which head it goes under: `rent`, `salaries`, `utilities`, `misc`.
  /// A key rather than an id, so renaming "Bijli" cannot break a posting.
  ///
  /// Or `#<account id>` for a head the shop added itself (M47), which has no
  /// key. Ignored when [forHome]: the owner's drawings have no head.
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

  /// Ghar ka kharcha (M47): the home's spending, paid out of the shop. Posted
  /// to Owner's Drawings, never to a head of expense, so it never reaches
  /// the profit and loss.
  final bool forHome;

  /// What every line of its entry carries in `journal_lines.cost_centre`, or
  /// null for none. Always `expense:...` (see `shop_money/tags.dart`): today
  /// only `expense:recurring:<id>`, the monthly bill an expense paid.
  final String? tag;

  bool get isPaidNow => paymentAccountId != null;
}

/// The account the home's spending is posted to (M47).
const ownerDrawingsKey = 'owner_drawings';

/// Whether [key] names a head an expense can go under: a shipped one, or
/// one of the shop's own as `#<account id>`. The writer checks the account
/// behind a `#` key before it posts.
bool isExpenseHeadKey(String key) =>
    expenseHeads.contains(key) || (key.startsWith('#') && key.length > 1);

/// Everything one expense writes.
final class ExpensePosting {
  const ExpensePosting({
    required this.document,
    required this.journal,
    required this.headSystemKey,
    required this.auditSummary,
    this.costCentre,
    this.forHome = false,
  });

  final DocumentPosting document;
  final JournalEntryPosting journal;

  /// Kept on the posting for the audit line only. The stored answer is the
  /// journal line's account, and nothing reads this back from a column.
  /// `owner_drawings` for the home's spending; `#<id>` for a shop's own head.
  final String headSystemKey;

  final String auditSummary;

  /// Written on every line's `cost_centre` (M47), or null.
  final String? costCentre;

  /// Whether this is the owner's drawings rather than the shop's spending.
  /// The service boundary asks, because only the owner and the accountant
  /// may post it.
  final bool forHome;

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
    final head = draft.forHome ? ownerDrawingsKey : draft.accountSystemKey;
    if (!draft.forHome && !isExpenseHeadKey(head)) {
      throw ExpenseRefused('"$head" is not an expense head this shop keeps.');
    }
    final tag = draft.tag;
    if (tag != null && !tag.startsWith('expense:')) {
      // The ledger's one free dimension is shared: M48's loans write
      // `loan:<id>` there. A tag of another prefix on an expense would be
      // read by whichever feature owns that prefix as one of its own.
      throw ExpenseRefused('"$tag" is not an expense tag.');
    }
    if (draft.forHome && !draft.isPaidNow) {
      // Money owed for the house is the owner's debt, not the shop's: it
      // has no place on a supplier's khata the shop settles.
      throw const ExpenseRefused(
        'Ghar ka kharcha is money taken out of the shop now. Pick the cash '
        'or the bank it came out of.',
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

    // What the book calls it: "Ghar ka kharcha" for the home's, so a day
    // book read months later says whose money it was without a lookup.
    final what = draft.forHome ? 'Ghar ka kharcha' : 'Expense';
    final journalLines = <JournalLinePosting>[
      JournalLinePosting(
        lineNo: 1,
        accountSystemKey: head,
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
        narration: '$what ${expenseNumber.formatted}',
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
        narration: '$what ${expenseNumber.formatted}: ${draft.note.trim()}',
        lines: journalLines,
      ),
      headSystemKey: head,
      auditSummary:
          '$what ${expenseNumber.formatted} of ${draft.amount.amountOnly} '
          'under $head: ${draft.note.trim()}',
      costCentre: tag,
      forHome: draft.forHome,
    );

    posting.assertBalanced();
    return posting;
  }
}
