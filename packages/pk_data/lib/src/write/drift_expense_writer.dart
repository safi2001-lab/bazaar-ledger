import 'package:pk_domain/pk_domain.dart';

import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The drift implementation of [ExpenseWriter].
///
/// The shortest writer here: a document, a journal entry with two lines, and
/// an audit row. No stock, no tax, no allocations.
///
/// The expense head is on the journal line and nowhere else. A column on
/// `documents` would be a second answer to a question the ledger already
/// holds, and the two would disagree the first time one was written by a path
/// that forgot the other.
final class DriftExpenseWriter implements ExpenseWriter {
  const DriftExpenseWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(ExpenseWriteContext write) body,
  ) =>
      runner.run(actor, (tx) => body(_DriftExpenseWriteContext(tx, sequences)));
}

/// The expense handle on a transaction somebody else opened: an edit (M31) that cancels an expense and writes its replacement in the
/// same commit.
ExpenseWriteContext expenseContextOn(
  Tx tx, {
  SequenceAllocator sequences = const SequenceAllocator(),
}) => _DriftExpenseWriteContext(tx, sequences);

final class _DriftExpenseWriteContext implements ExpenseWriteContext {
  _DriftExpenseWriteContext(this._tx, this._sequences);

  final Tx _tx;
  final SequenceAllocator _sequences;

  @override
  ActorContext get actor => _tx.actor;

  @override
  Future<AllocatedNumber> nextNumber(String docType) async {
    final number = await _sequences.allocate(
      _tx,
      docType: docType,
      fiscalYear: actor.businessDate.fiscalYear,
    );
    return AllocatedNumber(
      formatted: number.formatted,
      series: number.series,
      sequence: number.sequence,
    );
  }

  @override
  Future<String?> ledgerAccountFor(String paymentAccountId) async {
    final row = await _tx.selectOne(
      'SELECT ledger_account_id FROM payment_accounts '
      'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
      [paymentAccountId, actor.firmId],
    );
    return row?.readNullable<String>('ledger_account_id');
  }

  @override
  Future<RecordedExpense> apply(ExpensePosting posting) async {
    posting.assertBalanced();

    final doc = posting.document;
    final documentId = await _tx.insert('documents', {
      'doc_type': doc.docType,
      'doc_no': doc.docNo,
      'doc_series': doc.docSeries,
      'doc_seq': doc.docSeq,
      'fiscal_year': doc.fiscalYear,
      'doc_date_utc': doc.docDateUtcMillis,
      'doc_date_local': doc.docDateLocal,
      'party_id': doc.partyId,
      'status': 'posted',
      'posted_at_utc': doc.docDateUtcMillis,
      'subtotal_paisa': doc.subtotal.inPaisa,
      'taxable_paisa': doc.taxable.inPaisa,
      'total_paisa': doc.total.inPaisa,
      'paid_paisa': doc.paid.inPaisa,
      'balance_paisa': doc.balance.inPaisa,
      'rounding_mode': doc.roundingMode,
      'tax_rule_version': doc.taxRuleVersion,
      'notes': doc.notes,
    });

    final entry = posting.journal;
    final journalEntryId = await _tx.insert('journal_entries', {
      'entry_no': entry.entryNo,
      'entry_date_utc': entry.entryDateUtcMillis,
      'entry_date_local': entry.entryDateLocal,
      'fiscal_year': entry.fiscalYear,
      'source_type': entry.sourceType,
      'document_id': documentId,
      'narration': entry.narration,
      'total_debit_paisa': entry.totalDebit.inPaisa,
      'total_credit_paisa': entry.totalCredit.inPaisa,
    });

    final accountsByKey = await _accountsBySystemKey();
    for (final line in entry.lines) {
      final accountId = line.isResolvedAccountId
          ? line.accountId
          : accountsByKey[line.accountSystemKey];
      if (accountId == null) {
        throw ExpenseRefused(
          'This shop has no "${line.accountSystemKey}" account, so the '
          'expense has nowhere to go. The chart of accounts needs checking.',
        );
      }
      await _tx.insert('journal_lines', {
        'journal_entry_id': journalEntryId,
        'line_no': line.lineNo,
        'account_id': accountId,
        'debit_paisa': line.debit.inPaisa,
        'credit_paisa': line.credit.inPaisa,
        'party_id': line.partyId,
        'narration': line.narration,
      });
    }

    _tx.audit(
      action: 'EXPENSE_RECORDED',
      entityTable: 'documents',
      entityId: documentId,
      summary: posting.auditSummary,
      amountPaisa: doc.total.inPaisa,
    );

    return RecordedExpense(
      documentId: documentId,
      docNo: doc.docNo,
      amount: doc.total,
      head: posting.headSystemKey,
      journalEntryId: journalEntryId,
    );
  }

  Future<Map<String, String>> _accountsBySystemKey() async {
    final rows = await _tx.select(
      'SELECT id, system_key FROM accounts '
      'WHERE firm_id = ? AND system_key IS NOT NULL '
      '  AND deleted_at_utc IS NULL',
      [actor.firmId],
    );
    return {
      for (final r in rows) r.read<String>('system_key'): r.read<String>('id'),
    };
  }
}
