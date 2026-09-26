import 'package:pk_domain/pk_domain.dart';

import 'document_rows.dart';
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The drift implementation of [DebitNoteWriter]: a document with no lines,
/// and its entry.
final class DriftDebitNoteWriter implements DebitNoteWriter {
  const DriftDebitNoteWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(DebitNoteWriteContext write) body,
  ) => runner.run(actor, (tx) => body(_Context(tx, sequences)));
}

final class _Context implements DebitNoteWriteContext {
  _Context(this._tx, this._sequences);

  final Tx _tx;
  final SequenceAllocator _sequences;

  @override
  ActorContext get actor => _tx.actor;

  @override
  Future<AllocatedNumber> nextNumber(String docType) async {
    final n = await _sequences.allocate(
      _tx,
      docType: docType,
      fiscalYear: actor.businessDate.fiscalYear,
    );
    return AllocatedNumber(
      formatted: n.formatted,
      series: n.series,
      sequence: n.sequence,
    );
  }

  @override
  Future<String> apply(DebitNotePosting posting) async {
    final party = await _tx.selectOne(
      'SELECT id FROM parties WHERE id = ? AND firm_id = ? '
      '  AND deleted_at_utc IS NULL',
      [posting.document.partyId, actor.firmId],
    );
    if (party == null) {
      throw const DebitNoteRefused(
        'That customer is not in this shop, so nothing can be charged to '
        'them.',
      );
    }
    final (id, _) = await insertDocumentRows(_tx, posting.document, const []);
    await insertJournal(_tx, id, posting.journal);
    _tx.audit(
      action: 'DEBIT_NOTE_ISSUED',
      entityTable: 'documents',
      entityId: id,
      summary: posting.auditSummary,
      amountPaisa: posting.document.total.inPaisa,
    );
    return id;
  }
}
