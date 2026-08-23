import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:pk_data/pk_data.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';

/// Migrations, and the machinery that makes them testable at all.
///
/// `onUpgrade` used to throw unconditionally, which was the honest thing to do
/// while nothing could migrate — but it also meant that the day a table was
/// added, the migration would be written under pressure against a schema
/// nobody had written down. There is no way to migrate from a version that was
/// never captured, and by then every installed copy would be that version.
///
/// So the dumps and this file land BEFORE the first table is added, while
/// there is nothing at stake. `drift_schemas/drift_schema_v1.json` is the
/// snapshot; `test/generated/` is the code that can build a v1 database on
/// demand.
///
/// When v2 arrives, the shape of the new test is already here: seed a v1
/// database with a posted sale, migrate, then assert both that the schema
/// matches the dump AND that the books still balance. A migration that leaves
/// the ledger unbalanced is worse than one that fails.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('the committed dump matches the schema the code creates', () async {
    // The dump is only useful if it is true. A stale one produces migrations
    // that pass their own tests and mangle real databases.
    final connection = await verifier.startAt(1);
    final db = AppDatabase(connection);
    addTearDown(db.close);

    await verifier.migrateAndValidate(db, 1);
  });

  test('a database at the current version needs no migration', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // Opening is what runs onCreate. If this throws, the DDL and the generated
    // code disagree.
    await db.customSelect('SELECT 1').get();
    expect(db.schemaVersion, 1);
  });

  test('every schema version has a committed dump', () async {
    // A version without a dump cannot be migrated from, and the failure only
    // appears on a user's device. This asserts the two never drift: if
    // schemaVersion is bumped without running `drift_dev schema dump`, the
    // build fails here rather than in a shop.
    //
    // One database at a time, closed before the next opens. Two live drift
    // instances over one executor race, and the warning it prints is easy to
    // scroll past in a green run.
    final current = await _currentSchemaVersion();

    for (var version = 1; version <= current; version++) {
      final connection = await verifier.startAt(version);
      final probe = AppDatabase(connection);
      try {
        await verifier.migrateAndValidate(probe, version);
      } finally {
        await probe.close();
      }
    }
  });

  test('foreign keys survive a migration', () async {
    // Deferred during the migration and re-checked before it commits. SQLite's
    // twelve-step table rebuild moves rows through a temporary table, and with
    // enforcement on it trips halfway — on a shop's database with three years
    // of history, not on an empty test one.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final violations = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violations, isEmpty);

    final enforced = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(
      enforced.data.values.first,
      1,
      reason:
          'referential integrity is off, and every FK in the schema is '
          'decoration',
    );
  });
}

/// The version the code currently declares, read from a database that is then
/// closed, so nothing else in this file races with it.
Future<int> _currentSchemaVersion() async {
  final db = AppDatabase(NativeDatabase.memory());
  try {
    return db.schemaVersion;
  } finally {
    await db.close();
  }
}
