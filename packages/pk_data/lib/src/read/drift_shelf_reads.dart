import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';

import '../db/app_database.dart';

/// The shelf at the moment of sale, read from the stock ledger (M53).
///
/// One query for every item on the bill: its name, its base unit, its own
/// rule for selling below nothing and what is at the place the goods leave
/// from, summed off the ledger rather than read from a cache. Called inside
/// the sale's own transaction — drift runs any read made on the database
/// within a transaction block in that transaction — so the figure checked is
/// the one the sale is about to move, and a sale on another till of this
/// phone cannot slip between the two.
///
/// The counter screen asks through the same reader, so the question it puts
/// to the cashier and the refusal beneath it are worked from one figure.
final class DriftShelfReader implements ShelfReader {
  const DriftShelfReader(this._db);

  final AppDatabase _db;

  /// The shop's own rule, or [NegativeStock.shopDefault] when it never
  /// chose one.
  Future<NegativeStock> shopRule(String firmId) async {
    final row = await _db
        .customSelect(
          'SELECT setting_value FROM settings '
          'WHERE firm_id = ? AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(firmId),
            const Variable<String>(negativeStockSettingKey),
          ],
        )
        .getSingleOrNull();
    return NegativeStock.fromCode(row?.read<String>('setting_value')) ??
        NegativeStock.shopDefault;
  }

  @override
  Future<Map<String, ShelfState>> shelfFor(
    ActorContext actor,
    Iterable<String> itemIds, {
    required String locationCode,
  }) async {
    final ids = itemIds.toSet().toList();
    if (ids.isEmpty) return const {};
    final shop = await shopRule(actor.firmId);
    final rows = await _db
        .customSelect(
          '''
          SELECT i.id, i.name, i.track_stock, i.negative_stock,
                 u.code AS unit_code,
                 COALESCE((
                   SELECT SUM(sl.qty_delta_thousandths)
                   FROM stock_ledger sl
                   WHERE sl.firm_id = i.firm_id AND sl.item_id = i.id
                     AND sl.location_code = ? AND sl.deleted_at_utc IS NULL
                 ), 0) AS on_hand
          FROM items i
          JOIN units u ON u.id = i.base_unit_id
          WHERE i.firm_id = ? AND i.deleted_at_utc IS NULL
            AND i.id IN (${List.filled(ids.length, '?').join(', ')})
          ''',
          variables: [
            Variable<String>(locationCode),
            Variable<String>(actor.firmId),
            for (final id in ids) Variable<String>(id),
          ],
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('id'): ShelfState(
          itemId: r.read<String>('id'),
          itemName: r.read<String>('name'),
          unitCode: r.read<String>('unit_code'),
          onHand: Qty.raw(r.read<int>('on_hand')),
          rule:
              NegativeStock.fromCode(
                r.readNullable<String>('negative_stock'),
              ) ??
              shop,
          tracksStock: r.read<int>('track_stock') == 1,
        ),
    };
  }
}
