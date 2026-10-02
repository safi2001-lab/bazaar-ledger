import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// A shop set up before M56 gets the units shipped since.
///
/// Units are seeded once, at first run, so the carton, the dabba, the
/// packet, the strip and the tablet are missing from every shop that
/// existed before them. They are added through the one write path, so they
/// reach the change log (and so every counter) and the audit trail says so.
void main() {
  late AppDatabase db;
  late FirstRunResult firm;
  late ActorContext actor;
  late TxRunner runner;

  setUp(() async {
    db = await openTestDatabase();
    final clock = FixedClock(DateTime.utc(2026, 10, 2, 9));
    final ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    actor = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
  });

  tearDown(() async => db.close());

  /// The shop as it was before M56: none of the packs.
  Future<void> setUpBeforeM56() => db.customStatement(
    // A fixture, not the app: the rows a pre-M56 first run never wrote.
    "DELETE FROM units WHERE code IN ('carton', 'dabba', 'packet', 'strip', "
    "'tablet')",
  );

  Future<List<String>> codes() async => [
    for (final r
        in await db
            .customSelect(
              'SELECT code FROM units WHERE deleted_at_utc IS NULL ORDER BY code',
            )
            .get())
      r.read<String>('code'),
  ];

  group('units shipped since', () {
    test('a shop from before M56 is given the packs, once', () async {
      await setUpBeforeM56();
      expect(await codes(), isNot(contains('carton')));

      final added = await runner.run(actor, addMissingUnits);
      expect(added, ['carton', 'dabba', 'packet', 'strip', 'tablet']);
      expect(await codes(), containsAll(added));

      // Through the write path: every counter is told, and the owner can
      // see what happened and when.
      final logged = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM change_log WHERE entity_table = 'units' "
            "AND op = 'insert'",
          )
          .getSingle();
      expect(logged.read<int>('n'), greaterThanOrEqualTo(5));
      final audit = await db
          .customSelect(
            "SELECT summary FROM audit_log WHERE action_code = 'UNITS_ADDED'",
          )
          .getSingle();
      expect(audit.read<String>('summary'), contains('carton'));

      // And a second opening finds nothing to add.
      expect(await runner.run(actor, addMissingUnits), isEmpty);
    });

    test('a new shop has them all already, and nothing is added', () async {
      expect(await runner.run(actor, addMissingUnits), isEmpty);
      expect(await codes(), hasLength(defaultUnits.length));
    });

    test('a unit the shop hid stays hidden', () async {
      await setUpBeforeM56();
      final added = await runner.run(actor, addMissingUnits);
      final tablet =
          (await db
                  .customSelect("SELECT id FROM units WHERE code = 'tablet'")
                  .getSingle())
              .read<String>('id');
      await runner.run(actor, (tx) => tx.softDelete('units', tablet));

      expect(added, contains('tablet'));
      expect(await runner.run(actor, addMissingUnits), isEmpty);
      expect(await codes(), isNot(contains('tablet')));
    });
  });
}
