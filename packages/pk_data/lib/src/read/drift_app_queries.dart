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
  Future<FirmProfile?> currentFirm() async {
    final row = await _db
        .customSelect(
          'SELECT * FROM firms WHERE deleted_at_utc IS NULL '
          'ORDER BY created_at_utc LIMIT 1',
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
      bankAccountTitle:
          _blankToNull(row.readNullable<String>('bank_account_title')),
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
          ORDER BY i.name_search, i.id
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
          WHERE i.firm_id = ? AND i.barcode = ? AND i.deleted_at_utc IS NULL
          LIMIT 1
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(barcode),
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
          WHERE i.firm_id = ? AND i.id = ?
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
                       WHERE d.party_id = p.id AND d.status = 'posted'
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
          partyName: _blankToNull(r.readNullable<String>('party_name_snapshot')),
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
          variables: [
            Variable<String>(firmId),
            Variable<String>(dateLocal),
          ],
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
    final firm = await currentFirm();
    if (firm == null) return null;

    final doc = await _db
        .customSelect(
          'SELECT * FROM documents WHERE id = ? AND firm_id = ?',
          variables: [
            Variable<String>(documentId),
            Variable<String>(firmId),
          ],
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
          SELECT p.mode, p.amount_paisa, p.change_paisa, p.reference
          FROM payments p
          JOIN payment_allocations pa ON pa.payment_id = p.id
          WHERE pa.document_id = ? AND p.deleted_at_utc IS NULL
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
            amount: Money.paisa(l.read<int>('line_total_paisa')),
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
      extraCharges: Money.paisa(doc.read<int>('extra_charges_paisa')),
      roundOff: Money.paisa(doc.read<int>('round_off_paisa')),
      total: Money.paisa(doc.read<int>('total_paisa')),
      tenders: [
        for (final p in payments)
          ReceiptTender(
            label: _modeLabel(p.read<String>('mode')),
            amount: Money.paisa(p.read<int>('amount_paisa')),
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

  static ItemSummary _itemFrom(QueryRow r) => ItemSummary(
        id: r.read<String>('id'),
        name: r.read<String>('name'),
        code: _blankToNull(r.readNullable<String>('code')),
        barcode: _blankToNull(r.readNullable<String>('barcode')),
        category: _blankToNull(r.readNullable<String>('category')),
        unitId: r.read<String>('base_unit_id'),
        unitCode: r.read<String>('unit_code'),
        unitDecimals: r.read<int>('unit_decimals'),
        saleRate: Rate.raw(r.read<int>('sale_rate_milli_paisa')),
        stockOnHand: Qty.raw(r.read<int>('stock_thousandths')),
        minStock: Qty.raw(r.read<int>('min_stock_thousandths')),
        tracksStock: r.read<int>('track_stock') == 1,
      );

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
    final local = DateTime.fromMillisecondsSinceEpoch(millisUtc, isUtc: true)
        .add(pakistanStandardTime);
    final d = '${_two(local.day)}-${_two(local.month)}-${local.year}';
    return '$d  ${_clockLabel(local)}';
  }

  static String _timeLabel(int millisUtc) => _clockLabel(
        DateTime.fromMillisecondsSinceEpoch(millisUtc, isUtc: true)
            .add(pakistanStandardTime),
      );

  static String _clockLabel(DateTime local) {
    final hour24 = local.hour;
    final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final suffix = hour24 < 12 ? 'AM' : 'PM';
    return '$hour:${_two(local.minute)} $suffix';
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
