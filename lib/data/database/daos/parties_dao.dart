import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/all_tables.dart';

part 'parties_dao.g.dart';

@DriftAccessor(tables: [Parties, Companies])
class PartiesDao extends DatabaseAccessor<AppDatabase> with _$PartiesDaoMixin {
  PartiesDao(AppDatabase db) : super(db);

  /// Get all parties for a specific company
  Stream<List<Party>> watchAllParties(int companyId) {
    return (select(parties)..where((p) => p.companyId.equals(companyId))).watch();
  }

  /// Get a single party by ID
  Future<Party?> getPartyById(int id) {
    return (select(parties)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  /// Get parties by type (Customer, Supplier, Both)
  Stream<List<Party>> watchPartiesByType(int companyId, String partyType) {
    return (select(parties)
          ..where((p) => p.companyId.equals(companyId) & p.partyType.equals(partyType)))
        .watch();
  }

  /// Insert a new party
  Future<int> insertParty(PartiesCompanion party) {
    return into(parties).insert(party);
  }

  /// Update an existing party
  Future<bool> updateParty(Party party) {
    return update(parties).replace(party);
  }

  /// Delete a party
  Future<int> deleteParty(int id) {
    return (delete(parties)..where((p) => p.id.equals(id))).go();
  }

  /// Update current balance for a party (udhaar transaction)
  Future<void> updatePartyBalance(int partyId, double amountDelta) async {
    final party = await getPartyById(partyId);
    if (party != null) {
      final newBalance = party.currentBalance + amountDelta;
      await update(parties).replace(party.copyWith(
        currentBalance: newBalance,
        updatedAt: DateTime.now(),
      ));
    }
  }

  /// Get top debtors (parties with highest negative balance / udhaar)
  Future<List<Party>> getTopDebtors(int companyId, {int limit = 10}) {
    return (select(parties)
          ..where((p) => p.companyId.equals(companyId) & p.currentBalance.isBiggerThanValue(0.0))
          ..orderBy([(p) => OrderingTerm(expression: p.currentBalance, mode: OrderingMode.desc)])
          ..limit(limit))
        .get();
  }
}
