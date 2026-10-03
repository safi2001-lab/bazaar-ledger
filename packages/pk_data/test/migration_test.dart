import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v10.dart' as v10;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v8.dart' as v8;
import 'generated/schema_v9.dart' as v9;

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
          "'h', 1, 'X', 'x', 'platinum')",
        ),
        throwsA(anything),
      );
    });
  });

  group('v4 to v5 — a VIP price', () {
    test('a v4 wholesale customer comes through the rebuild whole', () async {
      // parties is rebuilt to change its CHECK, so every column of every row
      // has to come across, and nothing pointing at a party may dangle.
      final schema = await verifier.schemaAt(4);
      final old = v4.DatabaseAtV4(schema.newConnection());
      const firmId = 'FIRM0000000000000000000001';
      const userId = 'USER0000000000000000000001';
      const deviceId = 'DEV00000000000000000000001';
      await old.customStatement('PRAGMA foreign_keys = OFF');
      await old.customStatement(
        'INSERT INTO parties (id, firm_id, created_at_utc, updated_at_utc, '
        'created_by, updated_by, origin_device_id, hlc, rev, name, '
        'name_search, party_type, opening_balance_paisa, price_tier, '
        'default_discount_bp) '
        'VALUES (?, ?, 1, 1, ?, ?, ?, ?, 3, ?, ?, ?, ?, ?, ?)',
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
          'wholesale',
          250,
        ],
      );
      await old.close();

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 5);

      final row = await db
          .customSelect(
            'SELECT name, rev, opening_balance_paisa, price_tier, '
            'default_discount_bp FROM parties',
          )
          .getSingle();
      expect(row.data['name'], 'Rashid Traders');
      expect(row.data['rev'], 3);
      expect(row.data['opening_balance_paisa'], 4500000);
      expect(row.data['price_tier'], 'wholesale');
      expect(row.data['default_discount_bp'], 250);

      await db.customStatement("UPDATE parties SET price_tier = 'vip'");
      final vip = await db
          .customSelect('SELECT price_tier FROM parties')
          .getSingle();
      expect(vip.data['price_tier'], 'vip');
    });
  });

  group('v8 to v9 — names found however they are spelled', () {
    test(
      'every item and party is re-keyed, and nothing else is touched',
      () async {
        // A shop with an item and two customers entered under v8, whose
        // search keys are the plain name and nothing more — one of them in
        // Urdu, which v8 keyed as an empty string. v9 changes no table,
        // column or index; it rewrites those keys, and only those keys.
        final schema = await verifier.schemaAt(8);
        final old = v8.DatabaseAtV8(schema.newConnection());
        const firmId = 'FIRM0000000000000000000001';
        const userId = 'USER0000000000000000000001';
        const deviceId = 'DEV00000000000000000000001';
        await old.customStatement('PRAGMA foreign_keys = OFF');
        await old.customStatement(
          'INSERT INTO items (id, firm_id, created_at_utc, updated_at_utc, '
          'created_by, updated_by, origin_device_id, hlc, rev, name, '
          'name_search, base_unit_id, sale_rate_milli_paisa) '
          'VALUES (?, ?, 1, 1, ?, ?, ?, ?, 4, ?, ?, ?, ?)',
          [
            'ITM00000000000000000000001',
            firmId,
            userId,
            userId,
            deviceId,
            'a-0000-$deviceId',
            'Cheeni 1kg',
            'cheeni 1kg',
            'UNIT0000000000000000000001',
            15000000,
          ],
        );
        for (final (id, name, key) in const [
          ('PTY00000000000000000000001', 'Rehman Traders', 'rehman traders'),
          ('PTY00000000000000000000002', 'محمد علی', ''),
        ]) {
          await old.customStatement(
            'INSERT INTO parties (id, firm_id, created_at_utc, '
            'updated_at_utc, created_by, updated_by, origin_device_id, hlc, '
            'rev, name, name_search, party_type) '
            'VALUES (?, ?, 1, 1, ?, ?, ?, ?, 2, ?, ?, ?)',
            [
              id,
              firmId,
              userId,
              userId,
              deviceId,
              'b-0000-$deviceId',
              name,
              key,
              'customer',
            ],
          );
        }
        await old.close();

        final db = AppDatabase(schema.newConnection());
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, 9);

        final item = await db
            .customSelect(
              'SELECT name, name_search, rev, hlc, sale_rate_milli_paisa '
              'FROM items',
            )
            .getSingle();
        expect(item.data['name'], 'Cheeni 1kg');
        expect(item.data['name_search'], 'cheeni 1kg|cini1kg~CN1KG');
        // A derived key, not an edit: the row's revision and clock are
        // what they were, so no counter is told the item changed.
        expect(item.data['rev'], 4);
        expect(item.data['hlc'], 'a-0000-$deviceId');
        expect(item.data['sale_rate_milli_paisa'], 15000000);

        final parties = await db
            .customSelect('SELECT name_search, rev FROM parties ORDER BY id')
            .get();
        expect(parties.map((r) => r.data['name_search']), [
          'rehman traders|rahmantraders~RHMNTRDRS',
          'محمد علی|mhmdali~MHMDL',
        ]);
        expect(parties.map((r) => r.data['rev']), [2, 2]);

        // So "chini", spelled the other way, is in the key "Cheeni" now has.
        expect(
          item.data['name_search']! as String,
          contains('$nameSearchSeparator${spellingKey('chini')}'),
        );
      },
    );
  });

  group('v9 to v10 — selling below nothing, and packs that come back', () {
    test(
      'an item and its carton come through, the item following the shop, and '
      'a carton struck off no longer holds its place',
      () async {
        // A shop on v9 with an item and a per-item conversion of its own —
        // a carton of 24, which nothing in v9 wrote but the schema has
        // always held — struck out, the way v9's index kept it for ever:
        // on v9 no other carton could go on this item again.
        final schema = await verifier.schemaAt(9);
        final old = v9.DatabaseAtV9(schema.newConnection());
        const firmId = 'FIRM0000000000000000000001';
        const userId = 'USER0000000000000000000001';
        const deviceId = 'DEV00000000000000000000001';
        const itemId = 'ITM00000000000000000000001';
        const pcs = 'UNIT0000000000000000000001';
        const carton = 'UNIT0000000000000000000002';
        await old.customStatement('PRAGMA foreign_keys = OFF');
        await old.customStatement(
          'INSERT INTO items (id, firm_id, created_at_utc, updated_at_utc, '
          'created_by, updated_by, origin_device_id, hlc, rev, name, '
          'name_search, base_unit_id, sale_rate_milli_paisa, '
          'vip_rate_milli_paisa) '
          'VALUES (?, ?, 1, 1, ?, ?, ?, ?, 3, ?, ?, ?, ?, ?)',
          [
            itemId,
            firmId,
            userId,
            userId,
            deviceId,
            'a-0000-$deviceId',
            'Gala Biscuit',
            'gala biscuit|galabiskt~GLBSKT',
            pcs,
            5000000,
            4500000,
          ],
        );
        for (final (id, deleted) in const [('UCV00000000000000000000001', 2)]) {
          await old.customStatement(
            'INSERT INTO unit_conversions (id, firm_id, created_at_utc, '
            'updated_at_utc, created_by, updated_by, deleted_at_utc, '
            'origin_device_id, hlc, rev, from_unit_id, to_unit_id, '
            'factor_thousandths, item_id) '
            'VALUES (?, ?, 1, 1, ?, ?, ?, ?, ?, 1, ?, ?, 24000, ?)',
            [
              id,
              firmId,
              userId,
              userId,
              deleted,
              deviceId,
              'b-0000-$deviceId',
              carton,
              pcs,
              itemId,
            ],
          );
        }
        await old.close();

        final db = AppDatabase(schema.newConnection());
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, 10);

        final item = await db
            .customSelect(
              'SELECT name, rev, hlc, sale_rate_milli_paisa, '
              'vip_rate_milli_paisa, negative_stock FROM items',
            )
            .getSingle();
        expect(item.data['name'], 'Gala Biscuit');
        expect(item.data['rev'], 3);
        expect(item.data['hlc'], 'a-0000-$deviceId');
        expect(item.data['sale_rate_milli_paisa'], 5000000);
        expect(item.data['vip_rate_milli_paisa'], 4500000);
        expect(
          item.data['negative_stock'],
          isNull,
          reason: "an existing item follows the shop's rule",
        );
        final kept = await db
            .customSelect(
              'SELECT id, deleted_at_utc, factor_thousandths '
              'FROM unit_conversions ORDER BY id',
            )
            .get();
        expect(kept.single.data['factor_thousandths'], 24000);
        expect(kept.single.data['deleted_at_utc'], 2);

        // Another carton put on beside the struck-out one: v9 refused this.
        // (The fixture has no firm or units behind it, as above.)
        await db.customStatement('PRAGMA foreign_keys = OFF');
        await db.customStatement(
          'INSERT INTO unit_conversions (id, firm_id, created_at_utc, '
          'updated_at_utc, created_by, updated_by, origin_device_id, hlc, '
          'rev, from_unit_id, to_unit_id, factor_thousandths, item_id) '
          'VALUES (?, ?, 4, 4, ?, ?, ?, ?, 1, ?, ?, 20000, ?)',
          [
            'UCV00000000000000000000003',
            firmId,
            userId,
            userId,
            deviceId,
            'c-0000-$deviceId',
            carton,
            pcs,
            itemId,
          ],
        );
        // Two live cartons are still refused.
        await expectLater(
          db.customStatement(
            'INSERT INTO unit_conversions (id, firm_id, created_at_utc, '
            'updated_at_utc, created_by, updated_by, origin_device_id, hlc, '
            'rev, from_unit_id, to_unit_id, factor_thousandths, item_id) '
            'VALUES (?, ?, 5, 5, ?, ?, ?, ?, 1, ?, ?, 12000, ?)',
            [
              'UCV00000000000000000000004',
              firmId,
              userId,
              userId,
              deviceId,
              'd-0000-$deviceId',
              carton,
              pcs,
              itemId,
            ],
          ),
          throwsA(anything),
        );

        await db.customStatement("UPDATE items SET negative_stock = 'block'");
        await expectLater(
          db.customStatement("UPDATE items SET negative_stock = 'maybe'"),
          throwsA(anything),
          reason: 'a rule the counter does not know is refused',
        );
      },
    );
  });

  group('v10 to v11 — the pharmacy pack', () {
    test('an item and its batch come through as they were, neither a medicine '
        'nor held, and the register is there to be written', () async {
      // A shop on v10 with a medicine it already sells by batch: Panadol,
      // and a batch of it that came in from a distributor, with its
      // printed price and its supplier already in the columns v1 kept.
      final schema = await verifier.schemaAt(10);
      final old = v10.DatabaseAtV10(schema.newConnection());
      const firmId = 'FIRM0000000000000000000001';
      const userId = 'USER0000000000000000000001';
      const deviceId = 'DEV00000000000000000000001';
      const itemId = 'ITM00000000000000000000001';
      const lotId = 'LOT00000000000000000000001';
      await old.customStatement('PRAGMA foreign_keys = OFF');
      await old.customStatement(
        'INSERT INTO items (id, firm_id, created_at_utc, updated_at_utc, '
        'created_by, updated_by, origin_device_id, hlc, rev, name, '
        'name_search, base_unit_id, sale_rate_milli_paisa, mrp_paisa, '
        'track_batch, negative_stock) '
        'VALUES (?, ?, 1, 1, ?, ?, ?, ?, 5, ?, ?, ?, ?, ?, 1, ?)',
        [
          itemId,
          firmId,
          userId,
          userId,
          deviceId,
          'a-0000-$deviceId',
          'Panadol 500mg',
          nameSearchColumn('Panadol 500mg'),
          'UNIT0000000000000000000001',
          4000000,
          4000,
          'warn',
        ],
      );
      await old.customStatement(
        'INSERT INTO stock_lots (id, firm_id, created_at_utc, '
        'updated_at_utc, created_by, updated_by, origin_device_id, hlc, '
        'rev, item_id, lot_no, batch_no, expiry_date_local, mrp_paisa, '
        'cost_milli_paisa, supplier_party_id) '
        'VALUES (?, ?, 1, 1, ?, ?, ?, ?, 1, ?, ?, ?, ?, ?, ?, ?)',
        [
          lotId,
          firmId,
          userId,
          userId,
          deviceId,
          'b-0000-$deviceId',
          itemId,
          'B42',
          'B42',
          '2027-06-30',
          3800,
          3000000,
          'PTY00000000000000000000001',
        ],
      );
      await old.close();

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 11);

      final item = await db
          .customSelect(
            'SELECT name, rev, hlc, mrp_paisa, negative_stock, generic_name, '
            'strength, generic_search, manufacturer, schedule_class '
            'FROM items',
          )
          .getSingle();
      expect(item.data['name'], 'Panadol 500mg');
      expect(item.data['rev'], 5);
      expect(item.data['hlc'], 'a-0000-$deviceId');
      expect(item.data['mrp_paisa'], 4000);
      expect(item.data['negative_stock'], 'warn');
      for (final column in [
        'generic_name',
        'strength',
        'generic_search',
        'manufacturer',
        'schedule_class',
      ]) {
        expect(
          item.data[column],
          isNull,
          reason: 'no item becomes a medicine by an upgrade',
        );
      }
      final lot = await db
          .customSelect(
            'SELECT lot_no, expiry_date_local, mrp_paisa, supplier_party_id, '
            'hold_reason FROM stock_lots',
          )
          .getSingle();
      expect(lot.data['lot_no'], 'B42');
      expect(lot.data['expiry_date_local'], '2027-06-30');
      expect(lot.data['mrp_paisa'], 3800);
      expect(lot.data['supplier_party_id'], 'PTY00000000000000000000001');
      expect(lot.data['hold_reason'], isNull, reason: 'no batch is held');

      // The new columns hold what they are for, and refuse what they are
      // not.
      await db.customStatement(
        "UPDATE items SET generic_name = 'Paracetamol', strength = '500 mg', "
        "schedule_class = 'B'",
      );
      await expectLater(
        db.customStatement("UPDATE items SET schedule_class = 'X'"),
        throwsA(anything),
        reason: 'a schedule the rules do not name is refused',
      );
      await expectLater(
        db.customStatement("UPDATE stock_lots SET hold_reason = '  '"),
        throwsA(anything),
        reason: 'a hold has to say why',
      );
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name = 'prescriptions'",
          )
          .get();
      expect(tables, hasLength(1));
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
const _currentVersion = 11;
