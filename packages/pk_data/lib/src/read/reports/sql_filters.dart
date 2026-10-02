part of '../drift_report_source.dart';

/// The parameters of a report query built a clause at a time (M33).
///
/// Numbered, never interpolated: a party's name or a category typed by a
/// shopkeeper goes into SQLite as a bound value, so a category called
/// `x' OR '1'='1` is a category and nothing else. `?1` is always the firm,
/// and `?2` and `?3` the period's first and last day when there is one.
final class _Params {
  _Params(String firmId, [ReportPeriod? period]) {
    text(firmId);
    if (period != null) {
      text(period.from.value);
      text(period.to.value);
    }
  }

  final List<Variable<Object>> variables = [];

  /// Binds [value] and returns its placeholder.
  String text(String value) {
    variables.add(Variable<String>(value));
    return '?${variables.length}';
  }
}

/// The accounts that hold money (M33): the drawer, the banks and the
/// wallets, and whatever ledger account each payment account posts into. Not
/// Cheques in Hand: a cheque is not money until it clears into a bank, and
/// counting it on the day it was taken would count it twice when it does.
/// Reads `?1` as the firm.
const _moneyAccounts = '''
  SELECT id FROM accounts
   WHERE firm_id = ?1 AND system_key IN ('cash_in_hand', 'bank', 'wallet')
  UNION
  SELECT pa.ledger_account_id FROM payment_accounts pa
    JOIN accounts a ON a.id = pa.ledger_account_id
   WHERE pa.firm_id = ?1
     AND COALESCE(a.system_key, '') <> 'cheques_in_hand'
''';

/// The drawer alone, as the Cash Book counts it. Reads `?1` as the firm.
const _drawerAccounts = '''
  SELECT id FROM accounts WHERE firm_id = ?1 AND system_key = 'cash_in_hand'
  UNION
  SELECT ledger_account_id FROM payment_accounts
   WHERE firm_id = ?1 AND mode_label = 'cash'
''';

/// The `AND ...` clauses that narrow a query over `documents` [doc], joined
/// to `parties` [party], by [f]: the filters every document report shares.
/// A transaction type is the caller's, because what it means differs from
/// one report to the next.
String _documentWhere(
  ReportFilters f,
  _Params q, {
  String doc = 'd',
  String party = 'p',
}) {
  final w = StringBuffer();
  if (f.partyId != null) {
    w.write(' AND $doc.party_id = ${q.text(f.partyId!)}');
  }
  if (f.partyGroup != null) {
    if (f.partyGroup == ReportFilters.ungrouped) {
      w.write(
        ' AND $doc.party_id IS NOT NULL'
        " AND COALESCE(TRIM($party.party_group), '') = ''",
      );
    } else {
      w.write(
        ' AND TRIM($party.party_group) = ${q.text(f.partyGroup!.trim())}',
      );
    }
  }
  if (f.userId != null) {
    w.write(' AND $doc.created_by = ${q.text(f.userId!)}');
  }
  switch (f.paymentStatus) {
    case PaymentStatus.paid:
      w.write(' AND $doc.balance_paisa <= 0');
    case PaymentStatus.partial:
      w.write(' AND $doc.balance_paisa > 0 AND $doc.paid_paisa > 0');
    case PaymentStatus.unpaid:
      w.write(' AND $doc.balance_paisa > 0 AND $doc.paid_paisa <= 0');
    case null:
      break;
  }
  if (f.paymentMode != null) {
    // Rides idx_alloc_doc: the bill's own allocations, and the payments
    // behind them.
    w.write('''
       AND EXISTS (
         SELECT 1 FROM payment_allocations fa
         JOIN payments fp ON fp.id = fa.payment_id
         WHERE fa.document_id = $doc.id
           AND fa.deleted_at_utc IS NULL
           AND fp.deleted_at_utc IS NULL
           AND fp.status <> 'void'
           AND fp.mode = ${q.text(f.paymentMode!)}
       )''');
  }
  if (f.itemId != null) {
    // Rides idx_doclines_seq, the bill's own lines.
    w.write('''
       AND EXISTS (
         SELECT 1 FROM document_lines fl
         WHERE fl.document_id = $doc.id
           AND fl.deleted_at_utc IS NULL
           AND fl.item_id = ${q.text(f.itemId!)}
       )''');
  }
  if (f.category != null) {
    w.write('''
       AND EXISTS (
         SELECT 1 FROM document_lines fl
         JOIN items fi ON fi.id = fl.item_id
         WHERE fl.document_id = $doc.id
           AND fl.deleted_at_utc IS NULL
           AND TRIM(fi.category) = ${q.text(f.category!.trim())}
       )''');
  }
  return w.toString();
}

/// What a journal entry `je` was, in the words the reports use (M58).
///
/// Its `source_type`, except where that alone gives the wrong word. An
/// `other_income` entry whose document has no party is the shop's own
/// income (M47), not a charge on a khata; an `expense` entry debiting the
/// owner's drawings is the home's spending, in money or in goods taken home
/// (M47), not the shop's; and a `manual` entry carrying a loan's tag in
/// `cost_centre` is a loan taken or paid back (M48), not a journal voucher.
/// The subqueries are reached only for those three source types, each by
/// the entry's own lines or its own document.
const _entryKindSql = '''
  CASE
    WHEN je.source_type = 'other_income' AND EXISTS (
           SELECT 1 FROM documents kd
           WHERE kd.id = je.document_id AND kd.party_id IS NULL)
      THEN 'shop_income'
    WHEN je.source_type = 'expense' AND EXISTS (
           SELECT 1 FROM journal_lines kl
           JOIN accounts ka ON ka.id = kl.account_id
           WHERE kl.journal_entry_id = je.id AND kl.debit_paisa > 0
             AND kl.deleted_at_utc IS NULL
             AND ka.system_key = 'owner_drawings')
      THEN 'owner_drawings'
    WHEN je.source_type = 'manual' AND EXISTS (
           SELECT 1 FROM journal_lines kl
           WHERE kl.journal_entry_id = je.id AND kl.deleted_at_utc IS NULL
             AND substr(kl.cost_centre, 1, 5) = 'loan:')
      THEN 'loan'
    ELSE je.source_type
  END''';

/// Whether the document `d` is an expense of the home's (M47): its own
/// expense entry debits the owner's drawings, as the expense book reads its
/// Ghar mark.
const _forHomeSql = '''
  EXISTS (
    SELECT 1 FROM journal_entries he
    JOIN journal_lines hl ON hl.journal_entry_id = he.id
    JOIN accounts ha ON ha.id = hl.account_id
    WHERE he.document_id = d.id AND he.source_type = 'expense'
      AND he.reverses_entry_id IS NULL AND he.deleted_at_utc IS NULL
      AND hl.debit_paisa > 0 AND hl.deleted_at_utc IS NULL
      AND ha.system_key = 'owner_drawings')''';
