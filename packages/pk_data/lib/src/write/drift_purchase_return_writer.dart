import 'package:drift/drift.dart' show QueryRow;
import 'package:pk_domain/pk_domain.dart';

import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The drift implementation of [PurchaseReturnWriter].
///
/// Its own document with its own number, linked to the delivery it came off.
/// Nothing on the delivery changes except how much of it is still owed — the
/// supplier's paper in the shopkeeper's drawer still says what it always
/// said.
final class DriftPurchaseReturnWriter implements PurchaseReturnWriter {
  const DriftPurchaseReturnWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(PurchaseReturnWriteContext write) body,
  ) => runner.run(
    actor,
    (tx) => body(_DriftPurchaseReturnWriteContext(tx, sequences)),
  );
}

/// What earlier returns already sent back of one delivery line, through
/// `doc_links`, in the base unit. The same subquery the read side uses, so
/// the screen cannot offer a quantity this refuses.
///
/// Matched on the unit as well as the item (M57), which every return line
/// copies from the line it came off: a delivery of two maunds of atta and
/// ten kilos of the same atta is two lines, and a maund sent back off one is
/// not counted off the other.
const returnedOffDeliveryLine = '''
  COALESCE((
    SELECT SUM(rl.base_qty_thousandths)
    FROM doc_links link
    JOIN documents r ON r.id = link.to_document_id
    JOIN document_lines rl ON rl.document_id = r.id
    WHERE link.from_document_id = dl.document_id
      AND link.link_type = 'returns'
      AND link.deleted_at_utc IS NULL
      AND r.doc_type = 'purchase_return'
      AND r.status = 'posted'
      AND r.deleted_at_utc IS NULL
      AND rl.item_id = dl.item_id
      AND rl.unit_code_snapshot = dl.unit_code_snapshot
      AND rl.deleted_at_utc IS NULL
  ), 0)
''';

final class _DriftPurchaseReturnWriteContext
    implements PurchaseReturnWriteContext {
  _DriftPurchaseReturnWriteContext(this._tx, this._sequences);

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
  Future<ReturnableDelivery?> deliveryFor(String documentId) async {
    final doc = await _tx.selectOne(
      'SELECT id, doc_no, party_id, balance_paisa FROM documents '
      "WHERE id = ? AND firm_id = ? AND doc_type = 'purchase_bill' "
      "  AND status = 'posted' AND deleted_at_utc IS NULL",
      [documentId, actor.firmId],
    );
    if (doc == null) return null;

    final lineRows = await _tx.select(
      '''
      SELECT dl.id, dl.item_id, dl.item_name_snapshot, dl.unit_id,
             dl.unit_code_snapshot, dl.qty_thousandths,
             dl.base_qty_thousandths, dl.rate_milli_paisa,
             dl.line_total_paisa, dl.cost_paisa,
             $returnedOffDeliveryLine AS returned
      FROM document_lines dl
      WHERE dl.document_id = ? AND dl.deleted_at_utc IS NULL
      ORDER BY dl.line_no
      ''',
      [documentId],
    );

    return ReturnableDelivery(
      documentId: documentId,
      docNo: doc.read<String>('doc_no'),
      partyId: doc.read<String>('party_id'),
      outstanding: Money.paisa(doc.read<int>('balance_paisa')),
      lines: [for (final r in lineRows) boughtLineFrom(r)],
    );
  }

  @override
  Future<Map<String, CostPosition>> costPositionsFor(
    Iterable<String> itemIds,
  ) async {
    final ids = itemIds.toSet().toList();
    if (ids.isEmpty) return const {};
    // The same read a delivery makes: balance off the stock ledger, average
    // off the item row, value derived by `CostPosition.onShelf`.
    final rows = await _tx.select(
      '''
      SELECT i.id,
             i.avg_cost_milli_paisa,
             COALESCE((
               SELECT SUM(s.qty_delta_thousandths) FROM stock_ledger s
               WHERE s.item_id = i.id AND s.firm_id = i.firm_id
                 AND s.deleted_at_utc IS NULL
             ), 0) AS balance
      FROM items i
      WHERE i.firm_id = ? AND i.id IN (${List.filled(ids.length, '?').join(', ')})
      ''',
      [actor.firmId, ...ids],
    );
    return {
      for (final r in rows)
        r.read<String>('id'): CostPosition.onShelf(
          qty: Qty.raw(r.read<int>('balance')),
          avg: Rate.raw(r.read<int>('avg_cost_milli_paisa')),
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
  Future<RecordedPurchaseReturn> apply(PurchaseReturnPosting posting) async {
    posting.assertBalanced();

    final doc = posting.document;
    final documentId = await _tx.insert('documents', {
      'doc_type': doc.docType,
      'doc_no': doc.docNo,
      'doc_series': doc.docSeries,
      'doc_seq': doc.docSeq,
      'fiscal_year': doc.fiscalYear,
      'doc_date_utc': doc.docDateUtcMillis,
      'doc_date_local': doc.docDateLocal,
      'party_id': doc.partyId,
      'status': 'posted',
      'posted_at_utc': doc.docDateUtcMillis,
      'subtotal_paisa': doc.subtotal.inPaisa,
      'taxable_paisa': doc.taxable.inPaisa,
      'total_paisa': doc.total.inPaisa,
      'paid_paisa': doc.paid.inPaisa,
      'balance_paisa': doc.balance.inPaisa,
      'cost_paisa': doc.cost.inPaisa,
      'rounding_mode': doc.roundingMode,
      'tax_rule_version': doc.taxRuleVersion,
      'notes': doc.notes,
    });

    final lineIdByNo = <int, String>{};
    for (final line in posting.lines) {
      lineIdByNo[line.lineNo] = await _tx.insert('document_lines', {
        'document_id': documentId,
        'line_no': line.lineNo,
        'item_id': line.itemId,
        'item_name_snapshot': line.itemNameSnapshot,
        'qty_thousandths': line.qty.inThousandths,
        'unit_id': line.unitId,
        'unit_code_snapshot': line.unitCodeSnapshot,
        'base_qty_thousandths': line.baseQty.inThousandths,
        'rate_milli_paisa': line.rate.inMilliPaisa,
        'gross_paisa': line.gross.inPaisa,
        'taxable_paisa': line.taxable.inPaisa,
        'line_total_paisa': line.lineTotal.inPaisa,
        'cost_paisa': line.cost.inPaisa,
      });
    }

    for (final movement in posting.stockMovements) {
      final running = await _tx.selectOne(
        'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS balance '
        'FROM stock_ledger '
        'WHERE firm_id = ? AND item_id = ? AND location_code = ? '
        '  AND deleted_at_utc IS NULL',
        [actor.firmId, movement.itemId, movement.locationCode],
      );
      await _tx.insert('stock_ledger', {
        'item_id': movement.itemId,
        'location_code': movement.locationCode,
        'document_id': documentId,
        'document_line_id': lineIdByNo[movement.lineNo],
        'txn_type': movement.txnType,
        'qty_delta_thousandths': movement.qtyDelta.inThousandths,
        'rate_milli_paisa': movement.rate.inMilliPaisa,
        'value_delta_paisa': movement.valueDelta.inPaisa,
        'balance_after_thousandths':
            (running?.read<int>('balance') ?? 0) +
            movement.qtyDelta.inThousandths,
        'occurred_at_utc': movement.occurredAtUtcMillis,
        'occurred_on_local': movement.occurredOnLocal,
      });
    }

    // The averages the builder computed. No arithmetic here, so no room to
    // do it a second way.
    for (final entry in posting.newAverages.entries) {
      await _tx.update('items', entry.key, {
        'avg_cost_milli_paisa': entry.value.inMilliPaisa,
      });
    }

    // What lets a second return know what the first sent back.
    await _tx.insert('doc_links', {
      'from_document_id': posting.originalDocumentId,
      'to_document_id': documentId,
      'link_type': 'returns',
      'amount_paisa': doc.total.inPaisa,
    });

    if (posting.againstBill.isPositive) {
      final original = await _tx.selectOne(
        'SELECT balance_paisa FROM documents WHERE id = ? AND firm_id = ?',
        [posting.originalDocumentId, actor.firmId],
      );
      if (original == null) {
        throw const ReturnRefused(
          'The delivery vanished between being read and being credited.',
        );
      }
      await _tx.update('documents', posting.originalDocumentId, {
        'balance_paisa':
            original.read<int>('balance_paisa') - posting.againstBill.inPaisa,
      });
    }

    final entry = posting.journal;
    final journalEntryId = await _tx.insert('journal_entries', {
      'entry_no': entry.entryNo,
      'entry_date_utc': entry.entryDateUtcMillis,
      'entry_date_local': entry.entryDateLocal,
      'fiscal_year': entry.fiscalYear,
      'source_type': entry.sourceType,
      'document_id': documentId,
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
          '${actor.firmId}. The chart of accounts is incomplete, and a '
          'return cannot be posted against an account that does not exist.',
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
      action: 'PURCHASE_RETURNED',
      entityTable: 'documents',
      entityId: documentId,
      summary: posting.auditSummary,
      amountPaisa: doc.total.inPaisa,
    );

    return RecordedPurchaseReturn(
      documentId: documentId,
      docNo: doc.docNo,
      total: doc.total,
      refunded: posting.refund,
      againstBill: posting.againstBill,
      journalEntryId: journalEntryId,
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

/// One delivery line as the return screen and the writer both read it.
BoughtLine boughtLineFrom(QueryRow r) => BoughtLine(
  documentLineId: r.read<String>('id'),
  itemId: r.read<String>('item_id'),
  itemName: r.read<String>('item_name_snapshot'),
  unitId: r.readNullable<String>('unit_id') ?? '',
  unitCode: r.read<String>('unit_code_snapshot'),
  // As billed and as shelved: the pair is the conversion the delivery was
  // made with, which is what a maund sent back is converted by (M57).
  qty: Qty.raw(r.read<int>('qty_thousandths')),
  rate: Rate.raw(r.read<int>('rate_milli_paisa')),
  boughtQty: Qty.raw(r.read<int>('base_qty_thousandths')),
  alreadyReturned: Qty.raw(r.read<int>('returned')),
  goodsValue: Money.paisa(r.read<int>('line_total_paisa')),
  // The snapshot of what it landed at. Never today's average.
  landedCost: Money.paisa(r.read<int>('cost_paisa')),
);
