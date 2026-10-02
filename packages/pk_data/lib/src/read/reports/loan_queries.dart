part of '../drift_report_source.dart';

/// The reads behind the Loan Statement in the hub (M58): M48's own, through
/// `DriftLoanReads`, so the hub's statement and the loan screen's are built
/// from the same rows by the same `buildLoanStatement`.
mixin _LoanQueries implements LoanReportSource {
  AppDatabase get _db;

  @override
  Future<List<LoanView>> loans(String firmId) =>
      DriftLoanReads(_db).loans(firmId);

  @override
  Future<List<LoanPosting>> loanPostings(String firmId, String loanId) =>
      DriftLoanReads(_db).postings(firmId, loanId);

  /// What the loan filter can be set to: every loan, matching [term] by its
  /// name or its lender. A shop has a handful, so they are read whole.
  Future<List<ReportChoice>> _loanChoices(String firmId, String term) async {
    final loans = await DriftLoanReads(_db).loans(firmId);
    return [
      for (final l in loans)
        if (term.isEmpty ||
            l.name.toLowerCase().contains(term) ||
            (l.terms?.lender.toLowerCase().contains(term) ?? false))
          ReportChoice(
            id: l.id,
            label: l.name,
            detail: 'Rs ${l.owed.amountOnly}',
          ),
    ];
  }
}
