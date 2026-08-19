import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:pakistan_sme_billing/data/database/app_database.dart';
import 'package:pakistan_sme_billing/services/double_entry_engine.dart';

void main() {
  late AppDatabase db;
  late DoubleEntryEngine engine;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    engine = DoubleEntryEngine(db);
    
    // Insert base company
    await db.into(db.companies).insert(CompaniesCompanion.insert(
      name: 'Test Company',
      ntnStrn: const Value('12345'),
    ));
    
    // Initialize chart of accounts
    await db.ledgerDao.initializeDefaultAccounts(1);
  });

  tearDown(() async {
    await db.close();
  });

  test('DoubleEntryEngine posts balanced sales invoice journal', () async {
    await engine.postSalesInvoice(
      companyId: 1,
      invoiceId: 101,
      invoiceNumber: 'INV-101',
      totalAmount: 5000.0,
      isCreditSale: true,
    );

    final entries = await db.select(db.journalEntries).get();
    expect(entries.length, 1);
    expect(entries.first.entryNumber, 'JRN-INV-INV-101');

    final lines = await (db.select(db.journalLines)..where((l) => l.journalEntryId.equals(entries.first.id))).get();
    expect(lines.length, 2);

    double totalDebit = 0;
    double totalCredit = 0;
    for (var line in lines) {
      totalDebit += line.debit;
      totalCredit += line.credit;
    }

    // Debits must equal credits
    expect(totalDebit, 5000.0);
    expect(totalCredit, 5000.0);
    expect(totalDebit, totalCredit);
  });

  test('DoubleEntryEngine throws if debits and credits do not match (manual check)', () async {
    final entry = JournalEntriesCompanion.insert(
      companyId: 1,
      entryNumber: 'ERR-1',
      referenceType: 'Manual',
    );

    final lines = [
      JournalLinesCompanion(accountId: const Value(1), debit: const Value(100.0), credit: const Value(0.0)),
      JournalLinesCompanion(accountId: const Value(2), debit: const Value(0.0), credit: const Value(99.0)),
    ];

    expect(
      () => db.ledgerDao.insertDoubleEntry(entry, lines),
      throwsException,
    );
  });
}
