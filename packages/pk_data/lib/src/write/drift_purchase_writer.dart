import 'package:pk_domain/pk_domain.dart';

import 'document_rows.dart';
import 'drift_order_writer.dart';
import 'sequence_allocator.dart';
import 'tx_runner.dart';

/// The drift implementation of [PurchaseWriter].
///
/// The first thing in this repository that ever moves
/// `items.avg_cost_milli_paisa`. It was written once at item creation and
/// `DriftCatalogueWriter` explicitly strips it from every update, so until
/// this exists every margin figure in the app is a guess.
final class DriftPurchaseWriter implements PurchaseWriter {
  const DriftPurchaseWriter({
    required this.runner,
    this.sequences = const SequenceAllocator(),
  });

  final TxRunner runner;
  final SequenceAllocator sequences;

  @override
  Future<T> inTransaction<T>(
    ActorContext actor,
    Future<T> Function(PurchaseWriteContext write) body,
  ) => runner.run(
    actor,
    (tx) => body(_DriftPurchaseWriteContext(tx, sequences)),
  );
}

final class _DriftPurchaseWriteContext implements PurchaseWriteContext {
  _DriftPurchaseWriteContext(this._tx, this._sequences);

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
  Future<Map<String, CostPosition>> costPositionsFor(
    Iterable<String> itemIds,
  ) async {
    final ids = itemIds.toSet().toList();
    if (ids.isEmpty) return const {};

    // The balance comes from the stock ledger and the average from the item
    // row. The carried VALUE is derived rather than stored, because the
    // invariant is `value == round(avg x qty)` — a stored column would be a
    // second answer to the same question, and the two would disagree the
    // first time one of them was written by a path that forgot the other.
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
      WHERE i.firm_id = ? AND i.id IN (${_placeholders(ids.length)})
      ''',
      [actor.firmId, ...ids],
    );

    final positions = <String, CostPosition>{};
    for (final row in rows) {
      final avg = Rate.raw(row.read<int>('avg_cost_milli_paisa'));
      final qty = Qty.raw(row.read<int>('balance'));
      positions[row.read<String>('id')] = CostPosition.onShelf(
        qty: qty,
        avg: avg,
      );
    }
    return positions;
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
  Future<PostedPurchase> apply(PurchasePosting posting) async {
    // Asserted again at the boundary. The builder is one caller; this is the
    // only door.
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
      // The schema refuses a posted document with no posting instant, and it
      // is right to: a document that claims to be posted and cannot say when
      // is one no report can place in a period.
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
      'supplier_bill_no': doc.supplierBillNo,
    });

    final lineIdByNo = <int, String>{};
    for (final line in posting.lines) {
      lineIdByNo[line.lineNo] = await _tx.insert('document_lines', {
        'document_id': documentId,
        'line_no': line.lineNo,
        'item_id': line.itemId,
        'item_name_snapshot': line.itemName,
        'qty_thousandths': line.qty.inThousandths,
        'unit_id': line.unitId,
        'unit_code_snapshot': line.unitCode,
        'base_qty_thousandths': line.baseQty.inThousandths,
        'rate_milli_paisa': line.rate.inMilliPaisa,
        'line_total_paisa': line.lineTotal.inPaisa,
        'cost_paisa': line.landedCost.inPaisa,
      });
    }

    await insertStockMovements(
      _tx,
      documentId,
      lineIdByNo,
      posting.stockMovements,
    );

    // The point of the whole milestone. `items` is not append-only, so
    // `tx.update` is the legitimate path — and the value written is the one
    // the pure builder computed, so this step has no arithmetic in it and
    // therefore no room to do it differently.
    final newAverages = <String, Rate>{};
    for (final line in posting.lines) {
      await _tx.update('items', line.itemId, {
        'avg_cost_milli_paisa': line.avgAfter.inMilliPaisa,
      });
      newAverages[line.itemId] = line.avgAfter;
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
          'delivery cannot be posted against an account that does not exist.',
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

    // Arrived against a purchase order (M41): linked, so the order knows
    // what of it has come in.
    if (posting.fromOrderId case final orderId?) {
      await linkDeliveryToOrder(
        _tx,
        orderId: orderId,
        deliveryId: documentId,
        supplierId: doc.partyId,
        total: doc.total,
      );
    }

    _tx.audit(
      action: 'PURCHASE_POSTED',
      entityTable: 'documents',
      entityId: documentId,
      summary: posting.auditSummary,
      amountPaisa: doc.total.inPaisa,
    );

    return PostedPurchase(
      documentId: documentId,
      docNo: doc.docNo,
      total: doc.total,
      paid: doc.paid,
      balance: doc.balance,
      journalEntryId: journalEntryId,
      newAverages: newAverages,
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

  static String _placeholders(int count) => List.filled(count, '?').join(', ');
}
