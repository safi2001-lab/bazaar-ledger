import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_reports/pk_reports.dart';

import '../db/app_database.dart';
import '../write/drift_order_writer.dart' show shortageKeyPrefix;
import 'drift_report_source.dart';

/// Reading orders, the shortage list and what to order (M41).
///
/// What has come in against a purchase order, or gone out against a sale
/// order, is read off the documents linked to it `converted_from` — a
/// delivery for a purchase order; a bill or a challan for a sale order —
/// and never stored on the order. A delivery cancelled, or a bill voided,
/// stops counting the moment it is, because it is the linked document's
/// own status that is read.
final class DriftOrderReads {
  const DriftOrderReads(this._db);

  final AppDatabase _db;

  /// Ids bound in one statement, well inside SQLite's limit.
  static const _chunk = 400;

  // -------------------------------------------------------------------------
  // Orders
  // -------------------------------------------------------------------------

  /// [kind]'s orders, newest first, cancelled ones included and marked.
  Future<List<OrderRow>> orders(
    String firmId,
    OrderKind kind, {
    bool standingOnly = false,
    String? partyId,
    int limit = 200,
  }) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_no, d.doc_date_local, d.party_id,
                 COALESCE(d.party_name_snapshot, p.name, '') AS party,
                 d.total_paisa, d.terms, d.status, d.notes
          FROM documents d
          LEFT JOIN parties p ON p.id = d.party_id
          WHERE d.firm_id = ?1 AND d.doc_type = ?2
            AND d.status IN (${standingOnly ? "'posted'" : "'posted', 'void'"})
            AND d.deleted_at_utc IS NULL
            ${partyId == null ? '' : 'AND d.party_id = ?4'}
          ORDER BY d.doc_date_local DESC, d.doc_seq DESC, d.id DESC
          LIMIT ?3
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(kind.docType),
            Variable<int>(limit),
            if (partyId != null) Variable<String>(partyId),
          ],
          readsFrom: {_db.documents, _db.parties},
        )
        .get();
    final views = await _views(firmId, kind, rows);
    return [
      for (final v in views)
        if (!standingOnly || v.row.status.isStanding) v.row,
    ];
  }

  /// One order, opened, or null when it is not one of this shop's.
  Future<OrderView?> order(String firmId, String orderId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_type, d.doc_no, d.doc_date_local, d.party_id,
                 COALESCE(d.party_name_snapshot, p.name, '') AS party,
                 d.total_paisa, d.terms, d.status, d.notes
          FROM documents d
          LEFT JOIN parties p ON p.id = d.party_id
          WHERE d.id = ?1 AND d.firm_id = ?2
            AND d.doc_type IN ('purchase_order', 'sale_order')
            AND d.status IN ('posted', 'void') AND d.deleted_at_utc IS NULL
          ''',
          variables: [Variable<String>(orderId), Variable<String>(firmId)],
          readsFrom: {_db.documents, _db.parties},
        )
        .get();
    if (rows.isEmpty) return null;
    final kind = OrderKind.ofDocType(rows.single.read<String>('doc_type'))!;
    final views = await _views(firmId, kind, rows, withFollowUps: true);
    return views.single;
  }

  /// Every standing purchase order's lines with what is still to come:
  /// what is already on its way, item by item, in each item's own unit.
  Future<Map<String, Qty>> onOrder(String firmId) async {
    final standing = await _standingViews(firmId, OrderKind.purchase);
    final out = <String, Qty>{};
    for (final v in standing) {
      for (final l in v.lines) {
        out[l.itemId] = (out[l.itemId] ?? Qty.zero) + l.pendingBase;
      }
    }
    return out;
  }

  /// Every standing order of [kind], opened, oldest first: what the order
  /// reports read (M41).
  Future<List<OrderView>> standing(String firmId, OrderKind kind) async =>
      (await _standingViews(firmId, kind)).reversed.toList();

  Future<List<OrderView>> _standingViews(String firmId, OrderKind kind) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_no, d.doc_date_local, d.party_id,
                 COALESCE(d.party_name_snapshot, p.name, '') AS party,
                 d.total_paisa, d.terms, d.status, d.notes
          FROM documents d
          LEFT JOIN parties p ON p.id = d.party_id
          WHERE d.firm_id = ?1 AND d.doc_type = ?2 AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
          ORDER BY d.doc_date_local DESC, d.doc_seq DESC, d.id DESC
          ''',
          variables: [Variable<String>(firmId), Variable<String>(kind.docType)],
          readsFrom: {_db.documents, _db.parties},
        )
        .get();
    final views = await _views(firmId, kind, rows, withFollowUps: false);
    return [
      for (final v in views)
        if (v.row.status.isStanding) v,
    ];
  }

  Future<List<OrderView>> _views(
    String firmId,
    OrderKind kind,
    List<QueryRow> docs, {
    bool withFollowUps = false,
  }) async {
    if (docs.isEmpty) return const [];
    final ids = [for (final d in docs) d.read<String>('id')];
    final lines = <String, List<OrderLineProgress>>{};
    final done = <String, Map<String, Qty>>{};
    final follow = <String, List<OrderFollowUp>>{};
    for (var at = 0; at < ids.length; at += _chunk) {
      final chunk = ids.skip(at).take(_chunk).toList();
      final marks = List.filled(chunk.length, '?').join(', ');
      final vars = [for (final id in chunk) Variable<String>(id)];
      for (final r
          in await _db
              .customSelect(
                '''
            SELECT dl.document_id, dl.line_no, dl.item_id,
                   dl.item_name_snapshot, dl.qty_thousandths,
                   dl.base_qty_thousandths, dl.unit_id,
                   dl.unit_code_snapshot, dl.rate_milli_paisa,
                   COALESCE(u.code, dl.unit_code_snapshot) AS base_unit,
                   i.base_unit_id
            FROM document_lines dl
            LEFT JOIN items i ON i.id = dl.item_id
            LEFT JOIN units u ON u.id = i.base_unit_id
            WHERE dl.document_id IN ($marks)
              AND dl.item_id IS NOT NULL AND dl.deleted_at_utc IS NULL
            ORDER BY dl.document_id, dl.line_no
            ''',
                variables: vars,
                readsFrom: {_db.documentLines, _db.items, _db.units},
              )
              .get()) {
        lines
            .putIfAbsent(r.read<String>('document_id'), () => [])
            .add(
              OrderLineProgress(
                lineNo: r.read<int>('line_no'),
                itemId: r.read<String>('item_id'),
                itemName: r.read<String>('item_name_snapshot'),
                qty: Qty.raw(r.read<int>('qty_thousandths')),
                baseQty: Qty.raw(r.read<int>('base_qty_thousandths')),
                unitId: r.readNullable<String>('unit_id') ?? '',
                unitCode: r.read<String>('unit_code_snapshot'),
                baseUnitId: r.readNullable<String>('base_unit_id') ?? '',
                baseUnitCode: r.read<String>('base_unit'),
                rate: Rate.raw(r.read<int>('rate_milli_paisa')),
                done: Qty.zero,
              ),
            );
      }
      // What came of each: a delivery for a purchase order; a bill or a
      // challan for a sale order. Only what still stands.
      for (final r
          in await _db
              .customSelect(
                '''
            SELECT link.from_document_id AS order_id, dl.item_id,
                   SUM(dl.base_qty_thousandths) AS qty
            FROM doc_links link
            JOIN documents d ON d.id = link.to_document_id
            JOIN document_lines dl
              ON dl.document_id = d.id AND dl.deleted_at_utc IS NULL
            WHERE link.from_document_id IN ($marks)
              AND link.link_type = 'converted_from'
              AND link.deleted_at_utc IS NULL
              AND d.status = 'posted' AND d.deleted_at_utc IS NULL
              AND d.doc_type IN ('purchase_bill', 'sale_invoice',
                                 'delivery_challan')
              AND dl.item_id IS NOT NULL
              -- M43: a bonus that came with the goods is not goods ordered.
              AND dl.is_free_item = 0
            GROUP BY link.from_document_id, dl.item_id
            ''',
                variables: vars,
                readsFrom: {_db.docLinks, _db.documents, _db.documentLines},
              )
              .get()) {
        done.putIfAbsent(r.read<String>('order_id'), () => {})[r.read<String>(
          'item_id',
        )] = Qty.raw(
          r.read<int>('qty'),
        );
      }
      if (withFollowUps) {
        for (final r
            in await _db
                .customSelect(
                  '''
              SELECT link.from_document_id AS order_id, d.id, d.doc_type,
                     d.doc_no, d.doc_date_local, d.total_paisa
              FROM doc_links link
              JOIN documents d ON d.id = link.to_document_id
              WHERE link.from_document_id IN ($marks)
                AND link.link_type = 'converted_from'
                AND link.deleted_at_utc IS NULL
                AND d.status = 'posted' AND d.deleted_at_utc IS NULL
              ORDER BY d.doc_date_local, d.created_at_utc, d.id
              ''',
                  variables: vars,
                  readsFrom: {_db.docLinks, _db.documents},
                )
                .get()) {
          follow
              .putIfAbsent(r.read<String>('order_id'), () => [])
              .add(
                OrderFollowUp(
                  documentId: r.read<String>('id'),
                  docType: r.read<String>('doc_type'),
                  docNo: r.read<String>('doc_no'),
                  date: BusinessDate(r.read<String>('doc_date_local')),
                  total: Money.paisa(r.read<int>('total_paisa')),
                ),
              );
        }
      }
    }
    final advances = kind == OrderKind.sale
        ? await _advances(firmId, docs)
        : const <String, Money>{};
    return [
      for (final d in docs)
        () {
          final id = d.read<String>('id');
          final progress = spreadDone(lines[id] ?? const [], done[id] ?? {});
          return OrderView(
            row: OrderRow(
              id: id,
              kind: kind,
              docNo: d.read<String>('doc_no'),
              date: BusinessDate(d.read<String>('doc_date_local')),
              partyId: d.readNullable<String>('party_id') ?? '',
              partyName: d.read<String>('party'),
              total: Money.paisa(d.read<int>('total_paisa')),
              status: orderStatusOf(
                isVoid: d.read<String>('status') == 'void',
                lines: progress,
              ),
              lineCount: progress.length,
              dueDate: orderDueDate(d.readNullable<String>('terms')),
              advance: advances[id] ?? Money.zero,
            ),
            lines: progress,
            followUps: follow[id] ?? const [],
            notes: d.readNullable<String>('notes'),
          );
        }(),
    ];
  }

  /// The advance taken against each sale order in [docs]: the standing
  /// receipts that name it, by its number, from its customer.
  Future<Map<String, Money>> _advances(
    String firmId,
    List<QueryRow> docs,
  ) async {
    final out = <String, Money>{};
    final byNo = {
      for (final d in docs)
        d.read<String>('doc_no'): (
          id: d.read<String>('id'),
          party: d.readNullable<String>('party_id'),
        ),
    };
    final numbers = byNo.keys.toList();
    for (var at = 0; at < numbers.length; at += _chunk) {
      final chunk = numbers.skip(at).take(_chunk).toList();
      final marks = List.filled(chunk.length, '?').join(', ');
      for (final r
          in await _db
              .customSelect(
                '''
            SELECT p.reference, p.party_id, SUM(p.amount_paisa) AS paid
            FROM payments p
            WHERE p.firm_id = ? AND p.direction = 'in'
              AND p.status IN ('cleared', 'pending')
              AND p.deleted_at_utc IS NULL
              AND p.reference IN ($marks)
            GROUP BY p.reference, p.party_id
            ''',
                variables: [
                  Variable<String>(firmId),
                  for (final n in chunk) Variable<String>(n),
                ],
                readsFrom: {_db.payments},
              )
              .get()) {
        final order = byNo[r.read<String>('reference')];
        if (order == null ||
            order.party != r.readNullable<String>('party_id')) {
          continue;
        }
        out[order.id] =
            (out[order.id] ?? Money.zero) + Money.paisa(r.read<int>('paid'));
      }
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // The shortage list
  // -------------------------------------------------------------------------

  /// What customers asked for that is still to get, oldest first.
  ///
  /// A line naming an item leaves the list by itself once a delivery of
  /// that item is entered after it was written: it has arrived. A line in
  /// the customer's own words stays until somebody ticks it off.
  Future<List<ShortageEntry>> shortage(String firmId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT s.id, s.setting_value, s.created_at_utc, u.name AS who
          FROM settings s
          LEFT JOIN users u ON u.id = s.created_by
          WHERE s.firm_id = ? AND s.setting_key LIKE ?
            AND s.deleted_at_utc IS NULL
          ORDER BY s.created_at_utc, s.id
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>('$shortageKeyPrefix%'),
          ],
          readsFrom: {_db.settings, _db.users},
        )
        .get();
    final entries = <(ShortageEntry, int)>[];
    for (final r in rows) {
      final json = jsonDecode(r.read<String>('setting_value'));
      if (json is! Map<String, Object?>) continue;
      final qty = json['qty'];
      entries.add((
        ShortageEntry(
          id: r.read<String>('id'),
          name: json['name'] as String? ?? '',
          itemId: json['item_id'] as String?,
          qty: qty is int ? Qty.raw(qty) : null,
          unitCode: json['unit'] as String?,
          note: json['note'] as String?,
          addedOn:
              BusinessDate.tryParse(json['on'] as String? ?? '') ??
              BusinessDate.fromUtc(
                DateTime.fromMillisecondsSinceEpoch(
                  r.read<int>('created_at_utc'),
                  isUtc: true,
                ),
              ),
          addedBy: r.readNullable<String>('who'),
        ),
        r.read<int>('created_at_utc'),
      ));
    }
    final arrived = await _lastDelivered(firmId, {
      for (final (e, _) in entries) ?e.itemId,
    });
    return [
      for (final (e, at) in entries)
        // Strictly after: a delivery entered in the same instant the line
        // was written is the one the customer was told was not here yet.
        if (e.itemId == null || (arrived[e.itemId] ?? -1) <= at) e,
    ];
  }

  /// When each of [itemIds] last arrived on a delivery, as the instant the
  /// delivery was entered.
  Future<Map<String, int>> _lastDelivered(
    String firmId,
    Set<String> itemIds,
  ) async {
    final ids = itemIds.toList();
    final out = <String, int>{};
    for (var at = 0; at < ids.length; at += _chunk) {
      final chunk = ids.skip(at).take(_chunk).toList();
      final marks = List.filled(chunk.length, '?').join(', ');
      for (final r
          in await _db
              .customSelect(
                '''
            SELECT dl.item_id, MAX(d.created_at_utc) AS last
            FROM document_lines dl
            JOIN documents d ON d.id = dl.document_id
            WHERE d.firm_id = ? AND d.doc_type = 'purchase_bill'
              AND d.status = 'posted' AND d.deleted_at_utc IS NULL
              AND dl.deleted_at_utc IS NULL AND dl.item_id IN ($marks)
            GROUP BY dl.item_id
            ''',
                variables: [
                  Variable<String>(firmId),
                  for (final id in chunk) Variable<String>(id),
                ],
                readsFrom: {_db.documentLines, _db.documents},
              )
              .get()) {
        out[r.read<String>('item_id')] = r.read<int>('last');
      }
    }
    return out;
  }

  // -------------------------------------------------------------------------
  // What to order
  // -------------------------------------------------------------------------

  /// What to order now, item by item, each with the supplier it last came
  /// from and what it cost a unit then.
  ///
  /// The shelf's side is M34's Low Stock read and its reorder quantity —
  /// the same query and the same function the report prints, called rather
  /// than copied, so the screen and the report cannot disagree about how
  /// much to order. Less what is on its way on a standing purchase order;
  /// and at least what a customer asked for at the counter that is not.
  Future<List<ReorderLine>> reorder(
    String firmId,
    BusinessDate asOf, {
    int salesDays = StockDefaults.lowStockDays,
    int coverDays = StockDefaults.coverDays,
  }) async {
    final low = await DriftReportSource(
      _db,
    ).lowStock(firmId, asOf, salesDays: salesDays);
    final onOrder = await this.onOrder(firmId);
    final asked = <String, Qty>{};
    final askedAny = <String>{};
    for (final e in await shortage(firmId)) {
      final id = e.itemId;
      if (id == null) continue;
      askedAny.add(id);
      // A line with no number is one of it; the shelf's figure, if bigger,
      // wins below.
      asked[id] = (asked[id] ?? Qty.zero) + (e.qty ?? Qty.one);
    }
    final lowIds = {for (final l in low) l.itemId};
    final items = await _items(firmId, {...lowIds, ...askedAny});
    final suppliers = await _lastSuppliers(firmId, items.keys.toSet());

    ReorderLine line(
      String itemId, {
      required Qty needed,
      Qty stock = Qty.zero,
      Qty minStock = Qty.zero,
      Qty sold = Qty.zero,
    }) {
      final item = items[itemId]!;
      final from = suppliers[itemId];
      return ReorderLine(
        itemId: itemId,
        itemName: item.name,
        unitId: item.unitId,
        unitCode: item.unitCode,
        qty: orderToPlace(
          needed: needed,
          onOrder: onOrder[itemId] ?? Qty.zero,
          asked: asked[itemId] ?? Qty.zero,
        ),
        stock: stock,
        minStock: minStock,
        sold: sold,
        onOrder: onOrder[itemId] ?? Qty.zero,
        asked: asked[itemId] ?? Qty.zero,
        wasAsked: askedAny.contains(itemId),
        supplierId: from?.id,
        supplierName: from?.name,
        rate: from?.rate ?? item.rate,
      );
    }

    return [
      for (final l in low)
        if (items.containsKey(l.itemId))
          line(
            l.itemId,
            needed: reorderQty(l, salesDays: salesDays, coverDays: coverDays),
            stock: l.stock,
            minStock: l.minStock,
            sold: l.sold,
          ),
      for (final id in askedAny)
        if (!lowIds.contains(id) && items.containsKey(id))
          line(id, needed: Qty.zero, stock: items[id]!.stock),
    ].where((l) => l.qty.isPositive).toList();
  }

  Future<
    Map<
      String,
      ({String name, String unitId, String unitCode, Rate? rate, Qty stock})
    >
  >
  _items(String firmId, Set<String> itemIds) async {
    final ids = itemIds.toList();
    final out =
        <
          String,
          ({String name, String unitId, String unitCode, Rate? rate, Qty stock})
        >{};
    for (var at = 0; at < ids.length; at += _chunk) {
      final chunk = ids.skip(at).take(_chunk).toList();
      final marks = List.filled(chunk.length, '?').join(', ');
      for (final r
          in await _db
              .customSelect(
                '''
            SELECT i.id, i.name, i.base_unit_id, u.code AS unit_code,
                   i.purchase_rate_milli_paisa,
                   COALESCE((
                     SELECT SUM(s.qty_delta_thousandths) FROM stock_ledger s
                     WHERE s.item_id = i.id AND s.firm_id = i.firm_id
                       AND s.deleted_at_utc IS NULL
                   ), 0) AS stock
            FROM items i
            JOIN units u ON u.id = i.base_unit_id
            WHERE i.firm_id = ? AND i.deleted_at_utc IS NULL
              AND i.id IN ($marks)
            ''',
                variables: [
                  Variable<String>(firmId),
                  for (final id in chunk) Variable<String>(id),
                ],
                readsFrom: {_db.items, _db.units, _db.stockLedger},
              )
              .get()) {
        final rate = r.readNullable<int>('purchase_rate_milli_paisa');
        out[r.read<String>('id')] = (
          name: r.read<String>('name'),
          unitId: r.read<String>('base_unit_id'),
          unitCode: r.read<String>('unit_code'),
          rate: rate == null || rate == 0 ? null : Rate.raw(rate),
          stock: Qty.raw(r.read<int>('stock')),
        );
      }
    }
    return out;
  }

  /// Who each of [itemIds] last came from, and what a unit of it cost on
  /// that delivery, before freight: the rate the supplier will be held to.
  Future<Map<String, ({String id, String name, Rate rate})>> _lastSuppliers(
    String firmId,
    Set<String> itemIds,
  ) async {
    final ids = itemIds.toList();
    final out = <String, ({String id, String name, Rate rate})>{};
    for (var at = 0; at < ids.length; at += _chunk) {
      final chunk = ids.skip(at).take(_chunk).toList();
      final marks = List.filled(chunk.length, '?').join(', ');
      for (final r
          in await _db
              .customSelect(
                '''
            SELECT i.id AS item_id, d.party_id,
                   COALESCE(p.name, d.party_name_snapshot, '') AS name,
                   dl.line_total_paisa, dl.base_qty_thousandths
            FROM items i
            JOIN document_lines dl ON dl.id = (
              SELECT dl2.id FROM document_lines dl2
              JOIN documents d2 ON d2.id = dl2.document_id
              WHERE dl2.item_id = i.id AND d2.firm_id = i.firm_id
                AND d2.doc_type = 'purchase_bill' AND d2.status = 'posted'
                AND d2.deleted_at_utc IS NULL AND dl2.deleted_at_utc IS NULL
                AND d2.party_id IS NOT NULL
                -- M43: the supplier's bonus row has no rate to order at.
                AND dl2.is_free_item = 0
              ORDER BY d2.doc_date_local DESC, d2.created_at_utc DESC,
                       dl2.line_no DESC
              LIMIT 1)
            JOIN documents d ON d.id = dl.document_id
            LEFT JOIN parties p ON p.id = d.party_id
            WHERE i.firm_id = ? AND i.id IN ($marks)
            ''',
                variables: [
                  Variable<String>(firmId),
                  for (final id in chunk) Variable<String>(id),
                ],
                readsFrom: {_db.items, _db.documentLines, _db.documents},
              )
              .get()) {
        final base = r.read<int>('base_qty_thousandths');
        out[r.read<String>('item_id')] = (
          id: r.read<String>('party_id'),
          name: r.read<String>('name'),
          // Per the item's own unit, to the milli-paisa: a delivery of two
          // cartons at Rs 1,200 is Rs 100 a piece.
          rate: base <= 0
              ? Rate.zero
              : Rate.raw(
                  divideRounded(
                    r.read<int>('line_total_paisa') * 1000 * 1000,
                    base,
                    RoundingMode.halfUp,
                  ),
                ),
        );
      }
    }
    return out;
  }
}
