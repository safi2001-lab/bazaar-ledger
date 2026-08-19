import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../data/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';

part 'party_ledger_controller.g.dart';

@riverpod
class PartyLedgerController extends _$PartyLedgerController {
  @override
  Stream<List<Party>> build() {
    final db = ref.watch(appDatabaseProvider);
    // Hardcoded companyId = 1 for now, in a real app this comes from an auth provider
    return db.partiesDao.watchAllParties(1);
  }

  Future<void> addParty(String name, String phone, String partyType, double creditLimit, double openingBalance) async {
    final db = ref.watch(appDatabaseProvider);
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
    final db = ref.watch(appDatabaseProvider);
    
    // Decrease the udhaar balance (negative balance means they owe us)
    // Actually, let's treat positive as they owe us, negative as we owe them (standard AR approach).
    // If they pay us, the balance decreases.
    await db.partiesDao.updatePartyBalance(partyId, -amount);

    // Record the payment entry
    final payment = PaymentsCompanion.insert(
      companyId: 1,
      partyId: partyId,
      amount: amount,
      paymentType: 'Payment-In',
      paymentMode: paymentMode,
    );
    final paymentId = await db.into(db.payments).insert(payment);

    // Record Double-Entry Journal
    // We would inject or call the DoubleEntryEngine here.
    // For now, this is a placeholder for where that integration goes.
  }
}
