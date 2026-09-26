import 'package:pk_domain/pk_domain.dart';

import 'tx_runner.dart';

/// The tax context a document for [partyId] is priced under: the firm's
/// registration and province, and the buyer's. One reading, shared by the
/// bill and the quotation, so a quotation cannot be priced under different
/// rules from the bill made from it.
Future<TaxContext> taxContextOf(Tx tx, String? partyId) async {
  final firm = await tx.selectOne(
    'SELECT is_sales_tax_registered, province, prices_include_tax '
    'FROM firms WHERE id = ?',
    [tx.actor.firmId],
  );
  if (firm == null) {
    throw StateError('Firm ${tx.actor.firmId} does not exist.');
  }

  var buyerRegistered = false;
  bool? buyerOnAtl;
  if (partyId != null) {
    final party = await tx.selectOne(
      'SELECT buyer_registration_type, is_on_atl FROM parties '
      'WHERE id = ? AND firm_id = ?',
      [partyId, tx.actor.firmId],
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

/// Writes a document and its lines with their taxes, as [status]. Returns the
/// document id and each line's id by line number.
///
/// Every document the sale calculator prices is stored through this, so a
/// line reads back the same whichever kind of document holds it.
Future<(String, Map<int, String>)> insertDocumentRows(
  Tx tx,
  DocumentPosting doc,
  List<DocumentLinePosting> lines, {
  String status = 'posted',
}) async {
  final documentId = await tx.insert('documents', {
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
    'status': status,
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
    'terms': doc.terms,
    'posted_at_utc': doc.docDateUtcMillis,
  });

  // --- Lines and their taxes -------------------------------------------
  final lineIdByNo = <int, String>{};
  for (final line in lines) {
    final lineId = await tx.insert('document_lines', {
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
      await tx.insert('document_line_taxes', {
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

  return (documentId, lineIdByNo);
}
