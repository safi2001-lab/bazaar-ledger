import 'package:drift/drift.dart';
import '../data/database/app_database.dart';

class DoubleEntryEngine {
  final AppDatabase db;

  DoubleEntryEngine(this.db);

  /// Fetch account ID by code
  Future<int?> _getAccountId(int companyId, String code) async {
    final account = await (db.select(db.accounts)..where((a) => a.companyId.equals(companyId) & a.accountCode.equals(code))).getSingleOrNull();
    return account?.id;
  }

  /// Post a Sales Invoice to the ledger
  Future<void> postSalesInvoice({
    required int companyId,
    required int invoiceId,
    required String invoiceNumber,
    required double totalAmount,
    required bool isCreditSale, // true for Udhaar Khata, false for Cash
  }) async {
    // Determine Debit Account (Cash or Accounts Receivable)
    final debitAccountCode = isCreditSale ? '1100' : '1010';
    final debitAccountId = await _getAccountId(companyId, debitAccountCode);
    
    // Credit Account (Sales Revenue)
    final creditAccountId = await _getAccountId(companyId, '4010');

    if (debitAccountId == null || creditAccountId == null) {
      throw Exception('Chart of Accounts not initialized properly.');
    }

    final entry = JournalEntriesCompanion.insert(
      companyId: companyId,
      entryNumber: 'JRN-INV-$invoiceNumber',
      referenceType: 'Invoice',
      referenceId: Value(invoiceId),
      description: Value('Sales Invoice $invoiceNumber'),
    );

    final lines = [
      JournalLinesCompanion(
        accountId: Value(debitAccountId),
        debit: Value(totalAmount),
        credit: const Value(0.0),
      ),
      JournalLinesCompanion(
        accountId: Value(creditAccountId),
        debit: const Value(0.0),
        credit: Value(totalAmount),
      ),
    ];

    await db.ledgerDao.insertDoubleEntry(entry, lines);
  }

  /// Post a Payment Received from Customer
  Future<void> postPaymentReceived({
    required int companyId,
    required int paymentId,
    required String paymentMode,
    required double amount,
  }) async {
    final debitAccountCode = paymentMode == 'Cash' ? '1010' : '1020';
    final debitAccountId = await _getAccountId(companyId, debitAccountCode);
    final creditAccountId = await _getAccountId(companyId, '1100'); // Accounts Receivable

    if (debitAccountId == null || creditAccountId == null) {
      throw Exception('Chart of Accounts not initialized properly.');
    }

    final entry = JournalEntriesCompanion.insert(
      companyId: companyId,
      entryNumber: 'JRN-PAY-$paymentId',
      referenceType: 'Payment',
      referenceId: Value(paymentId),
      description: Value('Payment Received via $paymentMode'),
    );

    final lines = [
      JournalLinesCompanion(
        accountId: Value(debitAccountId),
        debit: Value(amount),
        credit: const Value(0.0),
      ),
      JournalLinesCompanion(
        accountId: Value(creditAccountId),
        debit: const Value(0.0),
        credit: Value(amount),
      ),
    ];

    await db.ledgerDao.insertDoubleEntry(entry, lines);
  }
}
