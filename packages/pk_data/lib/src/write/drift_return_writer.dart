import 'package:pk_domain/pk_domain.dart';

import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The drift implementation of [ReturnWriter].
///
/// The return is its own document with its own number, linked to the bill it
/// came off. Nothing on the original changes except how much of it is still
/// owed — the bill a customer is holding still says what it always said.
final class DriftReturnWriter implements ReturnWriter {
  const DriftReturnWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(ReturnWriteContext write) body,
  ) => runner.run(actor, (tx) => body(_DriftReturnWriteContext(tx, sequences)));
}

final class _DriftReturnWriteContext implements ReturnWriteContext {
  _DriftReturnWriteContext(this._tx, this._sequences);

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
  Future<ReturnableBill?> billFor(String documentId) async {
    final doc = await _tx.selectOne(
      'SELECT id, doc_no, party_id, balance_paisa FROM documents '
      "WHERE id = ? AND firm_id = ? AND doc_type = 'sale_invoice' "
      "  AND status = 'posted' AND deleted_at_utc IS NULL",
      [documentId, actor.firmId],
    );
    if (doc == null) return null;

    // Each line as sold, and what earlier returns already took off it.
    //
    // The subquery counts returns through `doc_links`, so a second visit
    // knows what the first took. Counted here rather than cached on the line,
    // because a cache is a second answer and the whole point of the limit is
    // that it cannot be walked past.
    final lineRows = await _tx.select(
      '''
      SELECT dl.id, dl.item_id, dl.item_name_snapshot, dl.unit_id,
             dl.unit_code_snapshot, dl.base_qty_thousandths,
             dl.rate_milli_paisa, dl.cost_paisa,
             COALESCE((
               SELECT SUM(rl.base_qty_thousandths)
               FROM doc_links link
               JOIN documents r ON r.id = link.to_document_id
               JOIN document_lines rl ON rl.document_id = r.id
               WHERE link.from_document_id = dl.document_id
                 AND link.link_type = 'returns'
                 AND link.deleted_at_utc IS NULL
                 AND r.status = 'posted'
                 AND r.deleted_at_utc IS NULL
                 AND (rl.item_id = dl.item_id
                      -- A loose line (M37) has no item to match on. It is
                      -- known by what it was called, its price and its
                      -- unit, which the return line copies from it.
                      OR (dl.item_id IS NULL AND rl.item_id IS NULL
                          AND rl.item_name_snapshot = dl.item_name_snapshot
                          AND rl.rate_milli_paisa = dl.rate_milli_paisa
                          AND rl.unit_code_snapshot = dl.unit_code_snapshot))
                 AND rl.deleted_at_utc IS NULL
             ), 0) AS returned,
             COALESCE((SELECT SUM(t.amount_paisa) FROM document_line_taxes t
                        WHERE t.document_line_id = dl.id
                          AND t.tax_kind = 'sales_tax'), 0) AS sales_tax,
             COALESCE((SELECT SUM(t.amount_paisa) FROM document_line_taxes t
                        WHERE t.document_line_id = dl.id
                          AND t.tax_kind = 'further_tax'), 0) AS further_tax,
             COALESCE((SELECT MAX(t.is_inclusive) FROM document_line_taxes t
                        WHERE t.document_line_id = dl.id
                          AND t.tax_kind = 'sales_tax'), 0) AS tax_inclusive
      FROM document_lines dl
      WHERE dl.document_id = ? AND dl.deleted_at_utc IS NULL
      ORDER BY dl.line_no
      ''',
      [documentId],
    );

    return ReturnableBill(
      documentId: documentId,
      docNo: doc.read<String>('doc_no'),
      partyId: doc.readNullable<String>('party_id'),
      outstanding: Money.paisa(doc.read<int>('balance_paisa')),
      lines: [
        for (final r in lineRows)
          SoldLine(
            documentLineId: r.read<String>('id'),
            itemId: r.readNullable<String>('item_id'),
            itemName: r.read<String>('item_name_snapshot'),
            unitId: r.readNullable<String>('unit_id') ?? '',
            unitCode: r.read<String>('unit_code_snapshot'),
            soldQty: Qty.raw(r.read<int>('base_qty_thousandths')),
            alreadyReturned: Qty.raw(r.read<int>('returned')),
            rate: Rate.raw(r.read<int>('rate_milli_paisa')),
            // The snapshot. Never today's average — see ReturnBuilder.
            cost: Money.paisa(r.read<int>('cost_paisa')),
            salesTax: Money.paisa(r.read<int>('sales_tax')),
            furtherTax: Money.paisa(r.read<int>('further_tax')),
            taxInclusive: r.read<int>('tax_inclusive') == 1,
          ),
      ],
    );
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

  /// Where goods coming back go (M27): into the batches the bill took them
  /// from, as far as those batches gave them, so a strip of tablets
  /// returned is back under its own expiry rather than in no batch at all.
  /// Anything beyond what the batches gave, or an item kept without
  /// batches, goes back as it came: unbatched.
  Future<List<({String? lotId, int qty, Money value})>> _intoLots(
    String billId,
    StockMovementPosting movement,
  ) async {
    final whole = [
      (
        lotId: movement.lotId,
        qty: movement.qtyDelta.inThousandths,
        value: movement.valueDelta,
      ),
    ];
    if (movement.lotId != null || !movement.qtyDelta.isPositive) return whole;
    final taken = await _tx.select(
      'SELECT s.lot_id, -SUM(s.qty_delta_thousandths) AS taken '
      'FROM stock_ledger s '
      'WHERE s.document_id = ? AND s.item_id = ? AND s.lot_id IS NOT NULL '
      '  AND s.deleted_at_utc IS NULL '
      'GROUP BY s.lot_id ORDER BY MIN(s.occurred_at_utc), s.lot_id',
      [billId, movement.itemId],
    );
    if (taken.isEmpty) return whole;
    final back = {
      for (final r in await _tx.select(
        'SELECT s.lot_id, SUM(s.qty_delta_thousandths) AS back '
        'FROM stock_ledger s '
        'JOIN doc_links l ON l.to_document_id = s.document_id '
        "  AND l.from_document_id = ? AND l.link_type = 'returns' "
        '  AND l.deleted_at_utc IS NULL '
        'WHERE s.item_id = ? AND s.lot_id IS NOT NULL '
        '  AND s.deleted_at_utc IS NULL '
        'GROUP BY s.lot_id',
        [billId, movement.itemId],
      ))
        r.read<String>('lot_id'): r.read<int>('back'),
    };
    var left = movement.qtyDelta.inThousandths;
    final parts = <({String? lotId, int qty})>[];
    for (final r in taken) {
      if (left <= 0) break;
      final lot = r.read<String>('lot_id');
      final room = r.read<int>('taken') - (back[lot] ?? 0);
      if (room <= 0) continue;
      final q = room < left ? room : left;
      parts.add((lotId: lot, qty: q));
      left -= q;
    }
    if (left > 0) parts.add((lotId: null, qty: left));
    final values = movement.valueDelta.allocate([for (final p in parts) p.qty]);
    return [
      for (var i = 0; i < parts.length; i++)
        (lotId: parts[i].lotId, qty: parts[i].qty, value: values[i]),
    ];
  }

  @override
  Future<RecordedReturn> apply(ReturnPosting posting) async {
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
      'line_discount_paisa': doc.lineDiscount.inPaisa,
      'bill_discount_paisa': doc.billDiscount.inPaisa,
      'taxable_paisa': doc.taxable.inPaisa,
      'tax_paisa': doc.tax.inPaisa,
      'further_tax_paisa': doc.furtherTax.inPaisa,
      'withholding_paisa': doc.withholding.inPaisa,
      'extra_charges_paisa': doc.extraCharges.inPaisa,
      'round_off_paisa': doc.roundOff.inPaisa,
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
        'discount_paisa': line.discount.inPaisa,
        'discount_bp': line.discountBp,
        'taxable_paisa': line.taxable.inPaisa,
        'tax_paisa': line.tax.inPaisa,
        'line_total_paisa': line.lineTotal.inPaisa,
        'cost_paisa': line.cost.inPaisa,
        'is_free_item': line.isFreeItem ? 1 : 0,
      });
      // The tax given back on the line, kept beside it as a sale's is, so
      // the sales tax summary can take it off what was charged.
      for (final tax in line.taxes) {
        await _tx.insert('document_line_taxes', {
          'document_line_id': lineIdByNo[line.lineNo],
          'document_id': documentId,
          'tax_kind': tax.kind.code,
          'tax_code': tax.code,
          'rate_bp': tax.rateBp,
          'base_paisa': tax.base.inPaisa,
          'amount_paisa': tax.amount.inPaisa,
          'is_inclusive': tax.isInclusive ? 1 : 0,
        });
      }
    }

    for (final movement in posting.stockMovements) {
      for (final part in await _intoLots(
        posting.originalDocumentId,
        movement,
      )) {
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
          'lot_id': part.lotId,
          'document_id': documentId,
          'document_line_id': lineIdByNo[movement.lineNo],
          'txn_type': movement.txnType,
          'qty_delta_thousandths': part.qty,
          'rate_milli_paisa': movement.rate.inMilliPaisa,
          'value_delta_paisa': part.value.inPaisa,
          'balance_after_thousandths':
              (running?.read<int>('balance') ?? 0) + part.qty,
          'occurred_at_utc': movement.occurredAtUtcMillis,
          'occurred_on_local': movement.occurredOnLocal,
        });
      }
    }

    // The link, which is what lets a second return know what the first took.
    // Without it the limit is only ever within one visit, and a customer can
    // return the same tin every day.
    await _tx.insert('doc_links', {
      'from_document_id': posting.originalDocumentId,
      'to_document_id': documentId,
      'link_type': 'returns',
      'amount_paisa': doc.total.inPaisa,
    });

    // What the original bill can still absorb comes off it. The rest is money
    // the shop is holding, and the journal has already credited it to
    // Customer Advances — nothing more to do here for that half.
    if (posting.againstBill.isPositive) {
      final original = await _tx.selectOne(
        'SELECT balance_paisa FROM documents WHERE id = ? AND firm_id = ?',
        [posting.originalDocumentId, actor.firmId],
      );
      if (original == null) {
        throw const ReturnRefused(
          'The bill vanished between being read and being credited.',
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
      action: 'SALE_RETURNED',
      entityTable: 'documents',
      entityId: documentId,
      summary: posting.auditSummary,
      amountPaisa: doc.total.inPaisa,
    );

    return RecordedReturn(
      documentId: documentId,
      docNo: doc.docNo,
      total: doc.total,
      refunded: posting.refund,
      againstBill: posting.againstBill,
      onAccount: posting.onAccount,
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
