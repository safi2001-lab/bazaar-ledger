import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../../data/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';

class PdcNotifier extends StateNotifier<AsyncValue<List<PostDatedCheque>>> {
  final Ref ref;

  PdcNotifier(this.ref) : super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    final db = ref.read(appDatabaseProvider);
    db.pdcDao.watchUpcomingPdc(1).listen(
      (data) => state = AsyncValue.data(data),
      onError: (err, stack) => state = AsyncValue.error(err, stack),
    );
  }

  Future<void> addPdc(
    int partyId,
    String chequeNumber,
    String bankName,
    double amount,
    DateTime maturityDate,
    String chequeType,
  ) async {
    final db = ref.read(appDatabaseProvider);
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
    final db = ref.read(appDatabaseProvider);
    await db.pdcDao.markAsDeposited(pdcId);
  }

  Future<void> clearPdc(int pdcId) async {
    final db = ref.read(appDatabaseProvider);
    await db.pdcDao.markAsCleared(pdcId, DateTime.now());
  }

  Future<void> bouncePdc(int pdcId, String memoRef) async {
    final db = ref.read(appDatabaseProvider);
    await db.pdcDao.markAsBounced(pdcId, memoRef);
  }
}

final pdcControllerProvider =
    StateNotifierProvider<PdcNotifier, AsyncValue<List<PostDatedCheque>>>((ref) {
  return PdcNotifier(ref);
});
