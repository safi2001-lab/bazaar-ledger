import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:pk_data/pk_data.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;

/// Migrations, and the machinery that makes them testable at all.
///
/// `onUpgrade` used to throw unconditionally, which was honest while nothing
/// could migrate — but it also meant that the day a table was added, the
/// migration would be written under pressure against a schema nobody had
/// written down. There is no migrating from a version that was never captured,
/// and by then every installed copy would be that version.
///
/// So the dumps and this file landed BEFORE the first table was added, while
/// there was nothing at stake. `print_jobs` is the first thing to use them.
void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('the committed dumps match the schema the code creates', () async {
    // A dump is only useful if it is true. A stale one produces migrations
    // that pass their own tests and mangle real databases.
    //
    // One database at a time, closed before the next opens: two live drift
    // instances over one executor race, and the warning is easy to scroll past
    // in a green run.
    for (var version = 1; version <= _currentVersion; version++) {
      final connection = await verifier.startAt(version);
      final db = AppDatabase(connection);
      try {
        await verifier.migrateAndValidate(db, version);
      } finally {
        await db.close();
      }
    }
  });

  test('this file knows about every version the code declares', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(
      db.schemaVersion,
      _currentVersion,
      reason:
          'schemaVersion moved and this test file did not. Update '
          '_currentVersion, run `drift_dev schema dump`, and write the step.',
    );
  });

  test('every schema version has a committed dump on disk', () async {
    // If `schemaVersion` is bumped without running `drift_dev schema dump`,
    // the failure otherwise appears on a shopkeeper's device rather than here.
    for (var version = 1; version <= _currentVersion; version++) {
      expect(
        File('drift_schemas/drift_schema_v$version.json').existsSync(),
        isTrue,
        reason: 'schema v$version has no dump, so nothing can migrate from it',
      );
    }
  });

  group('v1 to v2 — print_jobs', () {
    test(
      'a shop with real data comes through with everything intact',
      () async {
        // The case that matters: not an empty database, but one that has been
        // used. A migration tested only against a fresh schema is a migration
        // tested against the one database nobody has.
        //
        // One schema, two connections onto the same database. This test used
        // to call `startAt` twice, which hands back a fresh, empty database
        // each time — so the row below went into one database and a different,
        // empty one was migrated, and the test proved nothing about data at
        // all while its name said it did.
        final schema = await verifier.schemaAt(1);
        final old = v1.DatabaseAtV1(schema.newConnection());

        const firmId = 'FIRM0000000000000000000001';
        const userId = 'USER0000000000000000000001';
        const deviceId = 'DEV00000000000000000000001';

        // The envelope columns are not optional even here: a v1 row that
        // could not have been written by TxRunner is not a v1 row, and
        // migrating one would prove nothing about a real database.
        await old.customStatement('PRAGMA foreign_keys = OFF');
        await old.customStatement(
          'INSERT INTO firms (id, firm_id, created_at_utc, updated_at_utc, '
          'created_by, updated_by, origin_device_id, hlc, rev, name, '
          'fiscal_year_start_month, base_currency, rounding_mode) '
          'VALUES (?, ?, 1, 1, ?, ?, ?, ?, 1, ?, 7, ?, ?)',
          // customStatement binds raw values, unlike customSelect, which wants
          // Variable wrappers.
          [
            firmId,
            firmId,
            userId,
            userId,
            deviceId,
            'a-0000-$deviceId',
            'Test Kiryana',
            'PKR',
            'half_up',
          ],
        );
        await old.close();

        // Migrate.
        final db = AppDatabase(schema.newConnection());
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, 2);

        final firm = await db
            .customSelect(
              'SELECT name FROM firms WHERE id = ?',
              variables: [Variable<String>(firmId)],
            )
            .getSingle();
        expect(firm.data['name'], 'Test Kiryana');
      },
    );

    test('the new table exists and holds a job after the migration', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final tables = await db
          .customSelect(
            'SELECT name FROM sqlite_master WHERE type = ? AND name = ?',
            variables: [
              Variable<String>('table'),
              Variable<String>('print_jobs'),
            ],
          )
          .get();
      expect(
        tables,
        hasLength(1),
        reason:
            'print_jobs is missing, so nothing remembers whether a bill '
            'was already printed and a reprint after an app kill is a second '
            'receipt',
      );
    });

    test('one job key per firm, enforced by the database', () async {
      // The uniqueness the whole no-double-print design rests on. If two rows
      // can share a key, the second submit does not find the first and prints.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final index = await db
          .customSelect(
            'SELECT sql FROM sqlite_master WHERE type = ? AND name = ?',
            variables: [
              Variable<String>('index'),
              Variable<String>('idx_printjobs_key'),
            ],
          )
          .getSingle();
      expect(index.data['sql'], contains('UNIQUE'));
    });

    test(
      'an unfinished job may not claim a finish time, and vice versa',
      () async {
        // `sending` is the state that means "nobody knows", and it is only
        // meaningful if a finished job cannot wear it. The CHECK is what stops a
        // half-written row looking like a completed one.
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);

        final ddl = await db
            .customSelect(
              'SELECT sql FROM sqlite_master WHERE type = ? AND name = ?',
              variables: [
                Variable<String>('table'),
                Variable<String>('print_jobs'),
              ],
            )
            .getSingle();
        final sql = ddl.data['sql']! as String;
        expect(sql, contains('finished_at_utc IS NULL'));
        expect(sql, contains('sending'));
        expect(sql, contains('printed'));
        expect(sql, contains('partial'));
        expect(sql, contains('failed'));
      },
    );
  });

  group('v2 to v3 — the supplier\'s own bill number', () {
    test(
      'a v2 purchase comes through whole, with room for the number',
      () async {
        // A shop that has already entered deliveries under v2. The column is
        // added in place, so every existing row must come through untouched
        // and simply have no supplier number.
        final schema = await verifier.schemaAt(2);
        final old = v2.DatabaseAtV2(schema.newConnection());

        const firmId = 'FIRM0000000000000000000001';
        const userId = 'USER0000000000000000000001';
        const deviceId = 'DEV00000000000000000000001';
        await old.customStatement('PRAGMA foreign_keys = OFF');
        await old.customStatement(
          'INSERT INTO documents (id, firm_id, created_at_utc, updated_at_utc, '
          'created_by, updated_by, origin_device_id, hlc, rev, doc_type, '
          'doc_no, doc_series, doc_seq, fiscal_year, doc_date_utc, '
          'doc_date_local, status, posted_at_utc, total_paisa) '
          'VALUES (?, ?, 1, 1, ?, ?, ?, ?, 1, ?, ?, ?, 1, 2627, 1, ?, ?, 1, ?)',
          [
            'DOC00000000000000000000001',
            firmId,
            userId,
            userId,
            deviceId,
            'a-0000-$deviceId',
            'purchase_bill',
            'PUR-2627-0001',
            'PUR',
            '2026-08-23',
            'posted',
            120000,
          ],
        );
        await old.close();

        final db = AppDatabase(schema.newConnection());
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, 3);

        final row = await db
            .customSelect(
              'SELECT doc_no, total_paisa, supplier_bill_no FROM documents',
            )
            .getSingle();
        expect(row.data['doc_no'], 'PUR-2627-0001');
        expect(row.data['total_paisa'], 120000);
        expect(row.data['supplier_bill_no'], isNull);
      },
    );
  });

  group('v3 to v4 — the price a party is sold at', () {
    test('a v3 customer comes through whole, as a retail customer', () async {
      // Every customer a shop has entered was charged the retail price, so
      // that is what the new column must say for each of them.
      final schema = await verifier.schemaAt(3);
      final old = v3.DatabaseAtV3(schema.newConnection());

      const firmId = 'FIRM0000000000000000000001';
      const userId = 'USER0000000000000000000001';
      const deviceId = 'DEV00000000000000000000001';
      await old.customStatement('PRAGMA foreign_keys = OFF');
      await old.customStatement(
        'INSERT INTO parties (id, firm_id, created_at_utc, updated_at_utc, '
        'created_by, updated_by, origin_device_id, hlc, rev, name, '
        'name_search, party_type, opening_balance_paisa, credit_limit_paisa) '
        'VALUES (?, ?, 1, 1, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?)',
        [
          'PTY00000000000000000000001',
          firmId,
          userId,
          userId,
          deviceId,
          'a-0000-$deviceId',
          'Rashid Traders',
          'rashid traders',
          'customer',
          4500000,
          10000000,
        ],
      );
      await old.close();

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 4);

      final row = await db
          .customSelect(
            'SELECT name, opening_balance_paisa, credit_limit_paisa, '
            'price_tier FROM parties',
          )
          .getSingle();
      expect(row.data['name'], 'Rashid Traders');
      expect(row.data['opening_balance_paisa'], 4500000);
      expect(row.data['credit_limit_paisa'], 10000000);
      expect(row.data['price_tier'], 'retail');
    });

    test('a price tier the counter does not know is refused', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await expectLater(
        db.customStatement(
          'INSERT INTO parties (id, firm_id, created_at_utc, updated_at_utc, '
          'created_by, updated_by, origin_device_id, hlc, rev, name, '
          "name_search, price_tier) VALUES ('P', 'F', 1, 1, 'U', 'U', 'D', "
          "'h', 1, 'X', 'x', 'vip')",
        ),
        throwsA(anything),
      );
    });
  });

  test('foreign keys are enforced and nothing is dangling', () async {
    // Deferred during a migration and re-checked before it commits. SQLite's
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

/// The version this test file knows how to check.
///
/// Written down rather than read from a database, and asserted equal to the
/// real one below. A loop bounded by `db.schemaVersion` would silently keep
/// passing when a version was added and its dump was not — which is the one
/// thing these tests exist to catch.
const _currentVersion = 4;
