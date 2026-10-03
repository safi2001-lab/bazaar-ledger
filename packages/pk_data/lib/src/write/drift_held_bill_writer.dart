import 'package:pk_domain/pk_domain.dart';

import 'document_rows.dart';
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// Writes a salesman's bill for the cashier (M68): a `proforma` document
/// and its lines, and nothing else.
///
/// The quotation's writer (M25) with its own audit code: no stock ledger,
/// no journal, no payment, a balance of nothing, so no receivable query can
/// take it for udhaar and no stock figure moves while it waits. The bill
/// made from it when the cashier takes the money is an ordinary sale.
final class DriftHeldBillWriter implements QuotationWriter {
  const DriftHeldBillWriter({
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
    if (posting.document.docType != heldBillDocType) {
      throw StateError('Only a bill for the cashier is written here.');
    }
    final (id, _) = await insertDocumentRows(
      _tx,
      posting.document,
      posting.lines,
    );
    _tx.audit(
      action: billHeldAction,
      entityTable: 'documents',
      entityId: id,
      summary: posting.auditSummary,
      amountPaisa: posting.document.total.inPaisa,
    );
    return id;
  }
}
