part of '../drift_report_source.dart';

/// The reads behind the order reports (M35): the quotations and challans
/// nobody has billed yet.
///
/// Open is what the counter already means by it (M25): a document that
/// stands and has no `converted_from` link to anything that still stands. A
/// bill voided after it was made from a challan leaves the challan open
/// again, as the challan list shows it.
mixin _OrderQueries implements OrderReportSource {
  AppDatabase get _db;

  /// The `AND` clause that keeps document `q` only while it is open.
  static const _open = '''
    AND NOT EXISTS (
      SELECT 1 FROM doc_links link
      JOIN documents made ON made.id = link.to_document_id
      WHERE link.from_document_id = q.id
        AND link.link_type = 'converted_from'
        AND link.deleted_at_utc IS NULL
        AND made.status <> 'void'
    )
  ''';

  @override
  Future<List<OpenOrder>> openOrders(
    String firmId, {
    required Set<String> docTypes,
    ReportFilters filters = ReportFilters.none,
  }) async {
    if (docTypes.isEmpty) return const [];
    final q = _Params(firmId);
    final types = [for (final t in docTypes) q.text(t)].join(', ');
    final where = _documentWhere(filters, q, doc: 'q');
    final rows = await _db
        .customSelect(
          '''
          SELECT q.id, q.doc_type, q.doc_no, q.doc_date_local, q.party_id,
                 COALESCE(q.party_name_snapshot, p.name, '') AS party,
                 q.total_paisa, q.terms,
                 (SELECT COUNT(*) FROM document_lines l
                   WHERE l.document_id = q.id
                     AND l.deleted_at_utc IS NULL) AS lines
          FROM documents q
          LEFT JOIN parties p ON p.id = q.party_id
          WHERE q.firm_id = ?1
            AND q.doc_type IN ($types)
            AND q.status = 'posted'
            AND q.deleted_at_utc IS NULL
            $_open
            $where
          ORDER BY q.doc_date_local, q.doc_seq, q.id
          ''',
          variables: q.variables,
          readsFrom: {
            _db.documents,
            _db.parties,
            _db.documentLines,
            _db.docLinks,
            _db.paymentAllocations,
            _db.payments,
            _db.items,
          },
        )
        .get();
    return [
      for (final r in rows)
        OpenOrder(
          documentId: r.read<String>('id'),
          docType: r.read<String>('doc_type'),
          docNo: r.read<String>('doc_no'),
          date: BusinessDate(r.read<String>('doc_date_local')),
          partyId: r.readNullable<String>('party_id'),
          party: r.read<String>('party'),
          total: Money.paisa(r.read<int>('total_paisa')),
          lines: r.read<int>('lines'),
          validUntil: r.read<String>('doc_type') == TransactionType.quotation
              ? _goodUntil(r.readNullable<String>('terms'))
              : null,
        ),
    ];
  }

  @override
  Future<List<OpenOrderItem>> openOrderItems(
    String firmId, {
    required Set<String> docTypes,
    ReportFilters filters = ReportFilters.none,
  }) async {
    if (docTypes.isEmpty) return const [];
    final q = _Params(firmId);
    final types = [for (final t in docTypes) q.text(t)].join(', ');
    final where = _documentWhere(filters, q, doc: 'q');
    final rows = await _db
        .customSelect(
          '''
          SELECT COALESCE(i.name, dl.item_name_snapshot) AS name,
                 COALESCE(u.code, dl.unit_code_snapshot) AS unit_code,
                 q.doc_type,
                 SUM(dl.base_qty_thousandths) AS qty,
                 SUM(dl.taxable_paisa) AS value,
                 COUNT(DISTINCT q.id) AS documents
          FROM document_lines dl
          JOIN documents q ON q.id = dl.document_id
          LEFT JOIN items i ON i.id = dl.item_id
          LEFT JOIN units u ON u.id = i.base_unit_id
          LEFT JOIN parties p ON p.id = q.party_id
          WHERE q.firm_id = ?1
            AND q.doc_type IN ($types)
            AND q.status = 'posted'
            AND q.deleted_at_utc IS NULL
            AND dl.deleted_at_utc IS NULL
            $_open
            $where
          GROUP BY COALESCE(dl.item_id, dl.item_name_snapshot), q.doc_type
          ''',
          variables: q.variables,
          readsFrom: {
            _db.documentLines,
            _db.documents,
            _db.items,
            _db.units,
            _db.parties,
            _db.docLinks,
            _db.paymentAllocations,
            _db.payments,
          },
        )
        .get();
    return [
      for (final r in rows)
        OpenOrderItem(
          itemName: r.read<String>('name'),
          unitCode: r.read<String>('unit_code'),
          docType: r.read<String>('doc_type'),
          qty: Qty.raw(r.read<int>('qty')),
          value: Money.paisa(r.read<int>('value')),
          documents: r.read<int>('documents'),
        ),
    ];
  }

  /// The date the quotation builder writes into a quotation's terms, as
  /// the quotation list reads it.
  static BusinessDate? _goodUntil(String? terms) {
    final match = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(terms ?? '');
    return match == null ? null : BusinessDate(match.group(1)!);
  }
}
