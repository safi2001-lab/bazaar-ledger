import 'package:drift/drift.dart' show QueryRow;
import 'package:pk_domain/pk_domain.dart';

import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The drift implementation of [ChequeWriter].
///
/// A cheque step changes the payment's status, and for clearing and bouncing
/// appends a journal entry that points at the payment. A bounce also puts the
/// bills it paid back to what they owed. Nothing in the ledger is edited.
final class DriftChequeWriter implements ChequeWriter {
  const DriftChequeWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(ChequeWriteContext write) body,
  ) => runner.run(actor, (tx) => body(_DriftChequeWriteContext(tx, sequences)));
}

/// The columns a cheque in hand is read from, on the write side and the read
/// side alike, so the register and the writer agree on what "in hand" means.
const chequeInHandSelect = '''
  SELECT p.id, p.payment_no, p.party_id, pa.name AS party_name,
         p.amount_paisa, p.cheque_no, p.cheque_bank, p.cheque_date_utc,
         p.payment_date_local, p.cheque_status
  FROM payments p
  JOIN parties pa ON pa.id = p.party_id
  WHERE p.mode = 'cheque'
    AND p.direction = 'in'
    AND p.status = 'pending'
    AND p.deleted_at_utc IS NULL
''';

/// One row of [chequeInHandSelect], as the domain sees it.
ChequeInHand chequeInHandFrom(QueryRow r) {
  final due = r.readNullable<int>('cheque_date_utc');
  return ChequeInHand(
    paymentId: r.read<String>('id'),
    paymentNo: r.read<String>('payment_no'),
    partyId: r.read<String>('party_id'),
    partyName: r.read<String>('party_name'),
    amount: Money.paisa(r.read<int>('amount_paisa')),
    chequeNo: r.read<String>('cheque_no'),
    bank: r.readNullable<String>('cheque_bank'),
    due: due == null ? null : chequeDueDate(due),
    receivedOn: BusinessDate(r.read<String>('payment_date_local')),
    deposited: r.readNullable<String>('cheque_status') == 'deposited',
  );
}

final class _DriftChequeWriteContext implements ChequeWriteContext {
  _DriftChequeWriteContext(this._tx, this._sequences);

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
  Future<ChequeInHand?> chequeInHand(String paymentId) async {
    final row = await _tx.selectOne(
      '$chequeInHandSelect AND p.id = ? AND p.firm_id = ?',
      [paymentId, actor.firmId],
    );
    return row == null ? null : chequeInHandFrom(row);
  }

  @override
  Future<List<ChequeAllocation>> allocationsOf(String paymentId) async {
    final rows = await _tx.select(
      'SELECT document_id, amount_paisa FROM payment_allocations '
      'WHERE payment_id = ? AND firm_id = ? AND deleted_at_utc IS NULL '
      'ORDER BY allocated_at_utc, id',
      [paymentId, actor.firmId],
    );
    return [
      for (final r in rows)
        ChequeAllocation(
          documentId: r.read<String>('document_id'),
          amount: Money.paisa(r.read<int>('amount_paisa')),
        ),
    ];
  }

  @override
  Future<Map<String, ({Money paid, Money balance})>> billsNow(
    Iterable<String> documentIds,
  ) async {
    final ids = documentIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final rows = await _tx.select(
      'SELECT id, paid_paisa, balance_paisa FROM documents '
      'WHERE firm_id = ? AND id IN (${List.filled(ids.length, '?').join(', ')})',
      [actor.firmId, ...ids],
    );
    return {
      for (final r in rows)
        r.read<String>('id'): (
          paid: Money.paisa(r.read<int>('paid_paisa')),
          balance: Money.paisa(r.read<int>('balance_paisa')),
        ),
    };
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
  Future<void> apply(ChequeStepPosting posting) async {
    posting.assertBalanced();

    await _tx.update('payments', posting.paymentId, {
      'status': posting.paymentStatus,
      'cheque_status': posting.chequeStatus,
    });

    // The bills a bounce reopens, to the totals the lifecycle stated.
    for (final bill in posting.reopened) {
      await _tx.update('documents', bill.documentId, {
        'paid_paisa': bill.paid.inPaisa,
        'balance_paisa': bill.balance.inPaisa,
      });
    }

    final entry = posting.journal;
    if (entry != null) {
      final journalEntryId = await _tx.insert('journal_entries', {
        'entry_no': entry.entryNo,
        'entry_date_utc': entry.entryDateUtcMillis,
        'entry_date_local': entry.entryDateLocal,
        'fiscal_year': entry.fiscalYear,
        'source_type': entry.sourceType,
        // The payment it moved, so a khata and a register can find the
        // bounce by the cheque and not by searching narrations.
        'payment_id': posting.paymentId,
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
          throw StateError(
            'No account with system key "${line.accountSystemKey}" in firm '
            '${actor.firmId}. A cheque cannot move into an account that does '
            'not exist.',
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
    }

    _tx.audit(
      action: posting.auditAction,
      entityTable: 'payments',
      entityId: posting.paymentId,
      summary: posting.auditSummary,
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
