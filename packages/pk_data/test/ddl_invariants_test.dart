import 'package:pk_data/pk_data.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// These tests read the database that actually exists — `sqlite_master` and the
/// schema pragmas — and never the Dart that was supposed to produce it.
///
/// That distinction is the whole point. The previous build declared more than
/// twenty `.references()` in a Dart table DSL and shipped DDL with zero
/// REFERENCES clauses in it. Every test it had passed. Nothing ever asked the
/// database what it had been given.
void main() {
  late AppDatabase db;
  late List<String> tables;
  late Map<String, List<_Column>> columns;
  late Map<String, List<_Fk>> foreignKeys;
  late Map<String, Set<String>> indexLeaders;
  late Map<String, bool> isStrict;

  setUpAll(() async {
    db = await openTestDatabase();

    final tableRows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .get();
    tables = [for (final r in tableRows) r.read<String>('name')];

    isStrict = {};
    for (final r in await db.customSelect('PRAGMA table_list').get()) {
      final name = r.read<String>('name');
      if (tables.contains(name)) {
        isStrict[name] = r.read<int>('strict') == 1;
      }
    }

    columns = {};
    foreignKeys = {};
    indexLeaders = {};
    for (final t in tables) {
      columns[t] = [
        for (final r in await db.customSelect('PRAGMA table_info($t)').get())
          _Column(
            name: r.read<String>('name'),
            type: r.read<String>('type'),
            notNull: r.read<int>('notnull') == 1,
            pkPosition: r.read<int>('pk'),
          ),
      ];

      foreignKeys[t] = [
        for (final r
            in await db.customSelect('PRAGMA foreign_key_list($t)').get())
          _Fk(
            from: r.read<String>('from'),
            parentTable: r.read<String>('table'),
            parentColumn: r.readNullable<String>('to'),
          ),
      ];

      // The leftmost column of every NON-PARTIAL index. A partial index cannot
      // serve a general foreign-key lookup or a parent-delete scan, so it does
      // not count as covering.
      final leaders = <String>{};
      for (final idx in await db.customSelect('PRAGMA index_list($t)').get()) {
        if (idx.read<int>('partial') == 1) continue;
        final name = idx.read<String>('name');
        final info = await db.customSelect("PRAGMA index_info('$name')").get();
        final first = info.firstWhere((r) => r.read<int>('seqno') == 0);
        final col = first.readNullable<String>('name');
        if (col != null) leaders.add(col);
      }
      // A single-column TEXT primary key is stored in the table's own b-tree
      // index, which covers it as well as any explicit index would.
      for (final c in columns[t]!) {
        if (c.pkPosition == 1) leaders.add(c.name);
      }
      indexLeaders[t] = leaders;
    }
  });

  tearDownAll(() async => db.close());

  test('the schema contains exactly the tables this version plans', () {
    // Keyed by version, not hardcoded to one. The list used to say "the
    // twenty-five planned tables" and adding a table broke a green ledger row
    // -- which is a test failing for bookkeeping rather than for a defect, and
    // the fastest route to somebody loosening the assertion instead of
    // updating it.
    final expected = _tablesByVersion[db.schemaVersion];
    expect(
      expected,
      isNotNull,
      reason:
          'schema v${db.schemaVersion} has no table list here. Add one '
          'when you add the version, so a table that arrives by accident '
          'still fails.',
    );
    expect(tables, equals(expected));
  });

  test('every table is STRICT', () {
    // Without STRICT, SQLite accepts the string "abc" into an INTEGER column
    // and stores it as text. A money column that can hold "abc" is not a money
    // column.
    final loose = [
      for (final t in tables)
        if (isStrict[t] != true) t,
    ];
    expect(loose, isEmpty, reason: 'these tables are not STRICT: $loose');
  });

  test('there is no REAL column anywhere in the database', () {
    // The reason this package exists. The previous build stored money in REAL
    // columns and then hid the accumulated drift behind a `> 0.01` tolerance
    // in its ledger balance check.
    final offenders = <String>[];
    for (final t in tables) {
      for (final c in columns[t]!) {
        final type = c.type.toUpperCase();
        if (type == 'REAL' || type == 'ANY') {
          offenders.add('$t.${c.name} ($type)');
        }
        if (!const {'INT', 'INTEGER', 'TEXT', 'BLOB'}.contains(type)) {
          offenders.add('$t.${c.name} has non-STRICT type "$type"');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('every primary key is a single TEXT column named id', () {
    // ULIDs. An autoincrementing integer makes LAN sync impossible without
    // renumbering every foreign key in the database at merge time.
    for (final t in tables) {
      final pk = columns[t]!.where((c) => c.pkPosition > 0).toList();
      expect(pk, hasLength(1), reason: '$t must have a single-column PK');
      expect(pk.single.name, 'id', reason: '$t primary key');
      expect(pk.single.type.toUpperCase(), 'TEXT', reason: '$t.id type');
      expect(pk.single.notNull, isTrue, reason: '$t.id nullability');
    }
  });

  test('every table carries the universal row envelope', () {
    // You cannot backfill `created_by` for rows created before the column
    // existed. Either every table has the envelope on day one or the audit
    // trail has a hole in it forever.
    for (final t in tables) {
      final names = {for (final c in columns[t]!) c.name};
      for (final e in _envelope) {
        expect(names, contains(e), reason: '$t is missing envelope column $e');
      }
      final byName = {for (final c in columns[t]!) c.name: c};
      for (final e in _envelopeNotNull) {
        expect(byName[e]!.notNull, isTrue, reason: '$t.$e must be NOT NULL');
      }
      expect(
        byName['deleted_at_utc']!.notNull,
        isFalse,
        reason:
            '$t.deleted_at_utc must be nullable — a live row has no '
            'deletion timestamp',
      );
    }
  });

  test('every *_id column is a real foreign key', () {
    final offenders = <String>[];
    for (final t in tables) {
      final fkColumns = {for (final f in foreignKeys[t]!) f.from};
      for (final c in columns[t]!) {
        if (!c.name.endsWith('_id')) continue;
        if (_looseIdColumns.contains('$t.${c.name}')) continue;
        if (!fkColumns.contains(c.name)) {
          offenders.add('$t.${c.name}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'columns named like a foreign key but declaring none:\n'
          '${offenders.join('\n')}',
    );
  });

  test('every foreign key points at an existing table and column', () {
    for (final t in tables) {
      for (final f in foreignKeys[t]!) {
        expect(
          tables,
          contains(f.parentTable),
          reason: '$t.${f.from} references unknown table ${f.parentTable}',
        );
        // A null `to` means the FK targets the parent's primary key.
        final target = f.parentColumn ?? 'id';
        final parentColumns = {for (final c in columns[f.parentTable]!) c.name};
        expect(
          parentColumns,
          contains(target),
          reason:
              '$t.${f.from} references '
              '${f.parentTable}.$target, which does not exist',
        );
      }
    }
  });

  test('every foreign key has a covering index', () {
    // Without one, SQLite full-scans the child table for every parent delete
    // and every join through the key. On a 20,000-SKU database that is the
    // difference between a report drawing and a report timing out.
    final offenders = <String>[];
    for (final t in tables) {
      for (final f in foreignKeys[t]!) {
        if (_envelopeActorColumns.contains(f.from)) continue;
        if (!indexLeaders[t]!.contains(f.from)) {
          offenders.add('$t.${f.from} -> ${f.parentTable}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'foreign keys with no index leading on the child column:\n'
          '${offenders.join('\n')}',
    );
  });

  test('firm scoping is universal', () {
    for (final t in tables) {
      // `firms` is the one table where scoping to a firm means looking the
      // firm up by its own primary key: CHECK (firm_id = id) holds, so the
      // table's own b-tree already is the index this rule asks for.
      if (t == 'firms') continue;
      expect(
        indexLeaders[t],
        contains('firm_id'),
        reason:
            '$t must have an index leading on firm_id — every query in '
            'the app filters by firm, and a multi-firm user must never see '
            'a scan across firms',
      );
    }
  });

  test('quantity, money and rate columns declare their unit in their name', () {
    // `amount` is a question. `amount_paisa` is an answer. This is what stops
    // someone adding a column in eighteen months whose scale nobody can
    // reconstruct from the schema.
    final offenders = <String>[];
    for (final t in tables) {
      for (final c in columns[t]!) {
        if (_bareNumericNames.contains(c.name)) {
          offenders.add(
            '$t.${c.name} — needs a _paisa / _milli_paisa / '
            '_thousandths / _bp suffix',
          );
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('timestamp columns declare their zone in their name', () {
    // Pakistan Standard Time is UTC+5 with no daylight saving, so a UTC day
    // boundary pushes the last five hours of every business day into
    // tomorrow's Day Book. Instants are `_utc`; business dates that must group
    // by the shopkeeper's day are `_local` text.
    final offenders = <String>[];
    for (final t in tables) {
      for (final c in columns[t]!) {
        final n = c.name;
        final looksTemporal =
            n.endsWith('_at') ||
            n.endsWith('_date') ||
            n.endsWith('_on') ||
            n.endsWith('_time');
        if (looksTemporal) offenders.add('$t.$n');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'these need a _utc or _local suffix:\n'
          '${offenders.join('\n')}',
    );
  });

  test('the test harness itself enforces foreign keys', () async {
    // Named explicitly, because a suite that runs with foreign keys off proves
    // nothing about a product that runs with them on.
    final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(row.data.values.first, 1);
  });

  test('a freshly created schema has no orphan rows', () async {
    final orphans = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(orphans, isEmpty);
  });

  test('quick_check passes on a fresh database', () async {
    final health = await db.checkHealth();
    expect(health.isHealthy, isTrue, reason: health.toString());
  });
}

/// Every table, per schema version.
///
/// A new version copies the previous list and adds to it. Spelling the whole
/// set out each time is deliberate: a diff then shows exactly what a migration
/// introduced, and a table that arrives without anybody deciding to add it
/// fails here rather than shipping.
/// Compared against `sqlite_master` in name order, so each list is sorted.
const _tablesByVersion = <int, List<String>>{
  1: _tablesV1,
  2: _tablesV2,
  // v3 added a column, not a table.
  3: _tablesV2,
  // v4 added a column, not a table.
  4: _tablesV2,
  // v5 added a column and rebuilt parties, not a table.
  5: _tablesV2,
};

const _tablesV1 = <String>[
  'accounts',
  'attachments',
  'audit_log',
  'change_log',
  'devices',
  'doc_links',
  'document_line_taxes',
  'document_lines',
  'documents',
  'firms',
  'items',
  'journal_entries',
  'journal_lines',
  'numbering_sequences',
  'parties',
  'payment_accounts',
  'payment_allocations',
  'payments',
  'settings',
  'stock_ledger',
  'stock_lots',
  'tax_rules',
  'unit_conversions',
  'units',
  'users',
];

const _tablesV2 = <String>[
  'accounts',
  'attachments',
  'audit_log',
  'change_log',
  'devices',
  'doc_links',
  'document_line_taxes',
  'document_lines',
  'documents',
  'firms',
  'items',
  'journal_entries',
  'journal_lines',
  'numbering_sequences',
  'parties',
  'payment_accounts',
  'payment_allocations',
  'payments',
  'print_jobs',
  'settings',
  'stock_ledger',
  'stock_lots',
  'tax_rules',
  'unit_conversions',
  'units',
  'users',
];

const _envelope = <String>[
  'id',
  'firm_id',
  'created_at_utc',
  'updated_at_utc',
  'created_by',
  'updated_by',
  'deleted_at_utc',
  'origin_device_id',
  'hlc',
  'rev',
];

const _envelopeNotNull = <String>[
  'id',
  'firm_id',
  'created_at_utc',
  'updated_at_utc',
  'created_by',
  'updated_by',
  'origin_device_id',
  'hlc',
  'rev',
];

/// The actor columns of the envelope. They are exempt from the covering-index
/// rule: they are never a query predicate and their parents are never hard
/// deleted, so an index on each of them across twenty-five tables would cost
/// write throughput and database size on a Rs 19,000 handset and buy nothing.
const _envelopeActorColumns = <String>{
  'created_by',
  'updated_by',
  'origin_device_id',
};

/// The complete list of `*_id` columns that carry no foreign key, and why.
/// Nothing may be added here without a reason of the same kind.
const _looseIdColumns = <String>{
  // Bootstrap roots. The first firm row is written before any user or device
  // row exists to point at, and declaring the FK anyway makes
  // firms -> users -> devices -> firms a cycle no insert order resolves.
  // CHECK (firm_id = id) on `firms` is strictly stronger than the FK it
  // replaces.
  'firms.firm_id',
  'firms.origin_device_id',
  // Polymorphic back-references. A hard FK would need one nullable column per
  // owner table, and an attachment outlives the row that pointed at it.
  'attachments.owner_id',
  'audit_log.entity_id',
  'change_log.entity_id',
};

/// Numeric column names that state a magnitude without stating its unit.
const _bareNumericNames = <String>{
  'amount',
  'balance',
  'cost',
  'discount',
  'mrp',
  'paid',
  'price',
  'qty',
  'quantity',
  'rate',
  'subtotal',
  'tax',
  'total',
  'value',
};

class _Column {
  const _Column({
    required this.name,
    required this.type,
    required this.notNull,
    required this.pkPosition,
  });

  final String name;
  final String type;
  final bool notNull;
  final int pkPosition;

  @override
  String toString() => '$name $type';
}

class _Fk {
  const _Fk({
    required this.from,
    required this.parentTable,
    required this.parentColumn,
  });

  final String from;
  final String parentTable;
  final String? parentColumn;
}
