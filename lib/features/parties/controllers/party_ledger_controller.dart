import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../../data/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';

class PartyLedgerNotifier extends StateNotifier<AsyncValue<List<Party>>> {
  final Ref ref;

  PartyLedgerNotifier(this.ref) : super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    final db = ref.read(appDatabaseProvider);
    db.partiesDao.watchAllParties(1).listen(
      (data) => state = AsyncValue.data(data),
      onError: (err, stack) => state = AsyncValue.error(err, stack),
    );
  }

  Future<void> addParty(
    String name,
    String phone,
    String partyType,
    double creditLimit,
    double openingBalance,
  ) async {
    final db = ref.read(appDatabaseProvider);
    final companion = PartiesCompanion.insert(
      companyId: 1,
      name: name,
      phone: Value(phone),
      partyType: partyType,
      creditLimit: Value(creditLimit),
      openingBalance: Value(openingBalance),
      currentBalance: Value(openingBalance),
    );
    await db.partiesDao.insertParty(companion);
  }

  Future<void> recordPaymentReceived(int partyId, double amount, String paymentMode) async {
    final db = ref.read(appDatabaseProvider);
    await db.partiesDao.updatePartyBalance(partyId, -amount);

    final payment = PaymentsCompanion.insert(
      companyId: 1,
      partyId: partyId,
      amount: amount,
      paymentType: 'Payment-In',
      paymentMode: paymentMode,
    );
    await db.into(db.payments).insert(payment);
  }
}

final partyLedgerControllerProvider =
    StateNotifierProvider<PartyLedgerNotifier, AsyncValue<List<Party>>>((ref) {
  return PartyLedgerNotifier(ref);
});
