import 'package:pk_domain/pk_domain.dart';

import 'document_rows.dart';
import 'drift_order_writer.dart';
import 'drift_pharmacy_writer.dart' show keepScheduleRegister; // M54
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
    // M54: a Schedule medicine sent on a challan is registered here, against
    // the prescription asked for at the counter, because the register is
    // read off the stock that left (M49) and it left on the challan. A
    // challan that carries none — goods given rate later from the khata
    // (M55) — writes none, as before, and its bill asks.
    if (posting.prescription case final rx?) {
      await keepScheduleRegister(
        _tx,
        documentId: id,
        lineIdByNo: lineIdByNo,
        lines: posting.lines,
        prescription: rx,
      );
    }
    if (posting.fromQuotationId case final quotationId?) {
      final source = await _tx.selectOne(
        'SELECT doc_no, doc_type FROM documents WHERE id = ? AND firm_id = ? '
        "AND status = 'posted' AND deleted_at_utc IS NULL",
        [quotationId, actor.firmId],
      );
      // A sale order (M41) goes out on a challan as a quotation does, and
      // may go out a delivery at a time, so it is never "already sent".
      final isOrder = source != null && await isSaleOrder(_tx, quotationId);
      if (source == null ||
          (source.read<String>('doc_type') != 'quotation' && !isOrder)) {
        throw const ChallanRefused(
          'Only a quotation can be sent on a challan. A challan already '
          'sent is billed, not sent again.',
        );
      }
      final taken = await _tx.selectOne(
        'SELECT d.doc_no FROM doc_links link '
        'JOIN documents d ON d.id = link.to_document_id '
        "WHERE link.from_document_id = ? AND link.link_type = 'converted_from' "
        "  AND link.deleted_at_utc IS NULL AND d.status <> 'void'",
        [quotationId],
      );
      if (taken != null && !isOrder) {
        throw ChallanRefused(
          '${source.read<String>('doc_no')} is already '
          '${taken.read<String>('doc_no')}.',
        );
      }
      await _tx.insert('doc_links', {
        'from_document_id': quotationId,
        'to_document_id': id,
        'link_type': 'converted_from',
        'amount_paisa': posting.document.total.inPaisa,
      });
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
