part of '../drift_report_source.dart';

/// The reads behind the item and stock reports (M34).
///
/// Stock comes off `stock_ledger` and nowhere else: a quantity is a sum of
/// its rows and a value at cost is a sum of their `value_delta_paisa`, the
/// figure each movement put through Inventory when it was written. A
/// report that sums the same rows therefore lands on the Inventory account
/// to the paisa, on any day, without guessing what an item cost then.
///
/// Every read is one statement (two where a list's pieces hang off it)
/// grouped in SQLite. The business date is `occurred_on_local`, the day the
/// shopkeeper meant; a period's rows ride `idx_stock_daybook` and one
/// item's ride `idx_stock_position`.
mixin _ItemStockQueries implements ItemStockReportSource {
  AppDatabase get _db;

  /// What moved a stock row, as the stock reports column it: its own type,
  /// except that opening stock entered in the period and both halves of a
  /// cancelled bill (the goods going out and coming back) are adjustments.
  /// Reads `s` as the stock row and `d` as its document.
  static const _kind = '''
    CASE WHEN d.status = 'void' OR s.txn_type = 'opening' THEN 'adjustment'
         ELSE s.txn_type END
  ''';

  /// The [StockMoves] of the rows in `m` that meet [when], one column each.
  static String _moves(String when) =>
      '''
      SUM(CASE WHEN $when AND m.k = 'purchase' THEN m.q ELSE 0 END)
        AS purchased,
      SUM(CASE WHEN $when AND m.k = 'sale_return' THEN m.q ELSE 0 END)
        AS returns_in,
      SUM(CASE WHEN $when AND m.k = 'transfer_in' THEN m.q ELSE 0 END)
        AS transfers_in,
      SUM(CASE WHEN $when AND m.k = 'assembly_in' THEN m.q ELSE 0 END)
        AS produced,
      -SUM(CASE WHEN $when AND m.k = 'sale' THEN m.q ELSE 0 END) AS sold,
      -SUM(CASE WHEN $when AND m.k = 'purchase_return' THEN m.q ELSE 0 END)
        AS returns_out,
      -SUM(CASE WHEN $when AND m.k = 'transfer_out' THEN m.q ELSE 0 END)
        AS transfers_out,
      -SUM(CASE WHEN $when AND m.k = 'assembly_out' THEN m.q ELSE 0 END)
        AS used,
      -SUM(CASE WHEN $when AND m.k = 'wastage' THEN m.q ELSE 0 END)
        AS wasted,
      SUM(CASE WHEN $when AND m.k = 'adjustment' THEN m.q ELSE 0 END)
        AS adjusted
      ''';

  static StockMoves _movesFrom(QueryRow r) => StockMoves(
    purchased: Qty.raw(r.read<int>('purchased')),
    returnsIn: Qty.raw(r.read<int>('returns_in')),
    transfersIn: Qty.raw(r.read<int>('transfers_in')),
    produced: Qty.raw(r.read<int>('produced')),
    sold: Qty.raw(r.read<int>('sold')),
    returnsOut: Qty.raw(r.read<int>('returns_out')),
    transfersOut: Qty.raw(r.read<int>('transfers_out')),
    used: Qty.raw(r.read<int>('used')),
    wasted: Qty.raw(r.read<int>('wasted')),
    adjusted: Qty.raw(r.read<int>('adjusted')),
  );

  static String? _blankless(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();

  static BusinessDate? _date(String? s) => s == null ? null : BusinessDate(s);

  /// ` AND TRIM(<items>.category) = ?` when [f] names a category.
  static String _inCategory(ReportFilters f, _Params q, [String items = 'i']) =>
      f.category == null
      ? ''
      : ' AND TRIM($items.category) = ${q.text(f.category!.trim())}';

  @override
  Future<List<StockLine>> stockLines(
    String firmId,
    BusinessDate asOf, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId)..text(asOf.value);
    final place = filters.location == null
        ? ''
        : ' AND s.location_code = ${q.text(filters.location!)}';
    final category = _inCategory(filters, q);
    // One pass over the ledger to the day, grouped by item, then every
    // stocked item beside it: an item with nothing on the shelf is still
    // on a stock list, unless it was archived and has nothing left.
    final rows = await _db
        .customSelect(
          '''
          SELECT i.id, i.name, u.code AS unit_code, i.category,
                 i.sale_rate_milli_paisa, i.avg_cost_milli_paisa,
                 COALESCE(st.q, 0) AS qty, COALESCE(st.v, 0) AS value
          FROM items i
          JOIN units u ON u.id = i.base_unit_id
          LEFT JOIN (
            SELECT s.item_id, SUM(s.qty_delta_thousandths) AS q,
                   SUM(s.value_delta_paisa) AS v
            FROM stock_ledger s
            WHERE s.firm_id = ?1
              AND s.deleted_at_utc IS NULL
              AND s.occurred_on_local <= ?2
              $place
            GROUP BY s.item_id
          ) st ON st.item_id = i.id
          WHERE i.firm_id = ?1
            AND i.track_stock = 1
            AND ((i.deleted_at_utc IS NULL AND i.is_active = 1)
                 OR COALESCE(st.q, 0) <> 0 OR COALESCE(st.v, 0) <> 0)
            ${filters.inStockOnly ? 'AND COALESCE(st.q, 0) > 0' : ''}
            $category
          ''',
          variables: q.variables,
          readsFrom: {_db.items, _db.units, _db.stockLedger},
        )
        .get();
    return [
      for (final r in rows)
        StockLine(
          itemId: r.read<String>('id'),
          itemName: r.read<String>('name'),
          unitCode: r.read<String>('unit_code'),
          category: _blankless(r.readNullable<String>('category')),
          saleRate: Rate.raw(r.read<int>('sale_rate_milli_paisa')),
          averageCost: Rate.raw(r.read<int>('avg_cost_milli_paisa')),
          qty: Qty.raw(r.read<int>('qty')),
          value: Money.paisa(r.read<int>('value')),
        ),
    ];
  }

  @override
  Future<Money> inventoryAsOf(String firmId, BusinessDate asOf) async {
    // Rides idx_jl_firm_account for the account's lines, each entry by its
    // key for its date.
    final row = await _db
        .customSelect(
          '''
          SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS books
          FROM journal_lines jl
          JOIN accounts a ON a.id = jl.account_id
          JOIN journal_entries je ON je.id = jl.journal_entry_id
          WHERE jl.firm_id = ?1
            AND a.system_key = 'inventory'
            AND jl.deleted_at_utc IS NULL
            AND je.deleted_at_utc IS NULL
            AND je.entry_date_local <= ?2
          ''',
          variables: [Variable<String>(firmId), Variable<String>(asOf.value)],
          readsFrom: {_db.journalLines, _db.journalEntries, _db.accounts},
        )
        .getSingle();
    return Money.paisa(row.read<int>('books'));
  }

  @override
  Future<List<StockFlow>> stockFlows(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId, period);
    final narrow = StringBuffer();
    if (filters.location != null) {
      narrow.write(' AND s.location_code = ${q.text(filters.location!)}');
    }
    if (filters.itemId != null) {
      narrow.write(' AND s.item_id = ${q.text(filters.itemId!)}');
    }
    if (filters.category != null) {
      narrow.write(
        ' AND s.item_id IN (SELECT ci.id FROM items ci '
        'WHERE ci.firm_id = ?1${_inCategory(filters, q, 'ci')})',
      );
    }
    // Every row to the period's last day, once: before the period it is
    // the opening, inside it the movement. An item that neither held stock
    // nor moved is left out; one whose value alone is left (a paisa of
    // rounding) is not, or the closing would not be the books'.
    //
    // Summed by item first and only then joined to the item's name, so
    // the twenty thousand items of a big catalogue are looked up once each
    // rather than once for every movement of a busy year.
    final rows = await _db
        .customSelect(
          '''
          SELECT f.*, i.name, u.code AS unit_code, i.category
          FROM (
            SELECT m.item_id,
                   SUM(CASE WHEN m.day < ?2 THEN m.q ELSE 0 END) AS opening_q,
                   SUM(CASE WHEN m.day < ?2 THEN m.v ELSE 0 END) AS opening_v,
                   SUM(CASE WHEN m.day >= ?2 THEN m.v ELSE 0 END) AS moved_v,
                   SUM(CASE WHEN m.day >= ?2 THEN 1 ELSE 0 END) AS moves,
                   ${_moves('m.day >= ?2')}
            FROM (
              SELECT s.item_id, s.occurred_on_local AS day,
                     s.qty_delta_thousandths AS q, s.value_delta_paisa AS v,
                     $_kind AS k
              FROM stock_ledger s
              LEFT JOIN documents d ON d.id = s.document_id
              WHERE s.firm_id = ?1
                AND s.deleted_at_utc IS NULL
                AND s.occurred_on_local <= ?3
                $narrow
            ) m
            GROUP BY m.item_id
            HAVING opening_q <> 0 OR opening_v <> 0 OR moves > 0
          ) f
          JOIN items i ON i.id = f.item_id
          JOIN units u ON u.id = i.base_unit_id
          ''',
          variables: q.variables,
          readsFrom: {_db.stockLedger, _db.documents, _db.items, _db.units},
        )
        .get();
    return [
      for (final r in rows)
        StockFlow(
          itemId: r.read<String>('item_id'),
          itemName: r.read<String>('name'),
          unitCode: r.read<String>('unit_code'),
          category: _blankless(r.readNullable<String>('category')),
          openingQty: Qty.raw(r.read<int>('opening_q')),
          openingValue: Money.paisa(r.read<int>('opening_v')),
          moves: _movesFrom(r),
          movedValue: Money.paisa(r.read<int>('moved_v')),
        ),
    ];
  }

  @override
  Future<ItemHistory?> itemHistory(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final itemId = filters.itemId;
    if (itemId == null) return null;
    final item = await _db
        .customSelect(
          'SELECT i.name, u.code AS unit_code FROM items i '
          'JOIN units u ON u.id = i.base_unit_id '
          'WHERE i.id = ?1 AND i.firm_id = ?2',
          variables: [Variable<String>(itemId), Variable<String>(firmId)],
          readsFrom: {_db.items, _db.units},
        )
        .getSingleOrNull();
    if (item == null) return null;

    final q = _Params(firmId, period)..text(itemId);
    final place = filters.location == null
        ? ''
        : ' AND s.location_code = ${q.text(filters.location!)}';
    // One item's rows ride idx_stock_position (firm, item, place, time).
    final opening = await _db
        .customSelect(
          '''
          SELECT COALESCE(SUM(s.qty_delta_thousandths), 0) AS q
          FROM stock_ledger s
          WHERE s.firm_id = ?1 AND s.item_id = ?4
            AND s.deleted_at_utc IS NULL
            AND s.occurred_on_local < ?2
            $place
          ''',
          variables: q.variables,
          readsFrom: {_db.stockLedger},
        )
        .getSingle();
    final days = await _db
        .customSelect(
          '''
          SELECT m.day, ${_moves('1 = 1')}
          FROM (
            SELECT s.occurred_on_local AS day,
                   s.qty_delta_thousandths AS q, $_kind AS k
            FROM stock_ledger s
            LEFT JOIN documents d ON d.id = s.document_id
            WHERE s.firm_id = ?1 AND s.item_id = ?4
              AND s.deleted_at_utc IS NULL
              AND s.occurred_on_local BETWEEN ?2 AND ?3
              $place
          ) m
          GROUP BY m.day
          ORDER BY m.day
          ''',
          variables: q.variables,
          readsFrom: {_db.stockLedger, _db.documents},
        )
        .get();
    return ItemHistory(
      itemId: itemId,
      itemName: item.read<String>('name'),
      unitCode: item.read<String>('unit_code'),
      openingQty: Qty.raw(opening.read<int>('q')),
      days: [
        for (final r in days)
          ItemDay(
            date: BusinessDate(r.read<String>('day')),
            moves: _movesFrom(r),
          ),
      ],
    );
  }

  @override
  Future<List<ItemTrade>> itemTrade(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId, period);
    final narrow = StringBuffer();
    if (filters.itemId != null) {
      narrow.write(' AND dl.item_id = ${q.text(filters.itemId!)}');
    }
    narrow.write(_inCategory(filters, q));
    // The period's posted bills, returns and deliveries both ways, by
    // idx_documents_list, their lines by idx_doclines_seq, summed by item.
    // A sale line's discount is its own and its share of the bill's, as
    // the calculator apportioned it when the bill was printed. A delivery's
    // lines keep their total and no taxable figure of their own, so before
    // tax is total less tax, as in the party reports.
    //
    // A line with no item behind it, khula maal sold by the rupee (M37),
    // moved no stock and recorded no cost, but its money is in Sales. All
    // such lines are one row, with no name, unit or category of their own,
    // so the item reports' totals still come to the sale report's.
    final rows = await _db
        .customSelect(
          '''
          SELECT dl.item_id,
                 CASE WHEN dl.item_id IS NULL THEN NULL
                      ELSE COALESCE(i.name, dl.item_name_snapshot) END
                   AS name,
                 CASE WHEN dl.item_id IS NULL THEN ''
                      ELSE COALESCE(u.code, dl.unit_code_snapshot) END
                   AS unit_code,
                 i.category,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN dl.base_qty_thousandths ELSE 0 END) AS sold,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN dl.base_qty_thousandths ELSE 0 END) AS returned,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN dl.gross_paisa ELSE 0 END) AS gross,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN dl.discount_paisa ELSE 0 END) AS discount,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN dl.taxable_paisa ELSE 0 END) AS sales,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN dl.taxable_paisa ELSE 0 END) AS returns,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                          THEN dl.cost_paisa ELSE 0 END) AS cost,
                 SUM(CASE WHEN d.doc_type = 'sale_return'
                          THEN dl.cost_paisa ELSE 0 END) AS returned_cost,
                 SUM(CASE WHEN d.doc_type = 'purchase_bill'
                          THEN dl.base_qty_thousandths ELSE 0 END) AS bought,
                 SUM(CASE WHEN d.doc_type = 'purchase_return'
                          THEN dl.base_qty_thousandths ELSE 0 END)
                   AS sent_back,
                 SUM(CASE WHEN d.doc_type = 'purchase_bill'
                          THEN dl.line_total_paisa - dl.tax_paisa ELSE 0 END)
                   AS purchases,
                 SUM(CASE WHEN d.doc_type = 'purchase_return'
                          THEN dl.line_total_paisa - dl.tax_paisa ELSE 0 END)
                   AS purchase_returns,
                 SUM(CASE WHEN d.doc_type = 'sale_invoice'
                           AND dl.is_free_item = 1
                          THEN dl.base_qty_thousandths ELSE 0 END) AS bonus
          FROM documents d
          JOIN document_lines dl ON dl.document_id = d.id
          LEFT JOIN items i ON i.id = dl.item_id
          LEFT JOIN units u ON u.id = i.base_unit_id
          WHERE d.firm_id = ?1
            AND d.doc_type IN ('sale_invoice', 'sale_return',
                               'purchase_bill', 'purchase_return')
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
            AND dl.deleted_at_utc IS NULL
            AND d.doc_date_local BETWEEN ?2 AND ?3
            $narrow
          GROUP BY dl.item_id
          ''',
          variables: q.variables,
          readsFrom: {_db.documents, _db.documentLines, _db.items, _db.units},
        )
        .get();
    return [
      for (final r in rows)
        ItemTrade(
          itemId: r.readNullable<String>('item_id'),
          itemName: r.readNullable<String>('name') ?? ItemTrade.looseLines,
          unitCode: r.read<String>('unit_code'),
          category: _blankless(r.readNullable<String>('category')),
          qtySold: Qty.raw(r.read<int>('sold')),
          qtyReturned: Qty.raw(r.read<int>('returned')),
          salesGross: Money.paisa(r.read<int>('gross')),
          discount: Money.paisa(r.read<int>('discount')),
          sales: Money.paisa(r.read<int>('sales')),
          returns: Money.paisa(r.read<int>('returns')),
          cost: Money.paisa(r.read<int>('cost')),
          returnedCost: Money.paisa(r.read<int>('returned_cost')),
          qtyBought: Qty.raw(r.read<int>('bought')),
          qtySentBack: Qty.raw(r.read<int>('sent_back')),
          purchases: Money.paisa(r.read<int>('purchases')),
          purchaseReturns: Money.paisa(r.read<int>('purchase_returns')),
          // M43: given free under a scheme, inside qtySold.
          qtyBonus: Qty.raw(r.read<int>('bonus')),
        ),
    ];
  }

  @override
  Future<List<ItemPartyTrade>> itemParties(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final itemId = filters.itemId;
    if (itemId == null) return const [];
    final q = _Params(firmId, period)..text(itemId);
    // The item's own lines by idx_doclines_item, each document by its key,
    // grouped by who was on the other side; the walk-ins are one row.
    final rows = await _db
        .customSelect(
          '''
          SELECT d.party_id, p.name,
                 SUM(CASE d.doc_type
                       WHEN 'sale_invoice' THEN dl.base_qty_thousandths
                       WHEN 'sale_return' THEN -dl.base_qty_thousandths
                       ELSE 0 END) AS sold,
                 SUM(CASE d.doc_type
                       WHEN 'sale_invoice' THEN dl.taxable_paisa
                       WHEN 'sale_return' THEN -dl.taxable_paisa
                       ELSE 0 END) AS sale_amount,
                 SUM(CASE d.doc_type
                       WHEN 'purchase_bill' THEN dl.base_qty_thousandths
                       WHEN 'purchase_return' THEN -dl.base_qty_thousandths
                       ELSE 0 END) AS bought,
                 SUM(CASE d.doc_type
                       WHEN 'purchase_bill'
                         THEN dl.line_total_paisa - dl.tax_paisa
                       WHEN 'purchase_return'
                         THEN -(dl.line_total_paisa - dl.tax_paisa)
                       ELSE 0 END) AS purchase_amount
          FROM document_lines dl
          JOIN documents d ON d.id = dl.document_id
          LEFT JOIN parties p ON p.id = d.party_id
          WHERE dl.item_id = ?4
            AND d.firm_id = ?1
            AND d.doc_type IN ('sale_invoice', 'sale_return',
                               'purchase_bill', 'purchase_return')
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
            AND dl.deleted_at_utc IS NULL
            AND d.doc_date_local BETWEEN ?2 AND ?3
          GROUP BY d.party_id
          ''',
          variables: q.variables,
          readsFrom: {_db.documents, _db.documentLines, _db.parties},
        )
        .get();
    return [
      for (final r in rows)
        ItemPartyTrade(
          partyId: r.readNullable<String>('party_id'),
          name: r.readNullable<String>('name') ?? 'Walk-in customers',
          qtySold: Qty.raw(r.read<int>('sold')),
          saleAmount: Money.paisa(r.read<int>('sale_amount')),
          qtyBought: Qty.raw(r.read<int>('bought')),
          purchaseAmount: Money.paisa(r.read<int>('purchase_amount')),
        ),
    ];
  }

  @override
  Future<List<LowStockLine>> lowStock(
    String firmId,
    BusinessDate asOf, {
    required int salesDays,
    ReportFilters filters = ReportFilters.none,
  }) async {
    // What is low is the counter's own answer since M1, read through the
    // same query the home screen's alert does, so the report and the
    // alert can never disagree about which items to order.
    final low = await DriftAppQueries(
      _db,
    ).lowStockItems(firmId, limit: _everyItem);
    if (low.isEmpty) return const [];
    final since = asOf.addDays(1 - (salesDays < 1 ? 1 : salesDays));
    final extra = <String, ({Qty sold, String? supplier})>{};
    // What each sold lately and who last supplied it, a few hundred items
    // at a time so no list of ids outgrows SQLite's bound variables. The
    // category is narrowed here, in the query.
    for (var at = 0; at < low.length; at += _chunk) {
      final ids = low.skip(at).take(_chunk).map((i) => i.id).toList();
      final q = _Params(firmId)
        ..text(since.value)
        ..text(asOf.value);
      final idList = [for (final id in ids) q.text(id)].join(', ');
      final category = _inCategory(filters, q);
      final rows = await _db
          .customSelect(
            '''
            SELECT i.id,
                   COALESCE((
                     SELECT SUM(CASE d.doc_type
                                  WHEN 'sale_invoice'
                                    THEN dl.base_qty_thousandths
                                  ELSE -dl.base_qty_thousandths END)
                     FROM document_lines dl
                     JOIN documents d ON d.id = dl.document_id
                     WHERE dl.item_id = i.id
                       AND dl.deleted_at_utc IS NULL
                       AND d.deleted_at_utc IS NULL
                       AND d.doc_type IN ('sale_invoice', 'sale_return')
                       AND d.status = 'posted'
                       AND d.doc_date_local BETWEEN ?2 AND ?3
                   ), 0) AS sold,
                   (
                     SELECT COALESCE(d.party_name_snapshot, p.name)
                     FROM document_lines dl
                     JOIN documents d ON d.id = dl.document_id
                     LEFT JOIN parties p ON p.id = d.party_id
                     WHERE dl.item_id = i.id
                       AND dl.deleted_at_utc IS NULL
                       AND d.deleted_at_utc IS NULL
                       AND d.doc_type = 'purchase_bill'
                       AND d.status = 'posted'
                     ORDER BY d.doc_date_local DESC, d.created_at_utc DESC
                     LIMIT 1
                   ) AS supplier
            FROM items i
            WHERE i.firm_id = ?1 AND i.id IN ($idList) $category
            ''',
            variables: q.variables,
            readsFrom: {
              _db.items,
              _db.documents,
              _db.documentLines,
              _db.parties,
            },
          )
          .get();
      for (final r in rows) {
        extra[r.read<String>('id')] = (
          sold: Qty.raw(r.read<int>('sold')),
          supplier: _blankless(r.readNullable<String>('supplier')),
        );
      }
    }
    return [
      for (final i in low)
        if (extra[i.id] case final e?)
          LowStockLine(
            itemId: i.id,
            itemName: i.name,
            unitCode: i.unitCode,
            category: _blankless(i.category),
            minStock: i.minStock,
            stock: i.stockOnHand,
            sold: e.sold,
            lastSupplier: e.supplier,
          ),
    ];
  }

  /// More items than any shop keeps, for a list that must have them all.
  static const _everyItem = 1 << 30;

  /// Ids bound in one statement, well inside SQLite's limit.
  static const _chunk = 400;

  @override
  Future<List<BatchLine>> batches(
    String firmId, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId);
    final place = filters.location == null
        ? ''
        : ' AND s.location_code = ${q.text(filters.location!)}';
    final narrow = StringBuffer();
    if (filters.itemId != null) {
      narrow.write(' AND l.item_id = ${q.text(filters.itemId!)}');
    }
    narrow.write(_inCategory(filters, q));
    // Each batch's own rows by idx_stock_lot. A serial number is a batch of
    // one, and has a report of its own.
    final rows = await _db
        .customSelect(
          '''
          SELECT l.item_id, i.name, u.code AS unit_code, l.lot_no,
                 l.expiry_date_local, l.mrp_paisa,
                 SUM(s.qty_delta_thousandths) AS q,
                 SUM(s.value_delta_paisa) AS v
          FROM stock_lots l
          JOIN items i ON i.id = l.item_id
          JOIN units u ON u.id = i.base_unit_id
          JOIN stock_ledger s ON s.lot_id = l.id AND s.deleted_at_utc IS NULL
                             $place
          WHERE l.firm_id = ?1
            AND l.deleted_at_utc IS NULL
            AND l.serial IS NULL
            $narrow
          GROUP BY l.id
          HAVING SUM(s.qty_delta_thousandths) > 0
          ''',
          variables: q.variables,
          readsFrom: {_db.stockLots, _db.items, _db.units, _db.stockLedger},
        )
        .get();
    return [
      for (final r in rows)
        BatchLine(
          itemId: r.read<String>('item_id'),
          itemName: r.read<String>('name'),
          unitCode: r.read<String>('unit_code'),
          lotNo: r.read<String>('lot_no'),
          expiry: _date(r.readNullable<String>('expiry_date_local')),
          mrp: switch (r.readNullable<int>('mrp_paisa')) {
            final int p => Money.paisa(p),
            null => null,
          },
          qty: Qty.raw(r.read<int>('q')),
          value: Money.paisa(r.read<int>('v')),
        ),
    ];
  }

  @override
  Future<List<SerialLine>> serials(
    String firmId, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId);
    final narrow = StringBuffer();
    if (filters.itemId != null) {
      narrow.write(' AND l.item_id = ${q.text(filters.itemId!)}');
    }
    final term = filters.serial?.trim().toLowerCase() ?? '';
    if (term.isNotEmpty) {
      narrow.write(' AND LOWER(l.serial) LIKE ${q.text('%$term%')}');
    }
    // Each piece's rows by idx_stock_lot: the first that brought it in, the
    // last sale that stands, the last way it left, and whether a customer
    // brought it back. A cancelled bill's rows are passed over, so a phone
    // rung up by mistake is still on the shelf.
    final rows = await _db
        .customSelect(
          '''
          SELECT l.serial, l.item_id, i.name AS item_name,
                 COALESCE((SELECT SUM(s.qty_delta_thousandths)
                             FROM stock_ledger s
                            WHERE s.lot_id = l.id
                              AND s.deleted_at_utc IS NULL), 0) AS on_hand,
                 (SELECT s.txn_type FROM stock_ledger s
                    LEFT JOIN documents x ON x.id = s.document_id
                   WHERE s.lot_id = l.id AND s.deleted_at_utc IS NULL
                     AND s.qty_delta_thousandths < 0
                     AND s.txn_type <> 'transfer_out'
                     AND COALESCE(x.status, '') <> 'void'
                   ORDER BY s.occurred_at_utc DESC, s.id DESC
                   LIMIT 1) AS last_out,
                 bi.occurred_on_local AS bought_on,
                 COALESCE(bd.party_name_snapshot, bp.name, lp.name)
                   AS supplier,
                 so.occurred_on_local AS sold_on,
                 sd.id AS sale_id, sd.doc_no AS sale_no,
                 sd.doc_type AS sale_type,
                 COALESCE(sd.party_name_snapshot, sp.name) AS customer,
                 (SELECT MAX(s.occurred_on_local) FROM stock_ledger s
                    LEFT JOIN documents x ON x.id = s.document_id
                   WHERE s.lot_id = l.id AND s.deleted_at_utc IS NULL
                     AND s.txn_type = 'sale_return'
                     AND COALESCE(x.status, '') <> 'void') AS returned_on
          FROM stock_lots l
          JOIN items i ON i.id = l.item_id
          LEFT JOIN parties lp ON lp.id = l.supplier_party_id
          LEFT JOIN stock_ledger bi ON bi.id = (
            SELECT s.id FROM stock_ledger s
            LEFT JOIN documents x ON x.id = s.document_id
            WHERE s.lot_id = l.id AND s.deleted_at_utc IS NULL
              AND s.txn_type IN ('purchase', 'opening')
              AND COALESCE(x.status, '') <> 'void'
            ORDER BY s.occurred_at_utc, s.id
            LIMIT 1)
          LEFT JOIN documents bd ON bd.id = bi.document_id
          LEFT JOIN parties bp ON bp.id = bd.party_id
          LEFT JOIN stock_ledger so ON so.id = (
            SELECT s.id FROM stock_ledger s
            LEFT JOIN documents x ON x.id = s.document_id
            WHERE s.lot_id = l.id AND s.deleted_at_utc IS NULL
              AND s.txn_type = 'sale'
              AND COALESCE(x.status, '') <> 'void'
            ORDER BY s.occurred_at_utc DESC, s.id DESC
            LIMIT 1)
          LEFT JOIN documents sd ON sd.id = so.document_id
          LEFT JOIN parties sp ON sp.id = sd.party_id
          WHERE l.firm_id = ?1
            AND l.deleted_at_utc IS NULL
            AND l.serial IS NOT NULL
            $narrow
          ''',
          variables: q.variables,
          readsFrom: {
            _db.stockLots,
            _db.items,
            _db.stockLedger,
            _db.documents,
            _db.parties,
          },
        )
        .get();
    return [
      for (final r in rows)
        SerialLine(
          serial: r.read<String>('serial'),
          itemId: r.read<String>('item_id'),
          itemName: r.read<String>('item_name'),
          onHand: Qty.raw(r.read<int>('on_hand')),
          lastOut: r.readNullable<String>('last_out'),
          supplier: _blankless(r.readNullable<String>('supplier')),
          boughtOn: _date(r.readNullable<String>('bought_on')),
          customer: _blankless(r.readNullable<String>('customer')),
          soldOn: _date(r.readNullable<String>('sold_on')),
          saleId: r.readNullable<String>('sale_id'),
          saleNo: r.readNullable<String>('sale_no'),
          saleType: r.readNullable<String>('sale_type'),
          returnedOn: _date(r.readNullable<String>('returned_on')),
        ),
    ];
  }

  @override
  Future<List<StockTransferLine>> stockTransfers(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId, period);
    final narrow = StringBuffer();
    if (filters.itemId != null) {
      narrow.write(' AND o.item_id = ${q.text(filters.itemId!)}');
    }
    if (filters.location != null) {
      final place = q.text(filters.location!);
      narrow.write(
        ' AND (o.location_code = $place OR t.location_code = $place)',
      );
    }
    // A move is written as a pair, out of one place and into another, in
    // one transaction (DriftCatalogueWriter.transferStock, a van's day
    // settled). Each row out is matched to the row in written straight
    // after it for the same item, batch and moment, by idx_stock_item; the
    // pairs of one move split across batches are summed back into one.
    // The period's rows out ride idx_stock_daybook.
    final rows = await _db
        .customSelect(
          '''
          SELECT day, item_id, name, unit_code, from_place, to_place,
                 SUM(qty) AS qty, SUM(value) AS value
          FROM (
            SELECT o.occurred_on_local AS day, o.occurred_at_utc AS at,
                   o.item_id, i.name, u.code AS unit_code,
                   -o.qty_delta_thousandths AS qty,
                   -o.value_delta_paisa AS value,
                   COALESCE(vf.name, o.location_code) AS from_place,
                   COALESCE(vt.name, t.location_code, '?') AS to_place
            FROM stock_ledger o
            JOIN items i ON i.id = o.item_id
            JOIN units u ON u.id = i.base_unit_id
            LEFT JOIN stock_ledger t ON t.id = (
              SELECT x.id FROM stock_ledger x
              WHERE x.item_id = o.item_id
                AND x.occurred_at_utc = o.occurred_at_utc
                AND x.firm_id = o.firm_id
                AND x.txn_type = 'transfer_in'
                AND x.lot_id IS o.lot_id
                AND x.id > o.id
                AND x.deleted_at_utc IS NULL
              ORDER BY x.id
              LIMIT 1)
            LEFT JOIN vans vf ON vf.firm_id = o.firm_id
                             AND vf.location_code = o.location_code
            LEFT JOIN vans vt ON vt.firm_id = o.firm_id
                             AND vt.location_code = t.location_code
            WHERE o.firm_id = ?1
              AND o.occurred_on_local BETWEEN ?2 AND ?3
              AND o.txn_type = 'transfer_out'
              AND o.deleted_at_utc IS NULL
              $narrow
          )
          GROUP BY day, at, item_id, from_place, to_place
          ORDER BY day, at, name
          ''',
          variables: q.variables,
          readsFrom: {_db.stockLedger, _db.items, _db.units, _db.vans},
        )
        .get();
    return [
      for (final r in rows)
        StockTransferLine(
          date: BusinessDate(r.read<String>('day')),
          itemId: r.read<String>('item_id'),
          itemName: r.read<String>('name'),
          unitCode: r.read<String>('unit_code'),
          qty: Qty.raw(r.read<int>('qty')),
          from: r.read<String>('from_place'),
          to: r.read<String>('to_place'),
          value: Money.paisa(r.read<int>('value')),
        ),
    ];
  }

  @override
  Future<List<ProductionRun>> productionRuns(
    String firmId,
    ReportPeriod period, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId, period);
    final made = filters.itemId == null
        ? ''
        : ' AND a.output_item_id = ${q.text(filters.itemId!)}';
    final runs = await _db
        .customSelect(
          '''
          SELECT a.id, a.made_on_local, a.assembly_no, a.output_item_id,
                 i.name, u.code AS unit_code, a.output_qty_thousandths,
                 a.components_cost_paisa, a.overhead_paisa
          FROM assemblies a
          JOIN items i ON i.id = a.output_item_id
          JOIN units u ON u.id = i.base_unit_id
          WHERE a.firm_id = ?1
            AND a.deleted_at_utc IS NULL
            AND a.made_on_local BETWEEN ?2 AND ?3
            $made
          ''',
          variables: q.variables,
          readsFrom: {_db.assemblies, _db.items, _db.units},
        )
        .get();
    if (runs.isEmpty) return const [];
    // What each run used: the assembly_out rows written in its transaction,
    // on its device, at its moment, before the run's own row and after any
    // run written at the same moment before it. Each run's ids come from
    // one generator in order, so this is exactly its own components even
    // when two runs share a millisecond. The day narrows the rows to
    // idx_stock_daybook.
    final used = await _db
        .customSelect(
          '''
          SELECT a.id AS run_id, ci.name, cu.code AS unit_code,
                 -SUM(s.qty_delta_thousandths) AS q
          FROM assemblies a
          JOIN stock_ledger s
            ON s.firm_id = a.firm_id
           AND s.occurred_on_local = a.made_on_local
           AND s.txn_type = 'assembly_out'
           AND s.occurred_at_utc = a.created_at_utc
           AND s.origin_device_id = a.origin_device_id
           AND s.id < a.id
           AND s.id > COALESCE((
             SELECT MAX(p.id) FROM assemblies p
             WHERE p.firm_id = a.firm_id
               AND p.created_at_utc = a.created_at_utc
               AND p.id < a.id), '')
           AND s.deleted_at_utc IS NULL
          JOIN items ci ON ci.id = s.item_id
          JOIN units cu ON cu.id = ci.base_unit_id
          WHERE a.firm_id = ?1
            AND a.deleted_at_utc IS NULL
            AND a.made_on_local BETWEEN ?2 AND ?3
            $made
          GROUP BY a.id, s.item_id
          ORDER BY a.id, ci.name
          ''',
          variables: q.variables,
          readsFrom: {_db.assemblies, _db.stockLedger, _db.items, _db.units},
        )
        .get();
    final byRun = <String, List<RunComponent>>{};
    for (final r in used) {
      byRun
          .putIfAbsent(r.read<String>('run_id'), () => [])
          .add(
            RunComponent(
              itemName: r.read<String>('name'),
              unitCode: r.read<String>('unit_code'),
              qty: Qty.raw(r.read<int>('q')),
            ),
          );
    }
    return [
      for (final r in runs)
        ProductionRun(
          date: BusinessDate(r.read<String>('made_on_local')),
          runNo: r.read<String>('assembly_no'),
          itemId: r.read<String>('output_item_id'),
          itemName: r.read<String>('name'),
          unitCode: r.read<String>('unit_code'),
          qty: Qty.raw(r.read<int>('output_qty_thousandths')),
          components: byRun[r.read<String>('id')] ?? const [],
          componentsCost: Money.paisa(r.read<int>('components_cost_paisa')),
          overhead: Money.paisa(r.read<int>('overhead_paisa')),
        ),
    ];
  }

  @override
  Future<List<ItemSelling>> itemSelling(
    String firmId,
    BusinessDate asOf, {
    required int salesDays,
    ReportFilters filters = ReportFilters.none,
  }) async {
    final since = asOf.addDays(1 - (salesDays < 1 ? 1 : salesDays));
    final q = _Params(firmId)
      ..text(since.value)
      ..text(asOf.value);
    final category = _inCategory(filters, q);
    // The window's bills once, by idx_documents_list, summed by item; the
    // shelf to the day once, grouped by item; and each item's last sale by
    // idx_doclines_item. An item counts when it has stock or has sold.
    final rows = await _db
        .customSelect(
          '''
          SELECT i.id, i.name, u.code AS unit_code, i.category,
                 COALESCE(sold.bills, 0) AS bills,
                 COALESCE(sold.q, 0) AS sold_q,
                 COALESCE(st.q, 0) AS stock_q,
                 COALESCE(st.v, 0) AS stock_v,
                 (SELECT MAX(d.doc_date_local) FROM document_lines dl
                    JOIN documents d ON d.id = dl.document_id
                   WHERE dl.item_id = i.id
                     AND dl.deleted_at_utc IS NULL
                     AND d.deleted_at_utc IS NULL
                     AND d.doc_type = 'sale_invoice'
                     AND d.status = 'posted'
                     AND d.doc_date_local <= ?3) AS last_sold
          FROM items i
          JOIN units u ON u.id = i.base_unit_id
          LEFT JOIN (
            SELECT dl.item_id,
                   COUNT(DISTINCT CASE WHEN d.doc_type = 'sale_invoice'
                                       THEN d.id END) AS bills,
                   SUM(CASE d.doc_type
                         WHEN 'sale_invoice' THEN dl.base_qty_thousandths
                         ELSE -dl.base_qty_thousandths END) AS q
            FROM documents d
            JOIN document_lines dl ON dl.document_id = d.id
            WHERE d.firm_id = ?1
              AND d.doc_type IN ('sale_invoice', 'sale_return')
              AND d.status = 'posted'
              AND d.deleted_at_utc IS NULL
              AND dl.deleted_at_utc IS NULL
              AND dl.item_id IS NOT NULL
              AND d.doc_date_local BETWEEN ?2 AND ?3
            GROUP BY dl.item_id
          ) sold ON sold.item_id = i.id
          LEFT JOIN (
            SELECT s.item_id, SUM(s.qty_delta_thousandths) AS q,
                   SUM(s.value_delta_paisa) AS v
            FROM stock_ledger s
            WHERE s.firm_id = ?1
              AND s.deleted_at_utc IS NULL
              AND s.occurred_on_local <= ?3
            GROUP BY s.item_id
          ) st ON st.item_id = i.id
          WHERE i.firm_id = ?1
            AND i.deleted_at_utc IS NULL
            AND i.track_stock = 1
            AND (COALESCE(st.q, 0) <> 0 OR COALESCE(sold.bills, 0) > 0)
            $category
          ''',
          variables: q.variables,
          readsFrom: {
            _db.items,
            _db.units,
            _db.documents,
            _db.documentLines,
            _db.stockLedger,
          },
        )
        .get();
    return [
      for (final r in rows)
        ItemSelling(
          itemId: r.read<String>('id'),
          itemName: r.read<String>('name'),
          unitCode: r.read<String>('unit_code'),
          category: _blankless(r.readNullable<String>('category')),
          bills: r.read<int>('bills'),
          qtySold: Qty.raw(r.read<int>('sold_q')),
          lastSold: _date(r.readNullable<String>('last_sold')),
          stock: Qty.raw(r.read<int>('stock_q')),
          value: Money.paisa(r.read<int>('stock_v')),
        ),
    ];
  }

  @override
  Future<List<ItemAgeing>> stockAgeing(
    String firmId,
    BusinessDate asOf, {
    ReportFilters filters = ReportFilters.none,
  }) async {
    final q = _Params(firmId)..text(asOf.value);
    final category = _inCategory(filters, q);
    // First in, first out, in SQL: each receipt's running total newest
    // first (a window over the item's receipts), and from it how much of
    // that receipt is still what is on the shelf. A receipt is a delivery,
    // opening stock, a customer's return, a production run, or a count
    // that found more; a move between places is not, and nor is the
    // reversal of a cancelled bill, whose goods are as old as they were.
    // The age is in whole days on the business dates.
    final rows = await _db
        .customSelect(
          '''
          WITH onhand AS (
            SELECT s.item_id, SUM(s.qty_delta_thousandths) AS q,
                   SUM(s.value_delta_paisa) AS v
            FROM stock_ledger s
            WHERE s.firm_id = ?1
              AND s.deleted_at_utc IS NULL
              AND s.occurred_on_local <= ?2
            GROUP BY s.item_id
            HAVING SUM(s.qty_delta_thousandths) > 0
          ),
          receipts AS (
            SELECT s.item_id, s.qty_delta_thousandths AS q,
                   CAST(julianday(?2) - julianday(s.occurred_on_local)
                        AS INTEGER) AS age,
                   SUM(s.qty_delta_thousandths) OVER (
                     PARTITION BY s.item_id
                     ORDER BY s.occurred_on_local DESC, s.id DESC
                     ROWS UNBOUNDED PRECEDING
                   ) AS upto
            FROM stock_ledger s
            WHERE s.firm_id = ?1
              AND s.deleted_at_utc IS NULL
              AND s.occurred_on_local <= ?2
              AND s.qty_delta_thousandths > 0
              AND (s.txn_type IN ('opening', 'purchase', 'sale_return',
                                  'assembly_in')
                   OR (s.txn_type = 'adjustment' AND s.document_id IS NULL))
              AND s.item_id IN (SELECT item_id FROM onhand)
          ),
          held AS (
            SELECT r.item_id, r.age,
                   MAX(0, MIN(r.q, o.q - (r.upto - r.q))) AS q
            FROM receipts r
            JOIN onhand o ON o.item_id = r.item_id
          )
          SELECT o.item_id, i.name, u.code AS unit_code, i.category,
                 o.q AS on_hand, o.v AS value,
                 COALESCE(SUM(CASE WHEN h.age <= 45 THEN h.q END), 0) AS b0,
                 COALESCE(SUM(CASE WHEN h.age BETWEEN 46 AND 90
                                   THEN h.q END), 0) AS b1,
                 COALESCE(SUM(CASE WHEN h.age BETWEEN 91 AND 180
                                   THEN h.q END), 0) AS b2,
                 COALESCE(SUM(CASE WHEN h.age > 180 THEN h.q END), 0) AS b3
          FROM onhand o
          JOIN items i ON i.id = o.item_id
          JOIN units u ON u.id = i.base_unit_id
          LEFT JOIN held h ON h.item_id = o.item_id
          WHERE 1 = 1 $category
          GROUP BY o.item_id
          ''',
          variables: q.variables,
          readsFrom: {_db.stockLedger, _db.items, _db.units},
        )
        .get();
    return [
      for (final r in rows)
        ItemAgeing(
          itemId: r.read<String>('item_id'),
          itemName: r.read<String>('name'),
          unitCode: r.read<String>('unit_code'),
          category: _blankless(r.readNullable<String>('category')),
          onHand: Qty.raw(r.read<int>('on_hand')),
          value: Money.paisa(r.read<int>('value')),
          buckets: [
            for (final b in const ['b0', 'b1', 'b2', 'b3'])
              Qty.raw(r.read<int>(b)),
          ],
        ),
    ];
  }

  /// The places goods are kept (M34), for the place filter: the shop
  /// floor first, then each godown and van the ledger has seen, a van by
  /// its name.
  Future<List<ReportChoice>> _placeChoices(String firmId, String term) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT p.code, v.name FROM (
            SELECT DISTINCT location_code AS code FROM stock_ledger
            WHERE firm_id = ?1 AND deleted_at_utc IS NULL
            UNION
            SELECT location_code FROM vans
            WHERE firm_id = ?1 AND deleted_at_utc IS NULL
          ) p
          LEFT JOIN vans v ON v.firm_id = ?1 AND v.location_code = p.code
          ''',
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.stockLedger, _db.vans},
        )
        .get();
    final places = <ReportChoice>[
      for (final r in rows)
        if (r.read<String>('code') != ReportFilters.shopFloor)
          ReportChoice(
            id: r.read<String>('code'),
            label: r.readNullable<String>('name') ?? r.read<String>('code'),
          ),
    ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return [
          ReportChoice(
            id: ReportFilters.shopFloor,
            label: placeLabel(ReportFilters.shopFloor),
          ),
          ...places,
        ]
        .where((c) => term.isEmpty || c.label.toLowerCase().contains(term))
        .toList();
  }
}
