import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';
import 'document_rows.dart';
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The drift implementation of [SaleWriter].
///
/// Everything it does happens inside one [TxRunner] transaction, so the
/// document, its lines, its taxes, its payments, its allocations, its stock
/// movements, its journal entry, its audit row and its outbox entries all
/// commit together or none of them do.
final class DriftSaleWriter implements SaleWriter {
  const DriftSaleWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(SaleWriteContext write) body,
  ) => runner.run(actor, (tx) => body(_DriftSaleWriteContext(tx, sequences)));
}

final class _DriftSaleWriteContext implements SaleWriteContext {
  _DriftSaleWriteContext(this._tx, this._sequences);

  final Tx _tx;
  final SequenceAllocator _sequences;

  @override
  ActorContext get actor => _tx.actor;

  @override
  Future<TaxContext> taxContextFor(String? partyId) =>
      taxContextOf(_tx, partyId);

  @override
  Future<AllocatedNumber> nextNumber(String docType) async {
    final allocated = await _sequences.allocate(
      _tx,
      docType: docType,
      fiscalYear: actor.businessDate.fiscalYear,
    );
    return AllocatedNumber(
      formatted: allocated.formatted,
      series: allocated.series,
      sequence: allocated.sequence,
    );
  }

  @override
  Future<Map<String, Rate>> averageCostFor(Iterable<String> itemIds) async {
    final ids = itemIds.toList();
    if (ids.isEmpty) return const {};
    final rows = await _tx.select(
      'SELECT id, avg_cost_milli_paisa FROM items '
      'WHERE firm_id = ? AND id IN (${_placeholders(ids.length)})',
      [actor.firmId, ...ids],
    );
    return {
      for (final r in rows)
        r.read<String>('id'): Rate.raw(r.read<int>('avg_cost_milli_paisa')),
    };
  }

  @override
  Future<Map<String, String>> ledgerAccountsFor(
    Iterable<String> paymentAccountIds,
  ) async {
    final ids = paymentAccountIds.toList();
    if (ids.isEmpty) return const {};
    // Both ends have to be live. An archived payment account must not take
    // money, and neither must one whose entry in the chart has been archived
    // underneath it — otherwise the sale posts into an account that no longer
    // appears in any report, and the money is real but invisible.
    final rows = await _tx.select(
      'SELECT pa.id AS id, pa.ledger_account_id AS ledger_account_id '
      'FROM payment_accounts pa '
      'JOIN accounts a ON a.id = pa.ledger_account_id '
      'WHERE pa.firm_id = ? AND a.firm_id = pa.firm_id '
      'AND pa.deleted_at_utc IS NULL AND pa.is_active = 1 '
      'AND a.deleted_at_utc IS NULL AND a.is_active = 1 '
      'AND pa.id IN (${_placeholders(ids.length)})',
      [actor.firmId, ...ids],
    );
    final found = {
      for (final r in rows)
        r.read<String>('id'): r.read<String>('ledger_account_id'),
    };
    for (final id in ids) {
      if (!found.containsKey(id)) {
        throw StateError(
          'Payment account $id is not available in firm ${actor.firmId}: it '
          'has been archived, or the account it posts into has.',
        );
      }
    }
    return found;
  }

  @override
  Future<ChallanGoods?> deliveredOn(String documentId) async {
    final doc = await _tx.selectOne(
      'SELECT doc_no, doc_type, party_id FROM documents '
      "WHERE id = ? AND firm_id = ? AND status = 'posted' "
      '  AND deleted_at_utc IS NULL',
      [documentId, actor.firmId],
    );
    if (doc == null) {
      throw StateError(
        'The document this bill is made from is no longer standing.',
      );
    }
    if (doc.read<String>('doc_type') != 'delivery_challan') return null;
    final rows = await _tx.select(
      'SELECT item_id, SUM(base_qty_thousandths) AS qty, '
      '       SUM(cost_paisa) AS cost '
      'FROM document_lines '
      'WHERE document_id = ? AND item_id IS NOT NULL '
      '  AND deleted_at_utc IS NULL '
      'GROUP BY item_id',
      [documentId],
    );
    return ChallanGoods(
      challanId: documentId,
      docNo: doc.read<String>('doc_no'),
      partyId: doc.readNullable<String>('party_id'),
      byItem: {
        for (final r in rows)
          r.read<String>('item_id'): (
            qty: Qty.raw(r.read<int>('qty')),
            cost: Money.paisa(r.read<int>('cost')),
          ),
      },
    );
  }

  @override
  Future<PostedSale> apply(SalePosting posting) async {
    final doc = posting.document;

    final (documentId, lineIdByNo) = await insertDocumentRows(
      _tx,
      doc,
      posting.lines,
    );

    // A bill made from a quotation says so, once. Billing the same
    // quotation twice is two bills for one order, and the second is almost
    // always a double tap or a second till.
    if (posting.convertedFromId case final sourceId?) {
      final billed = await _tx.selectOne(
        'SELECT d.doc_no FROM doc_links link '
        'JOIN documents d ON d.id = link.to_document_id '
        "WHERE link.from_document_id = ? AND link.link_type = 'converted_from' "
        '  AND link.deleted_at_utc IS NULL AND d.status <> \'void\'',
        [sourceId],
      );
      if (billed != null) {
        final source = await _tx.selectOne(
          'SELECT doc_type FROM documents WHERE id = ?',
          [sourceId],
        );
        final kind = source?.read<String>('doc_type') == 'delivery_challan'
            ? 'challan'
            : 'quotation';
        throw StateError(
          'That $kind is already billed as '
          '${billed.read<String>('doc_no')}.',
        );
      }
      await _tx.insert('doc_links', {
        'from_document_id': sourceId,
        'to_document_id': documentId,
        'link_type': 'converted_from',
        'amount_paisa': doc.total.inPaisa,
      });
    }

    // --- Payments and their allocations ----------------------------------
    final paymentIds = <String>[];
    for (final payment in posting.payments) {
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
        'status': payment.isCheque ? 'pending' : 'cleared',
        'cheque_no': payment.chequeNo,
        'cheque_bank': payment.chequeBank,
        'cheque_date_utc': payment.chequeDateUtcMillis,
        'cheque_status': payment.isCheque ? 'issued' : null,
      });
      paymentIds.add(paymentId);

      await _tx.insert('payment_allocations', {
        'payment_id': paymentId,
        'document_id': documentId,
        'amount_paisa': payment.amount.inPaisa,
        'allocation_mode': 'exact',
        'allocated_at_utc': payment.paymentDateUtcMillis,
      });
    }

    // --- Stock ------------------------------------------------------------
    await insertStockMovements(
      _tx,
      documentId,
      lineIdByNo,
      posting.stockMovements,
      takeFromLots: true,
    );

    // --- Double entry ------------------------------------------------------
    final journalEntryId = await insertJournal(
      _tx,
      documentId,
      posting.journal,
    );

    _tx.audit(
      action: 'SALE_POSTED',
      entityTable: 'documents',
      entityId: documentId,
      summary: posting.auditSummary,
      amountPaisa: doc.total.inPaisa,
    );

    return PostedSale(
      documentId: documentId,
      docNo: doc.docNo,
      total: doc.total,
      paid: doc.paid,
      balance: doc.balance,
      change: Money.sum([for (final p in posting.payments) p.change]),
      journalEntryId: journalEntryId,
      paymentIds: paymentIds,
    );
  }

  static String _placeholders(int count) => List.filled(count, '?').join(', ');
}

/// Wires a [SaleWriter] onto an open database.
DriftSaleWriter saleWriterFor(
  AppDatabase database, {
  required IdGenerator ids,
  required HlcClock hlc,
}) => DriftSaleWriter(
  runner: TxRunner(database: database, ids: ids, hlc: hlc),
);
