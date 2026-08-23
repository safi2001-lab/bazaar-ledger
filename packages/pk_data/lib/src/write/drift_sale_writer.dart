import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';
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
  ) =>
      runner.run(actor, (tx) => body(_DriftSaleWriteContext(tx, sequences)));
}

final class _DriftSaleWriteContext implements SaleWriteContext {
  _DriftSaleWriteContext(this._tx, this._sequences);

  final Tx _tx;
  final SequenceAllocator _sequences;

  @override
  ActorContext get actor => _tx.actor;

  @override
  Future<TaxContext> taxContextFor(String? partyId) async {
    final firm = await _tx.selectOne(
      'SELECT is_sales_tax_registered, province, prices_include_tax '
      'FROM firms WHERE id = ?',
      [actor.firmId],
    );
    if (firm == null) {
      throw StateError('Firm ${actor.firmId} does not exist.');
    }

    var buyerRegistered = false;
    bool? buyerOnAtl;
    if (partyId != null) {
      final party = await _tx.selectOne(
        'SELECT buyer_registration_type, is_on_atl FROM parties '
        'WHERE id = ? AND firm_id = ?',
        [partyId, actor.firmId],
      );
      if (party != null) {
        buyerRegistered =
            party.read<String>('buyer_registration_type') == 'registered';
        final atl = party.readNullable<int>('is_on_atl');
        buyerOnAtl = atl == null ? null : atl == 1;
      }
    }

    return TaxContext(
      isSellerRegistered: firm.read<int>('is_sales_tax_registered') == 1,
      buyerIsRegistered: buyerRegistered,
      buyerIsOnAtl: buyerOnAtl,
      province: firm.read<String>('province'),
      pricesIncludeTax: firm.read<int>('prices_include_tax') == 1,
      ruleVersion: 'untaxed-v1',
    );
  }

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
      'WHERE pa.firm_id = ? AND pa.deleted_at_utc IS NULL '
      'AND a.deleted_at_utc IS NULL '
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
  Future<PostedSale> apply(SalePosting posting) async {
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
      'party_name_snapshot': doc.partyNameSnapshot,
      'party_ntn_snapshot': doc.partyNtnSnapshot,
      'party_strn_snapshot': doc.partyStrnSnapshot,
      'party_address_snapshot': doc.partyAddressSnapshot,
      'status': 'posted',
      'revision': 1,
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
      'cash_threshold_breached': doc.cashThresholdBreached ? 1 : 0,
      'salesperson_id': doc.salespersonId,
      'notes': doc.notes,
      'posted_at_utc': doc.docDateUtcMillis,
    });

    // --- Lines and their taxes -------------------------------------------
    final lineIdByNo = <int, String>{};
    for (final line in posting.lines) {
      final lineId = await _tx.insert('document_lines', {
        'document_id': documentId,
        'line_no': line.lineNo,
        'item_id': line.itemId,
        'item_name_snapshot': line.itemNameSnapshot,
        'item_code_snapshot': line.itemCodeSnapshot,
        'hs_code_snapshot': line.hsCodeSnapshot,
        'description': line.description,
        'qty_thousandths': line.qty.inThousandths,
        'unit_id': line.unitId,
        'unit_code_snapshot': line.unitCodeSnapshot,
        'base_qty_thousandths': line.baseQty.inThousandths,
        'rate_milli_paisa': line.rate.inMilliPaisa,
        'mrp_paisa': line.mrp?.inPaisa,
        'lot_id': line.lotId,
        'gross_paisa': line.gross.inPaisa,
        'discount_bp': line.discountBp,
        'discount_paisa': line.discount.inPaisa,
        'taxable_paisa': line.taxable.inPaisa,
        'tax_paisa': line.tax.inPaisa,
        'line_total_paisa': line.lineTotal.inPaisa,
        'cost_paisa': line.cost.inPaisa,
        'is_free_item': line.isFreeItem ? 1 : 0,
      });
      lineIdByNo[line.lineNo] = lineId;

      for (final tax in line.taxes) {
        await _tx.insert('document_line_taxes', {
          'document_line_id': lineId,
          'document_id': documentId,
          'tax_rule_id': tax.ruleId,
          'tax_kind': tax.kind.code,
          'tax_code': tax.code,
          'rate_bp': tax.rateBp,
          'base_paisa': tax.base.inPaisa,
          'amount_paisa': tax.amount.inPaisa,
          'is_inclusive': tax.isInclusive ? 1 : 0,
          'sro_schedule_no': tax.sroScheduleNo,
          'sro_item_no': tax.sroItemNo,
        });
      }
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
    for (final movement in posting.stockMovements) {
      final running = await _tx.selectOne(
        'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS balance '
        'FROM stock_ledger '
        'WHERE firm_id = ? AND item_id = ? AND location_code = ? '
        '  AND deleted_at_utc IS NULL',
        [actor.firmId, movement.itemId, movement.locationCode],
      );
      final balanceAfter = (running?.read<int>('balance') ?? 0) +
          movement.qtyDelta.inThousandths;

      await _tx.insert('stock_ledger', {
        'item_id': movement.itemId,
        'location_code': movement.locationCode,
        'lot_id': movement.lotId,
        'document_id': documentId,
        'document_line_id': lineIdByNo[movement.lineNo],
        'txn_type': movement.txnType,
        'qty_delta_thousandths': movement.qtyDelta.inThousandths,
        'rate_milli_paisa': movement.rate.inMilliPaisa,
        'value_delta_paisa': movement.valueDelta.inPaisa,
        'balance_after_thousandths': balanceAfter,
        'occurred_at_utc': movement.occurredAtUtcMillis,
        'occurred_on_local': movement.occurredOnLocal,
      });
    }

    // --- Double entry ------------------------------------------------------
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
          '${actor.firmId}. The chart of accounts is incomplete, and a sale '
          'cannot be posted against an account that does not exist.',
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

  static String _placeholders(int count) =>
      List.filled(count, '?').join(', ');
}

/// Wires a [SaleWriter] onto an open database.
DriftSaleWriter saleWriterFor(
  AppDatabase database, {
  required IdGenerator ids,
  required HlcClock hlc,
}) =>
    DriftSaleWriter(
      runner: TxRunner(database: database, ids: ids, hlc: hlc),
    );
