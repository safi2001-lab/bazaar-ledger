import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';

/// What credit control, the random stock check and the cashier's queue read
/// off the books (M68).
///
/// Every read goes through the database it was handed, so one made inside
/// a write's transaction -- credit control judging a bill beneath the
/// screen -- sees the rows that transaction has already written.
final class DriftControlReads {
  const DriftControlReads(this._db);

  final AppDatabase _db;

  // ---------------------------------------------------------------------
  // Credit control
  // ---------------------------------------------------------------------

  /// [partyId]'s sale bills with something still owed, and the date of the
  /// oldest. A charge put on the khata (M7) and an opening balance are not
  /// bills: "three bills on udhaar" counts what was sold.
  Future<({int count, BusinessDate? oldest})> openBills(
    String firmId,
    String partyId,
  ) async {
    final row = await _db
        .customSelect(
          '''
          SELECT COUNT(*) AS n, MIN(doc_date_local) AS oldest
          FROM documents
          WHERE firm_id = ? AND party_id = ?
            AND doc_type = 'sale_invoice' AND status = 'posted'
            AND balance_paisa > 0 AND deleted_at_utc IS NULL
          ''',
          variables: [Variable<String>(firmId), Variable<String>(partyId)],
          readsFrom: {_db.documents},
        )
        .getSingle();
    final oldest = row.readNullable<String>('oldest');
    return (
      count: row.read<int>('n'),
      oldest: oldest == null ? null : BusinessDate.tryParse(oldest),
    );
  }

  // ---------------------------------------------------------------------
  // The random stock check
  // ---------------------------------------------------------------------

  /// Every live item that carries stock, with what it is worth on [location]'s
  /// shelf and what left that shelf as sales in the thirty days to [today],
  /// both at average cost: what the picker weighs.
  Future<List<StockCheckCandidate>> stockCheckCandidates(
    String firmId, {
    required String location,
    required BusinessDate today,
  }) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT i.id, i.name, i.avg_cost_milli_paisa AS cost,
                 COALESCE(u.code, '') AS unit,
                 COALESCE(SUM(s.qty_delta_thousandths), 0) AS on_hand,
                 -COALESCE(SUM(CASE WHEN s.txn_type = 'sale'
                                     AND s.occurred_on_local >= ?3
                                    THEN s.value_delta_paisa END), 0)
                   AS moved
          FROM items i
          LEFT JOIN units u ON u.id = i.base_unit_id
          LEFT JOIN stock_ledger s
            ON s.item_id = i.id AND s.firm_id = i.firm_id
           AND s.location_code = ?2 AND s.deleted_at_utc IS NULL
          WHERE i.firm_id = ?1 AND i.deleted_at_utc IS NULL
            AND i.is_active = 1 AND i.track_stock = 1
          GROUP BY i.id
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(location),
            Variable<String>(today.addDays(-30).value),
          ],
          readsFrom: {_db.items, _db.stockLedger},
        )
        .get();
    return [
      for (final r in rows)
        () {
          final onHand = r.read<int>('on_hand');
          final cost = Rate.raw(r.read<int>('cost'));
          final moved = r.read<int>('moved');
          return StockCheckCandidate(
            itemId: r.read<String>('id'),
            name: r.read<String>('name'),
            unitCode: r.read<String>('unit'),
            movedValue: Money.paisa(moved > 0 ? moved : 0),
            stockValue: onHand > 0
                ? cost.amountFor(Qty.raw(onHand))
                : Money.zero,
          );
        }(),
    ];
  }

  /// What the books say is on [location]'s shelf of each of [itemIds], in
  /// base units.
  Future<Map<String, Qty>> onHand(
    String firmId,
    Iterable<String> itemIds, {
    required String location,
  }) async {
    final ids = itemIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final rows = await _db
        .customSelect(
          'SELECT item_id, COALESCE(SUM(qty_delta_thousandths), 0) AS q '
          'FROM stock_ledger WHERE firm_id = ? AND location_code = ? '
          'AND deleted_at_utc IS NULL '
          'AND item_id IN (${List.filled(ids.length, '?').join(', ')}) '
          'GROUP BY item_id',
          variables: [
            Variable<String>(firmId),
            Variable<String>(location),
            for (final id in ids) Variable<String>(id),
          ],
          readsFrom: {_db.stockLedger},
        )
        .get();
    final found = {
      for (final r in rows)
        r.read<String>('item_id'): Qty.raw(r.read<int>('q')),
    };
    return {for (final id in ids) id: found[id] ?? Qty.zero};
  }

  /// Each of [itemIds]' average cost per base unit, as the books carry it.
  Future<Map<String, Rate>> averageCosts(
    String firmId,
    Iterable<String> itemIds,
  ) async {
    final ids = itemIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final rows = await _db
        .customSelect(
          'SELECT id, avg_cost_milli_paisa FROM items WHERE firm_id = ? '
          'AND id IN (${List.filled(ids.length, '?').join(', ')})',
          variables: [
            Variable<String>(firmId),
            for (final id in ids) Variable<String>(id),
          ],
          readsFrom: {_db.items},
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('id'): Rate.raw(r.read<int>('avg_cost_milli_paisa')),
    };
  }

  /// Every value kept under a settings key starting [prefix], newest
  /// written first.
  Future<List<String>> settingsUnder(String firmId, String prefix) async {
    final rows = await _db
        .customSelect(
          'SELECT setting_value FROM settings WHERE firm_id = ? '
          "AND setting_key LIKE ? ESCAPE '\\' AND deleted_at_utc IS NULL "
          'ORDER BY updated_at_utc DESC',
          variables: [
            Variable<String>(firmId),
            Variable<String>(
              '${prefix.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%',
            ),
          ],
          readsFrom: {_db.settings},
        )
        .get();
    return [for (final r in rows) r.read<String>('setting_value')];
  }

  // ---------------------------------------------------------------------
  // The cashier's queue
  // ---------------------------------------------------------------------

  static const _heldSelect = '''
    SELECT h.id, h.doc_no, h.created_by, h.salesperson_id, h.created_at_utc,
           h.total_paisa, h.bill_discount_paisa, h.party_id,
           h.party_name_snapshot, h.status,
           COALESCE(u.name, '') AS made_by_name,
           (SELECT COUNT(*) FROM document_lines dl
             WHERE dl.document_id = h.id AND dl.deleted_at_utc IS NULL
               AND dl.is_free_item = 0) AS line_count,
           (SELECT bill.doc_no FROM doc_links link
              JOIN documents bill ON bill.id = link.to_document_id
             WHERE link.from_document_id = h.id
               AND link.link_type = 'converted_from'
               AND link.deleted_at_utc IS NULL
               AND bill.status <> 'void'
             LIMIT 1) AS paid_as
    FROM documents h
    LEFT JOIN users u ON u.id = COALESCE(h.salesperson_id, h.created_by)
  ''';

  /// The bills salesmen have made for the cashier. [waitingOnly] keeps
  /// those neither paid nor set aside, oldest first, as a queue reads;
  /// otherwise every one of [day], newest first.
  Future<List<HeldBill>> heldBills(
    String firmId, {
    bool waitingOnly = true,
    BusinessDate? day,
    int limit = 200,
  }) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT * FROM (
            $_heldSelect
            WHERE h.firm_id = ?1 AND h.doc_type = '$heldBillDocType'
              AND h.deleted_at_utc IS NULL
              AND (?2 IS NULL OR h.doc_date_local = ?2)
          ) held
          WHERE ?3 = 0 OR (held.status = 'posted' AND held.paid_as IS NULL)
          ORDER BY held.created_at_utc ${waitingOnly ? 'ASC' : 'DESC'}
          LIMIT ?4
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(day?.value),
            Variable<int>(waitingOnly ? 1 : 0),
            Variable<int>(limit),
          ],
          readsFrom: {_db.documents, _db.docLinks, _db.users},
        )
        .get();
    return [for (final r in rows) _held(r)];
  }

  /// One held bill, or null when there is none of that id.
  Future<HeldBill?> heldBill(String firmId, String id) async {
    final row = await _db
        .customSelect(
          '$_heldSelect WHERE h.id = ? AND h.firm_id = ? '
          "AND h.doc_type = '$heldBillDocType' AND h.deleted_at_utc IS NULL",
          variables: [Variable<String>(id), Variable<String>(firmId)],
          readsFrom: {_db.documents, _db.docLinks, _db.users},
        )
        .getSingleOrNull();
    return row == null ? null : _held(row);
  }

  static HeldBill _held(QueryRow r) => HeldBill(
    id: r.read<String>('id'),
    docNo: r.read<String>('doc_no'),
    madeBy:
        r.readNullable<String>('salesperson_id') ??
        r.read<String>('created_by'),
    madeByName: r.read<String>('made_by_name'),
    madeAtUtcMillis: r.read<int>('created_at_utc'),
    total: Money.paisa(r.read<int>('total_paisa')),
    billDiscount: Money.paisa(r.read<int>('bill_discount_paisa')),
    lineCount: r.read<int>('line_count'),
    partyId: r.readNullable<String>('party_id'),
    partyName: r.readNullable<String>('party_name_snapshot'),
    paidAs: r.readNullable<String>('paid_as'),
    dropped: r.read<String>('status') == 'void',
  );

  /// A held bill's lines, as made, for the cashier's counter: the same shape
  /// a quotation's lines come back in (M25), so the counter takes it the way
  /// it takes a quotation. A scheme's free line is worked out again there.
  Future<List<QuotedLine>> heldLines(String firmId, String heldId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT dl.item_id, dl.qty_thousandths, dl.unit_id,
                 dl.unit_code_snapshot, dl.rate_milli_paisa, dl.discount_bp,
                 dl.discount_paisa
          FROM document_lines dl
          JOIN documents d ON d.id = dl.document_id
          WHERE d.id = ? AND d.firm_id = ? AND d.doc_type = '$heldBillDocType'
            AND dl.item_id IS NOT NULL AND dl.deleted_at_utc IS NULL
            AND dl.is_free_item = 0
          ORDER BY dl.line_no
          ''',
          variables: [Variable<String>(heldId), Variable<String>(firmId)],
          readsFrom: {_db.documentLines, _db.documents},
        )
        .get();
    return [
      for (final r in rows)
        () {
          final bp = r.read<int>('discount_bp');
          final discount = r.read<int>('discount_paisa');
          return QuotedLine(
            itemId: r.read<String>('item_id'),
            qty: Qty.raw(r.read<int>('qty_thousandths')),
            unitId: r.readNullable<String>('unit_id'),
            unitCode: r.read<String>('unit_code_snapshot'),
            rate: Rate.raw(r.read<int>('rate_milli_paisa')),
            discountBp: bp,
            explicitDiscount: bp == 0 && discount > 0
                ? Money.paisa(discount)
                : null,
          );
        }(),
    ];
  }
}
