import 'package:pk_domain/pk_domain.dart';

import 'chart_top_up.dart';
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The drift implementation of [PaymentWriter].
///
/// Everything happens inside one [TxRunner] transaction, so the payment, its
/// allocations, the bills it settled, its journal entry, its audit row and
/// its outbox entries all commit together or none of them do.
final class DriftPaymentWriter implements PaymentWriter {
  const DriftPaymentWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(PaymentWriteContext write) body,
  ) =>
      runner.run(actor, (tx) => body(_DriftPaymentWriteContext(tx, sequences)));
}

/// The payment handle on a transaction somebody else opened: an edit (M31)
/// that cancels a payment and takes its replacement in the same commit, so
/// the replacement is written by exactly this code and no copy of it.
PaymentWriteContext paymentContextOn(
  Tx tx, {
  SequenceAllocator sequences = const SequenceAllocator(),
}) => _DriftPaymentWriteContext(tx, sequences);

final class _DriftPaymentWriteContext implements PaymentWriteContext {
  _DriftPaymentWriteContext(this._tx, this._sequences);

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
  Future<List<OpenBill>> openBillsFor(String partyId) async {
    // Voided and deleted bills are excluded here rather than filtered later:
    // a payment allocated against a void document is money the customer's
    // khata gains that nobody returned, and findOverAllocatedPayments() will
    // not catch it because the sum still fits.
    //
    // Rides idx_documents_open_balance, which is already
    // (firm_id, party_id, doc_date_local) WHERE balance_paisa <> 0.
    //
    // Sale invoices only. Without the type filter a party who is both a
    // customer and a supplier had their payment to the shop settle the
    // shop's own purchase bills from them: money in, applied to money out,
    // and the payable quietly vanished while the udhaar stayed.
    //
    // A charge put on the khata with no sale behind it (a debit note) is
    // owed exactly as a bill is, and settled by the same receipts.
    return _open(partyId, "doc_type IN ('sale_invoice', 'other_income')");
  }

  @override
  Future<List<OpenBill>> openPayablesFor(String partyId) =>
      // What the shop owes: deliveries not yet paid for, and expenses left
      // on account. The same WHERE otherwise, so a void purchase is never
      // paid against either.
      _open(partyId, "doc_type IN ('purchase_bill', 'expense')");

  Future<List<OpenBill>> _open(String partyId, String typeFilter) async {
    final rows = await _tx.select(
      '''
      SELECT id, doc_no, doc_type, doc_date_local, doc_seq, balance_paisa
      FROM documents
      WHERE firm_id = ? AND party_id = ?
        AND $typeFilter
        AND balance_paisa > 0
        AND status NOT IN ('void', 'draft')
        AND deleted_at_utc IS NULL
      ORDER BY doc_date_local, doc_seq, id
      ''',
      [actor.firmId, partyId],
    );

    return [
      for (final row in rows)
        OpenBill(
          documentId: row.read<String>('id'),
          dateLocal: row.read<String>('doc_date_local'),
          sequence: row.read<int>('doc_seq'),
          outstanding: Money.paisa(row.read<int>('balance_paisa')),
          docNo: row.read<String>('doc_no'),
          docType: row.read<String>('doc_type'),
        ),
    ];
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
  Future<RecordedReceipt> apply(ReceiptPosting posting) async {
    // Asserted again here, at the boundary, even though the builder already
    // did it. The builder is one caller; this is the only door.
    posting.assertBalanced();

    final payment = posting.payment;
    final paymentId = await _tx.insert('payments', {
      'payment_no': payment.paymentNo,
      'direction': payment.direction,
      'party_id': payment.partyId,
      'payment_account_id': payment.paymentAccountId,
      'mode': payment.mode,
      'reference': payment.reference,
      'amount_paisa': payment.amount.inPaisa,
      'tendered_paisa': payment.tendered?.inPaisa,
      'change_paisa': payment.change.inPaisa,
      'payment_date_utc': payment.paymentDateUtcMillis,
      'payment_date_local': payment.paymentDateLocal,
      // A cheque is not cleared money. It sits pending until the PDC
      // lifecycle says otherwise, matching the Cheques in Hand debit.
      'status': payment.isCheque ? 'pending' : 'cleared',
      'cheque_no': payment.chequeNo,
      'cheque_bank': payment.chequeBank,
      'cheque_date_utc': payment.chequeDateUtcMillis,
      'cheque_status': payment.isCheque ? 'issued' : null,
      'notes': payment.notes,
    });

    for (final allocation in posting.allocations) {
      await _tx.insert('payment_allocations', {
        'payment_id': paymentId,
        'document_id': allocation.documentId,
        'amount_paisa': allocation.amount.inPaisa,
        'allocation_mode': allocation.mode,
        'allocated_at_utc': payment.paymentDateUtcMillis,
      });
    }

    // The bills' new totals, computed by the builder. Absolute values rather
    // than deltas, so this cannot read-modify-write and cannot lose an update
    // to a second till working on the same bill.
    for (final settlement in posting.settlements) {
      final current = await _tx.selectOne(
        'SELECT paid_paisa FROM documents WHERE id = ? AND firm_id = ?',
        [settlement.documentId, actor.firmId],
      );
      if (current == null) {
        throw StateError(
          'Bill ${settlement.documentId} vanished between being listed as '
          'open and being settled.',
        );
      }
      await _tx.update('documents', settlement.documentId, {
        'paid_paisa': current.read<int>('paid_paisa') + settlement.paid.inPaisa,
        'balance_paisa': settlement.balance.inPaisa,
      });
    }

    final entry = posting.journal;
    final journalEntryId = await _tx.insert('journal_entries', {
      'entry_no': entry.entryNo,
      'entry_date_utc': entry.entryDateUtcMillis,
      'entry_date_local': entry.entryDateLocal,
      'fiscal_year': entry.fiscalYear,
      'source_type': entry.sourceType,
      // The payment it put on the books (M31), so cancelling it finds this
      // entry by the column made for it rather than by its narration.
      // Entries written before carry none, and are found by narration.
      'payment_id': paymentId,
      'narration': entry.narration,
      'total_debit_paisa': entry.totalDebit.inPaisa,
      'total_credit_paisa': entry.totalCredit.inPaisa,
    });

    final accountsByKey = await accountsBySystemKey(_tx, {
      for (final line in entry.lines)
        if (!line.isResolvedAccountId) line.accountSystemKey,
    });
    for (final line in entry.lines) {
      final accountId = line.isResolvedAccountId
          ? line.accountId
          : accountsByKey[line.accountSystemKey];
      if (accountId == null) {
        throw StateError(
          'No account with system key "${line.accountSystemKey}" in firm '
          '${actor.firmId}. The chart of accounts is incomplete, and a '
          'receipt cannot be posted against an account that does not exist.',
        );
      }
      await _tx.insert('journal_lines', {
        'journal_entry_id': journalEntryId,
        'line_no': line.lineNo,
        'account_id': accountId,
        'debit_paisa': line.debit.inPaisa,
        'credit_paisa': line.credit.inPaisa,
        'party_id': line.partyId,
        'item_id': line.itemId,
        'narration': line.narration,
      });
    }

    _tx.audit(
      action:
          posting.auditAction ??
          (payment.direction == 'out' ? 'PAYMENT_MADE' : 'PAYMENT_RECEIVED'),
      entityTable: 'payments',
      entityId: paymentId,
      summary: posting.auditSummary,
      amountPaisa: payment.amount.inPaisa,
    );

    return RecordedReceipt(
      paymentId: paymentId,
      paymentNo: payment.paymentNo,
      amount: payment.amount,
      applied: Money.sum([for (final a in posting.allocations) a.amount]),
      unapplied: posting.unapplied,
      journalEntryId: journalEntryId,
      settledDocumentIds: [for (final a in posting.allocations) a.documentId],
    );
  }
}
