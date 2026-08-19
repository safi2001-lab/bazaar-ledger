import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pakistan_sme_billing/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    // In-memory SQLite executor for fast, isolated unit testing
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Drift Relational Database Tests', () {
    test('Can insert and retrieve Company profile', () async {
      final companyId = await db.into(db.companies).insert(
        CompaniesCompanion.insert(
          name: 'Al-Madina Traders',
          ntnStrn: const Value('1234567-8'),
          address: const Value('Akbari Mandi, Lahore'),
          phone: const Value('03001234567'),
          isTajirDost: const Value(true),
        ),
      );

      expect(companyId, equals(1));

      final company = await (db.select(db.companies)..where((c) => c.id.equals(companyId))).getSingle();
      expect(company.name, 'Al-Madina Traders');
      expect(company.isTajirDost, true);
      expect(company.currencyCode, 'PKR');
    });

    test('Can insert Items and query with stock levels', () async {
      final companyId = await db.into(db.companies).insert(
        CompaniesCompanion.insert(name: 'Demo Mart'),
      );

      final itemId = await db.into(db.items).insert(
        ItemsCompanion.insert(
          companyId: companyId,
          name: 'Cooking Oil 5L',
          barcode: const Value('8964000112233'),
          unit: const Value('Can'),
          salePrice: 2800.0,
          purchasePrice: const Value(2500.0),
          taxRate: const Value(18.0),
          stockQuantity: const Value(25.0),
        ),
      );

      expect(itemId, equals(1));

      final item = await (db.select(db.items)..where((i) => i.id.equals(itemId))).getSingle();
      expect(item.name, 'Cooking Oil 5L');
      expect(item.salePrice, 2800.0);
      expect(item.stockQuantity, 25.0);
    });

    test('Can insert Party and track running credit balance', () async {
      final companyId = await db.into(db.companies).insert(
        CompaniesCompanion.insert(name: 'Wholesale Depot'),
      );

      final partyId = await db.into(db.parties).insert(
        PartiesCompanion.insert(
          companyId: companyId,
          name: 'Tariq Kiryana Store',
          partyType: 'Customer',
          creditLimit: const Value(50000.0),
          currentBalance: const Value(12500.0),
        ),
      );

      final party = await (db.select(db.parties)..where((p) => p.id.equals(partyId))).getSingle();
      expect(party.name, 'Tariq Kiryana Store');
      expect(party.currentBalance, 12500.0);
      expect(party.creditLimit, 50000.0);
      expect(party.creditRatingScore, 100);
    });
  });
}
