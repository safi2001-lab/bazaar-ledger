/// Closing a year into retained earnings (M26).
///
/// At the end of June every income and expense account is emptied into
/// Retained Earnings with one entry dated the last day of the year, so the
/// next year's profit and loss starts at nothing and the balance sheet
/// carries what was made as the owner's. Nothing is edited: the closing is
/// an entry like any other, and a year closed by mistake is undone by
/// reversing it.
library;

import 'package:pk_money/pk_money.dart';

import '../sales/sale_posting.dart'
    show JournalEntryPosting, JournalLinePosting;

/// Why a year cannot be closed, in words.
final class YearCloseRefused implements Exception {
  const YearCloseRefused(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// One income or expense account's movement in the year: debits less
/// credits, so an expense is positive and an income negative.
typedef YearBalance = ({String accountId, String name, Money net});

/// The last day of the Pakistani fiscal year [fiscalYear] (`2526` is
/// 1 July 2025 to 30 June 2026).
String fiscalYearEnd(int fiscalYear) =>
    '20${(fiscalYear % 100).toString().padLeft(2, '0')}-06-30';

/// The closing entry: every account in [balances] brought to nothing, the
/// difference to [retainedAccountId]. Null when there is nothing to close.
JournalEntryPosting? yearCloseEntry({
  required int fiscalYear,
  required String entryNo,
  required int entryDateUtcMillis,
  required List<YearBalance> balances,
  required String retainedAccountId,
}) {
  final open = [
    for (final b in balances)
      if (!b.net.isZero) b,
  ]..sort((a, b) => a.name.compareTo(b.name));
  if (open.isEmpty) return null;

  final lines = <JournalLinePosting>[];
  var n = 0;
  for (final b in open) {
    n++;
    lines.add(
      JournalLinePosting(
        lineNo: n,
        accountSystemKey: '#${b.accountId}',
        debit: b.net.isNegative ? -b.net : Money.zero,
        credit: b.net.isNegative ? Money.zero : b.net,
        narration: 'Year closed: ${b.name}',
      ),
    );
  }
  // What the year made: income (credit balances) less expense.
  final profit = -Money.sum([for (final b in open) b.net]);
  if (!profit.isZero) {
    n++;
    lines.add(
      JournalLinePosting(
        lineNo: n,
        accountSystemKey: '#$retainedAccountId',
        debit: profit.isNegative ? -profit : Money.zero,
        credit: profit.isNegative ? Money.zero : profit,
        narration: profit.isNegative
            ? 'Loss for the year'
            : 'Profit for the year',
      ),
    );
  }
  final total = Money.sum([for (final l in lines) l.debit]);
  final end = fiscalYearEnd(fiscalYear);
  return JournalEntryPosting(
    entryNo: entryNo,
    entryDateUtcMillis: entryDateUtcMillis,
    entryDateLocal: end,
    fiscalYear: fiscalYear,
    sourceType: 'year_close',
    totalDebit: total,
    totalCredit: Money.sum([for (final l in lines) l.credit]),
    narration:
        'Year ${fiscalYear ~/ 100}-${(fiscalYear % 100).toString().padLeft(2, '0')} '
        'closed into retained earnings',
    lines: lines,
  );
}
