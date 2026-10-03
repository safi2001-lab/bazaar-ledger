import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';

/// A challan still waiting for its bill (M25, M55): posted, not cancelled,
/// and not billed on a bill that stands. `d` is the challan.
///
/// The same test the challans list reads `billed_as` by — a `converted_from`
/// link from the challan to a bill that is not void — so the khata and the
/// list cannot disagree about which challans are still open.
const unbilledChallanSql = '''
  d.doc_type = 'delivery_challan'
  AND d.status = 'posted'
  AND d.deleted_at_utc IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM doc_links link
    JOIN documents bill ON bill.id = link.to_document_id
    WHERE link.from_document_id = d.id
      AND link.link_type = 'converted_from'
      AND link.deleted_at_utc IS NULL
      AND bill.status <> 'void'
  )
''';

/// A challan line given with the rate still to be agreed: an item, at no
/// rate, and not a free item (which carries no rate on purpose). `dl` is the
/// line.
const unpricedLineSql = '''
  dl.deleted_at_utc IS NULL
  AND dl.item_id IS NOT NULL
  AND dl.rate_milli_paisa = 0
  AND dl.is_free_item = 0
''';

/// The drift implementation of [CollectionQueries] (M55).
final class DriftCollectionQueries implements CollectionQueries {
  const DriftCollectionQueries(this._db);

  final AppDatabase _db;

  @override
  Future<List<GoodsGiven>> goodsGivenTo(String firmId, String partyId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT d.id, d.doc_no, d.doc_date_local, d.party_id,
                 d.party_name_snapshot, d.notes,
                 dl.item_id, dl.item_name_snapshot, dl.qty_thousandths,
                 dl.unit_id, dl.unit_code_snapshot, dl.rate_milli_paisa,
                 dl.is_free_item, dl.discount_bp, dl.discount_paisa
          FROM documents d
          JOIN document_lines dl ON dl.document_id = d.id
          WHERE d.firm_id = ?1 AND d.party_id = ?2 AND $unbilledChallanSql
            AND dl.deleted_at_utc IS NULL AND dl.item_id IS NOT NULL
          ORDER BY d.doc_date_local, d.doc_seq, d.id, dl.line_no
          ''',
          variables: [Variable<String>(firmId), Variable<String>(partyId)],
          readsFrom: {_db.documents, _db.documentLines, _db.docLinks},
        )
        .get();

    final order = <String>[];
    final heads = <String, QueryRow>{};
    final lines = <String, List<GoodsGivenLine>>{};
    for (final r in rows) {
      final id = r.read<String>('id');
      if (!heads.containsKey(id)) {
        heads[id] = r;
        order.add(id);
      }
      final bp = r.read<int>('discount_bp');
      final discount = r.read<int>('discount_paisa');
      (lines[id] ??= []).add(
        GoodsGivenLine(
          itemId: r.read<String>('item_id'),
          itemName: r.read<String>('item_name_snapshot'),
          qty: Qty.raw(r.read<int>('qty_thousandths')),
          unitId: r.readNullable<String>('unit_id'),
          unitCode: r.read<String>('unit_code_snapshot'),
          rate: Rate.raw(r.read<int>('rate_milli_paisa')),
          isFree: r.read<int>('is_free_item') == 1,
          discountBp: bp,
          discount: Money.paisa(discount),
        ),
      );
    }
    return [
      for (final id in order)
        GoodsGiven(
          challanId: id,
          docNo: heads[id]!.read<String>('doc_no'),
          dateLocal: heads[id]!.read<String>('doc_date_local'),
          partyId: heads[id]!.readNullable<String>('party_id'),
          partyName: heads[id]!.readNullable<String>('party_name_snapshot'),
          notes: heads[id]!.readNullable<String>('notes'),
          lines: lines[id]!,
        ),
    ];
  }

  @override
  Future<List<UnpricedParty>> unpricedParties(String firmId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT d.party_id, p.name, COUNT(*) AS lines,
                 COUNT(DISTINCT d.id) AS challans,
                 MIN(d.doc_date_local) AS oldest
          FROM documents d
          JOIN document_lines dl ON dl.document_id = d.id
          JOIN parties p ON p.id = d.party_id
          WHERE d.firm_id = ?1 AND $unbilledChallanSql AND $unpricedLineSql
            AND p.deleted_at_utc IS NULL
          GROUP BY d.party_id, p.name
          ORDER BY oldest, p.name
          ''',
          variables: [Variable<String>(firmId)],
          readsFrom: {
            _db.documents,
            _db.documentLines,
            _db.docLinks,
            _db.parties,
          },
        )
        .get();
    return [
      for (final r in rows)
        UnpricedParty(
          partyId: r.read<String>('party_id'),
          partyName: r.read<String>('name'),
          lines: r.read<int>('lines'),
          challans: r.read<int>('challans'),
          oldestLocal: r.read<String>('oldest'),
        ),
    ];
  }

  @override
  Future<List<CollectionSheet>> sheets(String firmId, {int limit = 100}) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT id, setting_value FROM settings
          WHERE firm_id = ? AND setting_key LIKE ? AND deleted_at_utc IS NULL
          ORDER BY created_at_utc DESC, id DESC
          LIMIT ?
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>('$collectionSheetKeyPrefix%'),
            Variable<int>(limit),
          ],
          readsFrom: {_db.settings},
        )
        .get();
    return [for (final r in rows) ?_sheetOf(r)];
  }

  @override
  Future<CollectionSheet?> sheet(String firmId, String sheetId) async {
    final row = await _db
        .customSelect(
          'SELECT id, setting_value FROM settings '
          'WHERE id = ? AND firm_id = ? AND setting_key = ? '
          '  AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(sheetId),
            Variable<String>(firmId),
            Variable<String>(collectionSheetKey(sheetId)),
          ],
          readsFrom: {_db.settings},
        )
        .getSingleOrNull();
    return row == null ? null : _sheetOf(row);
  }

  static CollectionSheet? _sheetOf(QueryRow row) {
    try {
      return CollectionSheet.fromJson(
        row.read<String>('id'),
        jsonDecode(row.read<String>('setting_value')),
      );
    } on FormatException {
      // A row nobody can read is not a sheet: left out rather than taking
      // the whole list down with it.
      return null;
    }
  }
}
