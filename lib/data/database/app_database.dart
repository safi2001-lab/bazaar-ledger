import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables/all_tables.dart';
import 'daos/parties_dao.dart';
import 'daos/pdc_dao.dart';
import 'daos/ledger_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Companies,
  Users,
  Parties,
  Items,
  Invoices,
  InvoiceItems,
  PostDatedCheques,
  StockMovements,
  Payments,
  Expenses,
  Accounts,
  JournalEntries,
  JournalLines,
  SyncQueue,
  AuditLogs,
], daos: [
  PartiesDao,
  PdcDao,
  LedgerDao,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // 1. Enable Foreign Key referential constraints
      await customStatement('PRAGMA foreign_keys = ON;');
      // 2. Enable Write-Ahead Logging (WAL) for high-speed concurrent transactions
      await customStatement('PRAGMA journal_mode = WAL;');
      // 3. Set synchronous to NORMAL for high write throughput
      await customStatement('PRAGMA synchronous = NORMAL;');
      // 4. Quick integrity check on startup
      final result = await customSelect('PRAGMA quick_check;').getSingle();
      if (result.data.values.first != 'ok') {
        throw StateError('Database integrity check failed: corrupt pages detected.');
      }
    },
  );

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'pakistan_sme_billing.sqlite'));

      // Executes all SQL operations in a dedicated background Dart isolate
      // ensuring the Flutter UI thread runs smoothly at 60 FPS on 2GB RAM devices
      return NativeDatabase.createInBackground(file);
    });
  }

  /// In-memory database factory for unit tests
  factory AppDatabase.forTesting(QueryExecutor executor) {
    return AppDatabase(executor);
  }
}
