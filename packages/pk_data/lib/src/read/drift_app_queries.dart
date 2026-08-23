import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';

/// Every read the app performs, as indexed SQL.
///
/// Nothing here loads a table into memory to add it up. That is not a style
/// preference: the largest single cluster of crash reports against the nearest
/// competitor is reports on catalogues of a few thousand items, and the cause
/// is aggregation in Dart over rows fetched in full. Every total below is a
/// SUM the database computes behind an index, and every list is keyset
/// paginated on the primary key — which works because a ULID sorts by
/// creation time, so there is no secondary sort and no OFFSET anywhere.
final class DriftAppQueries implements AppQueries {
  const DriftAppQueries(this._db);

  final AppDatabase _db;

  @override
  Future<FirmProfile?> currentFirm() => _firm();

  /// The named firm, or -- with no argument -- the one this device belongs to.
  ///
  /// The argument exists because a receipt has to carry the shop whose invoice
  /// it is. Reading "the first firm" to build a receipt header prints the
  /// wrong name, NTN and bank details the moment M10 adds a second firm, and
  /// the mistake is invisible until then.
  Future<FirmProfile?> _firm([String? firmId]) async {
    final row = await _db
        .customSelect(
          firmId == null
              ? 'SELECT * FROM firms WHERE deleted_at_utc IS NULL '
                    'ORDER BY created_at_utc LIMIT 1'
              : 'SELECT * FROM firms WHERE id = ? AND deleted_at_utc IS NULL',
          variables: firmId == null ? const [] : [Variable<String>(firmId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return FirmProfile(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      city: _blankToNull(row.readNullable<String>('city')),
      addressLine1: _blankToNull(row.readNullable<String>('address_line1')),
      phone: _blankToNull(row.readNullable<String>('phone')),
      province: row.read<String>('province'),
      ntn: _blankToNull(row.readNullable<String>('ntn')),
      strn: _blankToNull(row.readNullable<String>('strn')),
      isSalesTaxRegistered: row.read<int>('is_sales_tax_registered') == 1,
      roundInvoiceToRupee: row.read<int>('round_invoice_to_rupee') == 1,
      raastAlias: _blankToNull(row.readNullable<String>('raast_alias')),
      bankName: _blankToNull(row.readNullable<String>('bank_name')),
      bankAccountTitle: _blankToNull(
        row.readNullable<String>('bank_account_title'),
      ),
      bankIban: _blankToNull(row.readNullable<String>('bank_iban')),
    );
  }

  @override
  Future<String> userName(String userId) async {
    final row = await _db
        .customSelect(
          'SELECT name FROM users WHERE id = ?',
          variables: [Variable<String>(userId)],
        )
        .getSingleOrNull();
    return row?.read<String>('name') ?? 'Unknown';
  }

  @override
  Future<List<PaymentAccountSummary>> paymentAccounts(String firmId) async {
    final rows = await _db
        .customSelect(
          'SELECT id, name, account_kind, mode_label, is_default '
          'FROM payment_accounts '
          'WHERE firm_id = ? AND deleted_at_utc IS NULL AND is_active = 1 '
          'ORDER BY is_default DESC, name',
          variables: [Variable<String>(firmId)],
        )
        .get();
    return [
      for (final r in rows)
        PaymentAccountSummary(
          id: r.read<String>('id'),
          name: r.read<String>('name'),
          kind: r.read<String>('account_kind'),
          modeLabel: r.read<String>('mode_label'),
          isDefault: r.read<int>('is_default') == 1,
        ),
    ];
  }

  @override
  Future<List<ItemSummary>> searchItems(
    String firmId, {
    String query = '',
    String? afterId,
    int limit = 40,
  }) async {
    final term = _normalise(query);
    final rows = await _db
        .customSelect(
          '''
          SELECT i.*, u.code AS unit_code, u.decimals AS unit_decimals,
                 COALESCE((
                   SELECT SUM(sl.qty_delta_thousandths)
                   FROM stock_ledger sl
                   WHERE sl.item_id = i.id AND sl.deleted_at_utc IS NULL
                 ), 0) AS stock_thousandths
          FROM items i
          JOIN units u ON u.id = i.base_unit_id
          WHERE i.firm_id = ?
            AND i.deleted_at_utc IS NULL
            AND i.is_active = 1
            AND (? = '' OR i.name_search LIKE ? OR i.code = ? OR i.barcode = ?)
            AND (? IS NULL OR i.id > ?)
          -- Ordered by id, which is what the cursor pages on. Ordering by
          -- name while paginating on id silently drops and repeats rows on
          -- page two, and a 20,000-SKU catalogue is exactly where nobody
          -- would notice. ULIDs sort by creation, so this is "most recently
          -- stocked last" — and the counter's own search is a filter, not a
          -- browse. Alphabetical browsing arrives in M1 on an FTS5 index with
          -- a matching composite cursor.
          ORDER BY i.id
          LIMIT ?
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(term),
            Variable<String>('%$term%'),
            Variable<String>(query.trim()),
            Variable<String>(query.trim()),
            Variable<String>(afterId),
            Variable<String>(afterId),
            Variable<int>(limit),
          ],
        )
        .get();
    return [for (final r in rows) _itemFrom(r)];
  }

  @override
  Future<ItemSummary?> itemByBarcode(String firmId, String barcode) async {
    // Every form the same physical barcode can arrive in, most likely first.
    //
    // A UPC-A packet reaches a hardware wedge as twelve digits and a phone
    // camera as thirteen, because ML Kit reports UPC-A as the EAN-13 it
    // formally is. An exact match therefore finds the item when the counter
    // scans it with the USB gun and misses when the same packet is scanned
    // with the phone — and nothing about that failure suggests a
    // normalisation problem. It looks like the item is missing, so the cashier
    // adds it again by hand, and the catalogue ends up with one packet twice
    // at two prices.
    final variants = barcodeVariants(barcode);
    if (variants.isEmpty) return null;

    final placeholders = List.filled(variants.length, '?').join(', ');
    final rows = await _db
        .customSelect(
          '''
          SELECT i.*, u.code AS unit_code, u.decimals AS unit_decimals,
                 COALESCE((
                   SELECT SUM(sl.qty_delta_thousandths)
                   FROM stock_ledger sl
                   WHERE sl.item_id = i.id AND sl.deleted_at_utc IS NULL
                 ), 0) AS stock_thousandths
          FROM items i
          JOIN units u ON u.id = i.base_unit_id
          WHERE i.firm_id = ? AND i.barcode IN ($placeholders)
            AND i.deleted_at_utc IS NULL
            AND i.is_active = 1
          -- Exactly what was scanned wins over anything inferred from it. Two
          -- items really can carry the twelve- and thirteen-digit forms of one
          -- code, and the one the scanner actually read is the right answer.
          ORDER BY CASE i.barcode WHEN ? THEN 0 ELSE 1 END
          LIMIT 1
          ''',
          variables: [
            Variable<String>(firmId),
            for (final v in variants) Variable<String>(v),
            Variable<String>(variants.first),
          ],
        )
        .get();
    return rows.isEmpty ? null : _itemFrom(rows.single);
  }

  @override
  Future<ItemSummary?> itemById(String firmId, String itemId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT i.*, u.code AS unit_code, u.decimals AS unit_decimals,
                 COALESCE((
                   SELECT SUM(sl.qty_delta_thousandths)
                   FROM stock_ledger sl
                   WHERE sl.item_id = i.id AND sl.deleted_at_utc IS NULL
                 ), 0) AS stock_thousandths
          FROM items i
          JOIN units u ON u.id = i.base_unit_id
          WHERE i.firm_id = ? AND i.id = ? AND i.deleted_at_utc IS NULL
          LIMIT 1
          ''',
          variables: [Variable<String>(firmId), Variable<String>(itemId)],
        )
        .get();
    return rows.isEmpty ? null : _itemFrom(rows.single);
  }

  @override
  Future<List<PartySummary>> searchParties(
    String firmId, {
    String query = '',
    int limit = 40,
  }) async {
    final term = _normalise(query);
    final rows = await _db
        .customSelect(
          '''
          SELECT p.id, p.name, p.phone, p.party_type, p.credit_limit_paisa,
                 p.opening_balance_paisa
                   + COALESCE((
                       SELECT SUM(d.balance_paisa) FROM documents d
                       WHERE d.party_id = p.id
                         AND d.firm_id = p.firm_id
                         AND d.doc_type = 'sale_invoice'
                         AND d.status = 'posted'
                         AND d.deleted_at_utc IS NULL
                     ), 0) AS balance_paisa
          FROM parties p
          WHERE p.firm_id = ?
            AND p.deleted_at_utc IS NULL
            AND p.is_active = 1
            AND (? = '' OR p.name_search LIKE ? OR p.phone LIKE ?)
          ORDER BY p.name_search
          LIMIT ?
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(term),
            Variable<String>('%$term%'),
            Variable<String>('%${query.trim()}%'),
            Variable<int>(limit),
          ],
        )
        .get();
    return [
      for (final r in rows)
        PartySummary(
          id: r.read<String>('id'),
          name: r.read<String>('name'),
          phone: _blankToNull(r.readNullable<String>('phone')),
          partyType: r.read<String>('party_type'),
          balance: Money.paisa(r.read<int>('balance_paisa')),
          creditLimit: r.readNullable<int>('credit_limit_paisa') == null
              ? null
              : Money.paisa(r.read<int>('credit_limit_paisa')),
        ),
    ];
  }

  @override
  Future<List<OpenBill>> openBillsFor(String firmId, String partyId) async {
    // Deliberately the same WHERE and the same ORDER BY as
    // `_DriftPaymentWriteContext.openBillsFor`. The preview a shopkeeper
    // approves has to be what the write actually does, and two orderings
    // would make it a guess.
    //
    // Rides idx_documents_open_balance:
    // (firm_id, party_id, doc_date_local) WHERE balance_paisa <> 0.
    final rows = await _db
        .customSelect(
          '''
          SELECT id, doc_date_local, doc_seq, balance_paisa
          FROM documents
          WHERE firm_id = ? AND party_id = ?
            AND balance_paisa > 0
            AND status NOT IN ('void', 'draft')
            AND deleted_at_utc IS NULL
          ORDER BY doc_date_local, doc_seq, id
          ''',
          variables: [Variable<String>(firmId), Variable<String>(partyId)],
          readsFrom: {_db.documents},
        )
        .get();

    return [
      for (final r in rows)
        OpenBill(
          documentId: r.read<String>('id'),
          dateLocal: r.read<String>('doc_date_local'),
          sequence: r.read<int>('doc_seq'),
          outstanding: Money.paisa(r.read<int>('balance_paisa')),
        ),
    ];
  }

  @override
  Future<List<SaleListRow>> recentSales(
    String firmId, {
    String? afterId,
    int limit = 40,
    String? onDateLocal,
  }) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_no, d.doc_date_local, d.doc_date_utc,
                 d.party_name_snapshot, d.total_paisa, d.balance_paisa,
                 d.status,
                 (SELECT COUNT(*) FROM document_lines dl
                    WHERE dl.document_id = d.id
                      AND dl.deleted_at_utc IS NULL) AS line_count
          FROM documents d
          WHERE d.firm_id = ?
            AND d.doc_type = 'sale_invoice'
            AND d.deleted_at_utc IS NULL
            AND (? IS NULL OR d.doc_date_local = ?)
            AND (? IS NULL OR d.id < ?)
          ORDER BY d.id DESC
          LIMIT ?
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(onDateLocal),
            Variable<String>(onDateLocal),
            Variable<String>(afterId),
            Variable<String>(afterId),
            Variable<int>(limit),
          ],
        )
        .get();
    return [
      for (final r in rows)
        SaleListRow(
          id: r.read<String>('id'),
          docNo: r.read<String>('doc_no'),
          dateLocal: r.read<String>('doc_date_local'),
          timeLabel: _timeLabel(r.read<int>('doc_date_utc')),
          partyName: _blankToNull(
            r.readNullable<String>('party_name_snapshot'),
          ),
          total: Money.paisa(r.read<int>('total_paisa')),
          balance: Money.paisa(r.read<int>('balance_paisa')),
          lineCount: r.read<int>('line_count'),
          status: r.read<String>('status'),
        ),
    ];
  }

  @override
  Future<DayTotals> dayTotals(String firmId, String dateLocal) async {
    final row = await _db
        .customSelect(
          '''
          SELECT COUNT(*) AS bills,
                 COALESCE(SUM(total_paisa), 0) AS sales,
                 COALESCE(SUM(paid_paisa), 0) AS received,
                 COALESCE(SUM(balance_paisa), 0) AS udhaar
          FROM documents
          WHERE firm_id = ? AND doc_type = 'sale_invoice'
            AND doc_date_local = ? AND status = 'posted'
            AND deleted_at_utc IS NULL
          ''',
          variables: [Variable<String>(firmId), Variable<String>(dateLocal)],
        )
        .getSingle();
    return DayTotals(
      dateLocal: dateLocal,
      billCount: row.read<int>('bills'),
      sales: Money.paisa(row.read<int>('sales')),
      received: Money.paisa(row.read<int>('received')),
      onUdhaar: Money.paisa(row.read<int>('udhaar')),
    );
  }

  @override
  Future<ReceiptData?> receiptFor(String firmId, String documentId) async {
    final firm = await _firm(firmId);
    if (firm == null) return null;

    final doc = await _db
        .customSelect(
          'SELECT * FROM documents WHERE id = ? AND firm_id = ? '
          'AND deleted_at_utc IS NULL',
          variables: [Variable<String>(documentId), Variable<String>(firmId)],
        )
        .getSingleOrNull();
    if (doc == null) return null;

    final lines = await _db
        .customSelect(
          'SELECT * FROM document_lines WHERE document_id = ? '
          'AND deleted_at_utc IS NULL ORDER BY line_no',
          variables: [Variable<String>(documentId)],
        )
        .get();

    final payments = await _db
        .customSelect(
          '''
          SELECT DISTINCT p.id, p.mode, p.amount_paisa, p.tendered_paisa,
                 p.change_paisa, p.reference
          FROM payments p
          JOIN payment_allocations pa ON pa.payment_id = p.id
          WHERE pa.document_id = ?
            AND pa.deleted_at_utc IS NULL
            AND p.deleted_at_utc IS NULL
          ORDER BY p.payment_no
          ''',
          variables: [Variable<String>(documentId)],
        )
        .get();

    final cashier = await userName(doc.read<String>('created_by'));

    return ReceiptData(
      shop: firm.toReceiptShop(),
      docNo: doc.read<String>('doc_no'),
      dateTimeLabel: _dateTimeLabel(doc.read<int>('doc_date_utc')),
      cashierName: cashier,
      customerName: _blankToNull(
        doc.readNullable<String>('party_name_snapshot'),
      ),
      lines: [
        for (final l in lines)
          ReceiptLine(
            name: l.read<String>('item_name_snapshot'),
            qtyDisplay: Qty.raw(l.read<int>('qty_thousandths')).display,
            unitCode: l.read<String>('unit_code_snapshot'),
            rate: Rate.raw(l.read<int>('rate_milli_paisa')),
            // Gross, because the line below it prints the discount as a
            // deduction and the Subtotal is gross too. Printing the net
            // figure here deducted the discount twice on the paper: a Rs 100
            // line at 10% off read "1 pcs x 100.00 ... 90.00" with "less
            // discount -10.00" under it, so the Amount column summed to 90
            // while the Subtotal claimed 100, and reading the line as printed
            // gave 80. None of the three numbers agreed.
            amount: Money.paisa(l.read<int>('gross_paisa')),
            discount: Money.paisa(l.read<int>('discount_paisa')),
            isFreeItem: l.read<int>('is_free_item') == 1,
          ),
      ],
      subtotal: Money.paisa(doc.read<int>('subtotal_paisa')),
      discount: Money.paisa(
        doc.read<int>('line_discount_paisa') +
            doc.read<int>('bill_discount_paisa'),
      ),
      tax: Money.paisa(doc.read<int>('tax_paisa')),
      furtherTax: Money.paisa(doc.read<int>('further_tax_paisa')),
      withholding: Money.paisa(doc.read<int>('withholding_paisa')),
      extraCharges: Money.paisa(doc.read<int>('extra_charges_paisa')),
      roundOff: Money.paisa(doc.read<int>('round_off_paisa')),
      total: Money.paisa(doc.read<int>('total_paisa')),
      tenders: [
        for (final p in payments)
          ReceiptTender(
            label: _modeLabel(p.read<String>('mode')),
            isCash: p.read<String>('mode') == 'cash',
            // What the customer handed over, not what the bill took off it.
            //
            // The receipt prints the tenders and then the change, and a
            // customer checks the paper by subtracting one from the other.
            // Printing `amount_paisa` — the settled figure — made every cash
            // receipt with change fail that check: a Rs 5,525 bill paid with
            // a Rs 6,000 note printed "Cash 5,525.00" and "Change 475.00",
            // which comes to 5,050, and also stated the customer had handed
            // over 5,525 when they had handed over 6,000.
            amount: Money.paisa(
              p.readNullable<int>('tendered_paisa') ??
                  p.read<int>('amount_paisa'),
            ),
            reference: _blankToNull(p.readNullable<String>('reference')),
          ),
      ],
      paid: Money.paisa(doc.read<int>('paid_paisa')),
      balance: Money.paisa(doc.read<int>('balance_paisa')),
      change: Money.paisa(
        payments.fold(0, (sum, p) => sum + p.read<int>('change_paisa')),
      ),
      footerLines: const ['Shukriya! Phir tashreef laayen'],
    );
  }

  @override
  Future<List<({String id, String code, String name, int decimals})>> units(
    String firmId,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT id, code, name_en, decimals FROM units '
          'WHERE firm_id = ? AND deleted_at_utc IS NULL AND is_active = 1 '
          'ORDER BY is_base DESC, code',
          variables: [Variable<String>(firmId)],
        )
        .get();
    return [
      for (final r in rows)
        (
          id: r.read<String>('id'),
          code: r.read<String>('code'),
          name: r.read<String>('name_en'),
          decimals: r.read<int>('decimals'),
        ),
    ];
  }

  @override
  Future<List<ItemSummary>> lowStockItems(
    String firmId, {
    int limit = 50,
  }) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT i.*, u.code AS unit_code, u.decimals AS unit_decimals,
                 COALESCE((
                   SELECT SUM(sl.qty_delta_thousandths)
                   FROM stock_ledger sl
                   WHERE sl.item_id = i.id AND sl.deleted_at_utc IS NULL
                 ), 0) AS stock_thousandths
          FROM items i
          JOIN units u ON u.id = i.base_unit_id
          WHERE i.firm_id = ?
            AND i.deleted_at_utc IS NULL
            AND i.is_active = 1
            AND i.track_stock = 1
            -- Only where the shop has set a floor. Defaulting to zero would
            -- turn every item that has ever sold out into a permanent alert,
            -- and a list that is always full is a list nobody reads.
            AND i.min_stock_thousandths > 0
            AND stock_thousandths <= i.min_stock_thousandths
          -- Worst first: how far below the floor, as a fraction of it, so a
          -- staple that is 90% gone outranks a slow-moving line that is one
          -- unit short. Ordering by the raw shortfall would put a 500-piece
          -- line that is ten short above a 2-piece line nearly out.
          --
          -- Both operands are INTEGER columns, so this is SQLite's integer
          -- division and there is no floating point in it anywhere. The
          -- result is a truncated per-mille used as a sort key, never a
          -- number anyone is shown.
          ORDER BY (stock_thousandths * 1000) -- arch_check: allow no_floating_point_money — integer sort key
                     / i.min_stock_thousandths,
                   i.name_search
          LIMIT ?
          ''',
          variables: [Variable<String>(firmId), Variable<int>(limit)],
        )
        .get();
    return [for (final r in rows) _itemFrom(r)];
  }

  @override
  Future<List<StockMovement>> stockMovements(
    String firmId,
    String itemId, {
    String? afterId,
    int limit = 50,
  }) async {
    // Keyset, not OFFSET. The cursor is the (occurred_at_utc, id) pair of the
    // last row shown, which is the tail of `idx_stock_position` — so page
    // fifty costs what page one costs. An OFFSET would get slower the further
    // back a shopkeeper scrolled, and the interesting rows in a stock history
    // are usually the old ones.
    //
    // The tuple comparison is spelled out rather than written as a row value.
    // SQLite accepts `(a, b) < (?, ?)` but does not reliably use an index for
    // it, and using the index is the entire point of this shape.
    const cursor =
        ' AND (sl.occurred_at_utc < (SELECT occurred_at_utc FROM stock_ledger'
        ' WHERE id = ?)'
        ' OR (sl.occurred_at_utc = (SELECT occurred_at_utc FROM stock_ledger'
        ' WHERE id = ?) AND sl.id < ?))';

    final rows = await _db
        .customSelect(
          'SELECT sl.id, sl.txn_type, sl.qty_delta_thousandths, '
          'sl.occurred_on_local, sl.balance_after_thousandths, sl.reason, '
          'd.doc_no '
          'FROM stock_ledger sl '
          'LEFT JOIN documents d ON d.id = sl.document_id '
          'WHERE sl.firm_id = ? AND sl.item_id = ? '
          // The stock ledger is append-only and TxRunner refuses to tombstone
          // a row in it, so this should never exclude anything. It is here
          // because a history that quietly dropped a movement would be worse
          // than one that showed a strange one.
          'AND sl.deleted_at_utc IS NULL'
          '${afterId == null ? '' : cursor} '
          'ORDER BY sl.occurred_at_utc DESC, sl.id DESC '
          'LIMIT ?',
          variables: [
            Variable<String>(firmId),
            Variable<String>(itemId),
            if (afterId != null) ...[
              Variable<String>(afterId),
              Variable<String>(afterId),
              Variable<String>(afterId),
            ],
            Variable<int>(limit),
          ],
        )
        .get();

    return [
      for (final r in rows)
        StockMovement(
          id: r.read<String>('id'),
          txnType: r.read<String>('txn_type'),
          qtyDelta: Qty.raw(r.read<int>('qty_delta_thousandths')),
          occurredOnLocal: r.read<String>('occurred_on_local'),
          balanceAfter: switch (r.readNullable<int>(
            'balance_after_thousandths',
          )) {
            final int t => Qty.raw(t),
            null => null,
          },
          docNo: r.readNullable<String>('doc_no'),
          reason: r.readNullable<String>('reason'),
        ),
    ];
  }

  @override
  Future<StockSummary> stockSummary(String firmId) async {
    // One pass. The per-item balance is a correlated SUM over the append-only
    // ledger, which `idx_stock_position` serves, and everything else is
    // counted from that in the outer query. Nothing is fetched into Dart to be
    // added up — the largest cluster of crash reports against the nearest
    // competitor is reports on catalogues of a few thousand items, and that is
    // the cause every time.
    //
    // The value is accumulated in MILLI-PAISA and converted once, in Dart,
    // through the project's own rounding. Two reasons. Dividing per row would
    // truncate up to a paisa per item, which on a 20,000-SKU catalogue is a
    // stock valuation wrong by two hundred rupees. And multiplying without
    // scaling down first (thousandths x milli-paisa) reaches 1e18 on a large
    // shop, which is close enough to the int64 ceiling to be a real risk
    // rather than a theoretical one.
    final row = await _db
        .customSelect(
          '''
          SELECT
            COUNT(*) AS tracked,
            COALESCE(SUM(
              CASE WHEN stock_thousandths <> 0
                   -- Both operands are INTEGER columns, so SQLite performs
              -- integer division and there is no floating point anywhere in
              -- it. The result is milli-paisa, converted to paisa once in
              -- Dart with the project's own half-up rounding. Scaling here
              -- rather than after the SUM keeps the running total four orders
              -- of magnitude below the int64 ceiling on a large shop.
              THEN stock_thousandths * i.avg_cost_milli_paisa / 1000 -- arch_check: allow no_floating_point_money — integer scaling
                   ELSE 0 END
            ), 0) AS value_milli_paisa,
            COALESCE(SUM(CASE
              WHEN stock_thousandths > 0
               AND i.min_stock_thousandths > 0
               AND stock_thousandths <= i.min_stock_thousandths
              THEN 1 ELSE 0 END), 0) AS low_count,
            COALESCE(SUM(CASE WHEN stock_thousandths = 0
                              THEN 1 ELSE 0 END), 0) AS out_count,
            COALESCE(SUM(CASE WHEN stock_thousandths < 0
                              THEN 1 ELSE 0 END), 0) AS negative_count
          FROM (
            SELECT i.id, i.min_stock_thousandths, i.avg_cost_milli_paisa,
                   COALESCE((
                     SELECT SUM(sl.qty_delta_thousandths)
                     FROM stock_ledger sl
                     WHERE sl.item_id = i.id AND sl.deleted_at_utc IS NULL
                   ), 0) AS stock_thousandths
            FROM items i
            WHERE i.firm_id = ?
              AND i.deleted_at_utc IS NULL
              AND i.is_active = 1
              -- A service has no shelf, so counting it as "out of stock"
              -- would put every tailoring charge in the shop on an alert
              -- list, and an alert list that is always full is a list nobody
              -- reads.
              AND i.track_stock = 1
          ) AS i
          ''',
          variables: [Variable<String>(firmId)],
        )
        .getSingle();

    return StockSummary(
      trackedItems: row.read<int>('tracked'),
      // Half-up, once, through the same rounding policy every other figure in
      // the application uses.
      stockValue: Money.paisa(
        divideRounded(
          row.read<int>('value_milli_paisa'),
          1000,
          RoundingMode.halfUp,
        ),
      ),
      lowCount: row.read<int>('low_count'),
      outCount: row.read<int>('out_count'),
      negativeCount: row.read<int>('negative_count'),
    );
  }

  @override
  Future<List<UnitEdge>> unitConversions(String firmId) async {
    final rows = await _db
        .customSelect(
          'SELECT from_unit_id, to_unit_id, factor_thousandths, item_id '
          'FROM unit_conversions '
          'WHERE firm_id = ? AND deleted_at_utc IS NULL',
          variables: [Variable<String>(firmId)],
        )
        .get();
    return [
      for (final r in rows)
        UnitEdge(
          fromUnitId: r.read<String>('from_unit_id'),
          toUnitId: r.read<String>('to_unit_id'),
          factorThousandths: r.read<int>('factor_thousandths'),
          itemId: r.readNullable<String>('item_id'),
        ),
    ];
  }

  static ItemSummary _itemFrom(QueryRow r) => ItemSummary(
    id: r.read<String>('id'),
    name: r.read<String>('name'),
    code: _blankToNull(r.readNullable<String>('code')),
    barcode: _blankToNull(r.readNullable<String>('barcode')),
    category: _blankToNull(r.readNullable<String>('category')),
    description: _blankToNull(r.readNullable<String>('description')),
    purchaseRate: _rateOrNull(r, 'purchase_rate_milli_paisa'),
    wholesaleRate: _rateOrNull(r, 'wholesale_rate_milli_paisa'),
    mrp: _moneyOrNull(r, 'mrp_paisa'),
    hsCode: _blankToNull(r.readNullable<String>('hs_code')),
    unitId: r.read<String>('base_unit_id'),
    unitCode: r.read<String>('unit_code'),
    unitDecimals: r.read<int>('unit_decimals'),
    saleRate: Rate.raw(r.read<int>('sale_rate_milli_paisa')),
    stockOnHand: Qty.raw(r.read<int>('stock_thousandths')),
    minStock: Qty.raw(r.read<int>('min_stock_thousandths')),
    tracksStock: r.read<int>('track_stock') == 1,
  );

  /// Null stays null rather than becoming zero.
  ///
  /// A wholesale price of nothing and no wholesale price at all are different
  /// facts, and the editor has to be able to tell them apart or it will show
  /// a shopkeeper a price of Rs 0.00 they never typed.
  static Rate? _rateOrNull(QueryRow r, String column) {
    final raw = r.readNullable<int>(column);
    return raw == null ? null : Rate.raw(raw);
  }

  static Money? _moneyOrNull(QueryRow r, String column) {
    final raw = r.readNullable<int>(column);
    return raw == null ? null : Money.paisa(raw);
  }

  /// Lowercased, punctuation-stripped, space-collapsed.
  ///
  /// The same transformation `items.name_search` is stored with, so a search
  /// for "cooking oil" finds "Cooking Oil 5L" and a search for "dalda" finds
  /// it too.
  static String _normalise(String raw) => raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String? _blankToNull(String? s) =>
      s == null || s.trim().isEmpty ? null : s;

  static String _modeLabel(String mode) => switch (mode) {
    'cash' => 'Cash',
    'bank_transfer' => 'Bank Transfer',
    'jazzcash' => 'JazzCash',
    'easypaisa' => 'EasyPaisa',
    'raast' => 'Raast',
    'card' => 'Card',
    'cheque' => 'Cheque',
    _ => 'Adjustment',
  };

  static String _dateTimeLabel(int millisUtc) {
    final local = DateTime.fromMillisecondsSinceEpoch(
      millisUtc,
      isUtc: true,
    ).add(pakistanStandardTime);
    final d = '${_two(local.day)}-${_two(local.month)}-${local.year}';
    return '$d  ${_clockLabel(local)}';
  }

  static String _timeLabel(int millisUtc) => _clockLabel(
    DateTime.fromMillisecondsSinceEpoch(
      millisUtc,
      isUtc: true,
    ).add(pakistanStandardTime),
  );

  static String _clockLabel(DateTime local) {
    final hour24 = local.hour;
    final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final suffix = hour24 < 12 ? 'AM' : 'PM';
    return '$hour:${_two(local.minute)} $suffix';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
