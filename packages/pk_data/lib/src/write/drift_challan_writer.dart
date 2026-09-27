import 'package:pk_domain/pk_domain.dart';

import 'document_rows.dart';
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The drift implementation of [ChallanWriter].
///
/// A challan writes a document and its lines, the stock that left, and the
/// entry moving its cost from Inventory to Goods on Challan. No payment and
/// no receivable: its balance is zero, so no khata query can read it as
/// udhaar.
final class DriftChallanWriter implements ChallanWriter {
  const DriftChallanWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(ChallanWriteContext write) body,
  ) => runner.run(actor, (tx) => body(_Context(tx, sequences)));
}

final class _Context implements ChallanWriteContext {
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
  Future<Map<String, Rate>> averageCostFor(Iterable<String> itemIds) async {
    final ids = itemIds.toList();
    if (ids.isEmpty) return const {};
    final rows = await _tx.select(
      'SELECT id, avg_cost_milli_paisa FROM items '
      'WHERE firm_id = ? AND id IN (${List.filled(ids.length, '?').join(', ')})',
      [actor.firmId, ...ids],
    );
    return {
      for (final r in rows)
        r.read<String>('id'): Rate.raw(r.read<int>('avg_cost_milli_paisa')),
    };
  }

  @override
  Future<String> apply(ChallanPosting posting) async {
    final (id, lineIdByNo) = await insertDocumentRows(
      _tx,
      posting.document,
      posting.lines,
    );
    await insertStockMovements(
      _tx,
      id,
      lineIdByNo,
      posting.stockMovements,
      takeFromLots: true,
    );
    if (posting.journal case final entry?) {
      await insertJournal(_tx, id, entry);
    }
    _tx.audit(
      action: 'CHALLAN_ISSUED',
      entityTable: 'documents',
      entityId: id,
      summary: posting.auditSummary,
      amountPaisa: posting.document.total.inPaisa,
    );
    return id;
  }
}
