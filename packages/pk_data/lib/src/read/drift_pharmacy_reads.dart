import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';
import 'drift_app_queries.dart';

/// The pharmacy pack's reads (M49): the shop's standing, a medicine's
/// substitutes, the batches going out of date and the deliveries they came
/// on, and what a bill may charge under the printed prices.
///
/// Called inside the sale's own transaction by the use case, and outside it
/// by the counter — drift runs a read made on the database within a
/// transaction block in that transaction — so the counter's question and the
/// refusal beneath it are worked out from one reading, the way M53's shelf
/// is.
final class DriftPharmacyReads implements PharmacyReader {
  const DriftPharmacyReads(this._db);

  final AppDatabase _db;

  /// M54: the prescription [documentId]'s Schedule lines were registered
  /// against — a challan's, for the bill made from it — or null.
  Future<Prescription?> prescriptionOn(String firmId, String documentId) async {
    final r = await _db
        .customSelect(
          '''
          SELECT patient_name, patient_address, prescriber_name,
                 prescriber_reg_no, prescription_ref
          FROM prescriptions
          WHERE firm_id = ? AND document_id = ? AND deleted_at_utc IS NULL
          ORDER BY created_at_utc LIMIT 1
          ''',
          variables: [Variable<String>(firmId), Variable<String>(documentId)],
          readsFrom: {_db.prescriptions},
        )
        .getSingleOrNull();
    if (r == null) return null;
    return Prescription(
      patientName: r.read<String>('patient_name'),
      patientAddress: r.readNullable<String>('patient_address'),
      prescriberName: r.read<String>('prescriber_name'),
      prescriberRegNo: r.read<String>('prescriber_reg_no'),
      reference: r.readNullable<String>('prescription_ref'),
    );
  }

  @override
  Future<PharmacyRules> rulesFor(String firmId) async {
    final row = await _db
        .customSelect(
          '''
          SELECT f.business_kind,
                 (SELECT s.setting_value FROM settings s
                   WHERE s.firm_id = f.id AND s.setting_key = ?
                     AND s.deleted_at_utc IS NULL) AS off_mrp
          FROM firms f WHERE f.id = ?
          ''',
          variables: [
            const Variable<String>(offMrpSettingKey),
            Variable<String>(firmId),
          ],
        )
        .getSingleOrNull();
    if (row == null) return PharmacyRules.none;
    final off = int.tryParse(row.readNullable<String>('off_mrp') ?? '') ?? 0;
    return PharmacyRules(
      isPharmacy: row.read<String>('business_kind') == 'pharmacy',
      offMrpBp: off.clamp(0, 10000),
    );
  }

  @override
  Future<Map<String, MedicineOnBill>> medicinesFor(
    ActorContext actor,
    Map<String, Qty> baseQtyByItem, {
    required String locationCode,
  }) async {
    final ids = baseQtyByItem.keys.toList();
    if (ids.isEmpty) return const {};
    final rows = await _db
        .customSelect(
          '''
          SELECT id, name, schedule_class, mrp_paisa, track_batch
          FROM items
          WHERE firm_id = ? AND id IN (${List.filled(ids.length, '?').join(', ')})
          ''',
          variables: [
            Variable<String>(actor.firmId),
            for (final id in ids) Variable<String>(id),
          ],
        )
        .get();
    final out = <String, MedicineOnBill>{};
    for (final r in rows) {
      final id = r.read<String>('id');
      final qty = baseQtyByItem[id]!;
      final itemMrp = switch (r.readNullable<int>('mrp_paisa')) {
        final int p => Money.paisa(p),
        null => null,
      };
      final batches = r.read<int>('track_batch') == 1
          ? await _batchCeiling(actor, id, qty, locationCode, itemMrp)
          : (
              ceiling: retailValueOf(mrp: itemMrp, baseQty: qty),
              refused: null,
            );
      out[id] = MedicineOnBill(
        itemId: id,
        itemName: r.read<String>('name'),
        schedule: ScheduleClass.fromCode(
          r.readNullable<String>('schedule_class'),
        ),
        ceiling: batches.ceiling,
        refused: batches.refused,
      );
    }
    return out;
  }

  /// The most [qty] of a batch item may be sold for: each part at the price
  /// printed on the batch first-expiry-first-out takes it from, or the
  /// item's own where the batch has none. Null when some part of it has no
  /// printed price at all, since nothing then bounds the whole; and the
  /// item's own price when the batches cannot make it up, which the sale
  /// path refuses in its own words a moment later.
  Future<({Money? ceiling, String? refused})> _batchCeiling(
    ActorContext actor,
    String itemId,
    Qty qty,
    String location,
    Money? itemMrp,
  ) async {
    final lots = await lotBalances(itemId, location);
    final List<LotTake> takes;
    try {
      takes = takeFefo(
        needed: qty,
        lots: lots,
        unlotted: await _unlotted(itemId, location),
        today: actor.businessDate,
      );
    } on StockRefused catch (refused) {
      return (
        ceiling: retailValueOf(mrp: itemMrp, baseQty: qty),
        refused: refused.reason,
      );
    }
    final byId = {for (final l in lots) l.lotId: l};
    var ceiling = Money.zero;
    for (final take in takes) {
      // The one place a printed price is multiplied out (pricing/mrp.dart).
      final part = retailValueOf(
        mrp: byId[take.lotId]?.mrp ?? itemMrp,
        baseQty: take.qty,
      );
      if (part == null) return (ceiling: null, refused: null);
      ceiling += part;
    }
    return (ceiling: ceiling, refused: null);
  }

  /// Why batch [lotNo] of [itemId] may not be sold, when it is on hold; null
  /// when it may, or there is no such batch. What a scanned pack is checked
  /// against at the counter.
  Future<String?> holdReasonOf(
    String firmId,
    String itemId,
    String lotNo,
  ) async {
    final row = await _db
        .customSelect(
          'SELECT hold_reason FROM stock_lots '
          'WHERE firm_id = ? AND item_id = ? AND lot_no = ? '
          'AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(firmId),
            Variable<String>(itemId),
            Variable<String>(lotNo),
          ],
        )
        .getSingleOrNull();
    return row?.readNullable<String>('hold_reason');
  }

  /// What is left in each batch of [itemId] at [location], with its hold and
  /// its printed price: the reading first-expiry-first-out is run over.
  Future<List<LotBalance>> lotBalances(String itemId, String location) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT l.id, l.lot_no, l.expiry_date_local, l.hold_reason,
                 l.mrp_paisa, SUM(s.qty_delta_thousandths) AS qty
          FROM stock_lots l JOIN stock_ledger s ON s.lot_id = l.id
          WHERE l.item_id = ? AND s.location_code = ?
            AND s.deleted_at_utc IS NULL AND l.deleted_at_utc IS NULL
          GROUP BY l.id HAVING SUM(s.qty_delta_thousandths) > 0
          ''',
          variables: [Variable<String>(itemId), Variable<String>(location)],
        )
        .get();
    return [
      for (final r in rows)
        LotBalance(
          lotId: r.read<String>('id'),
          lotNo: r.read<String>('lot_no'),
          qty: Qty.raw(r.read<int>('qty')),
          expiry: switch (r.readNullable<String>('expiry_date_local')) {
            final String d => BusinessDate(d),
            null => null,
          },
          holdReason: r.readNullable<String>('hold_reason'),
          mrp: switch (r.readNullable<int>('mrp_paisa')) {
            final int p => Money.paisa(p),
            null => null,
          },
        ),
    ];
  }

  Future<Qty> _unlotted(String itemId, String location) async {
    final row = await _db
        .customSelect(
          'SELECT COALESCE(SUM(qty_delta_thousandths), 0) AS qty '
          'FROM stock_ledger WHERE item_id = ? AND location_code = ? '
          'AND lot_id IS NULL AND deleted_at_utc IS NULL',
          variables: [Variable<String>(itemId), Variable<String>(location)],
        )
        .getSingle();
    return Qty.raw(row.read<int>('qty'));
  }

  /// The items with the same salt and strength as [itemId], the ones on the
  /// shelf first: what the chemist offers when the brand asked for is out.
  /// Empty for an item with no salt.
  Future<List<ItemSummary>> substitutes(String firmId, String itemId) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT o.id
          FROM items i
          JOIN items o
            ON o.firm_id = i.firm_id AND o.generic_search = i.generic_search
          WHERE i.id = ? AND i.firm_id = ? AND i.generic_search IS NOT NULL
            AND o.id <> i.id AND o.is_active = 1 AND o.deleted_at_utc IS NULL
          ORDER BY o.name_search
          LIMIT 50
          ''',
          variables: [Variable<String>(itemId), Variable<String>(firmId)],
        )
        .get();
    final queries = DriftAppQueries(_db);
    final found = [
      for (final r in rows)
        ?await queries.itemById(firmId, r.read<String>('id')),
    ];
    // The ones the shelf has first; a substitute that is not here is no
    // answer to a customer at the counter, but it is still worth knowing.
    found.sort((a, b) {
      final inA = a.stockOnHand.isPositive ? 0 : 1;
      final inB = b.stockOnHand.isPositive ? 0 : 1;
      return inA != inB ? inA - inB : 0;
    });
    return found;
  }

  /// Every batch on the shop floor that expires before [before], or is on
  /// hold, with the supplier it came from: the near-expiry list.
  ///
  /// The supplier is the one the batch remembers, or — for a batch from
  /// before M49 remembered it — the party on the first delivery that put
  /// stock into it.
  Future<List<ExpiringBatch>> expiringBatches(
    String firmId, {
    required BusinessDate before,
    bool withHeld = true,
  }) async {
    final rows = await _db
        .customSelect(
          '''
          SELECT b.*, p.name AS supplier_name
          FROM (
            SELECT l.id, l.item_id, i.name AS item_name, l.lot_no,
                   l.expiry_date_local, l.cost_milli_paisa, l.mrp_paisa,
                   l.hold_reason, u.code AS unit_code,
                   COALESCE(l.supplier_party_id, (
                     SELECT d.party_id FROM stock_ledger f
                     JOIN documents d ON d.id = f.document_id
                     WHERE f.lot_id = l.id AND f.txn_type = 'purchase'
                       AND f.deleted_at_utc IS NULL
                     ORDER BY f.occurred_at_utc, f.id LIMIT 1
                   )) AS supplier_id,
                   SUM(s.qty_delta_thousandths) AS qty
            FROM stock_lots l
            JOIN items i ON i.id = l.item_id
            JOIN units u ON u.id = i.base_unit_id
            JOIN stock_ledger s
              ON s.lot_id = l.id AND s.deleted_at_utc IS NULL
             AND s.location_code = 'MAIN'
            WHERE l.firm_id = ?1 AND l.deleted_at_utc IS NULL
              AND l.serial IS NULL
              AND ((l.expiry_date_local IS NOT NULL
                    AND l.expiry_date_local < ?2)
                   OR (?3 = 1 AND l.hold_reason IS NOT NULL))
            GROUP BY l.id
            HAVING SUM(s.qty_delta_thousandths) > 0
          ) b
          LEFT JOIN parties p ON p.id = b.supplier_id
          ORDER BY b.expiry_date_local IS NULL, b.expiry_date_local,
                   b.item_name, b.lot_no
          ''',
          variables: [
            Variable<String>(firmId),
            Variable<String>(before.value),
            Variable<int>(withHeld ? 1 : 0),
          ],
        )
        .get();
    return [
      for (final r in rows)
        ExpiringBatch(
          lotId: r.read<String>('id'),
          itemId: r.read<String>('item_id'),
          itemName: r.read<String>('item_name'),
          lotNo: r.read<String>('lot_no'),
          qty: Qty.raw(r.read<int>('qty')),
          unitCode: r.read<String>('unit_code'),
          cost: Rate.raw(r.read<int>('cost_milli_paisa')),
          expiry: switch (r.readNullable<String>('expiry_date_local')) {
            final String d => BusinessDate(d),
            null => null,
          },
          mrp: switch (r.readNullable<int>('mrp_paisa')) {
            final int p => Money.paisa(p),
            null => null,
          },
          supplierId: r.readNullable<String>('supplier_id'),
          supplierName: r.readNullable<String>('supplier_name'),
          holdReason: r.readNullable<String>('hold_reason'),
        ),
    ];
  }

  /// The delivery lines that put stock into each of [lotIds], oldest first,
  /// and how much each put in: what an expired batch can be sent back
  /// against, and on which supplier's bill.
  Future<Map<String, List<({String documentId, String lineId, Qty qty})>>>
  deliveriesInto(Iterable<String> lotIds) async {
    final ids = lotIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final rows = await _db
        .customSelect(
          '''
          SELECT s.lot_id, s.document_id, s.document_line_id,
                 SUM(s.qty_delta_thousandths) AS qty,
                 MIN(s.occurred_at_utc) AS at_utc
          FROM stock_ledger s
          JOIN documents d ON d.id = s.document_id
          WHERE s.lot_id IN (${List.filled(ids.length, '?').join(', ')})
            AND s.txn_type = 'purchase' AND s.deleted_at_utc IS NULL
            AND d.doc_type = 'purchase_bill' AND d.status = 'posted'
            AND s.document_line_id IS NOT NULL
          GROUP BY s.lot_id, s.document_id, s.document_line_id
          ORDER BY at_utc, s.document_id
          ''',
          variables: [for (final id in ids) Variable<String>(id)],
        )
        .get();
    final out = <String, List<({String documentId, String lineId, Qty qty})>>{};
    for (final r in rows) {
      (out[r.read<String>('lot_id')] ??= []).add((
        documentId: r.read<String>('document_id'),
        lineId: r.read<String>('document_line_id'),
        qty: Qty.raw(r.read<int>('qty')),
      ));
    }
    return out;
  }
}
