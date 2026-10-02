import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';

/// Every entry that moved one loan, in the order the books hold them (M48).
///
/// ?1 the firm, ?2 the loan's account id, ?3 its tag (`loan:<id>`).
///
/// An entry belongs to a loan when it touches the loan's account, or when it
/// carries the loan's tag on a line to one of the borrowing-cost accounts:
/// a month in which only interest was paid never touches the loan itself.
/// Both halves go through the account index, so a shop with years of bills
/// does not scan them to draw one loan's statement.
///
/// Kept as SQL here so the reports pack's source can read the same rows and
/// hand them to the same `buildLoanStatement`.
const loanPostingsSql = '''
  SELECT je.id, je.entry_no, je.entry_date_local,
         COALESCE(je.narration, '') AS narration,
         je.reverses_entry_id,
         EXISTS (
           SELECT 1 FROM journal_entries r
           WHERE r.reverses_entry_id = je.id AND r.firm_id = ?1
             AND r.deleted_at_utc IS NULL
         ) AS reversed,
         COALESCE(SUM(CASE WHEN jl.account_id = ?2
                           THEN jl.debit_paisa END), 0) AS loan_debit,
         COALESCE(SUM(CASE WHEN jl.account_id = ?2
                           THEN jl.credit_paisa END), 0) AS loan_credit,
         COALESCE(SUM(CASE WHEN substr(a.system_key, 1, 13) = 'loan_interest'
                           THEN jl.debit_paisa - jl.credit_paisa END), 0)
           AS interest,
         COALESCE(SUM(CASE WHEN substr(a.system_key, 1, 19)
                                  = 'loan_processing_fee'
                             OR substr(a.system_key, 1, 12) = 'loan_charges'
                           THEN jl.debit_paisa - jl.credit_paisa END), 0)
           AS charges
  FROM journal_entries je
  JOIN journal_lines jl
    ON jl.journal_entry_id = je.id AND jl.deleted_at_utc IS NULL
  JOIN accounts a ON a.id = jl.account_id
  WHERE je.firm_id = ?1 AND je.deleted_at_utc IS NULL
    AND je.id IN (
      SELECT journal_entry_id FROM journal_lines
      WHERE firm_id = ?1 AND account_id = ?2 AND deleted_at_utc IS NULL
      UNION
      SELECT journal_entry_id FROM journal_lines
      WHERE firm_id = ?1 AND cost_centre = ?3 AND deleted_at_utc IS NULL
        AND account_id IN (
          SELECT id FROM accounts
          WHERE firm_id = ?1 AND substr(system_key, 1, 5) = 'loan_'
        )
    )
  GROUP BY je.id
  ORDER BY je.entry_date_local, je.created_at_utc, je.id
''';

/// Every loan the shop has taken, with what is owed on each now. ?1 firm.
const loansSql = '''
  SELECT a.id, a.code, a.name, s.setting_value,
         COALESCE((
           SELECT SUM(jl.credit_paisa - jl.debit_paisa) FROM journal_lines jl
           WHERE jl.firm_id = ?1 AND jl.account_id = a.id
             AND jl.deleted_at_utc IS NULL
         ), 0) AS owed
  FROM settings s
  JOIN accounts a
    ON a.id = substr(s.setting_key, 6) AND a.firm_id = s.firm_id
   AND a.deleted_at_utc IS NULL
  WHERE s.firm_id = ?1 AND substr(s.setting_key, 1, 5) = 'loan.'
    AND s.deleted_at_utc IS NULL
  ORDER BY a.code
''';

/// Reading loans out of the books (M48).
final class DriftLoanReads {
  const DriftLoanReads(this._db);

  final AppDatabase _db;

  /// Every loan, by its code in the chart.
  Future<List<LoanView>> loans(String firmId) async {
    final rows = await _db
        .customSelect(
          loansSql,
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.settings, _db.accounts, _db.journalLines},
        )
        .get();
    return [for (final r in rows) await _view(firmId, r)];
  }

  /// One loan, or null when [loanId] is not a loan of this firm.
  Future<LoanView?> loan(String firmId, String loanId) async {
    for (final l in await loans(firmId)) {
      if (l.id == loanId) return l;
    }
    return null;
  }

  /// Every entry that moved [loanId], oldest first.
  Future<List<LoanPosting>> postings(String firmId, String loanId) async {
    final rows = await _db
        .customSelect(
          loanPostingsSql,
          variables: [
            Variable<String>(firmId),
            Variable<String>(loanId),
            Variable<String>(loanTag(loanId)),
          ],
          readsFrom: {_db.journalEntries, _db.journalLines, _db.accounts},
        )
        .get();
    return [for (final r in rows) loanPostingFrom(r)];
  }

  Future<LoanView> _view(String firmId, QueryRow r) async {
    final terms = LoanTerms.fromJson(r.read<String>('setting_value'));
    var cancelled = false;
    if (terms != null) {
      final undone = await _db
          .customSelect(
            'SELECT 1 FROM journal_entries WHERE firm_id = ? '
            'AND reverses_entry_id = ? AND deleted_at_utc IS NULL',
            variables: [
              Variable<String>(firmId),
              Variable<String>(terms.receiptEntryId),
            ],
            readsFrom: {_db.journalEntries},
          )
          .get();
      cancelled = undone.isNotEmpty;
    }
    return LoanView(
      id: r.read<String>('id'),
      code: r.read<String>('code'),
      name: r.read<String>('name'),
      owed: Money.paisa(r.read<int>('owed')),
      terms: terms,
      cancelled: cancelled,
    );
  }
}

/// One row of [loanPostingsSql] as the domain reads it.
LoanPosting loanPostingFrom(QueryRow r) => LoanPosting(
  entryId: r.read<String>('id'),
  entryNo: r.read<String>('entry_no'),
  date: BusinessDate(r.read<String>('entry_date_local')),
  narration: r.read<String>('narration'),
  loanDebit: Money.paisa(r.read<int>('loan_debit')),
  loanCredit: Money.paisa(r.read<int>('loan_credit')),
  interest: Money.paisa(r.read<int>('interest')),
  charges: Money.paisa(r.read<int>('charges')),
  reversesEntryId: r.readNullable<String>('reverses_entry_id'),
  reversed: r.read<int>('reversed') == 1,
);
