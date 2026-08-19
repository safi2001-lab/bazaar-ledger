import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../data/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';

part 'pdc_controller.g.dart';

@riverpod
class PdcController extends _$PdcController {
  @override
  Stream<List<PostDatedCheque>> build() {
    final db = ref.watch(appDatabaseProvider);
    return db.pdcDao.watchUpcomingPdc(1); // 1 = companyId
  }

  Future<void> addPdc(int partyId, String chequeNumber, String bankName, double amount, DateTime maturityDate, String chequeType) async {
    final db = ref.watch(appDatabaseProvider);
    final pdc = PostDatedChequesCompanion.insert(
      companyId: 1,
      partyId: partyId,
      chequeNumber: chequeNumber,
      bankName: bankName,
      amount: amount,
      chequeDate: maturityDate,
      chequeType: chequeType,
      status: const Value('InHand'),
    );
    await db.pdcDao.insertPdc(pdc);
  }

  Future<void> depositPdc(int pdcId) async {
    final db = ref.watch(appDatabaseProvider);
    await db.pdcDao.markAsDeposited(pdcId);
  }

  Future<void> clearPdc(int pdcId) async {
    final db = ref.watch(appDatabaseProvider);
    await db.pdcDao.markAsCleared(pdcId, DateTime.now());
  }

  Future<void> bouncePdc(int pdcId, String memoRef) async {
    final db = ref.watch(appDatabaseProvider);
    await db.pdcDao.markAsBounced(pdcId, memoRef);
    // Note: Section 489-F PPC Legal Notice generation would trigger here
  }
}
