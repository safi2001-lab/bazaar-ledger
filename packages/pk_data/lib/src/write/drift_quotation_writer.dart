import 'package:pk_domain/pk_domain.dart';

import 'document_rows.dart';
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The drift implementation of [QuotationWriter].
///
/// A quotation writes a document and its lines and nothing else: no stock
/// ledger, no journal, no payment. Its balance is zero, so no receivable
/// query can mistake it for udhaar.
final class DriftQuotationWriter implements QuotationWriter {
  const DriftQuotationWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(QuotationWriteContext write) body,
  ) => runner.run(actor, (tx) => body(_Context(tx, sequences)));
}

final class _Context implements QuotationWriteContext {
  _Context(this._tx, this._sequences);

  final Tx _tx;
  final SequenceAllocator _sequences;

  @override
  ActorContext get actor => _tx.actor;

  @override
  Future<TaxContext> taxContextFor(String? partyId) =>
      taxContextOf(_tx, partyId);

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
  Future<String> apply(QuotationPosting posting) async {
    final (id, _) = await insertDocumentRows(
      _tx,
      posting.document,
      posting.lines,
    );
    _tx.audit(
      action: 'QUOTATION_ISSUED',
      entityTable: 'documents',
      entityId: id,
      summary: posting.auditSummary,
    );
    return id;
  }
}
