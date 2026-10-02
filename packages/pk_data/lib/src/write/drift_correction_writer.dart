import 'package:drift/drift.dart' show QueryRow;
import 'package:pk_domain/pk_domain.dart';

import 'drift_debit_note_writer.dart' show debitNoteContextOn;
import 'drift_expense_writer.dart' show expenseContextOn;
import 'drift_payment_writer.dart' show paymentContextOn;
import 'drift_void_writer.dart' show voidContextOn;
import 'opening_entries.dart' show postOpeningBalance;
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The drift implementation of [CorrectionWriter] (M31).
///
/// One [TxRunner] transaction with every writer's handle opened on it, so a
/// cancellation and the entry that replaces it commit together or not at
/// all. Nothing in the ledger is edited: `journal_entries`, `journal_lines`
/// and `stock_ledger` are append-only and `TxRunner` refuses to update them.
/// What moves is a payment's status, a bill's paid and owed totals, an
/// allocation struck out, and a party's opening column — each through the
/// same `Tx` that writes the outbox, so a correction made at one counter
/// reaches every other (M13).
final class DriftCorrectionWriter implements CorrectionWriter {
  const DriftCorrectionWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(CorrectionWriteContext write) body,
  ) => runner.run(
    actor,
    (tx) => body(_DriftCorrectionWriteContext(tx, sequences)),
  );
}

final class _DriftCorrectionWriteContext implements CorrectionWriteContext {
  _DriftCorrectionWriteContext(this._tx, this._sequences)
    : documents = voidContextOn(_tx, sequences: _sequences),
      payments = paymentContextOn(_tx, sequences: _sequences),
      expenses = expenseContextOn(_tx, sequences: _sequences),
      charges = debitNoteContextOn(_tx, sequences: _sequences);

  final Tx _tx;
  final SequenceAllocator _sequences;

  @override
  final VoidWriteContext documents;

  @override
  final PaymentWriteContext payments;

  @override
  final ExpenseWriteContext expenses;

  @override
  final DebitNoteWriteContext charges;

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

  // -------------------------------------------------------------------------
  // Payments
  // -------------------------------------------------------------------------

  @override
  Future<PostedPaymentSnapshot?> paymentSnapshot(String paymentId) async {
    final p = await _tx.selectOne(
      'SELECT id, payment_no, direction, party_id, amount_paisa, mode, '
      '       status, cheque_no, cheque_status '
      'FROM payments WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
      [paymentId, actor.firmId],
    );
    if (p == null) return null;
    final no = p.read<String>('payment_no');

    // The entry that put this payment on the books. Since M31 the payment
    // writer stamps `payment_id` on it; before that it did not, and the
    // entry is found by the narration the receipt and payment builders have
    // always written — "Receipt <no>" and "Payment <no>", unique because the
    // number is. A cheque's later clearing entry also names the payment, but
    // under a narration of its own, so it can never be taken for this one.
    final entryRow = await _tx.selectOne(
      'SELECT id, entry_no, entry_date_utc, entry_date_local, fiscal_year, '
      '       source_type, total_debit_paisa, total_credit_paisa '
      'FROM journal_entries '
      "WHERE firm_id = ? AND source_type = 'payment' "
      '  AND deleted_at_utc IS NULL '
      '  AND (payment_id = ? OR payment_id IS NULL) '
      '  AND narration IN (?, ?) '
      'ORDER BY entry_date_utc, id LIMIT 1',
      [actor.firmId, paymentId, 'Receipt $no', 'Payment $no'],
    );

    final allocations = await _tx.select(
      'SELECT pa.id, pa.document_id, pa.amount_paisa, pa.allocation_mode, '
      '       d.doc_no, d.paid_paisa, d.balance_paisa '
      'FROM payment_allocations pa '
      'JOIN documents d ON d.id = pa.document_id '
      'WHERE pa.payment_id = ? AND pa.firm_id = ? '
      '  AND pa.deleted_at_utc IS NULL '
      'ORDER BY pa.allocated_at_utc, pa.id',
      [paymentId, actor.firmId],
    );

    return PostedPaymentSnapshot(
      paymentId: paymentId,
      paymentNo: no,
      direction: p.read<String>('direction'),
      partyId: p.readNullable<String>('party_id'),
      amount: Money.paisa(p.read<int>('amount_paisa')),
      mode: p.read<String>('mode'),
      status: p.read<String>('status'),
      chequeNo: p.readNullable<String>('cheque_no'),
      chequeStatus: p.readNullable<String>('cheque_status'),
      entryId: entryRow?.read<String>('id'),
      entry: entryRow == null ? null : await _entry(entryRow),
      allocations: [
        for (final a in allocations)
          PaymentAllocationSnapshot(
            allocationId: a.read<String>('id'),
            documentId: a.read<String>('document_id'),
            docNo: a.read<String>('doc_no'),
            amount: Money.paisa(a.read<int>('amount_paisa')),
            mode: a.read<String>('allocation_mode'),
            billPaid: Money.paisa(a.read<int>('paid_paisa')),
            billBalance: Money.paisa(a.read<int>('balance_paisa')),
          ),
      ],
    );
  }

  @override
  Future<VoidedPayment> applyPaymentVoid(PaymentVoidPosting posting) async {
    posting.assertBalanced();

    final reversingEntryId = await _insertReversal(
      posting.journal,
      reversesEntryId: posting.reversesEntryId,
      paymentId: posting.paymentId,
    );

    // The bills it settled are owed again, to the totals the builder stated.
    for (final bill in posting.reopened) {
      await _tx.update('documents', bill.documentId, {
        'paid_paisa': bill.paid.inPaisa,
        'balance_paisa': bill.balance.inPaisa,
      });
    }

    // Released. Struck out rather than left standing, because an allocation
    // from a cancelled receipt to a bill that is still live is not inert the
    // way a cancelled bill's own tender is: a reprinted bill lists every
    // payment allocated to it, and would print the cancelled receipt as
    // money the customer handed over. The tombstone stays, and the payment's
    // page still reads it to say what the receipt had settled.
    for (final id in posting.releasedAllocationIds) {
      await _tx.softDelete('payment_allocations', id);
    }

    // The only change to the payment row. The receipt the customer is
    // holding still matches it; it is simply no longer standing.
    await _tx.update('payments', posting.paymentId, {'status': 'void'});

    _tx.audit(
      action: 'PAYMENT_VOIDED',
      entityTable: 'payments',
      entityId: posting.paymentId,
      summary: posting.auditSummary,
      amountPaisa: posting.amount.inPaisa,
      after: {'status': 'void', 'reason': posting.reason},
    );

    return VoidedPayment(
      paymentId: posting.paymentId,
      paymentNo: posting.paymentNo,
      amount: posting.amount,
      reversingEntryId: reversingEntryId,
      reason: posting.reason,
      reopenedDocumentIds: [for (final b in posting.reopened) b.documentId],
    );
  }

  // -------------------------------------------------------------------------
  // Opening balances
  // -------------------------------------------------------------------------

  @override
  Future<OpeningSnapshot?> openingOf(String partyId) async {
    final party = await _tx.selectOne(
      'SELECT id, name, opening_balance_paisa FROM parties '
      'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
      [partyId, actor.firmId],
    );
    if (party == null) return null;

    // Every opening entry for this party still standing: posted when they
    // were added (or by `postMissingOpenings` for a party added before M10),
    // and not yet reversed by an earlier correction.
    final rows = await _tx.select(
      'SELECT DISTINCT je.id, je.entry_no, je.entry_date_utc, '
      '       je.entry_date_local, je.fiscal_year, je.source_type, '
      '       je.total_debit_paisa, je.total_credit_paisa '
      'FROM journal_entries je '
      'JOIN journal_lines jl ON jl.journal_entry_id = je.id '
      "WHERE je.firm_id = ? AND je.source_type = 'opening' "
      '  AND jl.party_id = ? AND je.deleted_at_utc IS NULL '
      '  AND jl.deleted_at_utc IS NULL '
      '  AND NOT EXISTS (SELECT 1 FROM journal_entries r '
      '                  WHERE r.reverses_entry_id = je.id '
      '                    AND r.deleted_at_utc IS NULL) '
      'ORDER BY je.entry_date_utc, je.id',
      [actor.firmId, partyId],
    );

    return OpeningSnapshot(
      partyId: partyId,
      partyName: party.read<String>('name'),
      opening: Money.paisa(party.read<int>('opening_balance_paisa')),
      entries: [
        for (final r in rows)
          OpeningEntrySnapshot(
            entryId: r.read<String>('id'),
            entry: await _entry(r),
          ),
      ],
    );
  }

  @override
  Future<void> applyOpeningCorrection(OpeningCorrectionPosting posting) async {
    posting.assertBalanced();
    for (final reversal in posting.reversals) {
      await _insertReversal(
        reversal.journal,
        reversesEntryId: reversal.reversesEntryId,
      );
    }
    // The new figure, posted by the code that posted the first one, so there
    // is one definition of an opening entry and not two that could drift.
    await postOpeningBalance(
      _tx,
      partyId: posting.partyId,
      partyName: posting.partyName,
      owed: posting.now,
      sequences: _sequences,
    );
    // And the party's own column, which the khata reads its opening line
    // from and every balance on screen starts with.
    await _tx.update('parties', posting.partyId, {
      'opening_balance_paisa': posting.now.inPaisa,
    });
    _tx.audit(
      action: 'OPENING_BALANCE_CORRECTED',
      entityTable: 'parties',
      entityId: posting.partyId,
      summary: posting.auditSummary,
      amountPaisa: posting.now.inPaisa,
      before: {'opening_balance_paisa': posting.was.inPaisa},
      after: {
        'opening_balance_paisa': posting.now.inPaisa,
        'reason': posting.reason,
      },
    );
  }

  // -------------------------------------------------------------------------
  // The link
  // -------------------------------------------------------------------------

  @override
  void recordCorrection(CorrectionRecord record) => _tx.audit(
    action: record.action,
    entityTable: record.entityTable,
    entityId: record.replacementId,
    summary: record.summary,
    amountPaisa: record.after.inPaisa,
    before: {
      'id': record.replacedId,
      'no': record.replacedNo,
      'amount_paisa': record.before.inPaisa,
    },
    after: {
      'id': record.replacementId,
      'no': record.replacementNo,
      'amount_paisa': record.after.inPaisa,
      'reason': record.reason,
    },
  );

  // -------------------------------------------------------------------------
  // Shared
  // -------------------------------------------------------------------------

  /// An entry as written, with its lines named by the account rows they hit
  /// — the same `#id` form the void writer reads, so the mirror lands on
  /// exactly the accounts the original did even if one has been renamed.
  Future<JournalEntryPosting> _entry(QueryRow row) async {
    final lines = await _tx.select(
      'SELECT line_no, account_id, debit_paisa, credit_paisa, party_id, '
      '       item_id, narration '
      'FROM journal_lines WHERE journal_entry_id = ? AND deleted_at_utc IS NULL '
      'ORDER BY line_no',
      [row.read<String>('id')],
    );
    return JournalEntryPosting(
      entryNo: row.read<String>('entry_no'),
      entryDateUtcMillis: row.read<int>('entry_date_utc'),
      entryDateLocal: row.read<String>('entry_date_local'),
      fiscalYear: row.read<int>('fiscal_year'),
      sourceType: row.read<String>('source_type'),
      totalDebit: Money.paisa(row.read<int>('total_debit_paisa')),
      totalCredit: Money.paisa(row.read<int>('total_credit_paisa')),
      lines: [
        for (final r in lines)
          JournalLinePosting(
            lineNo: r.read<int>('line_no'),
            accountSystemKey: '#${r.read<String>('account_id')}',
            debit: Money.paisa(r.read<int>('debit_paisa')),
            credit: Money.paisa(r.read<int>('credit_paisa')),
            partyId: r.readNullable<String>('party_id'),
            itemId: r.readNullable<String>('item_id'),
            narration: r.readNullable<String>('narration'),
          ),
      ],
    );
  }

  /// Appends a reversing entry, pointing at what it undoes.
  Future<String> _insertReversal(
    JournalEntryPosting entry, {
    required String reversesEntryId,
    String? paymentId,
  }) async {
    final id = await _tx.insert('journal_entries', {
      'entry_no': entry.entryNo,
      'entry_date_utc': entry.entryDateUtcMillis,
      'entry_date_local': entry.entryDateLocal,
      'fiscal_year': entry.fiscalYear,
      'source_type': entry.sourceType,
      'payment_id': paymentId,
      'reverses_entry_id': reversesEntryId,
      'narration': entry.narration,
      'total_debit_paisa': entry.totalDebit.inPaisa,
      'total_credit_paisa': entry.totalCredit.inPaisa,
    });
    for (final line in entry.lines) {
      if (!line.isResolvedAccountId) {
        throw StateError(
          'A reversal line names account "${line.accountSystemKey}" by key '
          'rather than by id. The mirror of a written entry must point at the '
          'same account rows the original did.',
        );
      }
      await _tx.insert('journal_lines', {
        'journal_entry_id': id,
        'line_no': line.lineNo,
        'account_id': line.accountId,
        'debit_paisa': line.debit.inPaisa,
        'credit_paisa': line.credit.inPaisa,
        'party_id': line.partyId,
        'item_id': line.itemId,
        'narration': line.narration,
      });
    }
    return id;
  }
}
