import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';
import '../write/drift_catalogue_writer.dart'
    show partyRemarksKey, partyRemarksKeyPrefix;
import '../write/drift_cheque_writer.dart'
    show
        chequeInHandFrom,
        chequeInHandSelect,
        chequeIssuedFrom,
        chequeIssuedSelect;
import '../write/drift_day_close_writer.dart' show cashInDrawerSql;
import '../write/drift_purchase_return_writer.dart'
    show boughtLineFrom, returnedOffDeliveryLine;
import '../write/drift_return_writer.dart' show soldLineFrom, soldLinesSql;
import '../write/drift_van_writer.dart' show vanCashSql, vanStockSql;
import 'spelling_search.dart';

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
  const DriftAppQueries(this._db, {this.activeFirmId, this.madeWith});

  final AppDatabase _db;

  /// The firm the phone has open, when it keeps more than one. Without it,
  /// the current firm is the first one set up.
  final String? Function()? activeFirmId;

  /// Whether a bill carries the line saying what made it: the free plan's
  /// (M21). Asked as each receipt is read, so a plan bought mid-day shows
  /// on the next bill.
  final bool Function()? madeWith;

  @override
  Future<FirmProfile?> currentFirm() => _firm(activeFirmId?.call());

  @override
  Future<List<FirmProfile>> firms() async {
    final rows = await _db
        .customSelect(
          'SELECT id FROM firms WHERE deleted_at_utc IS NULL '
          'ORDER BY created_at_utc',
          readsFrom: {_db.firms},
        )
        .get();
    return [for (final r in rows) ?await _firm(r.read<String>('id'))];
  }

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
      pricesIncludeTax: row.read<int>('prices_include_tax') == 1,
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
    final typed = SpellingQuery.of(query);
    if (!typed.isEmpty) {
      return _searchItemsBySpelling(firmId, typed, afterId, limit);
    }
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
            AND (? IS NULL OR i.id > ?)
          -- Ordered by id, which is what the cursor pages on. Ordering by
          -- name while paginating on id silently drops and repeats rows on
          -- page two, and a 20,000-SKU catalogue is exactly where nobody
          -- would notice. ULIDs sort by creation, so this is "most recently
          -- stocked last" — the browse. A search is ranked; see below.
          ORDER BY i.id
          LIMIT ?
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(afterId),
            Variable<String>(afterId),
            Variable<int>(limit),
          ],
        )
        .get();
    return [for (final r in rows) _itemFrom(r)];
  }

  /// A search, however it was spelled (M56), best matches first.
  ///
  /// Ranked rather than ordered by id, so the cursor is the pair (rank, id)
  /// of the last row shown, and the rank of that row is worked out again
  /// from the row itself. Only the page's ids are joined back to their
  /// stock, so the stock subquery runs forty times, not once per match.
  Future<List<ItemSummary>> _searchItemsBySpelling(
    String firmId,
    SpellingQuery typed,
    String? afterId,
    int limit,
  ) async {
    final search = SpellingSearch(
      typed,
      column: 'i.name_search',
      exactColumns: const ['i.code', 'i.barcode'],
    );
    final rows = await _db
        .customSelect(
          '''
          WITH hits AS (
            SELECT i.id AS id, ${search.rank} AS rnk
            FROM items i
            WHERE i.firm_id = ?
              -- The name first: it is near the front of the row, and on a
              -- row it rules out, the flags at the back are never read.
              AND ${search.where}
              AND i.is_active = 1
              AND i.deleted_at_utc IS NULL
          ),
          after_row AS (
            SELECT ${search.rank} AS rnk FROM items i WHERE i.id = ?
          ),
          page AS (
            SELECT h.id, h.rnk FROM hits h
            WHERE ? IS NULL
               OR h.rnk > (SELECT rnk FROM after_row)
               OR (h.rnk = (SELECT rnk FROM after_row) AND h.id > ?)
            ORDER BY h.rnk, h.id
            LIMIT ?
          )
          SELECT i.*, u.code AS unit_code, u.decimals AS unit_decimals,
                 COALESCE((
                   SELECT SUM(sl.qty_delta_thousandths)
                   FROM stock_ledger sl
                   WHERE sl.item_id = i.id AND sl.deleted_at_utc IS NULL
                 ), 0) AS stock_thousandths
          FROM page
          JOIN items i ON i.id = page.id
          JOIN units u ON u.id = i.base_unit_id
          ORDER BY page.rnk, page.id
          ''',
          variables: [
            ...search.rankVariables,
            Variable<String>(firmId),
            ...search.whereVariables,
            ...search.rankVariables,
            Variable<String>(afterId),
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
  Future<ItemSummary?> itemByCode(String firmId, String code) async {
    final wanted = code.trim().replaceFirst(RegExp('^0+(?=.)'), '');
    if (wanted.isEmpty) return null;
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
          WHERE i.firm_id = ? AND i.deleted_at_utc IS NULL AND i.is_active = 1
            AND (i.code = ? OR LTRIM(i.code, '0') = ?)
          -- The code exactly as keyed wins over one equal only without its
          -- leading zeros.
          ORDER BY i.code = ? DESC
          LIMIT 1
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(code.trim()),
            Variable<String>(wanted),
            Variable<String>(code.trim()),
          ],
        )
        .get();
    return rows.isEmpty ? null : _itemFrom(rows.single);
  }

  @override
  Future<List<BomView>> boms(String firmId) async {
    final heads = await _db
        .customSelect(
          '''
          SELECT b.id, b.name, b.output_item_id, b.output_qty_thousandths,
                 b.overhead_paisa, i.name AS output_name,
                 u.code AS output_unit
          FROM boms b
          JOIN items i ON i.id = b.output_item_id
          JOIN units u ON u.id = i.base_unit_id
          WHERE b.firm_id = ? AND b.deleted_at_utc IS NULL
          ORDER BY b.name COLLATE NOCASE
          ''',
          variables: [Variable<String>(firmId)],
        )
        .get();
    final lines = await _db
        .customSelect(
          '''
          SELECT l.bom_id, l.component_item_id, l.qty_thousandths,
                 i.name AS component_name
          FROM bom_lines l
          JOIN items i ON i.id = l.component_item_id
          WHERE l.firm_id = ? AND l.deleted_at_utc IS NULL
          ORDER BY l.bom_id, l.line_no
          ''',
          variables: [Variable<String>(firmId)],
        )
        .get();
    return [
      for (final h in heads)
        () {
          final mine = lines
              .where((l) => l.read<String>('bom_id') == h.read<String>('id'))
              .toList();
          return BomView(
            id: h.read<String>('id'),
            outputName: h.read<String>('output_name'),
            outputUnitCode: h.read<String>('output_unit'),
            componentNames: {
              for (final l in mine)
                l.read<String>('component_item_id'): l.read<String>(
                  'component_name',
                ),
            },
            draft: BomDraft(
              name: h.read<String>('name'),
              outputItemId: h.read<String>('output_item_id'),
              outputQty: Qty.raw(h.read<int>('output_qty_thousandths')),
              overhead: Money.paisa(h.read<int>('overhead_paisa')),
              lines: [
                for (final l in mine)
                  BomLineDraft(
                    itemId: l.read<String>('component_item_id'),
                    qty: Qty.raw(l.read<int>('qty_thousandths')),
                  ),
              ],
            ),
          );
        }(),
    ];
  }

  @override
  Future<List<VanView>> vans(String firmId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT v.id, v.name, v.location_code, v.rider_user_id,
                 u.name AS rider_name
          FROM vans v LEFT JOIN users u ON u.id = v.rider_user_id
          WHERE v.firm_id = ? AND v.deleted_at_utc IS NULL AND v.is_active = 1
          ORDER BY v.name COLLATE NOCASE
          ''',
          variables: [Variable<String>(firmId)],
        )
        .get();
    return [
      for (final r in rows)
        VanView(
          id: r.read<String>('id'),
          name: r.read<String>('name'),
          locationCode: r.read<String>('location_code'),
          riderUserId: r.readNullable<String>('rider_user_id'),
          riderName: r.readNullable<String>('rider_name'),
        ),
    ];
  }

  @override
  Future<VanDay> vanDay(String firmId, String vanId, BusinessDate day) async {
    final van = await _db
        .customSelect(
          'SELECT location_code FROM vans WHERE id = ? AND firm_id = ?',
          variables: [Variable<String>(vanId), Variable<String>(firmId)],
        )
        .getSingleOrNull();
    if (van == null) {
      return const VanDay(salesCount: 0, expectedCash: Money.zero, stock: []);
    }
    final location = van.read<String>('location_code');
    final cash = await _db
        .customSelect(
          vanCashSql,
          variables: [
            Variable<String>(firmId),
            Variable<String>(location),
            Variable<String>(day.value),
          ],
        )
        .getSingle();
    final stock = await _db
        .customSelect(
          vanStockSql,
          variables: [Variable<String>(firmId), Variable<String>(location)],
        )
        .get();
    final settled = await _db
        .customSelect(
          'SELECT cash_expected_paisa, cash_counted_paisa, '
          'lines_returned_count FROM van_settlements '
          'WHERE firm_id = ? AND van_id = ? AND settled_on_local = ? '
          'AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(firmId),
            Variable<String>(vanId),
            Variable<String>(day.value),
          ],
        )
        .getSingleOrNull();
    return VanDay(
      salesCount: cash.read<int>('sales'),
      expectedCash: Money.paisa(cash.read<int>('cash')),
      stock: [
        for (final r in stock)
          (
            itemId: r.read<String>('item_id'),
            name: r.read<String>('name'),
            unitCode: r.read<String>('unit_code'),
            qty: Qty.raw(r.read<int>('q')),
          ),
      ],
      settled: settled == null
          ? null
          : VanSettlementView(
              date: day,
              expected: Money.paisa(settled.read<int>('cash_expected_paisa')),
              counted: Money.paisa(settled.read<int>('cash_counted_paisa')),
              linesReturned: settled.read<int>('lines_returned_count'),
            ),
    );
  }

  @override
  Future<List<PartySummary>> searchParties(
    String firmId, {
    String query = '',
    int limit = 40,
  }) async {
    final typed = SpellingQuery.of(query);
    if (typed.isEmpty) {
      final rows = await _db
          .customSelect(
            '''
            $_partySelect
            WHERE p.firm_id = ?
              AND p.deleted_at_utc IS NULL
              AND p.is_active = 1
            ORDER BY p.name_search
            LIMIT ?
            ''',
            variables: [Variable<String>(firmId), Variable<int>(limit)],
          )
          .get();
      return [for (final r in rows) _party(r)];
    }
    // However the name was spelled (M56), best matches first; then by name,
    // which `name_search` sorts by because its plain half comes first.
    final search = SpellingSearch(
      typed,
      column: 'p.name_search',
      containsColumns: const ['p.phone'],
    );
    final rows = await _db
        .customSelect(
          '''
          WITH hits AS (
            SELECT p.id AS id, ${search.rank} AS rnk, p.name_search AS sort
            FROM parties p
            WHERE p.firm_id = ?
              AND ${search.where}
              AND p.deleted_at_utc IS NULL
              AND p.is_active = 1
            ORDER BY rnk, sort
            LIMIT ?
          )
          $_partySelect
          JOIN hits h ON h.id = p.id
          ORDER BY h.rnk, h.sort
          ''',
          variables: [
            ...search.rankVariables,
            Variable<String>(firmId),
            ...search.whereVariables,
            Variable<int>(limit),
          ],
        )
        .get();
    return [for (final r in rows) _party(r)];
  }

  /// What a customer owes, in one place.
  ///
  /// Two expressions for this would be two answers to the shop's only
  /// question, and the one on screen would eventually disagree with the one
  /// the credit limit is checked against.
  static const _partySelect =
      '''
    SELECT p.id, p.name, p.phone, p.party_type, p.credit_limit_paisa,
           p.price_tier, p.default_discount_bp, p.party_group,
           -- What the counter is told about them (M40), kept in settings
           -- under their id. One lookup on idx_settings_key per party.
           (SELECT s.setting_value FROM settings s
             WHERE s.firm_id = p.firm_id
               AND s.setting_key = '$partyRemarksKeyPrefix' || p.id
               AND s.deleted_at_utc IS NULL) AS remarks,
           p.opening_balance_paisa
             + COALESCE((
                 SELECT SUM(d.balance_paisa) FROM documents d
                 WHERE d.party_id = p.id
                   AND d.firm_id = p.firm_id
                   AND d.doc_type IN ('sale_invoice', 'other_income')
                   AND d.status = 'posted'
                   AND d.deleted_at_utc IS NULL
               ), 0)
             -- Money the shop is holding for them comes off what they owe.
             -- Without this a customer who paid Rs 5,000 against Rs 3,000 of
             -- bills reads as settled, and the Rs 2,000 the shop owes them is
             -- invisible in the one place anybody would look for it.
             --
             -- Read from the ledger rather than a cached column, because the
             -- ledger is what the advance actually is. Rides idx_jl_party.
             - COALESCE((
                 SELECT SUM(jl.credit_paisa - jl.debit_paisa)
                 FROM journal_lines jl
                 JOIN accounts a ON a.id = jl.account_id
                 WHERE jl.party_id = p.id
                   AND jl.firm_id = p.firm_id
                   AND a.system_key = 'customer_advances'
                   AND jl.deleted_at_utc IS NULL
               ), 0) AS balance_paisa,
           -- What the shop owes them, as its own figure and never netted
           -- against the above: the two debts are settled separately, each
           -- against its own bills.
           COALESCE((
               SELECT SUM(d.balance_paisa) FROM documents d
               WHERE d.party_id = p.id
                 AND d.firm_id = p.firm_id
                 AND d.doc_type IN ('purchase_bill', 'expense')
                 AND d.status = 'posted'
                 AND d.deleted_at_utc IS NULL
             ), 0) AS payable_paisa,
           -- Cheques of theirs the bank sent back. A customer whose cheque
           -- bounced and who still owes is one the counter asks about before
           -- giving more credit.
           (SELECT COUNT(*) FROM payments pm
             WHERE pm.party_id = p.id
               AND pm.firm_id = p.firm_id
               AND pm.mode = 'cheque'
               AND pm.direction = 'in'
               AND pm.status = 'bounced'
               AND pm.deleted_at_utc IS NULL) AS bounced_cheques
    FROM parties p
''';

  static PartySummary _party(QueryRow r) => PartySummary(
    id: r.read<String>('id'),
    name: r.read<String>('name'),
    phone: _blankToNull(r.readNullable<String>('phone')),
    partyType: r.read<String>('party_type'),
    balance: Money.paisa(r.read<int>('balance_paisa')),
    payable: Money.paisa(r.read<int>('payable_paisa')),
    bouncedCheques: r.read<int>('bounced_cheques'),
    priceTier: PriceTier.parse(r.read<String>('price_tier')),
    defaultDiscountBp: r.read<int>('default_discount_bp'),
    creditLimit: r.readNullable<int>('credit_limit_paisa') == null
        ? null
        : Money.paisa(r.read<int>('credit_limit_paisa')),
    group: _blankToNull(r.readNullable<String>('party_group')),
    remarks: _blankToNull(r.readNullable<String>('remarks'))?.trim(),
  );

  @override
  Future<List<LedgerEntry>> partyLedger(
    String firmId,
    String partyId, {
    int limit = 200,
  }) async {
    // One UNION rather than two queries stitched in Dart, so the ordering is
    // the database's and a bill and a payment on the same day cannot end up
    // in different relative orders on two different screens.
    //
    // Ordered oldest first because the running balance is computed forwards.
    // The screen reverses it to show the newest at the top, which is what a
    // shopkeeper looking for last week's payment wants.
    final rows = await _db
        .customSelect(
          '''
          SELECT id, kind, reference, date_local, amount_paisa FROM (
            -- Bills, and charges put on the khata with no sale behind
            -- them, which carry their reason so the customer can be told.
            SELECT d.id AS id,
                   CASE d.doc_type WHEN 'other_income' THEN 'charge'
                        ELSE 'sale' END AS kind,
                   CASE d.doc_type WHEN 'other_income'
                        THEN d.doc_no || ' · ' || COALESCE(d.notes, '')
                        ELSE d.doc_no END AS reference,
                   d.doc_date_local AS date_local,
                   d.total_paisa AS amount_paisa,
                   d.created_at_utc AS recorded
            FROM documents d
            WHERE d.firm_id = ? AND d.party_id = ?
              AND d.doc_type IN ('sale_invoice', 'other_income')
              AND d.status NOT IN ('void', 'draft')
              AND d.deleted_at_utc IS NULL

            UNION ALL

            -- Goods the customer brought back (found by M33's statement,
            -- put right here in M38). A return takes what it was worth off
            -- what they owe — off its bill, or kept for them as an advance
            -- — and a history without it ran ahead of the balance above it
            -- by exactly the return. What was handed back over the counter
            -- there and then moved nothing on the khata, so only the rest
            -- is a line: the total less the refund, the same figure the
            -- party statement lists.
            SELECT d.id AS id,
                   'return' AS kind,
                   d.doc_no AS reference,
                   d.doc_date_local AS date_local,
                   -(d.total_paisa - d.paid_paisa) AS amount_paisa,
                   d.created_at_utc AS recorded
            FROM documents d
            WHERE d.firm_id = ? AND d.party_id = ?
              AND d.doc_type = 'sale_return'
              AND d.status NOT IN ('void', 'draft')
              AND d.deleted_at_utc IS NULL
              AND d.total_paisa <> d.paid_paisa

            UNION ALL

            SELECT p.id AS id,
                   'payment' AS kind,
                   p.payment_no AS reference,
                   p.payment_date_local AS date_local,
                   -p.amount_paisa AS amount_paisa,
                   p.created_at_utc AS recorded
            FROM payments p
            WHERE p.firm_id = ? AND p.party_id = ?
              AND p.direction = 'in'
              AND p.status <> 'void'
              AND p.deleted_at_utc IS NULL

            UNION ALL

            -- A cheque that bounced. The payment above stays on the khata as
            -- what happened, and this puts the money back as what happened
            -- next, on the day it happened; the two together net to nothing.
            -- Dropping the payment instead would leave the customer asking
            -- where the cheque they remember handing over has gone.
            SELECT je.id AS id,
                   'bounce' AS kind,
                   p.payment_no AS reference,
                   je.entry_date_local AS date_local,
                   p.amount_paisa AS amount_paisa,
                   je.created_at_utc AS recorded
            FROM journal_entries je
            JOIN payments p ON p.id = je.payment_id
            WHERE p.firm_id = ? AND p.party_id = ?
              AND p.direction = 'in'
              AND p.status = 'bounced'
              AND je.source_type = 'reversal'
              AND je.deleted_at_utc IS NULL

            UNION ALL

            -- What they owed when the shop started keeping them here (M24).
            -- Left out until now, so the khata's running balance was short
            -- by exactly the opening for every customer entered with one,
            -- and never matched the balance shown above it.
            SELECT pa.id AS id,
                   'opening' AS kind,
                   'Opening balance' AS reference,
                   -- Set whenever a party is saved with an opening; a row
                   -- from before that falls back to its first document.
                   COALESCE(pa.opening_balance_as_of_local,
                            (SELECT MIN(d0.doc_date_local) FROM documents d0
                             WHERE d0.party_id = pa.id),
                            '2000-01-01') AS date_local,
                   pa.opening_balance_paisa AS amount_paisa,
                   pa.created_at_utc AS recorded
            FROM parties pa
            WHERE pa.firm_id = ? AND pa.id = ?
              AND pa.opening_balance_paisa <> 0
              AND pa.deleted_at_utc IS NULL
          )
          -- Within a day, in the order things were recorded. Sorting by a
          -- per-type sequence put every payment ahead of the bill it paid on
          -- the same day, so the running balance showed the customer in
          -- credit for one line before the bill caught up.
          ORDER BY date_local, recorded, id
          LIMIT ?
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(partyId),
            Variable<String>(firmId),
            Variable<String>(partyId),
            Variable<String>(firmId),
            Variable<String>(partyId),
            Variable<String>(firmId),
            Variable<String>(partyId),
            Variable<String>(firmId),
            Variable<String>(partyId),
            Variable<int>(limit),
          ],
          readsFrom: {
            _db.documents,
            _db.payments,
            _db.journalEntries,
            _db.parties,
          },
        )
        .get();

    // The running balance is computed here, never stored. A cached one is
    // wrong the moment a backdated bill is entered, which happens in every
    // shop that does its paperwork on Sundays.
    var running = Money.zero;
    return [
      for (final r in rows)
        () {
          final amount = Money.paisa(r.read<int>('amount_paisa'));
          running += amount;
          return LedgerEntry(
            id: r.read<String>('id'),
            kind: r.read<String>('kind'),
            reference: r.read<String>('reference'),
            dateLocal: r.read<String>('date_local'),
            amount: amount,
            balanceAfter: running,
          );
        }(),
    ];
  }

  @override
  Future<List<LedgerEntry>> payablesLedger(
    String firmId,
    String partyId, {
    int limit = 200,
  }) async {
    // The supplier side of [partyLedger], shaped the same way for the same
    // reasons: one UNION so the database decides the order, oldest first so
    // the running figure is computed forwards, never stored.
    //
    // Positive is what the shop took on — a delivery, an expense left on
    // account. Negative is money the shop paid them.
    final rows = await _db
        .customSelect(
          '''
          SELECT id, kind, reference, date_local, amount_paisa FROM (
            SELECT d.id AS id,
                   CASE d.doc_type WHEN 'expense' THEN 'expense'
                                   WHEN 'purchase_return' THEN 'return'
                                   ELSE 'purchase' END AS kind,
                   d.doc_no AS reference,
                   d.doc_date_local AS date_local,
                   -- What went onto the account, read off the payable line
                   -- the bill posted, not its total: a delivery half-paid at
                   -- the door put only the other half on the supplier's
                   -- khata, and `paid_paisa` has since moved with every
                   -- payment against it.
                   COALESCE((
                     SELECT SUM(jl.credit_paisa - jl.debit_paisa)
                     FROM journal_entries je
                     JOIN journal_lines jl ON jl.journal_entry_id = je.id
                     JOIN accounts a ON a.id = jl.account_id
                     WHERE je.document_id = d.id
                       AND a.system_key = 'accounts_payable'
                   ), 0) AS amount_paisa,
                   d.doc_seq AS seq
            FROM documents d
            WHERE d.firm_id = ? AND d.party_id = ?
              AND d.doc_type IN ('purchase_bill', 'expense', 'purchase_return')
              AND d.status NOT IN ('void', 'draft')
              AND d.deleted_at_utc IS NULL

            UNION ALL

            SELECT p.id AS id,
                   'payment' AS kind,
                   p.payment_no AS reference,
                   p.payment_date_local AS date_local,
                   -p.amount_paisa AS amount_paisa,
                   0 AS seq
            FROM payments p
            WHERE p.firm_id = ? AND p.party_id = ?
              AND p.direction = 'out'
              AND p.status <> 'void'
              AND p.deleted_at_utc IS NULL
          )
          WHERE amount_paisa <> 0
          ORDER BY date_local, seq, id
          LIMIT ?
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(partyId),
            Variable<String>(firmId),
            Variable<String>(partyId),
            Variable<int>(limit),
          ],
          readsFrom: {
            _db.documents,
            _db.payments,
            _db.journalEntries,
            _db.journalLines,
            _db.accounts,
          },
        )
        .get();

    var running = Money.zero;
    return [
      for (final r in rows)
        () {
          final amount = Money.paisa(r.read<int>('amount_paisa'));
          running += amount;
          return LedgerEntry(
            id: r.read<String>('id'),
            kind: r.read<String>('kind'),
            reference: r.read<String>('reference'),
            dateLocal: r.read<String>('date_local'),
            amount: amount,
            balanceAfter: running,
          );
        }(),
    ];
  }

  @override
  Future<Aging> aging(String firmId, {required String asOfDateLocal}) async {
    // Bucketed in SQL rather than by pulling every open bill into Dart. A
    // wholesaler with three years of udhaar has tens of thousands, and the
    // shopkeeper is looking at a summary card.
    //
    // julianday on the local business date, never on an epoch: PKT is UTC+5
    // with no daylight saving, so a bill raised at eight in the evening would
    // be a day older under UTC arithmetic — and 90 versus 91 days is exactly
    // where an ageing report starts arguments.
    //
    // Rides idx_documents_open_balance.
    final rows = await _db
        .customSelect(
          '''
          SELECT
            CAST(julianday(?) - julianday(d.doc_date_local) AS INTEGER) AS days,
            SUM(d.balance_paisa) AS owed
          FROM documents d
          WHERE d.firm_id = ?
            -- Udhaar is what customers owe. Without this, every delivery
            -- the shop has not finished paying for aged here as though a
            -- customer owed it, and the 90-day bucket filled with the
            -- shop's own debts.
            AND d.doc_type IN ('sale_invoice', 'other_income')
            AND d.balance_paisa > 0
            AND d.party_id IS NOT NULL
            AND d.status NOT IN ('void', 'draft')
            AND d.deleted_at_utc IS NULL
          GROUP BY days
          ''',
          variables: [
            Variable<String>(asOfDateLocal),
            Variable<String>(firmId),
          ],
          readsFrom: {_db.documents},
        )
        .get();

    return ageBills([
      for (final r in rows)
        AgedBill(
          documentId: '',
          days: r.read<int>('days'),
          outstanding: Money.paisa(r.read<int>('owed')),
        ),
    ]);
  }

  @override
  Future<List<AgedParty>> partiesToChase(
    String firmId, {
    required String asOfDateLocal,
    int limit = 100,
  }) async {
    // Ordered by the age of the oldest debt, not by size of balance. The
    // customer who owes Rs 3,000 since March is a different conversation from
    // the one who owes Rs 40,000 since last week, and a list sorted by amount
    // puts the second one first every time.
    final rows = await _db
        .customSelect(
          '''
          SELECT p.id,
                 MIN(d.doc_date_local) AS oldest,
                 COUNT(*) AS open_bills
          FROM documents d
          JOIN parties p ON p.id = d.party_id
          WHERE d.firm_id = ?
            -- Sale invoices only, or a party the shop also buys from is
            -- chased from the date of a delivery the shop owes on.
            AND d.doc_type IN ('sale_invoice', 'other_income')
            AND d.balance_paisa > 0
            AND d.status NOT IN ('void', 'draft')
            AND d.deleted_at_utc IS NULL
            AND p.deleted_at_utc IS NULL
            AND p.is_active = 1
          GROUP BY p.id
          ORDER BY oldest
          LIMIT ?
          ''',
          variables: [Variable<String>(firmId), Variable<int>(limit)],
          readsFrom: {_db.documents, _db.parties},
        )
        .get();

    final chase = <AgedParty>[];
    for (final row in rows) {
      // Through partyById so the balance is the one expression the whole app
      // uses — advances subtracted included. A customer who has paid on
      // account may owe on a bill and be in credit overall, and the chase
      // list must not go and knock on their door.
      final party = await partyById(firmId, row.read<String>('id'));
      if (party == null || !party.balance.isPositive) continue;

      final oldest = row.read<String>('oldest');
      chase.add(
        AgedParty(
          party: party,
          oldestDays: daysBetween(oldest, asOfDateLocal),
          oldestDateLocal: oldest,
          openBills: row.read<int>('open_bills'),
        ),
      );
    }
    return chase;
  }

  @override
  Future<List<SoldLine>> returnableLines(
    String firmId,
    String documentId,
  ) async {
    // Deliberately the same query as `DriftReturnWriter.billFor`, as one
    // shared string, down to the subquery that counts earlier returns. Two
    // different counts of what is left would let the screen offer a quantity
    // the writer then refuses, which is the worst of both — the shopkeeper
    // picks, taps, and is told no.
    final rows = await _db
        .customSelect(
          soldLinesSql,
          variables: [Variable<String>(documentId), Variable<String>(firmId)],
          readsFrom: {
            _db.documentLines,
            _db.documents,
            _db.docLinks,
            _db.documentLineTaxes,
          },
        )
        .get();

    return [for (final r in rows) soldLineFrom(r)];
  }

  @override
  Future<String?> documentStatus(String firmId, String documentId) async {
    final row = await _db
        .customSelect(
          'SELECT status FROM documents '
          'WHERE id = ? AND firm_id = ? AND deleted_at_utc IS NULL',
          variables: [Variable<String>(documentId), Variable<String>(firmId)],
          readsFrom: {_db.documents},
        )
        .getSingleOrNull();
    return row?.read<String>('status');
  }

  @override
  Future<PartySummary?> partyById(String firmId, String partyId) async {
    // The same SELECT as searchParties, with a different WHERE. Shared as a
    // string rather than by calling the other method and filtering: two
    // expressions for what a customer owes is two answers to the shop's only
    // question, and the one on screen would eventually disagree with the one
    // the credit limit is checked against. Filtering the other method's rows
    // would keep them in step and load every customer in the shop to show
    // one of them.
    final rows = await _db
        .customSelect(
          '$_partySelect WHERE p.id = ? AND p.firm_id = ?',
          variables: [Variable<String>(partyId), Variable<String>(firmId)],
        )
        .get();
    return rows.isEmpty ? null : _party(rows.first);
  }

  @override
  Future<List<OpenBill>> openBillsFor(String firmId, String partyId) =>
      // Deliberately the same WHERE and the same ORDER BY as
      // `_DriftPaymentWriteContext.openBillsFor`. The preview a shopkeeper
      // approves has to be what the write actually does, and two orderings
      // would make it a guess.
      _openDocuments(
        firmId,
        partyId,
        "doc_type IN ('sale_invoice', 'other_income')",
      );

  @override
  Future<List<OpenBill>> openPayablesFor(String firmId, String partyId) =>
      // And the same again for `openPayablesFor`, for the same reason.
      _openDocuments(
        firmId,
        partyId,
        "doc_type IN ('purchase_bill', 'expense')",
      );

  Future<List<OpenBill>> _openDocuments(
    String firmId,
    String partyId,
    String typeFilter,
  ) async {
    // Rides idx_documents_open_balance:
    // (firm_id, party_id, doc_date_local) WHERE balance_paisa <> 0.
    final rows = await _db
        .customSelect(
          '''
          SELECT id, doc_no, doc_type, doc_date_local, doc_seq, balance_paisa
          FROM documents
          WHERE firm_id = ? AND party_id = ?
            AND $typeFilter
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
          // The number on the paper, which the khata used to show as the
          // row's database id (M31).
          docNo: r.read<String>('doc_no'),
          docType: r.read<String>('doc_type'),
        ),
    ];
  }

  @override
  Future<List<SaleListRow>> recentSales(
    String firmId, {
    String? afterId,
    int limit = 40,
    String? onDateLocal,
    SaleFilter filter = SaleFilter.none,
  }) async {
    // Every narrowing is a predicate here, under the same keyset cursor, so
    // page two of "Rashid's bills this month" is page two of exactly that
    // (M30). The date range rides idx_documents_list; the text search is a
    // scan of one firm's bills, which a LIKE with a leading wildcard always
    // is, and a shop's bills are tens of thousands of rows, not millions.
    final where = StringBuffer();
    final variables = <Variable<Object>>[];

    if (filter.from case final from?) {
      where.write(' AND d.doc_date_local >= ?');
      variables.add(Variable<String>(from.value));
    }
    if (filter.to case final to?) {
      where.write(' AND d.doc_date_local <= ?');
      variables.add(Variable<String>(to.value));
    }

    where.write(switch (filter.standing) {
      SaleStanding.all => '',
      // Nothing left to pay. A return can take a settled bill below zero,
      // and that bill is not udhaar either.
      SaleStanding.paid => " AND d.status = 'posted' AND d.balance_paisa <= 0",
      SaleStanding.udhaar => " AND d.status = 'posted' AND d.balance_paisa > 0",
      SaleStanding.cancelled => " AND d.status = 'void'",
    });

    final search = filter.search;
    if (!search.isEmpty) {
      final like = '%${_escapeLike(search.text)}%';
      final either = <String>[
        r"d.doc_no LIKE ? ESCAPE '\'",
        r"d.party_name_snapshot LIKE ? ESCAPE '\'",
      ];
      variables
        ..add(Variable<String>(like))
        ..add(Variable<String>(like));
      // The khata's own name as well as the one printed, so a customer
      // renamed since still finds their old bills. Only when the search has
      // a letter or a digit left once normalised: `%%` matches every name.
      final name = plainSearchText(search.text);
      if (name.isNotEmpty) {
        either.add(r"p.name_search LIKE ? ESCAPE '\'");
        variables.add(Variable<String>('%${_escapeLike(name)}%'));
      }
      if (search.phoneDigits case final digits?) {
        // The khata's number with its punctuation taken out, because the
        // shop typed it one way into the khata and another into this box.
        either.add(
          'REPLACE(REPLACE(REPLACE(REPLACE(REPLACE('
          "COALESCE(NULLIF(TRIM(p.whatsapp), ''), p.phone, ''),"
          " '-', ''), ' ', ''), '+', ''), '(', ''), ')', '') LIKE ?",
        );
        variables.add(Variable<String>('%$digits%'));
      }
      if (search.paisa case (final low, final high)) {
        either.add('d.total_paisa BETWEEN ? AND ?');
        variables
          ..add(Variable<int>(low))
          ..add(Variable<int>(high));
      }
      where.write(' AND (${either.join(' OR ')})');
    }

    final rows = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_no, d.doc_date_local, d.doc_date_utc,
                 d.party_id, d.party_name_snapshot, d.total_paisa,
                 d.balance_paisa, d.status,
                 COALESCE(NULLIF(TRIM(p.whatsapp), ''), p.phone) AS party_phone,
                 (SELECT COUNT(*) FROM document_lines dl
                    WHERE dl.document_id = d.id
                      AND dl.deleted_at_utc IS NULL) AS line_count
          FROM documents d
          LEFT JOIN parties p
            ON p.id = d.party_id AND p.firm_id = d.firm_id
          WHERE d.firm_id = ?
            AND d.doc_type = 'sale_invoice'
            AND d.deleted_at_utc IS NULL
            AND (? IS NULL OR d.doc_date_local = ?)
            $where
            AND (? IS NULL OR d.id < ?)
          ORDER BY d.id DESC
          LIMIT ?
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(onDateLocal),
            Variable<String>(onDateLocal),
            ...variables,
            Variable<String>(afterId),
            Variable<String>(afterId),
            Variable<int>(limit),
          ],
          readsFrom: {_db.documents, _db.parties, _db.documentLines},
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
          partyId: r.readNullable<String>('party_id'),
          partyPhone: _blankToNull(r.readNullable<String>('party_phone')),
          total: Money.paisa(r.read<int>('total_paisa')),
          balance: Money.paisa(r.read<int>('balance_paisa')),
          lineCount: r.read<int>('line_count'),
          status: r.read<String>('status'),
        ),
    ];
  }

  @override
  Future<DocumentRecipient?> recipientOf(
    String firmId,
    String documentId,
  ) async {
    // The name on the paper, and the number on the khata now. A customer who
    // changed their number since the bill is reached on the new one; a
    // customer renamed since is still addressed as the bill names them.
    final row = await _db
        .customSelect(
          '''
          SELECT p.id, COALESCE(NULLIF(TRIM(d.party_name_snapshot), ''),
                                p.name) AS name,
                 COALESCE(NULLIF(TRIM(p.whatsapp), ''), p.phone) AS phone
          FROM documents d
          JOIN parties p ON p.id = d.party_id AND p.firm_id = d.firm_id
          WHERE d.id = ? AND d.firm_id = ? AND d.deleted_at_utc IS NULL
          ''',
          variables: [Variable<String>(documentId), Variable<String>(firmId)],
          readsFrom: {_db.documents, _db.parties},
        )
        .getSingleOrNull();
    if (row == null) return null;
    return DocumentRecipient(
      partyId: row.read<String>('id'),
      name: row.read<String>('name'),
      phone: _blankToNull(row.readNullable<String>('phone')),
    );
  }

  /// [raw] with LIKE's own wildcards taken literally. A bill series written
  /// `INV_26` is a shop's choice, and `_` would otherwise match any letter.
  static String _escapeLike(String raw) =>
      raw.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

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
  Future<Map<String, CostPosition>> costPositions(
    String firmId,
    Iterable<String> itemIds,
  ) async {
    final ids = itemIds.toSet().toList();
    if (ids.isEmpty) return const {};
    // The same read `DriftPurchaseWriter.costPositionsFor` makes inside its
    // transaction: the balance off the stock ledger, the average off the
    // item row, and the value derived by `CostPosition.onShelf`.
    final rows = await _db
        .customSelect(
          '''
          SELECT i.id,
                 i.avg_cost_milli_paisa,
                 COALESCE((
                   SELECT SUM(s.qty_delta_thousandths) FROM stock_ledger s
                   WHERE s.item_id = i.id AND s.firm_id = i.firm_id
                     AND s.deleted_at_utc IS NULL
                 ), 0) AS balance
          FROM items i
          WHERE i.firm_id = ? AND i.id IN (${List.filled(ids.length, '?').join(', ')})
          ''',
          variables: [
            Variable<String>(firmId),
            for (final id in ids) Variable<String>(id),
          ],
          readsFrom: {_db.items, _db.stockLedger},
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('id'): CostPosition.onShelf(
          qty: Qty.raw(r.read<int>('balance')),
          avg: Rate.raw(r.read<int>('avg_cost_milli_paisa')),
        ),
    };
  }

  @override
  Future<List<ChequeInHand>> chequesInHand(String firmId) async {
    // The writer's own select, so "in hand" means one thing. A cheque with no
    // date — taken before M6 asked for one — sorts last rather than first.
    final rows = await _db
        .customSelect(
          '$chequeInHandSelect AND p.firm_id = ? '
          'ORDER BY p.cheque_date_utc IS NULL, p.cheque_date_utc, '
          '         p.payment_no',
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.payments, _db.parties},
        )
        .get();
    return [for (final r in rows) chequeInHandFrom(r)];
  }

  @override
  Future<List<ActivityEntry>> activity(
    String firmId, {
    String? userId,
    int limit = 200,
  }) async {
    // Rides idx_audit_firm_time, or idx_audit_actor for one person's.
    final rows = await _db
        .customSelect(
          '''
          SELECT a.at_utc, a.created_by, u.name AS user_name, a.action_code,
                 a.summary, a.amount_paisa, a.entity_table, a.entity_id
          FROM audit_log a
          JOIN users u ON u.id = a.created_by
          WHERE a.firm_id = ?1 AND (?2 IS NULL OR a.created_by = ?2)
          ORDER BY a.at_utc DESC, a.id DESC
          LIMIT ?3
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(userId),
            Variable<int>(limit),
          ],
          readsFrom: {_db.auditLog, _db.users},
        )
        .get();
    return [for (final r in rows) _activity(r)];
  }

  @override
  Future<ActivityEntry?> lastDayClose(String firmId) async {
    final row = await _db
        .customSelect(
          '''
          SELECT a.at_utc, a.created_by, u.name AS user_name, a.action_code,
                 a.summary, a.amount_paisa, a.entity_table, a.entity_id
          FROM audit_log a
          JOIN users u ON u.id = a.created_by
          WHERE a.firm_id = ? AND a.action_code = 'DAY_CLOSED'
          ORDER BY a.at_utc DESC, a.id DESC
          LIMIT 1
          ''',
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.auditLog, _db.users},
        )
        .getSingleOrNull();
    return row == null ? null : _activity(row);
  }

  static ActivityEntry _activity(QueryRow r) => ActivityEntry(
    atUtcMillis: r.read<int>('at_utc'),
    userId: r.read<String>('created_by'),
    userName: r.read<String>('user_name'),
    actionCode: r.read<String>('action_code'),
    summary: r.readNullable<String>('summary'),
    amount: switch (r.readNullable<int>('amount_paisa')) {
      final int p => Money.paisa(p),
      null => null,
    },
    entityTable: r.readNullable<String>('entity_table'),
    entityId: r.readNullable<String>('entity_id'),
  );

  @override
  Future<TaxContext> taxContextFor(String firmId, String? partyId) async {
    final firm = await _db
        .customSelect(
          'SELECT is_sales_tax_registered, province, prices_include_tax '
          'FROM firms WHERE id = ?',
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.firms},
        )
        .getSingle();
    final party = partyId == null
        ? null
        : await _db
              .customSelect(
                'SELECT buyer_registration_type, is_on_atl FROM parties '
                'WHERE id = ? AND firm_id = ?',
                variables: [
                  Variable<String>(partyId),
                  Variable<String>(firmId),
                ],
                readsFrom: {_db.parties},
              )
              .getSingleOrNull();
    final atl = party?.readNullable<int>('is_on_atl');
    return TaxContext(
      hasNamedBuyer: partyId != null,
      isSellerRegistered: firm.read<int>('is_sales_tax_registered') == 1,
      buyerIsRegistered:
          party?.read<String>('buyer_registration_type') == 'registered',
      buyerIsOnAtl: atl == null ? null : atl == 1,
      province: firm.read<String>('province'),
      pricesIncludeTax: firm.read<int>('prices_include_tax') == 1,
      ruleVersion: 'pk-2026-27-v1',
    );
  }

  @override
  Future<Map<String, Qty>> stockByLocation(String firmId, String itemId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT location_code, SUM(qty_delta_thousandths) AS q
          FROM stock_ledger
          WHERE firm_id = ? AND item_id = ? AND deleted_at_utc IS NULL
          GROUP BY location_code
          ORDER BY location_code <> 'MAIN', location_code
          ''',
          variables: [Variable<String>(firmId), Variable<String>(itemId)],
          readsFrom: {_db.stockLedger},
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('location_code'): Qty.raw(r.read<int>('q')),
    };
  }

  @override
  Future<List<String>> stockLocations(String firmId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT DISTINCT location_code FROM stock_ledger
          WHERE firm_id = ? AND deleted_at_utc IS NULL
          ''',
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.stockLedger},
        )
        .get();
    final found = {for (final r in rows) r.read<String>('location_code')};
    return ['MAIN', ...(found..remove('MAIN')).toList()..sort()];
  }

  static const _lotSelect = '''
    SELECT l.id, l.item_id, i.name AS item_name, l.lot_no, l.serial,
           l.expiry_date_local, l.cost_milli_paisa,
           SUM(s.qty_delta_thousandths) AS q
    FROM stock_lots l
    JOIN items i ON i.id = l.item_id
    JOIN stock_ledger s ON s.lot_id = l.id AND s.deleted_at_utc IS NULL
  ''';

  static LotOnHand _lotFrom(QueryRow r) => LotOnHand(
    lotId: r.read<String>('id'),
    itemId: r.read<String>('item_id'),
    itemName: r.read<String>('item_name'),
    lotNo: r.read<String>('lot_no'),
    qty: Qty.raw(r.read<int>('q')),
    cost: Rate.raw(r.read<int>('cost_milli_paisa')),
    serial: r.readNullable<String>('serial'),
    expiry: switch (r.readNullable<String>('expiry_date_local')) {
      final String d => BusinessDate(d),
      null => null,
    },
  );

  @override
  Future<List<LotOnHand>> lotsOnHand(String firmId, {String? itemId}) async {
    final rows = await _db
        .customSelect(
          '''
          $_lotSelect
          WHERE l.firm_id = ?1 AND l.deleted_at_utc IS NULL
            AND (?2 IS NULL OR l.item_id = ?2)
          GROUP BY l.id
          HAVING SUM(s.qty_delta_thousandths) > 0
          ORDER BY l.expiry_date_local IS NULL, l.expiry_date_local, i.name,
                   l.lot_no
          ''',
          variables: [Variable<String>(firmId), Variable<String>(itemId)],
          readsFrom: {_db.stockLots, _db.items, _db.stockLedger},
        )
        .get();
    return [for (final r in rows) _lotFrom(r)];
  }

  @override
  Future<LotOnHand?> serialOnHand(String firmId, String serial) async {
    final row = await _db
        .customSelect(
          '''
          $_lotSelect
          WHERE l.firm_id = ?1 AND l.serial = ?2 AND l.deleted_at_utc IS NULL
          GROUP BY l.id
          HAVING SUM(s.qty_delta_thousandths) > 0
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(serial.trim()),
          ],
          readsFrom: {_db.stockLots, _db.items, _db.stockLedger},
        )
        .getSingleOrNull();
    return row == null ? null : _lotFrom(row);
  }

  @override
  Future<List<ChartAccount>> chartOfAccounts(String firmId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT a.id, a.code, a.name, a.account_type, a.system_key,
                 COALESCE((SELECT SUM(jl.debit_paisa - jl.credit_paisa)
                             FROM journal_lines jl
                            WHERE jl.account_id = a.id
                              AND jl.deleted_at_utc IS NULL), 0) AS balance
          FROM accounts a
          WHERE a.firm_id = ? AND a.deleted_at_utc IS NULL AND a.is_active = 1
          ORDER BY a.code
          ''',
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.accounts, _db.journalLines},
        )
        .get();
    return [
      for (final r in rows)
        ChartAccount(
          id: r.read<String>('id'),
          code: r.read<String>('code'),
          name: r.read<String>('name'),
          type: r.read<String>('account_type'),
          systemKey: r.readNullable<String>('system_key'),
          balance: Money.paisa(r.read<int>('balance')),
        ),
    ];
  }

  @override
  Future<List<AccountLedgerLine>> accountLedger(
    String firmId,
    String accountId, {
    int limit = 500,
  }) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT je.entry_date_local, je.entry_no,
                 COALESCE(jl.narration, je.narration, '') AS narration,
                 jl.debit_paisa, jl.credit_paisa
          FROM journal_lines jl
          JOIN journal_entries je ON je.id = jl.journal_entry_id
          WHERE jl.account_id = ?1 AND je.firm_id = ?2
            AND jl.deleted_at_utc IS NULL AND je.deleted_at_utc IS NULL
          ORDER BY je.entry_date_local, je.created_at_utc, je.id, jl.line_no
          LIMIT ?3
          ''',
          variables: [
            Variable<String>(accountId),
            Variable<String>(firmId),
            Variable<int>(limit),
          ],
          readsFrom: {_db.journalLines, _db.journalEntries},
        )
        .get();
    var running = Money.zero;
    return [
      for (final r in rows)
        () {
          final debit = Money.paisa(r.read<int>('debit_paisa'));
          final credit = Money.paisa(r.read<int>('credit_paisa'));
          running = running + debit - credit;
          return AccountLedgerLine(
            date: BusinessDate(r.read<String>('entry_date_local')),
            entryNo: r.read<String>('entry_no'),
            narration: r.read<String>('narration'),
            debit: debit,
            credit: credit,
            balanceAfter: running,
          );
        }(),
    ];
  }

  @override
  Future<Money> cashInDrawer(String firmId) async {
    final row = await _db
        .customSelect(
          cashInDrawerSql,
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.journalLines, _db.accounts, _db.paymentAccounts},
        )
        .getSingle();
    return Money.paisa(row.read<int>('cash'));
  }

  @override
  Future<List<QuotationRow>> quotations(String firmId, {int limit = 100}) =>
      _billableDocuments(firmId, 'quotation', limit);

  @override
  Future<List<QuotationRow>> challans(String firmId, {int limit = 100}) =>
      _billableDocuments(firmId, 'delivery_challan', limit);

  Future<List<QuotationRow>> _billableDocuments(
    String firmId,
    String docType,
    int limit,
  ) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT q.id, q.doc_no, q.doc_date_local, q.total_paisa, q.party_id,
                 q.party_name_snapshot, q.terms, q.status,
                 (SELECT bill.doc_no FROM doc_links link
                    JOIN documents bill ON bill.id = link.to_document_id
                   WHERE link.from_document_id = q.id
                     AND link.link_type = 'converted_from'
                     AND link.deleted_at_utc IS NULL
                     AND bill.status <> 'void'
                   LIMIT 1) AS billed_as
          FROM documents q
          WHERE q.firm_id = ? AND q.doc_type = ?
            AND q.status IN ('posted', 'void') AND q.deleted_at_utc IS NULL
          ORDER BY q.doc_date_local DESC, q.doc_seq DESC
          LIMIT ?
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(docType),
            Variable<int>(limit),
          ],
          readsFrom: {_db.documents, _db.docLinks},
        )
        .get();
    return [
      for (final r in rows)
        QuotationRow(
          id: r.read<String>('id'),
          docNo: r.read<String>('doc_no'),
          date: BusinessDate(r.read<String>('doc_date_local')),
          total: Money.paisa(r.read<int>('total_paisa')),
          partyId: r.readNullable<String>('party_id'),
          partyName: r.readNullable<String>('party_name_snapshot'),
          validUntil: docType == 'quotation'
              ? _validUntil(r.readNullable<String>('terms'))
              : null,
          billedAs: r.readNullable<String>('billed_as'),
          docType: docType,
          isVoid: r.read<String>('status') == 'void',
        ),
    ];
  }

  /// The date the builder writes into a quotation's terms.
  static BusinessDate? _validUntil(String? terms) {
    final match = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(terms ?? '');
    return match == null ? null : BusinessDate(match.group(1)!);
  }

  @override
  Future<List<QuotedLine>> quotedLines(
    String firmId,
    String quotationId,
  ) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT dl.item_id, dl.qty_thousandths, dl.unit_id,
                 dl.unit_code_snapshot, dl.rate_milli_paisa, dl.discount_bp,
                 dl.discount_paisa
          FROM document_lines dl
          JOIN documents d ON d.id = dl.document_id
          WHERE d.id = ? AND d.firm_id = ?
            AND d.doc_type IN ('quotation', 'delivery_challan')
            AND dl.item_id IS NOT NULL AND dl.deleted_at_utc IS NULL
          ORDER BY dl.line_no
          ''',
          variables: [Variable<String>(quotationId), Variable<String>(firmId)],
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
            // A discount typed as an amount is carried as that amount; one
            // set as a percentage recomputes to the same figure.
            explicitDiscount: bp == 0 && discount > 0
                ? Money.paisa(discount)
                : null,
          );
        }(),
    ];
  }

  @override
  Future<PartyDraft?> partyDraft(String firmId, String partyId) async {
    final r = await _db
        .customSelect(
          'SELECT * FROM parties WHERE id = ? AND firm_id = ?',
          variables: [Variable<String>(partyId), Variable<String>(firmId)],
          readsFrom: {_db.parties},
        )
        .getSingleOrNull();
    if (r == null) return null;
    final atl = r.readNullable<int>('is_on_atl');
    final limit = r.readNullable<int>('credit_limit_paisa');
    // The note lives in settings, not on the row (M40). Read here so the
    // editor writes it back rather than clearing it on every save.
    final remarks = await _db
        .customSelect(
          'SELECT setting_value FROM settings '
          'WHERE firm_id = ? AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(firmId),
            Variable<String>(partyRemarksKey(partyId)),
          ],
          readsFrom: {_db.settings},
        )
        .getSingleOrNull();
    return PartyDraft(
      name: r.read<String>('name'),
      partyType: r.read<String>('party_type'),
      phone: r.readNullable<String>('phone'),
      whatsapp: r.readNullable<String>('whatsapp'),
      addressLine1: r.readNullable<String>('address_line1'),
      city: r.readNullable<String>('city'),
      ntn: r.readNullable<String>('ntn'),
      strn: r.readNullable<String>('strn'),
      cnic: r.readNullable<String>('cnic'),
      buyerRegistrationType: r.read<String>('buyer_registration_type'),
      isOnAtl: atl == null ? null : atl == 1,
      openingBalance: Money.paisa(r.read<int>('opening_balance_paisa')),
      creditLimit: limit == null ? null : Money.paisa(limit),
      creditDays: r.readNullable<int>('credit_days'),
      priceTier: PriceTier.parse(r.read<String>('price_tier')),
      defaultDiscountBp: r.read<int>('default_discount_bp'),
      group: _blankToNull(r.readNullable<String>('party_group')),
      remarks: _blankToNull(remarks?.read<String>('setting_value'))?.trim(),
    );
  }

  @override
  Future<List<IssuedCheque>> chequesIssued(String firmId) async {
    // The writer's own select, as with cheques in hand.
    final rows = await _db
        .customSelect(
          '$chequeIssuedSelect AND p.firm_id = ? '
          'ORDER BY p.cheque_date_utc IS NULL, p.cheque_date_utc, '
          '         p.payment_no',
          variables: [Variable<String>(firmId)],
          readsFrom: {_db.payments, _db.parties, _db.paymentAccounts},
        )
        .get();
    return [for (final r in rows) chequeIssuedFrom(r)];
  }

  @override
  Future<List<BouncedCheque>> bouncedCheques(
    String firmId, {
    int limit = 50,
  }) async {
    // The bounce date is the reversal entry's, found by the payment it points
    // at — a date the payment row itself does not carry.
    final rows = await _db
        .customSelect(
          '''
          SELECT p.id, p.party_id, pa.name AS party_name, p.amount_paisa,
                 p.cheque_no, p.cheque_bank,
                 (SELECT MIN(je.entry_date_local) FROM journal_entries je
                  WHERE je.payment_id = p.id
                    AND je.source_type = 'reversal'
                    AND je.deleted_at_utc IS NULL) AS bounced_on
          FROM payments p
          JOIN parties pa ON pa.id = p.party_id
          WHERE p.firm_id = ? AND p.mode = 'cheque' AND p.status = 'bounced'
            -- Customers' cheques only. One of the shop's own that bounced is
            -- not a 489-F case the shop brings; it is one brought against it.
            AND p.direction = 'in'
            AND p.deleted_at_utc IS NULL
          ORDER BY bounced_on DESC, p.payment_no DESC
          LIMIT ?
          ''',
          variables: [Variable<String>(firmId), Variable<int>(limit)],
          readsFrom: {_db.payments, _db.parties, _db.journalEntries},
        )
        .get();
    return [
      for (final r in rows)
        BouncedCheque(
          paymentId: r.read<String>('id'),
          partyId: r.read<String>('party_id'),
          partyName: r.read<String>('party_name'),
          amount: Money.paisa(r.read<int>('amount_paisa')),
          chequeNo: r.read<String>('cheque_no'),
          bank: r.readNullable<String>('cheque_bank'),
          bouncedOn: BusinessDate(r.read<String>('bounced_on')),
        ),
    ];
  }

  @override
  Future<DemandNotice?> demandNotice(
    String firmId,
    String paymentId, {
    required BusinessDate issuedOn,
  }) async {
    final firm = await _firm(firmId);
    if (firm == null) return null;
    // The return memo's words are the ones the shop typed at the bounce, and
    // live in the bounce entry's narration after "bounced: " — the one place
    // they were ever written.
    final r = await _db
        .customSelect(
          '''
          SELECT p.amount_paisa, p.cheque_no, p.cheque_bank, p.cheque_date_utc,
                 pa.name AS party_name, pa.phone, pa.address_line1,
                 pa.address_line2, pa.city, pa.cnic,
                 je.entry_date_local AS bounced_on, je.narration
          FROM payments p
          JOIN parties pa ON pa.id = p.party_id
          JOIN journal_entries je ON je.id = (
            SELECT id FROM journal_entries
            WHERE payment_id = p.id AND source_type = 'reversal'
              AND deleted_at_utc IS NULL
            ORDER BY entry_date_utc, id LIMIT 1)
          WHERE p.id = ? AND p.firm_id = ? AND p.mode = 'cheque'
            AND p.direction = 'in'
            AND p.status = 'bounced' AND p.deleted_at_utc IS NULL
          ''',
          variables: [Variable<String>(paymentId), Variable<String>(firmId)],
          readsFrom: {_db.payments, _db.parties, _db.journalEntries},
        )
        .getSingleOrNull();
    if (r == null) return null;

    final narration = r.readNullable<String>('narration') ?? '';
    const marker = 'bounced: ';
    final at = narration.indexOf(marker);
    final due = r.readNullable<int>('cheque_date_utc');
    final address = [
      _blankToNull(r.readNullable<String>('address_line1')),
      _blankToNull(r.readNullable<String>('address_line2')),
    ].nonNulls.join(', ');

    return DemandNotice(
      shopName: firm.name,
      shopAddress: firm.addressLine1,
      shopCity: firm.city,
      shopPhone: firm.phone,
      partyName: r.read<String>('party_name'),
      partyAddress: address.isEmpty ? null : address,
      partyCity: _blankToNull(r.readNullable<String>('city')),
      partyPhone: _blankToNull(r.readNullable<String>('phone')),
      partyCnic: _blankToNull(r.readNullable<String>('cnic')),
      chequeNo: r.read<String>('cheque_no'),
      bank: _blankToNull(r.readNullable<String>('cheque_bank')),
      chequeDate: due == null ? null : chequeDueDate(due),
      amount: Money.paisa(r.read<int>('amount_paisa')),
      bouncedOn: BusinessDate(r.read<String>('bounced_on')),
      returnReason: at < 0 ? null : narration.substring(at + marker.length),
      issuedOn: issuedOn,
    );
  }

  @override
  Future<ReturnableDelivery?> returnableDelivery(
    String firmId,
    String documentId,
  ) async {
    // The same reads as `DriftPurchaseReturnWriter.deliveryFor`, down to the
    // shared subquery, so the screen cannot offer what the writer refuses.
    final doc = await _db
        .customSelect(
          'SELECT id, doc_no, party_id, balance_paisa FROM documents '
          "WHERE id = ? AND firm_id = ? AND doc_type = 'purchase_bill' "
          "  AND status = 'posted' AND deleted_at_utc IS NULL",
          variables: [Variable<String>(documentId), Variable<String>(firmId)],
        )
        .getSingleOrNull();
    if (doc == null) return null;

    final lines = await _db
        .customSelect(
          '''
          SELECT dl.id, dl.item_id, dl.item_name_snapshot, dl.unit_id,
                 dl.unit_code_snapshot, dl.qty_thousandths,
                 dl.base_qty_thousandths, dl.rate_milli_paisa,
                 dl.line_total_paisa, dl.cost_paisa,
                 $returnedOffDeliveryLine AS returned
          FROM document_lines dl
          WHERE dl.document_id = ? AND dl.deleted_at_utc IS NULL
          ORDER BY dl.line_no
          ''',
          variables: [Variable<String>(documentId)],
          readsFrom: {_db.documentLines, _db.documents, _db.docLinks},
        )
        .get();

    return ReturnableDelivery(
      documentId: documentId,
      docNo: doc.read<String>('doc_no'),
      partyId: doc.read<String>('party_id'),
      outstanding: Money.paisa(doc.read<int>('balance_paisa')),
      lines: [for (final r in lines) boughtLineFrom(r)],
    );
  }

  @override
  Future<List<PurchaseListRow>> recentPurchases(
    String firmId, {
    int limit = 60,
  }) async {
    // `balance_paisa` is what is still owed now, not at delivery: every
    // payment to the supplier since has written the bill's new balance.
    //
    // Rides idx_documents_list.
    final rows = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_no, d.doc_date_local, d.total_paisa,
                 d.balance_paisa, d.supplier_bill_no, p.name AS supplier,
                 (SELECT COUNT(*) FROM document_lines dl
                  WHERE dl.document_id = d.id
                    AND dl.deleted_at_utc IS NULL) AS lines
          FROM documents d
          JOIN parties p ON p.id = d.party_id
          WHERE d.firm_id = ? AND d.doc_type = 'purchase_bill'
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
          ORDER BY d.doc_date_local DESC, d.doc_seq DESC, d.id DESC
          LIMIT ?
          ''',
          variables: [Variable<String>(firmId), Variable<int>(limit)],
          readsFrom: {_db.documents, _db.parties, _db.documentLines},
        )
        .get();
    return [
      for (final r in rows)
        PurchaseListRow(
          id: r.read<String>('id'),
          docNo: r.read<String>('doc_no'),
          dateLocal: r.read<String>('doc_date_local'),
          supplierName: r.read<String>('supplier'),
          total: Money.paisa(r.read<int>('total_paisa')),
          owed: Money.paisa(r.read<int>('balance_paisa')),
          lineCount: r.read<int>('lines'),
          supplierBillNo: r.readNullable<String>('supplier_bill_no'),
        ),
    ];
  }

  @override
  Future<List<ItemSummary>> archivedItems(
    String firmId, {
    int limit = 200,
  }) async {
    // The same columns the counter's search reads, so a restored item comes
    // back exactly as it left. Most recently hidden first: the item a
    // shopkeeper is looking for in here is almost always the one they just
    // hid by mistake.
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
            AND i.is_active = 0
          ORDER BY i.updated_at_utc DESC, i.id DESC
          LIMIT ?
          ''',
          variables: [Variable<String>(firmId), Variable<int>(limit)],
          readsFrom: {_db.items, _db.units, _db.stockLedger},
        )
        .get();
    return [for (final r in rows) _itemFrom(r)];
  }

  @override
  Future<List<PartySummary>> archivedParties(
    String firmId, {
    int limit = 200,
  }) async {
    final rows = await _db
        .customSelect(
          '''
          $_partySelect
          WHERE p.firm_id = ?
            AND p.deleted_at_utc IS NULL
            AND p.is_active = 0
          ORDER BY p.updated_at_utc DESC, p.id DESC
          LIMIT ?
          ''',
          variables: [Variable<String>(firmId), Variable<int>(limit)],
        )
        .get();
    return [for (final r in rows) _party(r)];
  }

  @override
  Future<List<ExpenseRow>> recentExpenses(
    String firmId, {
    int limit = 60,
  }) async {
    // The head is the account on the entry's debit line — the same join the
    // Trial Balance makes. A column on `documents` would be a second answer
    // to that question, and the list would drift from the books the first
    // time a path wrote one and not the other.
    //
    // Rides idx_documents_list for the outer scan and idx_je_doc for
    // the head.
    final rows = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_no, d.doc_date_local, d.total_paisa,
                 d.balance_paisa, d.notes, p.name AS party_name,
                 (SELECT COALESCE(a.system_key, '#' || a.id)
                  FROM journal_entries je
                  JOIN journal_lines jl ON jl.journal_entry_id = je.id
                  JOIN accounts a ON a.id = jl.account_id
                  WHERE je.document_id = d.id
                    AND je.source_type = 'expense'
                    AND jl.debit_paisa > 0
                  ORDER BY jl.line_no
                  LIMIT 1) AS head
          FROM documents d
          LEFT JOIN parties p ON p.id = d.party_id
          WHERE d.firm_id = ? AND d.doc_type = 'expense'
            AND d.status = 'posted'
            AND d.deleted_at_utc IS NULL
          ORDER BY d.doc_date_local DESC, d.doc_seq DESC, d.id DESC
          LIMIT ?
          ''',
          variables: [Variable<String>(firmId), Variable<int>(limit)],
          readsFrom: {
            _db.documents,
            _db.parties,
            _db.journalEntries,
            _db.journalLines,
            _db.accounts,
          },
        )
        .get();

    return [
      for (final r in rows)
        ExpenseRow(
          id: r.read<String>('id'),
          docNo: r.read<String>('doc_no'),
          dateLocal: r.read<String>('doc_date_local'),
          // Read as required. An expense with no debit line is a hole in
          // the books, and filing it under misc here would hide it. A head
          // the shop added (M47) has no system key, and is named as an
          // expense draft names it, `#<account id>` (M58): it is not a hole.
          head: r.read<String>('head'),
          amount: Money.paisa(r.read<int>('total_paisa')),
          owed: Money.paisa(r.read<int>('balance_paisa')),
          note: r.readNullable<String>('notes') ?? '',
          partyName: r.readNullable<String>('party_name'),
        ),
    ];
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

    final docType = doc.read<String>('doc_type');
    final (docTitle, docLabel) = switch (docType) {
      'quotation' => ('Quotation', 'Quotation No'),
      'delivery_challan' => ('Delivery Challan', 'Challan No'),
      'other_income' => ('Debit Note', 'Note No'),
      // A delivery, shown back and sent on (M30). Nothing read one through
      // here before, and it would have fallen to the default and called
      // itself an Invoice, with the mill as its customer.
      'purchase_bill' => ('Purchase Bill', 'Purchase No'),
      // Goods a customer brought back (M57). It fell to the default and
      // called itself an Invoice, which is the one thing a credit is not.
      'sale_return' => ('Sale Return', 'Return No'),
      // Orders (M41): goods asked for, sent to the supplier or handed to
      // the customer as what was agreed. Neither is an invoice.
      'purchase_order' => ('Purchase Order', 'PO No'),
      'sale_order' => ('Sale Order', 'Order No'),
      _ => ('Invoice', 'Bill No'),
    };
    final isPurchase =
        docType == 'purchase_bill' || docType == 'purchase_order';
    final terms = _blankToNull(doc.readNullable<String>('terms'));
    final supplierBillNo = _blankToNull(
      doc.readNullable<String>('supplier_bill_no'),
    );
    return ReceiptData(
      shop: firm.toReceiptShop(),
      docNo: doc.read<String>('doc_no'),
      fbrInvoiceNo: _blankToNull(doc.readNullable<String>('fbr_invoice_no')),
      fbrPending: doc.readNullable<String>('fbr_status') == 'pending',
      docTitle: docTitle,
      docLabel: docLabel,
      partyLabel: isPurchase ? 'Supplier' : 'Customer',
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
      footerLines: [
        ?terms,
        // The number on the supplier's own paper is the one they quote; the
        // shop's thanks for visiting is for a customer, not a mill.
        if (isPurchase) ...[
          if (supplierBillNo != null) 'Supplier bill: $supplierBillNo',
        ] else
          'Shukriya! Phir tashreef laayen',
        if (madeWith?.call() ?? false) madeWithLine,
      ],
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
            --
            -- And anything below nothing, floor or none (M53): sold past
            -- what it had, by two counters each selling the last one while
            -- apart or by a cashier who was asked and said sell anyway. That
            -- is not a reorder, it is a count somebody has to make, and it
            -- is rare enough never to fill the list.
            AND (stock_thousandths < 0
                 OR (i.min_stock_thousandths > 0
                     AND stock_thousandths <= i.min_stock_thousandths))
          -- Below nothing first (M53). Then worst: how far below the floor,
          -- as a fraction of it, so a staple that is 90% gone outranks a
          -- slow-moving line that is one unit short. Ordering by the raw
          -- shortfall would put a 500-piece line that is ten short above a
          -- 2-piece line nearly out.
          --
          -- Both operands are INTEGER columns, so this is SQLite's integer
          -- division and there is no floating point in it anywhere. The
          -- result is a truncated per-mille used as a sort key, never a
          -- number anyone is shown.
          ORDER BY stock_thousandths < 0 DESC,
                   (stock_thousandths * 1000) -- arch_check: allow no_floating_point_money — integer sort key
                     / NULLIF(i.min_stock_thousandths, 0),
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
  Future<List<PastDeal>> lastSoldTo(
    String firmId, {
    required String partyId,
    required String itemId,
    int limit = 5,
  }) => _pastDeals(
    firmId,
    docType: 'sale_invoice',
    partyId: partyId,
    itemId: itemId,
    limit: limit,
  );

  @override
  Future<List<PastDeal>> lastBought(
    String firmId, {
    required String itemId,
    String? supplierId,
    int limit = 5,
  }) => _pastDeals(
    firmId,
    docType: 'purchase_bill',
    partyId: supplierId,
    itemId: itemId,
    limit: limit,
  );

  Future<List<PastDeal>> _pastDeals(
    String firmId, {
    required String docType,
    required String? partyId,
    required String itemId,
    required int limit,
  }) async {
    if (limit <= 0) return const [];
    final rows = await _db
        .customSelect(
          pastDealsSql(forParty: partyId != null),
          variables: [
            if (partyId != null) Variable<String>(partyId),
            Variable<String>(firmId),
            Variable<String>(docType),
            Variable<String>(itemId),
            Variable<int>(limit),
          ],
          readsFrom: {_db.documents, _db.documentLines, _db.parties},
        )
        .get();
    return [
      for (final r in rows)
        PastDeal(
          documentId: r.read<String>('document_id'),
          docNo: r.read<String>('doc_no'),
          dateLocal: r.read<String>('doc_date_local'),
          qty: Qty.raw(r.read<int>('qty')),
          unitId: r.readNullable<String>('unit_id'),
          unitCode: r.read<String>('unit_code_snapshot'),
          rate: Rate.raw(r.read<int>('rate_milli_paisa')),
          discountBp: r.read<int>('discount_bp'),
          discount: Money.paisa(r.read<int>('discount')),
          partyName: _blankToNull(r.readNullable<String>('party_name')),
        ),
    ];
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

  @override
  Future<PaymentDetail?> paymentDetail(String firmId, String id) async {
    // By the payment's own id, or by the id of a journal entry that names
    // it: a bounced cheque's line in the khata is the bounce entry, and
    // tapping it should open the cheque it is about.
    final p = await _db
        .customSelect(
          '''
          SELECT p.id, p.payment_no, p.direction, p.party_id, p.amount_paisa,
                 p.mode, p.payment_account_id, p.reference, p.notes,
                 p.payment_date_local, p.status, p.cheque_no, p.cheque_bank,
                 p.cheque_date_utc, p.cheque_status, p.created_by,
                 p.created_at_utc,
                 acct.name AS account_name, party.name AS party_name
          FROM payments p
          LEFT JOIN payment_accounts acct ON acct.id = p.payment_account_id
          LEFT JOIN parties party ON party.id = p.party_id
          WHERE p.firm_id = ? AND p.deleted_at_utc IS NULL
            AND (p.id = ? OR p.id = (SELECT je.payment_id
                                     FROM journal_entries je
                                     WHERE je.id = ? AND je.firm_id = ?))
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(id),
            Variable<String>(id),
            Variable<String>(firmId),
          ],
          readsFrom: {
            _db.payments,
            _db.paymentAccounts,
            _db.parties,
            _db.journalEntries,
          },
        )
        .getSingleOrNull();
    if (p == null) return null;
    final paymentId = p.read<String>('id');
    final status = p.read<String>('status');

    // What it settled. A cancelled payment's allocations were struck out
    // when it was cancelled, and are read anyway: "which bills did it pay"
    // is still the question asked about a receipt that was later undone.
    final bills = await _db
        .customSelect(
          '''
          SELECT pa.document_id, pa.amount_paisa, pa.allocation_mode,
                 d.doc_no, d.doc_type, d.doc_date_local, d.doc_seq,
                 d.void_reason
          FROM payment_allocations pa
          JOIN documents d ON d.id = pa.document_id
          WHERE pa.payment_id = ? AND pa.firm_id = ?
            AND (pa.deleted_at_utc IS NULL OR ? = 'void')
          ORDER BY d.doc_date_local, d.doc_seq, d.id
          ''',
          variables: [
            Variable<String>(paymentId),
            Variable<String>(firmId),
            Variable<String>(status),
          ],
          readsFrom: {_db.paymentAllocations, _db.documents},
        )
        .get();
    final counter = bills
        .where((b) => b.read<String>('allocation_mode') == 'exact')
        .firstOrNull;

    // Why it was cancelled, and what it replaced or was replaced by, are
    // kept where the cancellation and the edit wrote them: the activity log.
    final trail = await _db
        .customSelect(
          '''
          SELECT action_code, entity_id, before_json, after_json,
                 created_by, at_utc
          FROM audit_log
          WHERE firm_id = ?
            AND ((entity_table = 'payments' AND entity_id = ?
                  AND action_code IN ('PAYMENT_VOIDED', 'PAYMENT_EDITED'))
                 OR (action_code = 'PAYMENT_EDITED' AND before_json LIKE ?))
          ORDER BY at_utc, id
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(paymentId),
            Variable<String>('%"$paymentId"%'),
          ],
          readsFrom: {_db.auditLog},
        )
        .get();
    String? cancelReason;
    String? cancelledBy;
    String? cancelledAt;
    String? replaces;
    String? replacesId;
    String? replacedBy;
    String? replacedById;
    for (final row in trail) {
      final action = row.read<String>('action_code');
      final before = _jsonOf(row.readNullable<String>('before_json'));
      final after = _jsonOf(row.readNullable<String>('after_json'));
      if (action == 'PAYMENT_VOIDED') {
        cancelReason = after['reason'] as String?;
        cancelledBy = await userName(row.read<String>('created_by'));
        cancelledAt = _dateTimeLabel(row.read<int>('at_utc'));
      } else if (row.read<String>('entity_id') == paymentId) {
        replaces = before['no'] as String?;
        replacesId = before['id'] as String?;
      } else if (before['id'] == paymentId) {
        replacedBy = after['no'] as String?;
        replacedById = after['id'] as String?;
      }
    }
    // A tender cancelled with its bill has no log of its own; the bill's
    // reason is its reason.
    if (status == 'void' && cancelReason == null && counter != null) {
      cancelReason = _blankToNull(counter.readNullable<String>('void_reason'));
    }

    final due = p.readNullable<int>('cheque_date_utc');
    return PaymentDetail(
      id: paymentId,
      paymentNo: p.read<String>('payment_no'),
      direction: p.read<String>('direction'),
      partyId: p.readNullable<String>('party_id'),
      partyName: p.readNullable<String>('party_name'),
      amount: Money.paisa(p.read<int>('amount_paisa')),
      mode: p.read<String>('mode'),
      paymentAccountId: p.read<String>('payment_account_id'),
      paymentAccountName: p.readNullable<String>('account_name') ?? '',
      reference: _blankToNull(p.readNullable<String>('reference')),
      notes: _blankToNull(p.readNullable<String>('notes')),
      dateLocal: p.read<String>('payment_date_local'),
      status: status,
      chequeNo: _blankToNull(p.readNullable<String>('cheque_no')),
      chequeBank: _blankToNull(p.readNullable<String>('cheque_bank')),
      chequeDue: due == null ? null : chequeDueDate(due),
      chequeStatus: p.readNullable<String>('cheque_status'),
      enteredBy: await userName(p.read<String>('created_by')),
      enteredAt: _dateTimeLabel(p.read<int>('created_at_utc')),
      settled: [
        for (final b in bills)
          SettledBill(
            documentId: b.read<String>('document_id'),
            docNo: b.read<String>('doc_no'),
            docType: b.read<String>('doc_type'),
            dateLocal: b.read<String>('doc_date_local'),
            sequence: b.read<int>('doc_seq'),
            amount: Money.paisa(b.read<int>('amount_paisa')),
          ),
      ],
      counterBillId: counter?.read<String>('document_id'),
      counterBillNo: counter?.read<String>('doc_no'),
      cancelReason: cancelReason,
      cancelledBy: cancelledBy,
      cancelledAt: cancelledAt,
      replaces: replaces,
      replacesId: replacesId,
      replacedBy: replacedBy,
      replacedById: replacedById,
    );
  }

  @override
  Future<EntryDocument?> entryDocument(String firmId, String documentId) async {
    // The head and the account an expense was paid from both come off its
    // entry's lines, the same join the expense list and the Trial Balance
    // make: there is no column holding either anywhere else.
    final d = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_type, d.doc_no, d.doc_date_local, d.status,
                 d.party_id, d.total_paisa, d.balance_paisa, d.notes,
                 d.created_by, p.name AS party_name,
                 (SELECT a.system_key
                  FROM journal_entries je
                  JOIN journal_lines jl ON jl.journal_entry_id = je.id
                  JOIN accounts a ON a.id = jl.account_id
                  WHERE je.document_id = d.id
                    AND je.source_type = 'expense'
                    AND jl.debit_paisa > 0
                  ORDER BY jl.line_no LIMIT 1) AS head,
                 (SELECT jl.account_id
                  FROM journal_entries je
                  JOIN journal_lines jl ON jl.journal_entry_id = je.id
                  WHERE je.document_id = d.id
                    AND je.source_type = 'expense'
                    AND jl.credit_paisa > 0
                    AND jl.party_id IS NULL
                  ORDER BY jl.line_no LIMIT 1) AS paid_from_ledger
          FROM documents d
          LEFT JOIN parties p ON p.id = d.party_id
          WHERE d.id = ? AND d.firm_id = ? AND d.deleted_at_utc IS NULL
            AND d.doc_type IN ('other_income', 'expense')
          ''',
          variables: [Variable<String>(documentId), Variable<String>(firmId)],
          readsFrom: {
            _db.documents,
            _db.parties,
            _db.journalEntries,
            _db.journalLines,
            _db.accounts,
          },
        )
        .getSingleOrNull();
    if (d == null) return null;

    final ledger = d.readNullable<String>('paid_from_ledger');
    final paidFrom = ledger == null
        ? null
        : await _db
              .customSelect(
                'SELECT id FROM payment_accounts '
                'WHERE firm_id = ? AND ledger_account_id = ? '
                '  AND deleted_at_utc IS NULL '
                'ORDER BY is_active DESC, is_default DESC, name LIMIT 1',
                variables: [Variable<String>(firmId), Variable<String>(ledger)],
                readsFrom: {_db.paymentAccounts},
              )
              .getSingleOrNull();

    // The same payments the cancellation refuses over, so the page says
    // what is in the way before the shopkeeper is told no.
    final paidBy = await _db
        .customSelect(
          '''
          SELECT p.payment_no FROM payment_allocations pa
          JOIN payments p ON p.id = pa.payment_id
          WHERE pa.document_id = ? AND pa.deleted_at_utc IS NULL
            AND p.deleted_at_utc IS NULL AND p.status <> 'void'
            AND pa.allocation_mode <> 'exact'
          ORDER BY p.payment_no
          ''',
          variables: [Variable<String>(documentId)],
          readsFrom: {_db.paymentAllocations, _db.payments},
        )
        .get();

    return EntryDocument(
      id: documentId,
      docType: d.read<String>('doc_type'),
      docNo: d.read<String>('doc_no'),
      dateLocal: d.read<String>('doc_date_local'),
      status: d.read<String>('status'),
      partyId: d.readNullable<String>('party_id'),
      partyName: d.readNullable<String>('party_name'),
      total: Money.paisa(d.read<int>('total_paisa')),
      balance: Money.paisa(d.read<int>('balance_paisa')),
      note: d.readNullable<String>('notes') ?? '',
      enteredBy: await userName(d.read<String>('created_by')),
      head: d.readNullable<String>('head'),
      paidFromAccountId: paidFrom?.read<String>('id'),
      paidBy: [for (final r in paidBy) r.read<String>('payment_no')],
    );
  }

  // -------------------------------------------------------------------------
  // M40 — customers in groups, and a note the counter sees
  // -------------------------------------------------------------------------

  /// What a group's members owe and are owed, from the khata's own balance
  /// expression. Payable is the shop's debts to them as suppliers plus any
  /// money it is holding for them as an advance: both are money the shop
  /// owes them, and neither is netted against what they owe.
  static const _groupMoney = '''
    COALESCE(SUM(CASE WHEN x.balance_paisa > 0
                      THEN x.balance_paisa ELSE 0 END), 0) AS receivable,
    COALESCE(SUM(x.payable_paisa
                 + CASE WHEN x.balance_paisa < 0
                        THEN -x.balance_paisa ELSE 0 END), 0) AS payable
  ''';

  @override
  Future<List<PartyGroupSummary>> partyGroups(String firmId) async {
    // A SUM over the same rows the list shows, never a sum in Dart over a
    // page of them: a route of 400 retailers has a header that counts all
    // 400, whatever the list below it has loaded.
    final rows = await _db
        .customSelect(
          '''
          SELECT x.party_group AS name, COUNT(*) AS members, $_groupMoney
          FROM (
            $_partySelect
            WHERE p.firm_id = ?
              AND p.deleted_at_utc IS NULL
              AND p.is_active = 1
              AND p.party_group IS NOT NULL
              AND TRIM(p.party_group) <> ''
          ) x
          GROUP BY x.party_group
          ORDER BY lower(x.party_group), x.party_group
          ''',
          variables: [Variable<String>(firmId)],
        )
        .get();
    return [
      for (final r in rows)
        PartyGroupSummary(
          name: r.read<String>('name'),
          members: r.read<int>('members'),
          receivable: Money.paisa(r.read<int>('receivable')),
          payable: Money.paisa(r.read<int>('payable')),
        ),
    ];
  }

  @override
  Future<List<PartySummary>> partyList(
    String firmId, {
    PartyListFilter filter = const PartyListFilter(),
    int limit = 300,
  }) async {
    final term = plainSearchText(filter.query);
    // Matched exactly as stored: the chips offer the names the groups query
    // returned, and a tidied copy of one would match nobody.
    final group = filter.group;
    final order = switch (filter.sort) {
      PartySort.name => 'p.name_search, p.id',
      // Most owed first, then the shop's own debts to them: a supplier the
      // shop owes Rs 90,000 belongs above one it owes nothing.
      PartySort.balance =>
        'balance_paisa DESC, payable_paisa DESC, p.name_search, p.id',
      // The date of the oldest debt still standing: the oldest open bill,
      // or the opening balance a customer brought into the app, whichever
      // is older. Nobody who owes nothing is "overdue", so they go last,
      // after anyone whose debt has no date at all.
      PartySort.oldestDue =>
        '''
        CASE WHEN balance_paisa <= 0 THEN '9999-12-31'
             ELSE COALESCE(
               MIN(
                 COALESCE(
                   (SELECT MIN(d.doc_date_local) FROM documents d
                     WHERE d.party_id = p.id
                       AND d.firm_id = p.firm_id
                       AND d.doc_type IN ('sale_invoice', 'other_income')
                       AND d.balance_paisa > 0
                       AND d.status NOT IN ('void', 'draft')
                       AND d.deleted_at_utc IS NULL),
                   CASE WHEN p.opening_balance_paisa > 0
                        THEN p.opening_balance_as_of_local END),
                 COALESCE(
                   CASE WHEN p.opening_balance_paisa > 0
                        THEN p.opening_balance_as_of_local END,
                   (SELECT MIN(d.doc_date_local) FROM documents d
                     WHERE d.party_id = p.id
                       AND d.firm_id = p.firm_id
                       AND d.doc_type IN ('sale_invoice', 'other_income')
                       AND d.balance_paisa > 0
                       AND d.status NOT IN ('void', 'draft')
                       AND d.deleted_at_utc IS NULL))),
               '9999-12-30')
        END,
        balance_paisa DESC, p.name_search, p.id''',
    };
    final rows = await _db
        .customSelect(
          """
          $_partySelect
          WHERE p.firm_id = ?
            AND p.deleted_at_utc IS NULL
            AND p.is_active = 1
            AND (? = '' OR p.name_search LIKE ? OR p.phone LIKE ?)
            AND (? IS NULL OR p.party_group = ?)
            AND (? = 0 OR p.party_group IS NULL OR TRIM(p.party_group) = '')
          ORDER BY $order
          LIMIT ?
          """,
          variables: [
            Variable<String>(firmId),
            Variable<String>(term),
            Variable<String>('%$term%'),
            Variable<String>('%${filter.query.trim()}%'),
            Variable<String>(group),
            Variable<String>(group),
            Variable<int>(filter.ungrouped ? 1 : 0),
            Variable<int>(limit),
          ],
        )
        .get();
    return [for (final r in rows) _party(r)];
  }

  @override
  Future<List<PartyGroupTotals>> partyGroupTotals(
    String firmId, {
    required BusinessDate from,
    required BusinessDate to,
  }) async {
    // Every party the shop has not deleted, hidden ones included: a
    // customer hidden in June still bought in May, and a report for May
    // whose rows did not add up to May's sales would be a report nobody
    // trusts. The trade is joined once per party from one pass over the
    // period's documents, on idx_documents_list.
    final rows = await _db
        .customSelect(
          '''
          SELECT NULLIF(TRIM(x.party_group), '') AS grp,
                 COUNT(*) AS parties,
                 COALESCE(SUM(t.sales), 0) AS sales,
                 COALESCE(SUM(t.sales_returns), 0) AS sales_returns,
                 COALESCE(SUM(t.purchases), 0) AS purchases,
                 COALESCE(SUM(t.purchase_returns), 0) AS purchase_returns,
                 $_groupMoney
          FROM (
            $_partySelect
            WHERE p.firm_id = ?1
              AND p.deleted_at_utc IS NULL
          ) x
          LEFT JOIN (
            SELECT d.party_id,
                   SUM(CASE WHEN d.doc_type = 'sale_invoice'
                            THEN d.total_paisa ELSE 0 END) AS sales,
                   SUM(CASE WHEN d.doc_type = 'sale_return'
                            THEN d.total_paisa ELSE 0 END) AS sales_returns,
                   SUM(CASE WHEN d.doc_type = 'purchase_bill'
                            THEN d.total_paisa ELSE 0 END) AS purchases,
                   SUM(CASE WHEN d.doc_type = 'purchase_return'
                            THEN d.total_paisa ELSE 0 END)
                     AS purchase_returns
            FROM documents d
            WHERE d.firm_id = ?1
              AND d.doc_type IN ('sale_invoice', 'sale_return',
                                 'purchase_bill', 'purchase_return')
              AND d.status = 'posted'
              AND d.doc_date_local BETWEEN ?2 AND ?3
              AND d.party_id IS NOT NULL
              AND d.deleted_at_utc IS NULL
            GROUP BY d.party_id
          ) t ON t.party_id = x.id
          GROUP BY grp
          ORDER BY grp IS NULL, lower(grp), grp
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(from.value),
            Variable<String>(to.value),
          ],
        )
        .get();
    return [
      for (final r in rows)
        PartyGroupTotals(
          group: r.readNullable<String>('grp'),
          parties: r.read<int>('parties'),
          sales: Money.paisa(r.read<int>('sales')),
          salesReturns: Money.paisa(r.read<int>('sales_returns')),
          purchases: Money.paisa(r.read<int>('purchases')),
          purchaseReturns: Money.paisa(r.read<int>('purchase_returns')),
          receivable: Money.paisa(r.read<int>('receivable')),
          payable: Money.paisa(r.read<int>('payable')),
        ),
    ];
  }

  static Map<String, Object?> _jsonOf(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    final decoded = jsonDecode(raw);
    return decoded is Map<String, Object?> ? decoded : const {};
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
    vipRate: _rateOrNull(r, 'vip_rate_milli_paisa'),
    mrp: _moneyOrNull(r, 'mrp_paisa'),
    hsCode: _blankToNull(r.readNullable<String>('hs_code')),
    unitId: r.read<String>('base_unit_id'),
    unitCode: r.read<String>('unit_code'),
    unitDecimals: r.read<int>('unit_decimals'),
    saleRate: Rate.raw(r.read<int>('sale_rate_milli_paisa')),
    stockOnHand: Qty.raw(r.read<int>('stock_thousandths')),
    minStock: Qty.raw(r.read<int>('min_stock_thousandths')),
    tracksStock: r.read<int>('track_stock') == 1,
    tracksBatch: r.read<int>('track_batch') == 1,
    tracksSerial: r.read<int>('track_serial') == 1,
    // The item's own rule (M53); every query here reads `i.*`, so the
    // column is there, and an item that follows the shop's reads null.
    negativeStock: NegativeStock.fromCode(
      r.readNullable<String>('negative_stock'),
    ),
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

  @override
  Future<BillExtras?> billExtras(String firmId, String documentId) async {
    // The party's own row is read beside the bill's snapshot, and used only
    // where the bill recorded nothing: the counter has never snapshotted an
    // address or a tax number, so without the fallback no tax invoice could
    // name its buyer's NTN. A snapshot, where there is one, always wins.
    final doc = await _db
        .customSelect(
          '''
          SELECT d.doc_type, d.party_id, d.created_at_utc,
                 d.party_address_snapshot, d.party_ntn_snapshot,
                 d.party_strn_snapshot,
                 d.vehicle_no, d.bilty_no, d.transporter, d.ship_to,
                 p.phone AS party_phone, p.address_line1, p.address_line2,
                 p.city AS party_city, p.ntn AS party_ntn,
                 p.strn AS party_strn
          FROM documents d
          LEFT JOIN parties p ON p.id = d.party_id
          WHERE d.id = ? AND d.firm_id = ? AND d.deleted_at_utc IS NULL
          ''',
          variables: [Variable<String>(documentId), Variable<String>(firmId)],
          readsFrom: {_db.documents, _db.parties},
        )
        .getSingleOrNull();
    if (doc == null) return null;

    final docType = doc.read<String>('doc_type');
    final partyId = doc.readNullable<String>('party_id');
    final ownAddress = [
      _blankToNull(doc.readNullable<String>('address_line1')),
      _blankToNull(doc.readNullable<String>('address_line2')),
      _blankToNull(doc.readNullable<String>('party_city')),
    ].whereType<String>().join(', ');

    // Every tax on a line, split the way an invoice prints it. Sales tax is
    // the standard tax and whatever is charged in its place — the provincial
    // services tax, the extra tax, FED in sales-tax mode — and its rate is
    // the line's own; further tax is the unregistered buyer's surcharge and
    // is printed on its own.
    final lines = await _db
        .customSelect(
          '''
          SELECT l.line_no, l.taxable_paisa, l.hs_code_snapshot,
                 (SELECT MAX(t.rate_bp) FROM document_line_taxes t
                   WHERE t.document_line_id = l.id
                     AND t.deleted_at_utc IS NULL
                     AND t.tax_kind IN ('sales_tax', 'provincial_st'))
                   AS rate_bp,
                 COALESCE((SELECT SUM(t.amount_paisa) FROM document_line_taxes t
                   WHERE t.document_line_id = l.id
                     AND t.deleted_at_utc IS NULL
                     AND t.tax_kind IN ('sales_tax', 'provincial_st',
                                        'extra_tax', 'fed', 'cess')), 0)
                   AS sales_tax_paisa,
                 COALESCE((SELECT SUM(t.amount_paisa) FROM document_line_taxes t
                   WHERE t.document_line_id = l.id
                     AND t.deleted_at_utc IS NULL
                     AND t.tax_kind = 'further_tax'), 0)
                   AS further_tax_paisa
          FROM document_lines l
          WHERE l.document_id = ? AND l.deleted_at_utc IS NULL
          ORDER BY l.line_no
          ''',
          variables: [Variable<String>(documentId)],
          readsFrom: {_db.documentLines, _db.documentLineTaxes},
        )
        .get();

    return BillExtras(
      docType: docType,
      partyId: partyId,
      partyPhone: _blankToNull(doc.readNullable<String>('party_phone')),
      partyAddress:
          _blankToNull(doc.readNullable<String>('party_address_snapshot')) ??
          _blankToNull(ownAddress),
      partyNtn:
          _blankToNull(doc.readNullable<String>('party_ntn_snapshot')) ??
          _blankToNull(doc.readNullable<String>('party_ntn')),
      partyStrn:
          _blankToNull(doc.readNullable<String>('party_strn_snapshot')) ??
          _blankToNull(doc.readNullable<String>('party_strn')),
      transport: ReceiptTransport(
        transporter: _blankToNull(doc.readNullable<String>('transporter')),
        vehicleNo: _blankToNull(doc.readNullable<String>('vehicle_no')),
        biltyNo: _blankToNull(doc.readNullable<String>('bilty_no')),
        shipTo: _blankToNull(doc.readNullable<String>('ship_to')),
      ),
      lineTaxes: [
        for (final l in lines)
          ReceiptLineTax(
            valueExclTax: Money.paisa(l.read<int>('taxable_paisa')),
            salesTax: Money.paisa(l.read<int>('sales_tax_paisa')),
            rateBp: l.readNullable<int>('rate_bp'),
            furtherTax: Money.paisa(l.read<int>('further_tax_paisa')),
            hsCode: _blankToNull(l.readNullable<String>('hs_code_snapshot')),
          ),
      ],
      khata: docType == 'sale_invoice' && partyId != null
          ? await _khataAtBill(firmId, documentId, partyId)
          : null,
    );
  }

  /// The customer's khata at the moment [documentId] was made (M51).
  ///
  /// Read from the journal, because the journal is the one record of the
  /// khata that keeps its own history: a bill's `balance_paisa` is rewritten
  /// as payments come in, and the party's balance is a figure for today. The
  /// receivable and the advances the shop holds for them are both on lines
  /// carrying the party, so a sum over those lines up to a point in time is
  /// what the khata said at that point — opening balance, bills, payments,
  /// returns, bounced cheques and every correction included.
  ///
  /// "Up to" is in the order things were recorded, not the order of their
  /// dates. That is what the shop's screen showed when the bill was made,
  /// and so what the first sheet printed; a payment back-dated into last
  /// week on a later day was not on that sheet and is not on its duplicate.
  /// A payment recorded before the bill and cancelled after it is counted,
  /// as it was then; its cancellation is a later entry of its own.
  ///
  /// Null when the bill has no sale entry to stand on, which no posted sale
  /// should lack: better no block than a block that guesses.
  Future<KhataAtBill?> _khataAtBill(
    String firmId,
    String documentId,
    String partyId,
  ) async {
    final sale = await _db
        .customSelect(
          '''
          SELECT je.id, je.created_at_utc FROM journal_entries je
          WHERE je.document_id = ? AND je.firm_id = ?
            AND je.source_type = 'sale' AND je.deleted_at_utc IS NULL
          ORDER BY je.created_at_utc, je.id
          LIMIT 1
          ''',
          variables: [Variable<String>(documentId), Variable<String>(firmId)],
          readsFrom: {_db.journalEntries},
        )
        .getSingleOrNull();
    if (sale == null) return null;
    final entryId = sale.read<String>('id');
    final at = sale.read<int>('created_at_utc');

    // Both sums ride idx_jl_party.
    const khataAccounts =
        "a.system_key IN ('accounts_receivable', 'customer_advances')";
    final thisBill = await _db
        .customSelect(
          '''
          SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS owed
          FROM journal_lines jl
          JOIN accounts a ON a.id = jl.account_id
          WHERE jl.journal_entry_id = ? AND jl.party_id = ?
            AND jl.deleted_at_utc IS NULL AND $khataAccounts
          ''',
          variables: [Variable<String>(entryId), Variable<String>(partyId)],
          readsFrom: {_db.journalLines, _db.accounts},
        )
        .getSingle();
    // Strictly before the bill's own entry: earlier in time, or recorded in
    // the same millisecond with an id that sorts first, which for one
    // phone's ULIDs is the order they were made in.
    final before = await _db
        .customSelect(
          '''
          SELECT COALESCE(SUM(jl.debit_paisa - jl.credit_paisa), 0) AS owed
          FROM journal_lines jl
          JOIN journal_entries je ON je.id = jl.journal_entry_id
          JOIN accounts a ON a.id = jl.account_id
          WHERE jl.party_id = ? AND jl.firm_id = ?
            AND jl.deleted_at_utc IS NULL AND je.deleted_at_utc IS NULL
            AND $khataAccounts
            AND (je.created_at_utc < ?
                 OR (je.created_at_utc = ? AND je.id < ?))
          ''',
          variables: [
            Variable<String>(partyId),
            Variable<String>(firmId),
            Variable<int>(at),
            Variable<int>(at),
            Variable<String>(entryId),
          ],
          readsFrom: {_db.journalLines, _db.journalEntries, _db.accounts},
        )
        .getSingle();
    return KhataAtBill(
      before: Money.paisa(before.read<int>('owed')),
      thisBill: Money.paisa(thisBill.read<int>('owed')),
    );
  }

  /// The one SELECT for who a customer is and what they owe, for a reader
  /// outside this class that must not grow a second idea of either (M38's
  /// chase list). Ends at `FROM parties p`; the caller adds its WHERE.
  static String get partySelectSql => _partySelect;

  /// A row of [partySelectSql], read the way every screen reads it.
  static PartySummary partyFromRow(QueryRow row) => _party(row);

  // -------------------------------------------------------------------------
  // M36 — a bill rung again, or put right and issued again
  // -------------------------------------------------------------------------

  @override
  Future<BillCopy?> billCopy(String firmId, String documentId) async {
    final doc = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_no, d.status, d.party_id, d.party_name_snapshot,
                 d.bill_discount_paisa, d.rounding_mode
          FROM documents d
          WHERE d.id = ? AND d.firm_id = ? AND d.doc_type = 'sale_invoice'
            AND d.status IN ('posted', 'void') AND d.deleted_at_utc IS NULL
          ''',
          variables: [Variable<String>(documentId), Variable<String>(firmId)],
          readsFrom: {_db.documents},
        )
        .getSingleOrNull();
    if (doc == null) return null;

    // The item as it stands now beside the line as it was billed: a line
    // whose item has since been archived or deleted is said so, never
    // quietly put back on a bill the counter would not have let it onto.
    final lines = await _db
        .customSelect(
          '''
          SELECT dl.item_id, dl.item_name_snapshot, dl.qty_thousandths,
                 dl.unit_id, dl.unit_code_snapshot, dl.rate_milli_paisa,
                 dl.discount_bp, dl.discount_paisa, dl.lot_id,
                 dl.is_free_item, lot.lot_no,
                 CASE WHEN dl.item_id IS NULL THEN 0
                      WHEN i.id IS NULL OR i.deleted_at_utc IS NOT NULL
                        OR i.is_active = 0 THEN 1
                      ELSE 0 END AS item_gone
          FROM document_lines dl
          LEFT JOIN items i ON i.id = dl.item_id
          LEFT JOIN stock_lots lot ON lot.id = dl.lot_id
          WHERE dl.document_id = ? AND dl.deleted_at_utc IS NULL
          ORDER BY dl.line_no
          ''',
          variables: [Variable<String>(documentId)],
          readsFrom: {_db.documentLines, _db.items, _db.stockLots},
        )
        .get();

    // The bill's own tenders (`exact`, written by the sale for itself),
    // still standing. A receipt taken later against the khata is not money
    // "paid on this bill" in the sense the counter means, and a bill with
    // one cannot be cancelled anyway.
    final tenders = await _db
        .customSelect(
          '''
          SELECT p.mode, pa.amount_paisa, p.reference, p.cheque_no,
                 p.cheque_bank, p.cheque_date_utc
          FROM payment_allocations pa
          JOIN payments p ON p.id = pa.payment_id
          WHERE pa.document_id = ? AND pa.deleted_at_utc IS NULL
            AND pa.allocation_mode = 'exact'
            AND p.deleted_at_utc IS NULL AND p.status <> 'void'
            AND p.direction = 'in'
          ORDER BY p.payment_no
          ''',
          variables: [Variable<String>(documentId)],
          readsFrom: {_db.paymentAllocations, _db.payments},
        )
        .get();

    return BillCopy(
      documentId: doc.read<String>('id'),
      docNo: doc.read<String>('doc_no'),
      isVoid: doc.read<String>('status') == 'void',
      partyId: doc.readNullable<String>('party_id'),
      partyName: doc.readNullable<String>('party_name_snapshot'),
      billDiscount: Money.paisa(doc.read<int>('bill_discount_paisa')),
      roundingMode: switch (doc.read<String>('rounding_mode')) {
        'half_even' => RoundingMode.halfEven,
        'truncate' => RoundingMode.truncate,
        'ceil_abs' => RoundingMode.ceilAbs,
        _ => RoundingMode.halfUp,
      },
      lines: [
        for (final r in lines)
          BillCopyLine(
            itemId: r.readNullable<String>('item_id'),
            name: r.read<String>('item_name_snapshot'),
            qty: Qty.raw(r.read<int>('qty_thousandths')),
            unitId: r.readNullable<String>('unit_id'),
            unitCode: r.read<String>('unit_code_snapshot'),
            rate: Rate.raw(r.read<int>('rate_milli_paisa')),
            discountBp: r.read<int>('discount_bp'),
            discount: Money.paisa(r.read<int>('discount_paisa')),
            lotId: r.readNullable<String>('lot_id'),
            lotNo: r.readNullable<String>('lot_no'),
            isFree: r.read<int>('is_free_item') == 1,
            itemGone: r.read<int>('item_gone') == 1,
          ),
      ],
      tenders: [
        for (final r in tenders)
          BillCopyTender(
            mode: r.read<String>('mode'),
            amount: Money.paisa(r.read<int>('amount_paisa')),
            reference: r.readNullable<String>('reference'),
            chequeNo: r.readNullable<String>('cheque_no'),
            chequeBank: r.readNullable<String>('cheque_bank'),
            chequeDateUtcMillis: r.readNullable<int>('cheque_date_utc'),
          ),
      ],
    );
  }

  @override
  Future<LinkedBill?> lastBillFor(String firmId, String partyId) async {
    // Through the party's own index, newest first: the cost is this
    // customer's history, not the shop's.
    final row = await _db
        .customSelect(
          '''
          SELECT id, doc_no FROM documents
          WHERE party_id = ? AND firm_id = ? AND doc_type = 'sale_invoice'
            AND status = 'posted' AND deleted_at_utc IS NULL
          ORDER BY doc_date_local DESC, doc_date_utc DESC, doc_seq DESC
          LIMIT 1
          ''',
          variables: [Variable<String>(partyId), Variable<String>(firmId)],
          readsFrom: {_db.documents},
        )
        .getSingleOrNull();
    if (row == null) return null;
    return LinkedBill(
      id: row.read<String>('id'),
      docNo: row.read<String>('doc_no'),
    );
  }

  @override
  Future<BillLinks> billLinks(String firmId, String documentId) async {
    LinkedBill? read(QueryRow? r) => r == null
        ? null
        : LinkedBill(
            id: r.read<String>('id'),
            docNo: r.read<String>('doc_no'),
            isVoid: r.read<String>('status') == 'void',
          );

    final replaces = await _db
        .customSelect(
          '''
          SELECT o.id, o.doc_no, o.status FROM doc_links link
          JOIN documents o ON o.id = link.from_document_id
          WHERE link.to_document_id = ? AND link.link_type = 'revises'
            AND link.deleted_at_utc IS NULL AND o.firm_id = ?
          LIMIT 1
          ''',
          variables: [Variable<String>(documentId), Variable<String>(firmId)],
          readsFrom: {_db.docLinks, _db.documents},
        )
        .getSingleOrNull();
    final replacedBy = await _db
        .customSelect(
          '''
          SELECT n.id, n.doc_no, n.status FROM doc_links link
          JOIN documents n ON n.id = link.to_document_id
          WHERE link.from_document_id = ? AND link.link_type = 'revises'
            AND link.deleted_at_utc IS NULL AND n.firm_id = ?
          ORDER BY n.created_at_utc DESC, n.id DESC
          LIMIT 1
          ''',
          variables: [Variable<String>(documentId), Variable<String>(firmId)],
          readsFrom: {_db.docLinks, _db.documents},
        )
        .getSingleOrNull();
    return BillLinks(replaces: read(replaces), replacedBy: read(replacedBy));
  }
}

/// The read behind the last rates beside a counter line (M37), exposed so a
/// test can ask SQLite how it means to run it.
///
/// The counter asks this for every line it shows a named customer, so it has
/// to cost what the customer's own history costs and not what the shop's
/// does. Two plans are written down rather than left to the planner:
///
///  * with a party, its bills newest first through `idx_documents_party`,
///    each bill's lines through `idx_doclines_seq` -- a regular buyer's last
///    five are found in his last few bills, and one who never bought the
///    item costs his own bills and no more;
///  * without one (the last delivery from anybody), the shop's bills of that
///    kind newest first through `idx_documents_list`.
///
/// `INDEXED BY` rather than a hope. Without statistics SQLite can just as
/// well choose `idx_doclines_item` for the inner loop and read every line of
/// a best-selling item once for every bill of the customer's -- right, and
/// slow in exactly the shop that most needs this. Named, the plan cannot
/// drift; and if the index is ever dropped the query fails loudly instead of
/// quietly scanning. No new index was added: the schema stays at v8.
///
/// Lines of one bill at one price are one deal, their quantities added.
String pastDealsSql({required bool forParty}) =>
    """
    SELECT d.id AS document_id, d.doc_no, d.doc_date_local,
           COALESCE(d.party_name_snapshot,
                    (SELECT p.name FROM parties p WHERE p.id = d.party_id))
             AS party_name,
           l.unit_id, l.unit_code_snapshot, l.rate_milli_paisa, l.discount_bp,
           SUM(l.qty_thousandths) AS qty,
           SUM(l.discount_paisa) AS discount
    FROM documents AS d
         INDEXED BY ${forParty ? 'idx_documents_party' : 'idx_documents_list'}
    CROSS JOIN document_lines AS l INDEXED BY idx_doclines_seq
    WHERE ${forParty ? 'd.party_id = ? AND ' : ''}d.firm_id = ?
      AND d.doc_type = ?
      AND d.status = 'posted'
      AND d.deleted_at_utc IS NULL
      AND l.document_id = d.id
      AND l.item_id = ?
      AND l.deleted_at_utc IS NULL
      AND l.is_free_item = 0
    GROUP BY d.id, l.unit_id, l.unit_code_snapshot, l.rate_milli_paisa,
             l.discount_bp
    ORDER BY d.doc_date_local DESC, d.doc_date_utc DESC, d.doc_seq DESC,
             MIN(l.line_no)
    LIMIT ?
    """;

/// The line a free plan's bills end with.
const madeWithLine = 'Bazaar Ledger app se banaya gaya';
