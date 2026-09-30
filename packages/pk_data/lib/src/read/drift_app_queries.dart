import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';
import '../write/drift_cheque_writer.dart'
    show
        chequeInHandFrom,
        chequeInHandSelect,
        chequeIssuedFrom,
        chequeIssuedSelect;
import '../write/drift_day_close_writer.dart' show cashInDrawerSql;
import '../write/drift_purchase_return_writer.dart'
    show boughtLineFrom, returnedOffDeliveryLine;

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
  const DriftAppQueries(this._db, {this.activeFirmId});

  final AppDatabase _db;

  /// The firm the phone has open, when it keeps more than one. Without it,
  /// the current firm is the first one set up.
  final String? Function()? activeFirmId;

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
  Future<List<PartySummary>> searchParties(
    String firmId, {
    String query = '',
    int limit = 40,
  }) async {
    final term = _normalise(query);
    final rows = await _db
        .customSelect(
          """
          $_partySelect
          WHERE p.firm_id = ?
            AND p.deleted_at_utc IS NULL
            AND p.is_active = 1
            AND (? = '' OR p.name_search LIKE ? OR p.phone LIKE ?)
          ORDER BY p.name_search
          LIMIT ?
          """,
          variables: [
            Variable<String>(firmId),
            Variable<String>(term),
            Variable<String>('%$term%'),
            Variable<String>('%${query.trim()}%'),
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
  static const _partySelect = '''
    SELECT p.id, p.name, p.phone, p.party_type, p.credit_limit_paisa,
           p.price_tier, p.default_discount_bp,
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
            Variable<int>(limit),
          ],
          readsFrom: {_db.documents, _db.payments, _db.journalEntries},
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
    // Deliberately the same query as `DriftReturnWriter.billFor`, down to the
    // subquery that counts earlier returns. Two different counts of what is
    // left would let the screen offer a quantity the writer then refuses,
    // which is the worst of both — the shopkeeper picks, taps, and is told no.
    final rows = await _db
        .customSelect(
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
                     AND rl.item_id = dl.item_id
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
          JOIN documents d ON d.id = dl.document_id
          WHERE dl.document_id = ? AND d.firm_id = ?
            AND d.status = 'posted'
            AND dl.deleted_at_utc IS NULL
          ORDER BY dl.line_no
          ''',
          variables: [Variable<String>(documentId), Variable<String>(firmId)],
          readsFrom: {_db.documentLines, _db.documents, _db.docLinks},
        )
        .get();

    return [
      for (final r in rows)
        SoldLine(
          documentLineId: r.read<String>('id'),
          itemId: r.read<String>('item_id'),
          itemName: r.read<String>('item_name_snapshot'),
          unitId: r.readNullable<String>('unit_id') ?? '',
          unitCode: r.read<String>('unit_code_snapshot'),
          soldQty: Qty.raw(r.read<int>('base_qty_thousandths')),
          alreadyReturned: Qty.raw(r.read<int>('returned')),
          rate: Rate.raw(r.read<int>('rate_milli_paisa')),
          cost: Money.paisa(r.read<int>('cost_paisa')),
          salesTax: Money.paisa(r.read<int>('sales_tax')),
          furtherTax: Money.paisa(r.read<int>('further_tax')),
          taxInclusive: r.read<int>('tax_inclusive') == 1,
        ),
    ];
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
          SELECT id, doc_date_local, doc_seq, balance_paisa
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
                 a.summary, a.amount_paisa
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
                 a.summary, a.amount_paisa
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
                 dl.unit_code_snapshot, dl.base_qty_thousandths,
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
                 (SELECT a.system_key
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
          // the books, and filing it under misc here would hide it.
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

    final (docTitle, docLabel) = switch (doc.read<String>('doc_type')) {
      'quotation' => ('Quotation', 'Quotation No'),
      'delivery_challan' => ('Delivery Challan', 'Challan No'),
      'other_income' => ('Debit Note', 'Note No'),
      _ => ('Invoice', 'Bill No'),
    };
    final terms = _blankToNull(doc.readNullable<String>('terms'));
    return ReceiptData(
      shop: firm.toReceiptShop(),
      docNo: doc.read<String>('doc_no'),
      docTitle: docTitle,
      docLabel: docLabel,
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
      footerLines: [?terms, 'Shukriya! Phir tashreef laayen'],
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
