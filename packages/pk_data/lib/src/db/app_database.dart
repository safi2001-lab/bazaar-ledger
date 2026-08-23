import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// The Bazaar Ledger database.
///
/// The schema lives entirely in the `.drift` files included below. Nothing is
/// declared in Dart, because the previous build declared its foreign keys in a
/// Dart table DSL and shipped DDL that contained none of them — regenerating
/// would have forked production into two incompatible schemas under one
/// version number.
///
/// This class takes its [QueryExecutor] from outside and never constructs one.
/// The app supplies an encrypted file on a background isolate; tests supply an
/// in-memory database. That is the only reason the whole persistence layer can
/// be tested headless, without Flutter.
@DriftDatabase(
  include: {
    'tables/core.drift',
    'tables/catalogue.drift',
    'tables/documents.drift',
    'tables/payments.drift',
    'tables/stock.drift',
    'tables/ledger.drift',
    'tables/system.drift',
  },
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Set by the bootstrap when the database is opened for a migration test or
  /// a repair pass, so `beforeOpen` skips the integrity check it would
  /// otherwise run twice.
  bool skipIntegrityCheckOnOpen = false;

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // Every step gets its own committed schema dump and a test that runs
          // it against realistically seeded data. There is nothing to upgrade
          // from at v1; the first `stepByStep` handler arrives with v2.
          throw StateError(
            'No migration from schema v$from to v$to is registered. '
            'A build that can open a database it cannot migrate is how data '
            'gets silently mangled.',
          );
        },
        beforeOpen: (details) async {
          // Referential integrity is not optional and is not the ORM's job.
          // This pragma is per-connection, so it is set here rather than once
          // at creation — and `ddl_invariants_test` asserts the test harness
          // sets it too, because an integrity rule that only holds in
          // production is a rule nobody ever tests.
          await customStatement('PRAGMA foreign_keys = ON');

          // Load-shedding is the requirement, not an edge case. NORMAL loses
          // the last transactions when the power cuts mid-write, and the last
          // transaction is the sale the customer is standing there paying for.
          await customStatement('PRAGMA journal_mode = WAL');
          await customStatement('PRAGMA synchronous = FULL');

          // A cashier holding up the queue is worse than a query waiting.
          await customStatement('PRAGMA busy_timeout = 5000');
          // Temp tables in RAM: report aggregations should not touch the eMMC
          // on a Rs 19,000 handset.
          await customStatement('PRAGMA temp_store = MEMORY');
          // ~8 MB of page cache. Deliberately modest — the floor device has
          // 4 GB of RAM shared with an Android Go ROM that kills eagerly.
          await customStatement('PRAGMA cache_size = -8000');

          if (details.wasCreated) {
            await customStatement('PRAGMA foreign_key_check');
          }
        },
      );

  /// Asserts that the whole ledger balances, for every firm in the database.
  ///
  /// The per-transaction check on [Tx] is scoped to the entries a single write
  /// touched, because a shop with three years of history cannot afford a
  /// full-table sum on every sale. This is the unscoped version: the
  /// reconciler runs it, the Data Health screen runs it, and the test suite
  /// runs it as a global postcondition after every integration test.
  ///
  /// Silent accounting wrongness is invisible for six months and then nothing
  /// balances and nobody can say when it started. This is the tripwire.
  Future<List<String>> findLedgerImbalances() async {
    final findings = <String>[];

    final perFirm = await customSelect('''
      SELECT firm_id,
             COALESCE(SUM(debit_paisa), 0)  AS debit,
             COALESCE(SUM(credit_paisa), 0) AS credit
      FROM journal_lines
      WHERE deleted_at_utc IS NULL
      GROUP BY firm_id
    ''').get();
    for (final row in perFirm) {
      final debit = row.read<int>('debit');
      final credit = row.read<int>('credit');
      if (debit != credit) {
        findings.add(
          'firm ${row.read<String>('firm_id')}: debits $debit paisa but '
          'credits $credit paisa (out by ${debit - credit})',
        );
      }
    }

    final perEntry = await customSelect('''
      SELECT je.entry_no AS entry_no,
             je.total_debit_paisa  AS declared_debit,
             je.total_credit_paisa AS declared_credit,
             COALESCE(SUM(jl.debit_paisa), 0)  AS actual_debit,
             COALESCE(SUM(jl.credit_paisa), 0) AS actual_credit
      FROM journal_entries je
      LEFT JOIN journal_lines jl
        ON jl.journal_entry_id = je.id AND jl.deleted_at_utc IS NULL
      WHERE je.deleted_at_utc IS NULL
      GROUP BY je.id
      HAVING actual_debit <> actual_credit
          OR actual_debit <> declared_debit
          OR actual_credit <> declared_credit
    ''').get();
    for (final row in perEntry) {
      findings.add(
        'entry ${row.read<String>('entry_no')}: lines total '
        '${row.read<int>('actual_debit')}/${row.read<int>('actual_credit')} '
        'against a declared '
        '${row.read<int>('declared_debit')}/'
        '${row.read<int>('declared_credit')}',
      );
    }

    return findings;
  }

  /// Runs the checks the app performs on every cold start, and that the
  /// user-facing Data Health screen runs on demand.
  ///
  /// Returns findings rather than throwing: a shopkeeper opening the app to a
  /// crash screen has lost their business day, whereas one who is told the
  /// database needs repairing still has a working restore button.
  Future<DatabaseHealth> checkHealth() async {
    final findings = <String>[];

    // `quick_check` over `integrity_check`: it skips the UNIQUE-index
    // cross-verification that makes the full check O(minutes) on a large
    // database, and still catches every form of page corruption.
    final quick = await customSelect('PRAGMA quick_check').get();
    for (final row in quick.map((r) => r.data.values.first.toString())) {
      if (row != 'ok') findings.add('quick_check: $row');
    }

    final orphans = await customSelect('PRAGMA foreign_key_check').get();
    for (final row in orphans) {
      findings.add(
        'orphan row in ${row.data['table']} '
        '(rowid ${row.data['rowid']}) referencing ${row.data['parent']}',
      );
    }

    final fkEnabled = await customSelect('PRAGMA foreign_keys').getSingle();
    if (fkEnabled.data.values.first != 1) {
      findings.add('foreign_keys pragma is OFF on this connection');
    }

    findings.addAll(await findLedgerImbalances());

    return DatabaseHealth(
      findings: List.unmodifiable(findings),
      checkedAtUtc: DateTime.now().toUtc(),
    );
  }
}

/// The result of [AppDatabase.checkHealth].
class DatabaseHealth {
  const DatabaseHealth({required this.findings, required this.checkedAtUtc});

  final List<String> findings;
  final DateTime checkedAtUtc;

  bool get isHealthy => findings.isEmpty;

  @override
  String toString() => isHealthy
      ? 'DatabaseHealth(ok, checked $checkedAtUtc)'
      : 'DatabaseHealth(${findings.length} finding(s)): ${findings.join('; ')}';
}
