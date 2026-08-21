import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../data/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';

part 'inventory_controller.g.dart';

@riverpod
class InventoryController extends _$InventoryController {
  @override
  Stream<List<Item>> build() {
    final db = ref.watch(appDatabaseProvider);
    return db.itemsDao.watchAllItems(1); // Company ID 1
  }

  /// Add a new item to the catalog
  Future<int> addItem({
    required String name,
    String? barcode,
    String unit = 'Piece',
    String? hsCode,
    required double salePrice,
    double purchasePrice = 0.0,
    double taxRate = 18.0,
    double initialStock = 0.0,
    double minStockAlert = 5.0,
    bool trackBatch = false,
    bool trackSerial = false,
    bool is3rdSchedule = false,
  }) async {
    final db = ref.watch(appDatabaseProvider);
    final companion = ItemsCompanion.insert(
      companyId: 1,
      name: name,
      barcode: Value(barcode),
      unit: Value(unit),
      hsCode: Value(hsCode),
      salePrice: salePrice,
      purchasePrice: Value(purchasePrice),
      taxRate: Value(taxRate),
      stockQuantity: Value(initialStock),
      minStockAlert: Value(minStockAlert),
      trackBatch: Value(trackBatch),
      trackSerial: Value(trackSerial),
      is3rdSchedule: Value(is3rdSchedule),
    );
    return db.itemsDao.insertItem(companion);
  }

  /// Adjust stock level
  Future<void> adjustStock({
    required int itemId,
    required double quantityDelta,
    required String movementType, // 'Stock In', 'Stock Out', 'Wastage', 'Adjustment'
  }) async {
    final db = ref.watch(appDatabaseProvider);
    await db.itemsDao.adjustStock(
      companyId: 1,
      itemId: itemId,
      quantityDelta: quantityDelta,
      movementType: movementType,
    );
  }

  /// Delete item
  Future<void> deleteItem(int itemId) async {
    final db = ref.watch(appDatabaseProvider);
    await db.itemsDao.deleteItem(itemId);
  }
}

@riverpod
Stream<List<Item>> lowStockItems(LowStockItemsRef ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.itemsDao.watchLowStockItems(1);
}

@riverpod
Stream<List<StockMovement>> itemStockMovements(ItemStockMovementsRef ref, {int? itemId}) {
  final db = ref.watch(appDatabaseProvider);
  return db.itemsDao.watchStockMovements(1, itemId: itemId);
}
