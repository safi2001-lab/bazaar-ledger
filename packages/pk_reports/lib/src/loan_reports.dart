import 'package:pk_domain/pk_domain.dart';

import 'filters.dart';
import 'period.dart';
import 'report_table.dart';

/// The Loan Statement in the hub's Loans group (M58), over the loans the
/// shop has taken (M48).
///
/// One report, two pages. Narrowed to a loan, it is that loan's statement:
/// what was owed when the period began, every receipt and repayment with
/// principal, interest and charges apart, and what is owed at the end. Not
/// narrowed, it is every loan on one page: who lent it, what was owed at the
/// start, what came in and went back, the interest, and what is outstanding.
///
/// Both are built from the same postings by M48's `buildLoanStatement`, the
/// one the loan's own screen draws its statement from, so the hub and the
/// loan screen cannot tell the shopkeeper two different things, and every
/// loan's outstanding is its account in the books on the last day.

/// Where the loan reports read from (M58).
abstract interface class LoanReportSource {
  /// Every loan the shop has taken, by its code in the chart (M48).
  Future<List<LoanView>> loans(String firmId);

  /// Every entry that moved [loanId], oldest first (M48's
  /// `loanPostingsSql`).
  Future<List<LoanPosting>> loanPostings(String firmId, String loanId);
}

/// One loan's statement, or every loan's, for [period], as [filters] asks.
Future<ReportTable> loanReport(
  LoanReportSource source, {
  required String firmId,
  required ReportPeriod period,
  required ReportFilters filters,
}) async {
  final loans = await source.loans(firmId);
  final chosen = filters.loanId;
  if (chosen != null) {
    final loan = loans.where((l) => l.id == chosen).firstOrNull;
    final statement = buildLoanStatement(
      name: loan?.name ?? filters.loanName ?? chosen,
      postings: loan == null
          ? const []
          : await source.loanPostings(firmId, loan.id),
      from: period.from,
      to: period.to,
    );
    return loanStatementTable(statement, terms: loan?.terms);
  }
  return allLoans(period, [
    for (final l in loans)
      (
        loan: l,
        statement: buildLoanStatement(
          name: l.name,
          postings: await source.loanPostings(firmId, l.id),
          from: period.from,
          to: period.to,
        ),
      ),
  ]);
}

/// Every loan the shop has taken, over [period] (M58): who lent it, what
/// was owed when the period began, what came in, what went back as
/// principal, interest and charges, and what is outstanding at its end.
///
/// A loan with nothing owed and nothing moving in the period is left off,
/// so a loan paid off last year does not crowd this year's page; a loan
/// cancelled as entered by mistake (M48) shows under its name, marked, only
/// in the period that holds both its entry and its cancelling one.
ReportTable allLoans(
  ReportPeriod period,
  List<({LoanView loan, LoanStatement statement})> loans,
) {
  final shown = [
    for (final l in loans)
      if (!l.statement.opening.isZero || l.statement.lines.isNotEmpty) l,
  ];
  Money sum(Money Function(LoanStatement s) f) =>
      Money.sum(shown.map((l) => f(l.statement)));
  final outstanding = sum((s) => s.closing);
  final repaid = sum((s) => s.repaid);
  final interest = sum((s) => s.interest);
  return ReportTable(
    id: 'loans',
    title: 'Loans',
    period: period,
    columns: const [
      ReportColumn('Loan', CellKind.text),
      ReportColumn('Lender', CellKind.text),
      ReportColumn('Taken on', CellKind.text),
      ReportColumn('Owed at start', CellKind.money),
      ReportColumn('Received', CellKind.money),
      ReportColumn('Principal repaid', CellKind.money),
      ReportColumn('Interest', CellKind.money),
      ReportColumn('Fee and charges', CellKind.money),
      ReportColumn('Outstanding', CellKind.money),
    ],
    rows: [
      for (final l in shown)
        ReportRow([
          l.loan.cancelled ? '${l.loan.name} (cancelled)' : l.loan.name,
          l.loan.terms?.lender ?? '',
          l.loan.terms?.takenOn.value ?? '',
          l.statement.opening,
          l.statement.borrowed,
          l.statement.repaid,
          l.statement.interest,
          l.statement.charges,
          l.statement.closing,
        ], link: ReportLink.loan(l.loan.id, label: l.loan.name)),
      ReportRow([
        'Total',
        shown.length == 1 ? '1 loan' : '${shown.length} loans',
        null,
        sum((s) => s.opening),
        sum((s) => s.borrowed),
        repaid,
        interest,
        sum((s) => s.charges),
        outstanding,
      ], style: RowStyle.total),
    ],
    summary: [
      ReportFigure('Outstanding', outstanding),
      ReportFigure('Principal repaid', repaid),
      ReportFigure('Interest paid', interest),
    ],
    notes: const [_outstandingIsTheBooks, _loanCosts],
  );
}

const _outstandingIsTheBooks =
    "Outstanding is each loan's own account in the books on the last day, "
    'the liability on the balance sheet. Tap a loan for its statement.';

const _loanCosts =
    'Interest, the processing fee and charges are expenses of the shop, '
    'in the profit and loss; what is outstanding is a liability on the '
    'balance sheet.';

/// A loan's statement as a report table, for the Loan Statement in the
/// hub and for a PDF or a CSV through the share sheet from the loan's own
/// screen (M48; moved here from pk_bootstrap in M58, where the reports
/// pack's other tables are built, so the hub can build it).
///
/// In English like every report the pack prints: the table is what goes to
/// the bank or the accountant. Principal and interest have columns of their
/// own, and a cancelled entry is shown again as a minus in the columns it
/// was in, so each column adds up to what really happened.
ReportTable loanStatementTable(LoanStatement statement, {LoanTerms? terms}) {
  String what(LoanStatementLine l) => switch (l.kind) {
    LoanLineKind.received => 'Loan received',
    LoanLineKind.repaid => 'Repayment',
    LoanLineKind.cancelled => 'Cancelled',
  };
  Money? shown(Money m) => m.isZero ? null : m;
  final rate = terms?.rateBp;
  final months = terms?.termMonths;
  final instalment = terms?.instalment;
  final lent = terms == null
      ? null
      : 'Lent by ${terms.lender} on ${terms.takenOn.value}: '
            'Rs ${terms.amount.amountOnly}'
            '${rate == null ? '' : ' at ${formatBp(rate)} a year'}'
            '${months == null ? '' : ' for $months months'}'
            '${instalment == null ? '' : ', instalment Rs ${instalment.amountOnly}'}.';
  return ReportTable(
    id: 'loan_statement',
    title: 'Loan statement: ${statement.name}',
    period: ReportPeriod(statement.from, statement.to),
    columns: const [
      ReportColumn('Date', CellKind.text),
      ReportColumn('Details', CellKind.text),
      ReportColumn('Entry', CellKind.text),
      ReportColumn('Received', CellKind.money),
      ReportColumn('Principal paid', CellKind.money),
      ReportColumn('Interest', CellKind.money),
      ReportColumn('Fee and charges', CellKind.money),
      ReportColumn('Outstanding', CellKind.money),
    ],
    rows: [
      ReportRow([
        statement.from.value,
        'Opening balance',
        '',
        null,
        null,
        null,
        null,
        statement.opening,
      ], style: RowStyle.subtotal),
      for (final l in statement.lines)
        ReportRow([
          l.date.value,
          l.reversed ? '${what(l)} (cancelled)' : what(l),
          l.entryNo,
          shown(l.borrowed),
          shown(l.repaid),
          shown(l.interest),
          shown(l.charges),
          l.owedAfter,
        ]),
      ReportRow([
        statement.to.value,
        'Outstanding at the end',
        '',
        statement.borrowed,
        statement.repaid,
        statement.interest,
        statement.charges,
        statement.closing,
      ], style: RowStyle.total),
    ],
    notes: [?lent, _loanCosts],
  );
}
