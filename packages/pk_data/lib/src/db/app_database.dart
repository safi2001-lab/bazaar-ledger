import 'package:drift/drift.dart';
import 'package:pk_domain/pk_domain.dart';
import 'schema_versions.dart';

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
    'tables/manufacturing.drift',
    'tables/vans.drift',
    // M50: used phones bought, warranty claims, qist plans.
    'tables/mobile.drift',
  },
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Set by the bootstrap when the database is opened for a migration test or
  /// a repair pass, so `beforeOpen` skips the integrity check it would
  /// otherwise run twice.

  /// The schema this build writes, and the newest it can open.
  ///
  /// A constant as well as the override, so a restore can refuse a backup
  /// made by a newer build before it replaces anything — rather than after,
  /// when drift finds a database it has no migration down from.
  static const currentSchemaVersion = 12;

  @override
  int get schemaVersion => currentSchemaVersion;

  /// Writes a consistent copy of the whole database to [path].
  ///
  /// `VACUUM INTO` reads one snapshot, so a sale committed while it runs is
  /// either wholly in the copy or wholly out of it — never a bill without its
  /// journal lines. Copying the file instead would race the WAL: the main
  /// file alone is missing whatever has not been checkpointed yet, which on a
  /// busy counter is most of today.
  ///
  /// [path] must not exist. SQLite refuses to overwrite, which is the right
  /// answer for a file that is about to be somebody's only backup.
  Future<void> snapshotTo(String path) =>
      customStatement('VACUUM INTO ?', [path]);

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      // Every version has a committed dump under drift_schemas/ and a test
      // that migrates realistically seeded data into it. There is nothing
      // to upgrade from at v1, so this path does not run yet — but the
      // machinery lands before the first table is added rather than being
      // built under pressure once a shop's database already depends on it.
      //
      // Foreign keys are deliberately deferred for the duration. SQLite's
      // twelve-step table rebuild -- which is what any CHECK constraint
      // change requires -- moves rows through a temporary table, and with
      // enforcement on it trips `foreign_key_check` halfway. That failure
      // does not show up on an empty test database. It shows up on a shop
      // with three years of history.
      await customStatement('PRAGMA defer_foreign_keys = ON');
      try {
        await stepByStep(
          // v1 → v2: print_jobs, so that "was this bill already printed?"
          // survives Android reclaiming the app. Purely additive — one new
          // table and its indexes, no existing table touched, so there is
          // no twelve-step rebuild and nothing to lose.
          from1To2: (migrator, schema) async {
            await migrator.createTable(schema.printJobs);
            await migrator.create(schema.idxPrintjobsKey);
            await migrator.create(schema.idxPrintjobsDoc);
            await migrator.create(schema.idxPrintjobsOpen);
          },
          // v2 → v3: documents.supplier_bill_no. One nullable column added
          // at the end, which SQLite does in place — no rebuild, no row
          // touched, and every existing purchase simply has none.
          from2To3: (migrator, schema) async {
            await migrator.addColumn(
              schema.documents,
              schema.documents.supplierBillNo,
            );
          },
          // v3 → v4: parties.price_tier. Added in place with its default, so
          // every existing customer is a retail customer, which is what the
          // counter already charged them.
          from3To4: (migrator, schema) async {
            await migrator.addColumn(schema.parties, schema.parties.priceTier);
          },
          // v4 → v5 (M15): a VIP price. items gains its column in place;
          // parties is rebuilt, because its CHECK on price_tier has to learn
          // 'vip' and SQLite cannot change a CHECK any other way. Every row
          // is copied across as it was.
          from4To5: (migrator, schema) async {
            await migrator.addColumn(
              schema.items,
              schema.items.vipRateMilliPaisa,
            );
            await migrator.alterTable(TableMigration(schema.parties));
          },
          // v5 → v6 (M17): bills of materials and production runs. Three
          // new tables and their indexes; nothing existing is touched.
          from5To6: (migrator, schema) async {
            await migrator.createTable(schema.boms);
            await migrator.createTable(schema.bomLines);
            await migrator.createTable(schema.assemblies);
            for (final index in [
              schema.idxBomsFirm,
              schema.idxBomsOutput,
              schema.idxBomlinesFirm,
              schema.idxBomlinesBom,
              schema.idxBomlinesItem,
              schema.idxAssembliesNo,
              schema.idxAssembliesBom,
              schema.idxAssembliesOutput,
              schema.idxAssembliesJournal,
            ]) {
              await migrator.create(index);
            }
          },
          // v6 → v7 (M18): vans, their daily settlements, and where each
          // sale left from. The column is added in place and is empty for
          // every existing sale, which all left from the shop floor.
          from6To7: (migrator, schema) async {
            await migrator.addColumn(
              schema.documents,
              schema.documents.locationCode,
            );
            await migrator.createTable(schema.vans);
            await migrator.createTable(schema.vanSettlements);
            for (final index in [
              schema.idxVansLocation,
              schema.idxVansRider,
              schema.idxVansettleDay,
              schema.idxVansettleVan,
              schema.idxVansettleJournal,
            ]) {
              await migrator.create(index);
            }
          },
          // v7 → v8 (M19): FBR's answer on each bill. Four columns added in
          // place, empty on every existing bill, and an index for the queue.
          from7To8: (migrator, schema) async {
            for (final column in [
              schema.documents.fbrStatus,
              schema.documents.fbrInvoiceNo,
              schema.documents.fbrError,
              schema.documents.fbrPostedAtUtc,
            ]) {
              await migrator.addColumn(schema.documents, column);
            }
            await migrator.create(schema.idxDocumentsFbr);
          },
          // v8 → v9 (M56): no table, column or index changes — the search
          // key every item and party is found by changed shape, from the
          // plain name to the plain name and its spelling key, so a search
          // for "cheeni" finds "Chini". Every existing row is re-keyed here,
          // and a backup from before M56 is re-keyed when it is restored.
          from8To9: (migrator, schema) async {
            await respellNames();
          },
          // v9 → v10 (M53): what the counter does when an item would go
          // below nothing, and packs that can come back. items gains one
          // column in place, empty on every existing item, which follows
          // the shop's own setting exactly as it would have. The two unique
          // indexes on unit_conversions are dropped and made again counting
          // live rows only, so a carton struck off an item no longer holds
          // its place against a new one. Dropping an index touches no row,
          // and every pair that was unique among all rows is unique among
          // the live ones, so the new index always builds.
          from9To10: (migrator, schema) async {
            await migrator.addColumn(schema.items, schema.items.negativeStock);
            for (final index in [
              schema.idxUconvFirmwide,
              schema.idxUconvPeritem,
            ]) {
              await migrator.drop(index);
              await migrator.create(index);
            }
          },
          // v10 → v11 (M49): the pharmacy pack. items gains what a medicine
          // is — its salt, strength, maker and Schedule class, and the
          // spelling key of the salt it is found and substituted by — and
          // stock_lots why a batch may not be sold; every column is added in
          // place and is empty on every existing row, so no item becomes a
          // medicine and no batch is held by the upgrade. The register's
          // prescriptions are a new table with its indexes. No row is
          // touched, and nothing is rebuilt.
          from10To11: (migrator, schema) async {
            for (final column in [
              schema.items.genericName,
              schema.items.strength,
              schema.items.genericSearch,
              schema.items.manufacturer,
              schema.items.scheduleClass,
            ]) {
              await migrator.addColumn(schema.items, column);
            }
            await migrator.create(schema.idxItemsGeneric);
            await migrator.addColumn(
              schema.stockLots,
              schema.stockLots.holdReason,
            );
            await migrator.createTable(schema.prescriptions);
            for (final index in [
              schema.idxPrescriptionsLine,
              schema.idxPrescriptionsDoc,
              schema.idxPrescriptionsFirmItem,
              schema.idxPrescriptionsItem,
            ]) {
              await migrator.create(index);
            }
          },
          // v11 → v12 (M50): the mobile-shop pack. stock_lots gains a
          // phone's second IMEI and what PTA said of it; items how long its
          // warranty runs and whose it is; document_lines the day a sold
          // line's warranty ends. Every column is added in place and is
          // empty on every existing row, so no piece becomes a phone, no
          // item gains a warranty and no bill a warranty date by the
          // upgrade. Used phones bought, warranty claims and qist plans are
          // new tables with their indexes. firms is rebuilt, as parties was
          // at v5, because its CHECK on business_kind has to learn 'mobile'
          // and SQLite cannot change a CHECK any other way; every row is
          // copied across as it was.
          from11To12: (migrator, schema) async {
            for (final column in [
              schema.stockLots.serial2,
              schema.stockLots.ptaStatus,
              schema.stockLots.ptaCheckedOnLocal,
            ]) {
              await migrator.addColumn(schema.stockLots, column);
            }
            await migrator.create(schema.idxLotsSerial);
            await migrator.create(schema.idxLotsSerial2);
            for (final column in [
              schema.items.warrantyMonths,
              schema.items.warrantyKind,
            ]) {
              await migrator.addColumn(schema.items, column);
            }
            await migrator.addColumn(
              schema.documentLines,
              schema.documentLines.warrantyUntilLocal,
            );
            await migrator.alterTable(TableMigration(schema.firms));
            for (final table in [
              schema.usedPhoneBuys,
              schema.warrantyClaims,
              schema.qistPlans,
              schema.qistInstalments,
            ]) {
              await migrator.createTable(table);
            }
            for (final index in [
              schema.idxUsedphoneDoc,
              schema.idxUsedphoneFirmCnic,
              schema.idxUsedphoneParty,
              schema.idxWclaimsFirmLot,
              schema.idxWclaimsLot,
              schema.idxQistDoc,
              schema.idxQistFirmParty,
              schema.idxQistParty,
              schema.idxQinstPlanSeq,
              schema.idxQinstFirmDue,
            ]) {
              await migrator.create(index);
            }
          },
        )(m, from, to);
      } on ArgumentError {
        throw StateError(
          'No migration from schema v$from to v$to is registered. '
          'A build that can open a database it cannot migrate is how data '
          'gets silently mangled.',
        );
      }
      // Re-checked before the transaction closes, so a step that broke a
      // reference fails the migration instead of leaving a database that
      // opens and is quietly wrong.
      await customStatement('PRAGMA foreign_key_check');
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
  /// Payments allocated to more than they are worth.
  ///
  /// The books can balance perfectly while a payment is spread across two
  /// invoices for more than the customer handed over — the allocation table is
  /// many-to-many by design, and nothing in SQLite can express "the parts must
  /// not exceed the whole" as a CHECK. It is the most likely way a khata
  /// balance goes quietly wrong, so it is checked rather than assumed.
  Future<List<String>> findOverAllocatedPayments() async {
    final rows = await customSelect('''
      SELECT p.id AS id,
             p.amount_paisa AS amount,
             SUM(pa.amount_paisa) AS allocated
      FROM payments p
      JOIN payment_allocations pa ON pa.payment_id = p.id
      WHERE p.deleted_at_utc IS NULL AND pa.deleted_at_utc IS NULL
      GROUP BY p.id, p.amount_paisa
      HAVING SUM(pa.amount_paisa) > p.amount_paisa
      ''').get();
    return rows.map((r) {
      final id = r.read<String>('id');
      final allocated = r.read<int>('allocated');
      final amount = r.read<int>('amount');
      return 'payment $id is allocated $allocated paisa against $amount '
          'received';
    }).toList();
  }

  /// Cached stock balances that no longer match the ledger they came from.
  ///
  /// `balance_after_thousandths` is a cache, and the schema says so. A cache
  /// that has drifted from the append-only rows beneath it is how a shop finds
  /// out its stock figures are fiction — usually while counting.
  Future<List<String>> findStockLedgerDrift() async {
    // One ordered window pass, not a correlated subquery.
    //
    // Two things had to change beyond the cost. The running sum is ordered by
    // `occurred_at_utc`, which is what the cache was computed against —
    // ordering by id means ordering by ULID, which is insertion order, and a
    // backdated entry (opening stock, or yesterday's purchase keyed in this
    // morning) legitimately arrives later and would have made every
    // subsequent row on that item look wrong.
    //
    // Soft-deleted rows are excluded, because that is what the writer sums
    // when it stamps the cache and what every read sums when it shows stock
    // on hand. This check used to include them, on the stated grounds that
    // "they were included when the cache was written" — which was simply not
    // true of the writer. The two definitions could not be reconciled: a
    // voided row is invisible to the sale that comes after it and visible to
    // the checker, so the shopkeeper saw negative stock while Data Health
    // reported a different number, and `rebuildStockBalances` wrote back a
    // value the next sale immediately contradicted. `TxRunner.softDelete` now
    // refuses the table outright, and any deleted row still in there is
    // reported below as the corruption it is.
    final rows = await customSelect('''
      SELECT id, item_id, cached, actual FROM (
        SELECT sl.id AS id,
               sl.item_id AS item_id,
               sl.balance_after_thousandths AS cached,
               SUM(sl.qty_delta_thousandths) OVER (
                 PARTITION BY sl.firm_id, sl.item_id, sl.location_code
                 ORDER BY sl.occurred_at_utc, sl.id
                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
               ) AS actual
        FROM stock_ledger sl
        WHERE sl.deleted_at_utc IS NULL
      )
      WHERE cached IS NOT NULL AND cached <> actual
      ''').get();
    return rows.map((r) {
      final id = r.read<String>('id');
      final item = r.read<String>('item_id');
      final cached = r.read<int>('cached');
      final actual = r.read<int>('actual');
      return 'stock row $id on item $item caches $cached where the ledger '
          'says $actual';
    }).toList();
  }

  /// Recomputes every cached stock balance from the ledger beneath it.
  ///
  /// The counterpart to [findStockLedgerDrift], and the reason that check is
  /// worth having: a report with no remedy is half a feature. Drift is normal
  /// and expected — a purchase keyed in the morning after it happened is
  /// backdated, and correctly changes the running balance of every row after
  /// it — so the answer is to rebuild, not to panic.
  ///
  /// Writes the cache column only. It touches no financial value, invents no
  /// row and moves no stock, which is why it is allowed to go straight to the
  /// database instead of through the write path: there is nothing here for an
  /// audit trail to record and nothing for a peer to receive.
  Future<int> rebuildStockBalances() async {
    await customStatement('''
      -- This writes one column that is a SUM of rows already committed:
      -- nothing for an audit trail to record, nothing for a peer to receive.
      UPDATE stock_ledger -- arch_check: allow no_raw_dml — derived cache
      SET balance_after_thousandths = (
        SELECT SUM(prior.qty_delta_thousandths)
        FROM stock_ledger prior
        WHERE prior.firm_id = stock_ledger.firm_id
          AND prior.item_id = stock_ledger.item_id
          AND prior.location_code = stock_ledger.location_code
          AND prior.deleted_at_utc IS NULL
          AND (
            prior.occurred_at_utc < stock_ledger.occurred_at_utc
            OR (prior.occurred_at_utc = stock_ledger.occurred_at_utc
                AND prior.id <= stock_ledger.id)
          )
      )
      WHERE balance_after_thousandths IS NOT NULL
        AND deleted_at_utc IS NULL
    ''');
    final remaining = await findStockLedgerDrift();
    return remaining.length;
  }

  /// Re-keys every item's and party's `name_search` from its name, and
  /// returns how many rows it wrote.
  ///
  /// The column is derived: [nameSearchColumn] of the name, nothing a person
  /// typed and nothing another counter needs to be told about, because every
  /// device works it out from the same name with the same function. So, like
  /// [rebuildStockBalances], it goes straight to the database rather than
  /// through the write path — there is no new fact here for an audit trail
  /// or a peer, and stamping twenty thousand items as "edited" by whoever
  /// happened to open the app after an update would put a lie in both.
  ///
  /// Archived and deleted rows are re-keyed too: an item brought back from
  /// the recycle bin has to be findable the moment it is back.
  Future<int> respellNames() async {
    const rewrite = {
      'items': '''
        UPDATE items -- arch_check: allow no_raw_dml — derived search key
        SET name_search = ? WHERE id = ?''',
      'parties': '''
        UPDATE parties -- arch_check: allow no_raw_dml — derived search key
        SET name_search = ? WHERE id = ?''',
    };
    var written = 0;
    for (final MapEntry(key: table, value: sql) in rewrite.entries) {
      final rows = await customSelect(
        'SELECT id, name, name_search FROM $table',
      ).get();
      for (final r in rows) {
        final key = nameSearchColumn(r.read<String>('name'));
        if (key == r.read<String>('name_search')) continue;
        await customStatement(sql, [key, r.read<String>('id')]);
        written++;
      }
    }
    // M49: a medicine's salt is found the same way, and keyed the same way
    // again. Only from v11 on: an older database has no such column, and
    // this runs on its way up to v9, long before it does.
    final medicineColumns = await customSelect(
      "SELECT 1 FROM pragma_table_info('items') WHERE name = 'generic_search'",
    ).get();
    if (medicineColumns.isEmpty) return written;
    final medicines = await customSelect(
      'SELECT id, generic_name, strength, generic_search FROM items '
      'WHERE generic_name IS NOT NULL OR generic_search IS NOT NULL',
    ).get();
    for (final r in medicines) {
      final key = genericSearchColumn(
        r.readNullable<String>('generic_name'),
        r.readNullable<String>('strength'),
      );
      if (key == r.readNullable<String>('generic_search')) continue;
      await customStatement(
        'UPDATE items -- arch_check: allow no_raw_dml — derived search key\n'
        'SET generic_search = ? WHERE id = ?',
        [key, r.read<String>('id')],
      );
      written++;
    }
    return written;
  }

  /// Rows struck out of a ledger that may only be appended to.
  ///
  /// `TxRunner.softDelete` refuses these tables, so a row here did not come
  /// from this app's write path — it came from an older build, a hand-edited
  /// file, or a restore that went wrong. Either way a running balance stamped
  /// on top of it can no longer be reproduced, so it is reported rather than
  /// quietly absorbed.
  Future<List<String>> findDeletedLedgerRows() async {
    final findings = <String>[];
    for (final table in const [
      'stock_ledger',
      'journal_entries',
      'journal_lines',
    ]) {
      final rows = await customSelect(
        'SELECT COUNT(*) c FROM $table WHERE deleted_at_utc IS NOT NULL',
      ).getSingle();
      final count = rows.read<int>('c');
      if (count > 0) {
        findings.add(
          '$count row(s) struck out of $table, which is append-only: a '
          'balance cannot be recomputed across them',
        );
      }
    }
    return findings;
  }

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

    findings.addAll(await findDeletedLedgerRows());
    findings.addAll(await findLedgerImbalances());
    findings.addAll(await findOverAllocatedPayments());
    findings.addAll(await findStockLedgerDrift());

    return DatabaseHealth(
      findings: List.unmodifiable(findings),
      checkedAtUtc: DateTime.now().toUtc(),
    );
  }
}
