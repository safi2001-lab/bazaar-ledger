import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../../data/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';

class InventoryNotifier extends StateNotifier<AsyncValue<List<Item>>> {
  final Ref ref;

  InventoryNotifier(this.ref) : super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    final db = ref.read(appDatabaseProvider);
    db.itemsDao.watchAllItems(1).listen(
      (data) => state = AsyncValue.data(data),
      onError: (err, stack) => state = AsyncValue.error(err, stack),
    );
  }

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
    final db = ref.read(appDatabaseProvider);
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

  Future<void> adjustStock({
    required int itemId,
    required double quantityDelta,
    required String movementType,
  }) async {
    final db = ref.read(appDatabaseProvider);
    await db.itemsDao.adjustStock(
      companyId: 1,
      itemId: itemId,
      quantityDelta: quantityDelta,
      movementType: movementType,
    );
  }

  Future<void> deleteItem(int itemId) async {
    final db = ref.read(appDatabaseProvider);
    await db.itemsDao.deleteItem(itemId);
  }
}

final inventoryControllerProvider =
    StateNotifierProvider<InventoryNotifier, AsyncValue<List<Item>>>((ref) {
  return InventoryNotifier(ref);
});

final lowStockItemsProvider = StreamProvider<List<Item>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.itemsDao.watchLowStockItems(1);
});

final itemStockMovementsProvider =
    StreamProvider.family<List<StockMovement>, int?>((ref, itemId) {
  final db = ref.watch(appDatabaseProvider);
  return db.itemsDao.watchStockMovements(1, itemId: itemId);
});
