import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/all_tables.dart';

part 'items_dao.g.dart';

@DriftAccessor(tables: [Items, StockMovements, Companies])
class ItemsDao extends DatabaseAccessor<AppDatabase> with _$ItemsDaoMixin {
  ItemsDao(AppDatabase db) : super(db);

  /// Watch all items for a company
  Stream<List<Item>> watchAllItems(int companyId) {
    return (select(items)
          ..where((tbl) => tbl.companyId.equals(companyId))
          ..orderBy([(t) => OrderingTerm(expression: t.name, mode: OrderingMode.asc)]))
        .watch();
  }

  /// Search items by name or barcode
  Future<List<Item>> searchItems(int companyId, String query) {
    final searchPattern = '%$query%';
    return (select(items)
          ..where((tbl) =>
              tbl.companyId.equals(companyId) &
              (tbl.name.like(searchPattern) | tbl.barcode.like(searchPattern))))
        .get();
  }

  /// Find a single item by exact barcode
  Future<Item?> getItemByBarcode(int companyId, String barcode) {
    return (select(items)
          ..where((tbl) => tbl.companyId.equals(companyId) & tbl.barcode.equals(barcode)))
        .getSingleOrNull();
  }

  /// Get low stock items (stockQuantity <= minStockAlert)
  Stream<List<Item>> watchLowStockItems(int companyId) {
    return (select(items)
          ..where((tbl) =>
              tbl.companyId.equals(companyId) &
              tbl.stockQuantity.isSmallerOrEqual(tbl.minStockAlert)))
        .watch();
  }

  /// Insert a new inventory item and log initial stock movement
  Future<int> insertItem(ItemsCompanion item) async {
    return transaction(() async {
      final itemId = await into(items).insert(item);
      final initialStock = item.stockQuantity.present ? item.stockQuantity.value : 0.0;
      if (initialStock > 0) {
        await into(stockMovements).insert(
          StockMovementsCompanion.insert(
            itemId: itemId,
            companyId: item.companyId.value,
            quantityDelta: initialStock,
            movementType: 'Opening Stock',
            movementDate: Value(DateTime.now()),
          ),
        );
      }
      return itemId;
    });
  }

  /// Update item details
  Future<bool> updateItem(Item item) {
    return update(items).replace(item);
  }

  /// Adjust stock level with a recorded reason (Purchase, Sale, Wastage, Adjustment)
  Future<void> adjustStock({
    required int companyId,
    required int itemId,
    required double quantityDelta,
    required String movementType, // 'Sale', 'Purchase', 'Adjustment', 'Wastage'
  }) async {
    await transaction(() async {
      final item = await (select(items)..where((tbl) => tbl.id.equals(itemId))).getSingleOrNull();
      if (item == null) return;

      final updatedQty = item.stockQuantity + quantityDelta;
      await (update(items)..where((tbl) => tbl.id.equals(itemId))).write(
        ItemsCompanion(stockQuantity: Value(updatedQty)),
      );

      await into(stockMovements).insert(
        StockMovementsCompanion.insert(
          itemId: itemId,
          companyId: companyId,
          quantityDelta: quantityDelta,
          movementType: movementType,
          movementDate: Value(DateTime.now()),
        ),
      );
    });
  }

  /// Watch stock movements for a specific item or entire company
  Stream<List<StockMovement>> watchStockMovements(int companyId, {int? itemId}) {
    final query = select(stockMovements)
      ..where((tbl) =>
          tbl.companyId.equals(companyId) &
          (itemId != null ? tbl.itemId.equals(itemId) : const Constant(true)))
      ..orderBy([(t) => OrderingTerm(expression: t.movementDate, mode: OrderingMode.desc)]);
    return query.watch();
  }

  /// Delete an item
  Future<int> deleteItem(int itemId) {
    return (delete(items)..where((tbl) => tbl.id.equals(itemId))).go();
  }
}
