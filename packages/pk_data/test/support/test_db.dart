import 'package:drift/native.dart';
import 'package:pk_data/pk_data.dart';

/// Kept for the suites that call it. `package:sqlite3` 3.x bundles its own
/// SQLite through a build hook on every host, so there is nothing left to
/// point anywhere.
void resolveSqlite() {}

/// Opens an in-memory [AppDatabase] with the schema created.
///
/// The harness deliberately runs the SAME `beforeOpen` the application runs,
/// foreign keys included. An integrity rule that only holds in production is a
/// rule nobody ever tests, and `ddl_invariants_test` asserts the pragma is on
/// for exactly that reason.
Future<AppDatabase> openTestDatabase({bool logStatements = false}) async {
  resolveSqlite();
  final db = AppDatabase(NativeDatabase.memory(logStatements: logStatements));
  // Force the open, so `beforeOpen` has run before the first assertion.
  await db.customSelect('SELECT 1').get();
  return db;
}
