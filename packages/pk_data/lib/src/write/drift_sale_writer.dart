import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';
import 'document_rows.dart';
import 'drift_order_writer.dart';
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
  Future<PostedSale> apply(SalePosting given) async {
    // A bill made from a sale order takes the advance paid on it (M41).
    final posting = await withHeldAdvances(_tx, given);
    final doc = posting.document;

    final (documentId, lineIdByNo) = await insertDocumentRows(
      _tx,
      doc,
      posting.lines,
    );

    // A bill made from a quotation says so, once. Billing the same
    // quotation twice is two bills for one order, and the second is almost
    // always a double tap or a second till.
    // Several challans on one bill (M25) are each linked, and each checked.
    for (final sourceId in [?posting.convertedFromId, ...posting.alsoFromIds]) {
      final billed = await _tx.selectOne(
        'SELECT d.doc_no FROM doc_links link '
        'JOIN documents d ON d.id = link.to_document_id '
        "WHERE link.from_document_id = ? AND link.link_type = 'converted_from' "
        '  AND link.deleted_at_utc IS NULL AND d.status <> \'void\'',
        [sourceId],
      );
      // A sale order (M41) is billed a delivery at a time; it is never
      // "already billed", and what is left of it is read off its bills.
      if (billed != null && !await isSaleOrder(_tx, sourceId)) {
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

    // A bill put right (M36): the cancelled bill it replaces, linked in the
    // same commit, so a bill killed half way can never be one that replaces
    // nothing. Read both ways — "Replaces INV-…" on this one, "Replaced by"
    // on that — from the one row.
    if (posting.replacesId case final replacedId?) {
      await _linkReplaced(replacedId, documentId, doc);
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

  /// Links [documentId] as the bill that puts [replacedId] right (M36).
  ///
  /// `revises`, a link type the schema has carried since v1 for exactly
  /// this and nothing has written until now; no schema change. Not
  /// `supersedes_id`: that column is a revision of the SAME numbered
  /// document (`CHECK (revision = 1 OR supersedes_id IS NOT NULL)`), and a
  /// corrected bill is a new bill with a number of its own. Nor
  /// `voided_by_id`, which would have to be written onto a bill that is
  /// already cancelled and would name the wrong thing — the cancellation
  /// is the reversing entry, not this bill.
  ///
  /// Refused, in words, when the bill named is not a cancelled sale bill of
  /// this shop, or has already been put right by a bill still standing:
  /// two bills each saying they replace the same one is one customer billed
  /// twice for one mistake.
  Future<void> _linkReplaced(
    String replacedId,
    String documentId,
    DocumentPosting doc,
  ) async {
    final old = await _tx.selectOne(
      'SELECT doc_no, doc_type, status FROM documents '
      'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
      [replacedId, actor.firmId],
    );
    if (old == null || old.read<String>('doc_type') != 'sale_invoice') {
      throw StateError(
        'The bill this one is meant to replace is not a sale bill of this '
        'shop.',
      );
    }
    final oldNo = old.read<String>('doc_no');
    if (old.read<String>('status') != 'void') {
      throw StateError(
        '$oldNo is still standing. A bill is replaced only once it has been '
        'cancelled.',
      );
    }
    final already = await _tx.selectOne(
      'SELECT d.doc_no FROM doc_links link '
      'JOIN documents d ON d.id = link.to_document_id '
      "WHERE link.from_document_id = ? AND link.link_type = 'revises' "
      "  AND link.deleted_at_utc IS NULL AND d.status <> 'void'",
      [replacedId],
    );
    if (already != null) {
      throw StateError(
        '$oldNo has already been put right as '
        '${already.read<String>('doc_no')}.',
      );
    }
    await _tx.insert('doc_links', {
      'from_document_id': replacedId,
      'to_document_id': documentId,
      'link_type': 'revises',
      'amount_paisa': doc.total.inPaisa,
    });
    _tx.audit(
      action: 'BILL_REISSUED',
      entityTable: 'documents',
      entityId: documentId,
      summary: '${doc.docNo} replaces cancelled $oldNo',
      amountPaisa: doc.total.inPaisa,
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
