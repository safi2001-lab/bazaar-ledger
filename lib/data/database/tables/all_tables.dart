import 'package:drift/drift.dart';

// --- 1. COMPANY & PROFILE ---
class Companies extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get ntnStrn => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get currencyCode => text().withDefault(const Constant('PKR'))();
  IntColumn get fiscalStartMonth => integer().withDefault(const Constant(7))(); // July
  BoolColumn get isTajirDost => boolean().withDefault(const Constant(false))(); // 1% Turnover Regime
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// --- 2. USERS & ROLES ---
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get companyId => integer().references(Companies, #id)();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get role => text()(); // 'Owner', 'Cashier', 'Accountant', 'Viewer'
  TextColumn get pinHash => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// --- 3. PARTIES & UDHAAR LEDGERS ---
class Parties extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get companyId => integer().references(Companies, #id)();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get phone => text().nullable()();
  TextColumn get ntnCnic => text().nullable()();
  TextColumn get partyType => text()(); // 'Customer', 'Supplier', 'Both'
  RealColumn get creditLimit => real().withDefault(const Constant(0.0))();
  RealColumn get openingBalance => real().withDefault(const Constant(0.0))();
  RealColumn get currentBalance => real().withDefault(const Constant(0.0))();
  IntColumn get creditRatingScore => integer().withDefault(const Constant(100))(); // 1-100 score
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

// --- 4. INVENTORY & ITEMS ---
class Items extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get companyId => integer().references(Companies, #id)();
  TextColumn get name => text().withLength(min: 1, max: 150)();
  TextColumn get barcode => text().nullable()();
  TextColumn get unit => text().withDefault(const Constant('Piece'))(); // Piece, Kg, Carton, Meter, Gaz
  TextColumn get hsCode => text().nullable()(); // 8-digit Pakistan Customs Tariff
  RealColumn get salePrice => real()();
  RealColumn get purchasePrice => real().withDefault(const Constant(0.0))();
  RealColumn get taxRate => real().withDefault(const Constant(18.0))(); // 18% FBR standard
  RealColumn get stockQuantity => real().withDefault(const Constant(0.0))();
  RealColumn get minStockAlert => real().withDefault(const Constant(5.0))();
  BoolColumn get trackBatch => boolean().withDefault(const Constant(false))();
  BoolColumn get trackSerial => boolean().withDefault(const Constant(false))();
  BoolColumn get is3rdSchedule => boolean().withDefault(const Constant(false))(); // Tax on MRP
}

// --- 5. INVOICES & POS BILLS ---
class Invoices extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get companyId => integer().references(Companies, #id)();
  IntColumn get partyId => integer().nullable().references(Parties, #id)();
  TextColumn get invoiceNumber => text().withLength(min: 1, max: 50)();
  TextColumn get documentType => text()(); // 'Sale', 'Purchase', 'Estimate', 'Return', 'Challan'
  DateTimeColumn get invoiceDate => dateTime().withDefault(currentDateAndTime)();
  RealColumn get subtotal => real()();
  RealColumn get taxAmount => real().withDefault(const Constant(0.0))();
  RealColumn get furtherTaxAmount => real().withDefault(const Constant(0.0))(); // 3% Section 3(1A)
  RealColumn get discountAmount => real().withDefault(const Constant(0.0))();
  RealColumn get totalAmount => real()();
  RealColumn get paidAmount => real().withDefault(const Constant(0.0))();
  TextColumn get paymentMode => text().withDefault(const Constant('Cash'))(); // 'Cash', 'Raast', 'JazzCash', 'Credit', 'PDC', 'Split'
  TextColumn get fbrIrn => text().nullable()();
  TextColumn get fbrQrCode => text().nullable()();
  BoolColumn get isFbrSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// --- 6. INVOICE LINE ITEMS ---
class InvoiceItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get invoiceId => integer().references(Invoices, #id)();
  IntColumn get itemId => integer().references(Items, #id)();
  RealColumn get quantity => real()();
  RealColumn get unitPrice => real()();
  RealColumn get taxRate => real()();
  RealColumn get taxAmount => real()();
  RealColumn get furtherTaxRate => real().withDefault(const Constant(0.0))();
  RealColumn get furtherTaxAmount => real().withDefault(const Constant(0.0))();
  RealColumn get discount => real().withDefault(const Constant(0.0))();
  RealColumn get totalAmount => real()();
  TextColumn get batchNumber => text().nullable()();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  TextColumn get serialImei => text().nullable()();
}

// --- 7. POST-DATED CHEQUES (PDC) ---
class PostDatedCheques extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get companyId => integer().references(Companies, #id)();
  IntColumn get partyId => integer().references(Parties, #id)();
  IntColumn get invoiceId => integer().nullable().references(Invoices, #id)();
  TextColumn get chequeNumber => text().withLength(min: 1, max: 50)();
  TextColumn get bankName => text()();
  RealColumn get amount => real()();
  DateTimeColumn get chequeDate => dateTime()(); // Maturity Date
  TextColumn get chequeType => text()(); // 'Received', 'Issued'
  TextColumn get status => text().withDefault(const Constant('InHand'))(); // 'InHand', 'Deposited', 'Cleared', 'Bounced'
  TextColumn get returnMemoRef => text().nullable()();
  DateTimeColumn get clearanceDate => dateTime().nullable()();
}

// --- 8. STOCK MOVEMENTS ---
class StockMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get itemId => integer().references(Items, #id)();
  IntColumn get companyId => integer().references(Companies, #id)();
  RealColumn get quantityDelta => real()(); // Negative for sales, positive for purchases/returns
  TextColumn get movementType => text()(); // 'Sale', 'Purchase', 'Adjustment', 'Transfer'
  DateTimeColumn get movementDate => dateTime().withDefault(currentDateAndTime)();
}

// --- 9. PAYMENTS (CASH/BANK/WALLETS) ---
class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get companyId => integer().references(Companies, #id)();
  IntColumn get partyId => integer().references(Parties, #id)();
  IntColumn get invoiceId => integer().nullable().references(Invoices, #id)();
  RealColumn get amount => real()();
  TextColumn get paymentType => text()(); // 'Payment-In', 'Payment-Out'
  TextColumn get paymentMode => text()(); // 'Cash', 'Bank', 'Raast', 'JazzCash', 'EasyPaisa', 'PDC'
  TextColumn get transactionRef => text().nullable()();
  DateTimeColumn get paymentDate => dateTime().withDefault(currentDateAndTime)();
}

// --- 10. EXPENSES & UTILITY WHT ---
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get companyId => integer().references(Companies, #id)();
  TextColumn get category => text()();
  RealColumn get amount => real()();
  TextColumn get paymentMode => text()();
  TextColumn get notes => text().nullable()();
  RealColumn get whtAdvanceTax => real().withDefault(const Constant(0.0))(); // 100% adjustable against Tajir Dost 1%
  DateTimeColumn get expenseDate => dateTime().withDefault(currentDateAndTime)();
}

// --- 11. DOUBLE-ENTRY GENERAL LEDGER ACCOUNTS ---
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get companyId => integer().references(Companies, #id)();
  TextColumn get accountCode => text().withLength(min: 4, max: 10)(); // '1010', '1020', '4010', etc.
  TextColumn get accountName => text().withLength(min: 1, max: 100)();
  TextColumn get accountType => text()(); // 'Asset', 'Liability', 'Equity', 'Revenue', 'Expense'
}

class JournalEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get companyId => integer().references(Companies, #id)();
  TextColumn get entryNumber => text()();
  DateTimeColumn get entryDate => dateTime().withDefault(currentDateAndTime)();
  TextColumn get referenceType => text()(); // 'Invoice', 'Payment', 'Expense', 'PDC'
  IntColumn get referenceId => integer().nullable()();
  TextColumn get description => text().nullable()();
}

class JournalLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get journalEntryId => integer().references(JournalEntries, #id)();
  IntColumn get accountId => integer().references(Accounts, #id)();
  RealColumn get debit => real().withDefault(const Constant(0.0))();
  RealColumn get credit => real().withDefault(const Constant(0.0))();
}

// --- 12. SYNC QUEUE & AUDIT LOGS ---
class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()(); // 'Invoice', 'Party', 'Item', 'Payment', 'PDC'
  IntColumn get entityId => integer()();
  TextColumn get mutationType => text()(); // 'INSERT', 'UPDATE', 'DELETE'
  TextColumn get payloadJson => text()();
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
}

class AuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get companyId => integer().references(Companies, #id)();
  IntColumn get userId => integer().nullable().references(Users, #id)();
  TextColumn get action => text()(); // 'INVOICE_EDIT', 'ITEM_DELETE', 'PRICE_OVERRIDE'
  TextColumn get entityType => text()();
  IntColumn get entityId => integer()();
  TextColumn get detailsJson => text()();
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
}
