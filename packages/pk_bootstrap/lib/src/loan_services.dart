part of 'app_services.dart';

/// Loans the shop has taken, their repayments, and a statement for each
/// (M48).
///
/// Writing a loan writes the books, so it takes the journal permission:
/// the owner and the accountant. Reading one is reading the books, so the
/// statement takes the reports permission, as the trial balance does.
///
/// Taking a new loan is part of the paid accounting set, with the profit
/// and loss and the balance sheet it shows up in. Paying one back is not,
/// and neither is its statement: a shop whose plan lapsed still owes the
/// bank, and still has to write down what it paid. As with every plan
/// gate, only starting something new of a paid kind is refused.
final class LoanServices {
  LoanServices._(this._app);

  final AppServices _app;

  DriftLoanReads get _reads => DriftLoanReads(_app.database);
  DriftLoanWriter get _writer => DriftLoanWriter(runner: _app._runner);

  String get _firmId {
    final id = _app._identity;
    if (id == null) throw StateError('No shop is set up on this phone yet.');
    return id.firmId;
  }

  /// Every loan, by its code in the chart.
  Future<List<LoanView>> list() async {
    _app.require(Permission.reports);
    return _reads.loans(_firmId);
  }

  /// One loan, or null when it is not one of this shop's.
  Future<LoanView?> loan(String loanId) async {
    _app.require(Permission.reports);
    return _reads.loan(_firmId, loanId);
  }

  /// Every entry that moved [loanId], oldest first.
  Future<List<LoanPosting>> postings(String loanId) async {
    _app.require(Permission.reports);
    return _reads.postings(_firmId, loanId);
  }

  /// Takes a loan. Returns its id.
  Future<String> take(LoanDraft draft) async {
    _app.require(Permission.journal);
    _app.plans.require(PlanFeature.accountingReports);
    return _writer.take(_app.actorNow(), draft);
  }

  /// Pays some of a loan back. Returns the entry's number.
  Future<String> repay(RepaymentDraft draft) async {
    _app.require(Permission.journal);
    return _writer.repay(_app.actorNow(), draft);
  }

  /// Cancels a loan or one repayment entered by mistake, saying why.
  /// Returns the cancelling entry's number.
  Future<String> cancel({
    required String loanId,
    required String entryId,
    required String reason,
  }) async {
    _app.require(Permission.journal);
    return _writer.cancel(
      _app.actorNow(),
      loanId: loanId,
      entryId: entryId,
      reason: reason,
    );
  }

  /// What a repayment on [on] most likely is: the instalment, or what is
  /// left if that is less, and the interest at the loan's rate for the days
  /// since it was last paid. Both are suggestions the screen lets the
  /// shopkeeper overwrite.
  Future<({Money paid, Money interest})> suggestRepayment(
    String loanId,
    BusinessDate on,
  ) async {
    final view = await loan(loanId);
    final terms = view?.terms;
    if (view == null || terms == null || !view.owed.isPositive) {
      return (paid: Money.zero, interest: Money.zero);
    }
    final rate = terms.rateBp;
    final since = interestRunsFrom(await postings(loanId), on);
    final interest = rate == null || since == null
        ? Money.zero
        : suggestedInterest(
            owed: view.owed,
            rateBp: rate,
            since: since,
            on: on,
          );
    final instalment = terms.instalment;
    final settles = view.owed + interest;
    final paid = instalment == null
        ? Money.zero
        : (instalment > settles ? settles : instalment);
    return (paid: paid, interest: interest);
  }

  /// The loan's statement for [period], or from the day it was taken to
  /// today when none is given.
  Future<LoanStatement> statement(String loanId, {ReportPeriod? period}) async {
    final view = await loan(loanId);
    if (view == null) {
      throw const LoanRefused('That is not a loan this shop has taken.');
    }
    final postings = await this.postings(loanId);
    final today = BusinessDate.now(_app.clock);
    final first = postings.isEmpty ? today : postings.first.date;
    final span =
        period ??
        ReportPeriod(
          first.value.compareTo(today.value) > 0 ? today : first,
          today,
        );
    return buildLoanStatement(
      name: view.name,
      postings: postings,
      from: span.from,
      to: span.to,
    );
  }
}

// The statement as a report table, `loanStatementTable`, is built in
// pk_reports since M58, beside the hub's Loan Statement that shows it: the
// loan's own screen and the hub draw it from the one builder.
