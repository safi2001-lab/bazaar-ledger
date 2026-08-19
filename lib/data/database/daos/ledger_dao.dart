import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/all_tables.dart';

part 'ledger_dao.g.dart';

@DriftAccessor(tables: [Accounts, JournalEntries, JournalLines])
class LedgerDao extends DatabaseAccessor<AppDatabase> with _$LedgerDaoMixin {
  LedgerDao(AppDatabase db) : super(db);

  /// Ensure default chart of accounts exists
  Future<void> initializeDefaultAccounts(int companyId) async {
    final count = await (select(accounts)..where((a) => a.companyId.equals(companyId))).get().then((v) => v.length);
    if (count == 0) {
      await batch((batch) {
        batch.insertAll(accounts, [
          AccountsCompanion.insert(companyId: companyId, accountCode: '1010', accountName: 'Cash in Hand', accountType: 'Asset'),
          AccountsCompanion.insert(companyId: companyId, accountCode: '1020', accountName: 'Bank Accounts', accountType: 'Asset'),
          AccountsCompanion.insert(companyId: companyId, accountCode: '1100', accountName: 'Accounts Receivable', accountType: 'Asset'),
          AccountsCompanion.insert(companyId: companyId, accountCode: '1200', accountName: 'Inventory', accountType: 'Asset'),
          AccountsCompanion.insert(companyId: companyId, accountCode: '2100', accountName: 'Accounts Payable', accountType: 'Liability'),
          AccountsCompanion.insert(companyId: companyId, accountCode: '4010', accountName: 'Sales Revenue', accountType: 'Revenue'),
          AccountsCompanion.insert(companyId: companyId, accountCode: '5010', accountName: 'Cost of Goods Sold', accountType: 'Expense'),
        ]);
      });
    }
  }

  /// Insert a balanced journal entry
  Future<void> insertDoubleEntry(
    JournalEntriesCompanion entry,
    List<JournalLinesCompanion> lines,
  ) async {
    // Validate Debits == Credits
    double totalDebit = 0;
    double totalCredit = 0;
    for (var line in lines) {
      totalDebit += line.debit.value;
      totalCredit += line.credit.value;
    }

    if ((totalDebit - totalCredit).abs() > 0.01) {
      throw Exception('Double-entry validation failed: Debits ($totalDebit) != Credits ($totalCredit)');
    }

    // Execute in transaction
    await transaction(() async {
      final entryId = await into(journalEntries).insert(entry);
      
      final linesToInsert = lines.map((l) => l.copyWith(journalEntryId: Value(entryId))).toList();
      await batch((batch) {
        batch.insertAll(journalLines, linesToInsert);
      });
    });
  }

  /// Watch ledger for a specific account
  Stream<List<TypedResult>> watchAccountLedger(int companyId, int accountId) {
    final query = select(journalLines).join([
      innerJoin(journalEntries, journalEntries.id.equalsExp(journalLines.journalEntryId)),
    ])
      ..where(journalEntries.companyId.equals(companyId) & journalLines.accountId.equals(accountId))
      ..orderBy([OrderingTerm(expression: journalEntries.entryDate, mode: OrderingMode.desc)]);

    return query.watch();
  }
}
