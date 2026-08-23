import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:pk_data/pk_data.dart';
import 'package:sqlite3/open.dart';

var _resolved = false;

/// Points the `sqlite3` package at a native library on hosts that do not ship
/// one on the default search path.
///
/// Windows 10 1803 and later carry `winsqlite3.dll` in System32. It is a real,
/// current SQLite — 3.51 on the development machine — so the test suite runs
/// with no vendored binary and no download step. CI on Linux finds
/// `libsqlite3.so` the usual way.
void resolveSqlite() {
  if (_resolved) return;
  _resolved = true;
  if (Platform.isWindows) {
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open('winsqlite3.dll'),
    );
  }
}

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
