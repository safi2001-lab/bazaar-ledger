import 'package:drift/drift.dart' show QueryRow;
import 'package:pk_domain/pk_domain.dart';

import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The drift implementation of [VoidWriter].
///
/// Reads what was actually written, mirrors it, and appends. Nothing in the
/// ledger is edited: `journal_entries`, `journal_lines` and `stock_ledger`
/// are append-only and `TxRunner` refuses to update them. The only row that
/// changes is the document's own status.
final class DriftVoidWriter implements VoidWriter {
  const DriftVoidWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(VoidWriteContext write) body,
  ) => runner.run(actor, (tx) => body(_DriftVoidWriteContext(tx, sequences)));
}

/// The void handle on a transaction somebody else opened: a correction
/// (M31) that cancels a charge or an expense and writes its replacement in
/// the same commit. Only ever handed a [Tx], so it cannot be a way round the
/// one write path.
VoidWriteContext voidContextOn(
  Tx tx, {
  SequenceAllocator sequences = const SequenceAllocator(),
}) => _DriftVoidWriteContext(tx, sequences);

final class _DriftVoidWriteContext implements VoidWriteContext {
  _DriftVoidWriteContext(this._tx, this._sequences);

  final Tx _tx;
  final SequenceAllocator _sequences;

  /// The tenders each snapshot found, carried from `snapshotOf` to `apply`.
  /// Both run inside one transaction on one instance, so this cannot outlive
  /// the correction it belongs to.
  final _tendersOf = <String, List<String>>{};

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
  Future<PostedDocumentSnapshot?> snapshotOf(String documentId) async {
    final doc = await _tx.selectOne(
      'SELECT id, doc_no, doc_type, total_paisa FROM documents '
      "WHERE id = ? AND firm_id = ? AND status = 'posted' "
      '  AND deleted_at_utc IS NULL',
      [documentId, actor.firmId],
    );
    if (doc == null) return null;

    // Sale bills and challans only. Reversing the journal and the stock is the whole of
    // undoing a sale, because a sale takes goods out at the average and
    // leaves the average alone. A delivery is different: it MOVED the
    // average, and a void that put the stock back out without moving the
    // cost back would leave every margin in the shop resting on a delivery
    // that never happened. Nothing on screen offers a void for anything else
    // yet; this makes sure nothing can, until that arithmetic exists.
    //
    // A delivery challan is the other: it took goods out at the average and
    // left the average alone, exactly as a sale does, and cancelling one is
    // the goods coming back on the van. Not once it is billed, though: then
    // the goods are sold, and it is the bill that has to go first.
    final docType = doc.read<String>('doc_type');
    if (docType == 'delivery_challan') {
      final billed = await _tx.selectOne(
        'SELECT bill.doc_no FROM doc_links link '
        'JOIN documents bill ON bill.id = link.to_document_id '
        "WHERE link.from_document_id = ? AND link.link_type = 'converted_from' "
        "  AND link.deleted_at_utc IS NULL AND bill.status <> 'void'",
        [documentId],
      );
      if (billed != null) {
        throw VoidRefused(
          '${doc.read<String>('doc_no')} is already billed as '
          '${billed.read<String>('doc_no')}. Cancel that bill first.',
        );
      }
    } else if (docType != 'sale_invoice' &&
        docType != 'other_income' &&
        docType != 'expense') {
      // A debit note (`other_income`, M25) is a charge on the khata with no
      // goods behind it: undoing it is its entry mirrored, exactly as a bill
      // with nothing on the shelf to put back.
      //
      // An expense (M31) is the same shape the other way round: rent or
      // bijli, two lines and no stock. One left on account to a supplier is
      // settled by supplier payments, and those stand in the way exactly as
      // receipts stand in the way of a bill — the allocation check below
      // already finds them, because it reads every payment, not only money
      // in.
      throw VoidRefused(
        '${doc.read<String>('doc_no')} is not a sale bill, and only a sale '
        'bill can be cancelled this way.',
      );
    }

    if (docType == 'sale_invoice') await _refuseWhatCannotBeUndone(doc);

    final entryRow = await _tx.selectOne(
      'SELECT id, entry_no, entry_date_utc, entry_date_local, fiscal_year, '
      '       source_type, total_debit_paisa, total_credit_paisa '
      'FROM journal_entries '
      'WHERE document_id = ? AND firm_id = ? AND deleted_at_utc IS NULL '
      // A document with several entries would be an M5 revision chain; the
      // first is the one that put it on the books.
      'ORDER BY entry_date_utc, id LIMIT 1',
      [documentId, actor.firmId],
    );
    if (entryRow == null) {
      // A posted document with no entry is a document that never reached the
      // books. Refusing beats appending a reversal of nothing, which would
      // leave a journal number burned on an entry with no lines.
      throw VoidRefused(
        'Bill ${doc.read<String>('doc_no')} has no journal entry, so there '
        'is nothing to undo. The books need checking before it is voided.',
      );
    }

    final entryId = entryRow.read<String>('id');
    final lineRows = await _tx.select(
      'SELECT line_no, account_id, debit_paisa, credit_paisa, party_id, '
      '       item_id, narration '
      'FROM journal_lines WHERE journal_entry_id = ? AND deleted_at_utc IS NULL '
      'ORDER BY line_no',
      [entryId],
    );

    final movementRows = await _tx.select(
      'SELECT item_id, location_code, lot_id, txn_type, '
      '       qty_delta_thousandths, rate_milli_paisa, value_delta_paisa, '
      '       COALESCE(document_line_id, id) AS line_key '
      'FROM stock_ledger '
      'WHERE document_id = ? AND firm_id = ? AND deleted_at_utc IS NULL '
      'ORDER BY occurred_at_utc, id',
      [documentId, actor.firmId],
    );

    // The receipts standing in the way, which is NOT every payment touching
    // this bill.
    //
    // A cash sale writes its own tender and allocates it to itself, so
    // treating every allocation as an obstacle would make every cash sale
    // unvoidable — which is what the first version of this did.
    //
    // The two are different events. A tender at the counter is part of the
    // sale: cancelling the bill means handing the money straight back, and
    // both records go together. A receipt taken later is money the customer
    // really did hand over against a khata, and voiding the bill underneath
    // it would either lose that money or leave an allocation pointing at a
    // document no report considers real.
    //
    // The discriminator is `allocation_mode`. `DriftSaleWriter` writes
    // `exact` for a tender it created itself; `ReceiptDraft.allocationMode`
    // defaults to `fifo`. That is a real coupling between two files and it is
    // named here rather than left to be discovered — a proof asserts a
    // receipt against this single bill still refuses.
    final allocationRows = await _tx.select(
      'SELECT p.payment_no AS no FROM payment_allocations pa '
      'JOIN payments p ON p.id = pa.payment_id '
      'WHERE pa.document_id = ? AND pa.deleted_at_utc IS NULL '
      "  AND p.deleted_at_utc IS NULL AND p.status <> 'void' "
      "  AND pa.allocation_mode <> 'exact' "
      'ORDER BY p.payment_no',
      [documentId],
    );

    // The bill's own tenders, which go when it goes.
    final tenderRows = await _tx.select(
      'SELECT DISTINCT p.id AS payment_id FROM payment_allocations pa '
      'JOIN payments p ON p.id = pa.payment_id '
      'WHERE pa.document_id = ? AND pa.deleted_at_utc IS NULL '
      "  AND p.deleted_at_utc IS NULL AND p.status <> 'void' "
      "  AND pa.allocation_mode = 'exact'",
      [documentId],
    );
    _tendersOf[documentId] = [
      for (final r in tenderRows) r.read<String>('payment_id'),
    ];

    return PostedDocumentSnapshot(
      documentId: documentId,
      docNo: doc.read<String>('doc_no'),
      docType: docType,
      total: Money.paisa(doc.read<int>('total_paisa')),
      entryId: entryId,
      entry: JournalEntryPosting(
        entryNo: entryRow.read<String>('entry_no'),
        entryDateUtcMillis: entryRow.read<int>('entry_date_utc'),
        entryDateLocal: entryRow.read<String>('entry_date_local'),
        fiscalYear: entryRow.read<int>('fiscal_year'),
        sourceType: entryRow.read<String>('source_type'),
        totalDebit: Money.paisa(entryRow.read<int>('total_debit_paisa')),
        totalCredit: Money.paisa(entryRow.read<int>('total_credit_paisa')),
        lines: [
          for (final r in lineRows)
            JournalLinePosting(
              lineNo: r.read<int>('line_no'),
              // Already resolved, so the reversal names the same account row
              // the original did. Going back through a system key would
              // re-resolve, and an account renamed or re-keyed since would
              // send the reversal somewhere else.
              accountSystemKey: '#${r.read<String>('account_id')}',
              debit: Money.paisa(r.read<int>('debit_paisa')),
              credit: Money.paisa(r.read<int>('credit_paisa')),
              partyId: r.readNullable<String>('party_id'),
              itemId: r.readNullable<String>('item_id'),
              narration: r.readNullable<String>('narration'),
            ),
        ],
      ),
      movements: [
        for (var i = 0; i < movementRows.length; i++)
          StockMovementPosting(
            itemId: movementRows[i].read<String>('item_id'),
            locationCode: movementRows[i].read<String>('location_code'),
            lotId: movementRows[i].readNullable<String>('lot_id'),
            txnType: movementRows[i].read<String>('txn_type'),
            qtyDelta: Qty.raw(
              movementRows[i].read<int>('qty_delta_thousandths'),
            ),
            rate: Rate.raw(movementRows[i].read<int>('rate_milli_paisa')),
            valueDelta: Money.paisa(
              movementRows[i].read<int>('value_delta_paisa'),
            ),
            occurredAtUtcMillis: 0,
            occurredOnLocal: '',
            lineNo: i + 1,
          ),
      ],
      allocatedPayments: [for (final r in allocationRows) r.read<String>('no')],
    );
  }

  /// Two bills a cancel would count twice, refused before anything is read
  /// for the reversal (M36).
  ///
  /// Both were found putting "correct and reissue" on top of this path,
  /// which makes cancelling an everyday act rather than a rare one, and
  /// both would have doubled money.
  ///
  /// Goods already brought back. The return wrote its own entry — Sales
  /// Returns, the stock back on the shelf, the refund or the khata credit —
  /// and the reversal mirrors the WHOLE sale, so the returned goods would
  /// come back a second time and the customer be credited twice for them.
  /// A return cannot itself be cancelled, so the way on is taking the rest
  /// back as a return too.
  ///
  /// A cheque taken at the counter that has gone to the bank. Cancelling the
  /// bill cancels its own tenders, and a cancelled payment for a cheque the
  /// bank has cleared, is clearing or sent back contradicts the bank — the
  /// same rule M31 holds for a cheque taken against the khata. A cheque the
  /// shop still holds goes with the bill, as cash does.
  Future<void> _refuseWhatCannotBeUndone(QueryRow doc) async {
    final docNo = doc.read<String>('doc_no');
    final returned = await _tx.select(
      'SELECT r.doc_no FROM doc_links link '
      'JOIN documents r ON r.id = link.to_document_id '
      "WHERE link.from_document_id = ? AND link.link_type = 'returns' "
      "  AND link.deleted_at_utc IS NULL AND r.status = 'posted' "
      '  AND r.deleted_at_utc IS NULL '
      'ORDER BY r.doc_no',
      [doc.read<String>('id')],
    );
    if (returned.isNotEmpty) {
      final nos = [for (final r in returned) r.read<String>('doc_no')];
      throw VoidRefused(
        'Goods have already come back on $docNo (${nos.join(', ')}), so it '
        'can no longer be cancelled — the return would be counted twice. '
        'Take the rest back as a return instead.',
      );
    }
    final cheque = await _tx.selectOne(
      'SELECT p.cheque_no FROM payment_allocations pa '
      'JOIN payments p ON p.id = pa.payment_id '
      'WHERE pa.document_id = ? AND pa.deleted_at_utc IS NULL '
      "  AND pa.allocation_mode = 'exact' AND p.deleted_at_utc IS NULL "
      "  AND p.mode = 'cheque' AND p.status <> 'void' "
      "  AND (p.status IN ('cleared', 'bounced') "
      "       OR COALESCE(p.cheque_status, 'issued') <> 'issued') "
      'LIMIT 1',
      [doc.read<String>('id')],
    );
    if (cheque != null) {
      throw VoidRefused(
        '$docNo was paid by cheque ${cheque.readNullable<String>('cheque_no') ?? ''}, '
        'which has gone to the bank. Cancelling the bill would cancel a '
        'cheque the bank has already dealt with. Take the goods back as a '
        'return instead.',
      );
    }
  }

  @override
  Future<VoidedDocument> apply(VoidPosting posting) async {
    posting.assertBalanced();

    final entry = posting.journal;
    final journalEntryId = await _tx.insert('journal_entries', {
      'entry_no': entry.entryNo,
      'entry_date_utc': entry.entryDateUtcMillis,
      'entry_date_local': entry.entryDateLocal,
      'fiscal_year': entry.fiscalYear,
      'source_type': entry.sourceType,
      'document_id': posting.documentId,
      // The pair, findable together forever. A reversal that does not point
      // at its original is a second entry nobody can explain.
      'reverses_entry_id': posting.reversesEntryId,
      'narration': entry.narration,
      'total_debit_paisa': entry.totalDebit.inPaisa,
      'total_credit_paisa': entry.totalCredit.inPaisa,
    });

    for (final line in entry.lines) {
      if (!line.isResolvedAccountId) {
        throw StateError(
          'A reversal line names account "${line.accountSystemKey}" by key '
          'rather than by id. The mirror of a written entry must point at the '
          'same account rows the original did.',
        );
      }
      await _tx.insert('journal_lines', {
        'journal_entry_id': journalEntryId,
        'line_no': line.lineNo,
        'account_id': line.accountId,
        'debit_paisa': line.debit.inPaisa,
        'credit_paisa': line.credit.inPaisa,
        'party_id': line.partyId,
        'item_id': line.itemId,
        'narration': line.narration,
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
        'lot_id': movement.lotId,
        'document_id': posting.documentId,
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

    // The bill's own tenders go with it. The money went into the drawer for
    // a sale that is being cancelled at the counter, and the shopkeeper is
    // handing it back as they tap — the reversal above has already taken the
    // cash debit out of the books, so leaving the payment row standing would
    // claim money came in that did not.
    // The allocation row is left where it is. `amount_paisa > 0` is a CHECK,
    // so it cannot be zeroed, and `deleted_at_utc` is an envelope column
    // TxRunner refuses to let anything set by hand — both correctly. A row
    // pointing from a void payment at a void document is inert: every report
    // that reads allocations already has to filter on status, and the pair
    // remains as evidence of what happened.
    final tenders = _tendersOf[posting.documentId] ?? const <String>[];
    for (final paymentId in tenders) {
      await _tx.update('payments', paymentId, {'status': 'void'});
    }

    // The only other row that changes. The bill itself is left exactly as it
    // was printed, so the paper the customer is holding still matches what
    // the shop has — it is simply marked as no longer standing.
    await _tx.update('documents', posting.documentId, {
      'status': 'void',
      'void_reason': posting.reason,
    });

    _tx.audit(
      action: 'DOCUMENT_VOIDED',
      entityTable: 'documents',
      entityId: posting.documentId,
      summary: posting.auditSummary,
      amountPaisa: entry.totalDebit.inPaisa,
    );

    return VoidedDocument(
      documentId: posting.documentId,
      docNo: posting.docNo,
      reversingEntryId: journalEntryId,
      reason: posting.reason,
    );
  }
}
