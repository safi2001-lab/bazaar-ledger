part of '../drift_report_source.dart';

/// The read behind the expense reports (M35).
///
/// An expense voucher's head is the account its journal entry debited, and
/// where the money came from the account it credited (see
/// `expense_builder.dart`: the head lives on the journal line and nowhere
/// else). So the voucher is read back through its own entry, and the head
/// here is the head in the Trial Balance.
mixin _ExpenseQueries implements ExpenseReportSource {
  AppDatabase get _db;

  @override
  Future<List<ExpenseVoucher>> expenseVouchers(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId, period);
    final where = StringBuffer();
    if (filters.expenseHeadId != null) {
      where.write(' AND h.id = ${q.text(filters.expenseHeadId!)}');
    }
    if (filters.userId != null) {
      where.write(' AND d.created_by = ${q.text(filters.userId!)}');
    }
    if (filters.paymentMode != null) {
      // Paid by a mode: the account it came out of is one a payment
      // account of that mode posts into. Owed rather than paid is no mode.
      where.write('''
         AND EXISTS (
           SELECT 1 FROM payment_accounts fpa
           WHERE fpa.ledger_account_id = src.id
             AND fpa.firm_id = ?1
             AND fpa.deleted_at_utc IS NULL
             AND fpa.mode_label = ${q.text(filters.paymentMode!)}
         )''');
    }
    // Rides idx_documents_list for the vouchers and idx_je_doc for the
    // entry each one wrote. The entry is the voucher's own, not the
    // reversal an edit (M31) or a void posts against it.
    final rows = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_date_local, d.doc_no, d.total_paisa,
                 d.balance_paisa, d.notes,
                 COALESCE(d.party_name_snapshot, p.name) AS party,
                 u.name AS entered_by,
                 h.id AS head_id, h.name AS head, h.is_direct,
                 src.system_key AS source_key,
                 COALESCE((
                   SELECT pa.name FROM payment_accounts pa
                   WHERE pa.ledger_account_id = src.id AND pa.firm_id = ?1
                     AND pa.deleted_at_utc IS NULL
                   ORDER BY pa.is_default DESC, pa.name
                   LIMIT 1
                 ), src.name) AS paid_from
          FROM documents d
          JOIN journal_entries je
            ON je.document_id = d.id
           AND je.source_type = 'expense'
           AND je.reverses_entry_id IS NULL
           AND je.deleted_at_utc IS NULL
          JOIN journal_lines hl
            ON hl.journal_entry_id = je.id
           AND hl.debit_paisa > 0
           AND hl.deleted_at_utc IS NULL
          JOIN accounts h ON h.id = hl.account_id
          LEFT JOIN journal_lines sl
            ON sl.journal_entry_id = je.id
           AND sl.credit_paisa > 0
           AND sl.deleted_at_utc IS NULL
          LEFT JOIN accounts src ON src.id = sl.account_id
          LEFT JOIN parties p ON p.id = d.party_id
          LEFT JOIN users u ON u.id = d.created_by
          WHERE d.firm_id = ?1
            AND d.doc_type = 'expense'
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
            AND d.doc_date_local BETWEEN ?2 AND ?3
            $where
          ORDER BY d.doc_date_local, d.doc_seq, d.id
          ''',
          variables: q.variables,
          readsFrom: {
            _db.documents,
            _db.journalEntries,
            _db.journalLines,
            _db.accounts,
            _db.paymentAccounts,
            _db.parties,
            _db.users,
          },
        )
        .get();
    return [
      for (final r in rows)
        ExpenseVoucher(
          documentId: r.read<String>('id'),
          date: BusinessDate(r.read<String>('doc_date_local')),
          docNo: r.read<String>('doc_no'),
          party: _blank(r.readNullable<String>('party')),
          headId: r.read<String>('head_id'),
          head: r.read<String>('head'),
          isDirect: r.read<int>('is_direct') == 1,
          paidFrom: r.readNullable<String>('source_key') == 'accounts_payable'
              ? 'On account'
              : r.readNullable<String>('paid_from') ?? '',
          amount: Money.paisa(r.read<int>('total_paisa')),
          balance: Money.paisa(r.read<int>('balance_paisa')),
          note: r.readNullable<String>('notes') ?? '',
          enteredBy: r.readNullable<String>('entered_by'),
        ),
    ];
  }
}
