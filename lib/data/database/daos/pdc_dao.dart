import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/all_tables.dart';

part 'pdc_dao.g.dart';

@DriftAccessor(tables: [PostDatedCheques, Parties, Companies])
class PdcDao extends DatabaseAccessor<AppDatabase> with _$PdcDaoMixin {
  PdcDao(super.db);

  /// Get all PDCs for a company
  Stream<List<PostDatedCheque>> watchAllPdc(int companyId) {
    return (select(postDatedCheques)..where((p) => p.companyId.equals(companyId))).watch();
  }

  /// Get upcoming PDCs (InHand status, ordered by maturity date)
  Stream<List<PostDatedCheque>> watchUpcomingPdc(int companyId) {
    return (select(postDatedCheques)
          ..where((p) => p.companyId.equals(companyId) & p.status.equals('InHand'))
          ..orderBy([(p) => OrderingTerm(expression: p.chequeDate, mode: OrderingMode.asc)]))
        .watch();
  }

  /// Insert a new PDC
  Future<int> insertPdc(PostDatedChequesCompanion pdc) {
    return into(postDatedCheques).insert(pdc);
  }

  /// Update an existing PDC (e.g. changing status)
  Future<bool> updatePdc(PostDatedCheque pdc) {
    return update(postDatedCheques).replace(pdc);
  }

  /// Mark PDC as deposited
  Future<void> markAsDeposited(int pdcId) async {
    final pdc = await (select(postDatedCheques)..where((p) => p.id.equals(pdcId))).getSingleOrNull();
    if (pdc != null) {
      await update(postDatedCheques).replace(pdc.copyWith(status: 'Deposited'));
    }
  }

  /// Mark PDC as cleared
  Future<void> markAsCleared(int pdcId, DateTime clearanceDate) async {
    final pdc = await (select(postDatedCheques)..where((p) => p.id.equals(pdcId))).getSingleOrNull();
    if (pdc != null) {
      await update(postDatedCheques).replace(pdc.copyWith(
        status: 'Cleared',
        clearanceDate: Value(clearanceDate),
      ));
    }
  }

  /// Mark PDC as bounced (Triggers Section 489-F PPC workflow)
  Future<void> markAsBounced(int pdcId, String returnMemoRef) async {
    final pdc = await (select(postDatedCheques)..where((p) => p.id.equals(pdcId))).getSingleOrNull();
    if (pdc != null) {
      await update(postDatedCheques).replace(pdc.copyWith(
        status: 'Bounced',
        returnMemoRef: Value(returnMemoRef),
      ));
    }
  }
}
