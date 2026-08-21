import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:pakistan_sme_billing/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    
    // Insert base test company
    await db.into(db.companies).insert(
      CompaniesCompanion.insert(
        name: 'Super Med & Grocery',
        ntnStrn: const Value('9988776'),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('ItemsDao inserts item and logs initial opening stock movement', () async {
    final itemId = await db.itemsDao.insertItem(
      ItemsCompanion.insert(
        companyId: 1,
        name: 'Augmentin 625mg',
        barcode: const Value('8964000123456'),
        salePrice: 420.0,
        purchasePrice: const Value(360.0),
        stockQuantity: const Value(50.0),
        minStockAlert: const Value(10.0),
        trackBatch: const Value(true),
      ),
    );

    expect(itemId, isPositive);

    // Verify item created
    final item = await db.itemsDao.getItemByBarcode(1, '8964000123456');
    expect(item, isNotNull);
    expect(item!.name, 'Augmentin 625mg');
    expect(item.stockQuantity, 50.0);
    expect(item.trackBatch, isTrue);

    // Verify stock movement ledger recorded opening stock
    final movements = await db.itemsDao.watchStockMovements(1, itemId: itemId).first;
    expect(movements.length, 1);
    expect(movements.first.movementType, 'Opening Stock');
    expect(movements.first.quantityDelta, 50.0);
  });

  test('ItemsDao adjusts stock and records adjustment delta', () async {
    final itemId = await db.itemsDao.insertItem(
      ItemsCompanion.insert(
        companyId: 1,
        name: 'Basmati Rice 10kg',
        salePrice: 3200.0,
        stockQuantity: const Value(20.0),
      ),
    );

    // Perform sale adjustment (-5 bags)
    await db.itemsDao.adjustStock(
      companyId: 1,
      itemId: itemId,
      quantityDelta: -5.0,
      movementType: 'Sale',
    );

    final item = await (db.select(db.items)..where((t) => t.id.equals(itemId))).getSingle();
    expect(item.stockQuantity, 15.0);

    final movements = await db.itemsDao.watchStockMovements(1, itemId: itemId).first;
    expect(movements.length, 2); // Opening Stock + Sale
    expect(movements.first.movementType, 'Sale');
    expect(movements.first.quantityDelta, -5.0);
  });

  test('ItemsDao watchLowStockItems filters correctly', () async {
    await db.itemsDao.insertItem(
      ItemsCompanion.insert(
        companyId: 1,
        name: 'Item In Stock',
        salePrice: 100.0,
        stockQuantity: const Value(20.0),
        minStockAlert: const Value(5.0),
      ),
    );

    await db.itemsDao.insertItem(
      ItemsCompanion.insert(
        companyId: 1,
        name: 'Item Low Stock',
        salePrice: 250.0,
        stockQuantity: const Value(2.0),
        minStockAlert: const Value(5.0),
      ),
    );

    final lowStock = await db.itemsDao.watchLowStockItems(1).first;
    expect(lowStock.length, 1);
    expect(lowStock.first.name, 'Item Low Stock');
  });
}
