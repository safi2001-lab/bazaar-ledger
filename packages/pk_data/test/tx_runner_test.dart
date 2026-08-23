import 'dart:convert';

import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

void main() {
  late AppDatabase db;
  late FixedClock clock;
  late UlidGenerator ids;
  late FirstRunResult firm;
  late TxRunner runner;
  late ActorContext actor;

  setUp(() async {
    db = await openTestDatabase();
    clock = FixedClock(DateTime.utc(2026, 8, 23, 9, 15));
    ids = UlidGenerator(now: clock.nowUtc);
    firm = await FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
      platform: 'test',
      city: 'Lahore',
    );
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    actor = firm.actorAt(clock.nowUtc());
  });

  tearDown(() async => db.close());

  group('first run', () {
    test('seeds a complete, balanced, self-consistent shop', () async {
      Future<int> count(String table) async {
        final row = await db
            .customSelect('SELECT COUNT(*) AS n FROM $table')
            .getSingle();
        return row.read<int>('n');
      }

      expect(await count('firms'), 1);
      expect(await count('users'), 1);
      expect(await count('devices'), 1);
      // Literal numbers, not `defaultChartOfAccounts.length`. An oracle
      // that reads the same constant the seeder iterates says only that
      // the loop ran; empty the list and it becomes 0 == 0.
      expect(await count('accounts'), 37);
      expect(await count('units'), 10);
      expect(await count('unit_conversions'), 6);
      expect(await count('payment_accounts'), 1);
      expect(await count('numbering_sequences'), 3);

      final health = await db.checkHealth();
      expect(health.isHealthy, isTrue, reason: health.toString());
    });

    test('the chart of accounts hangs together', () async {
      // Every posting rule looks accounts up by system_key, so a missing or
      // duplicated key is a sale that cannot be posted.
      final rows = await db
          .customSelect(
            'SELECT code, system_key, parent_id FROM accounts '
            'WHERE system_key IS NOT NULL',
          )
          .get();
      final keys = [for (final r in rows) r.read<String>('system_key')];
      expect(keys.toSet().length, keys.length, reason: 'system keys are unique');
      expect(keys, contains('cash_in_hand'));
      expect(keys, contains('sales'));
      expect(keys, contains('accounts_receivable'));
      expect(keys, contains('output_tax'));
      expect(keys, contains('cogs'));
      expect(keys, contains('round_off'));

      // Children resolved to a real parent id, not a dangling code.
      for (final r in rows) {
        expect(r.readNullable<String>('parent_id'), isNotNull,
            reason: '${r.read<String>('code')} should sit under a root');
      }
    });

    test('a maund is forty kilos', () async {
      final row = await db
          .customSelect('''
            SELECT uc.factor_thousandths AS factor
            FROM unit_conversions uc
            JOIN units u ON u.id = uc.from_unit_id
            WHERE u.code = 'maund'
          ''')
          .getSingle();
      // Base unit is the kilo, so one maund is 40 kg — not the historic
      // British-Indian 37.324 kg, which is not what anybody in the wheat trade
      // means by the word.
      expect(row.read<int>('factor') ~/ 1000, 40);
    });

    test('cannot be run twice', () async {
      expect(
        FirstRunSeeder(database: db, ids: ids, clock: clock).seed(
          shopName: 'Second Shop',
          ownerName: 'Someone Else',
          deviceLabel: 'Counter 1',
          platform: 'test',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('the envelope', () {
    test('is stamped on every row from the ActorContext', () async {
      final partyId = await runner.run(
        actor,
        (tx) => tx.insert('parties', {
          'name': 'Bilal General Store',
          'name_search': 'bilal general store',
          'party_type': 'customer',
        }),
      );

      final row = await db
          .customSelect(
            'SELECT * FROM parties WHERE id = ?',
            variables: [Variable<String>(partyId)],
          )
          .getSingle();

      expect(row.read<String>('firm_id'), firm.firmId);
      expect(row.read<String>('created_by'), firm.ownerUserId);
      expect(row.read<String>('updated_by'), firm.ownerUserId);
      expect(row.read<String>('origin_device_id'), firm.deviceId);
      expect(row.read<int>('created_at_utc'), actor.epochMillis);
      expect(row.read<int>('rev'), 1);
      expect(row.readNullable<int>('deleted_at_utc'), isNull);
      expect(Hlc.tryParse(row.read<String>('hlc')), isNotNull);
      expect(UlidGenerator.isValid(partyId), isTrue);
    });

    test('cannot be forged by a caller', () async {
      // A use case that could set its own created_by could write a sale as
      // somebody else, and the audit trail would be worthless.
      for (final forged in const [
        {'created_by': 'someone-else'},
        {'firm_id': 'another-firm'},
        {'rev': 99},
        {'hlc': 'ZZZ'},
      ]) {
        await expectLater(
          runner.run(
            actor,
            (tx) => tx.insert('parties', {
              'name': 'X',
              'name_search': 'x',
              ...forged,
            }),
          ),
          throwsA(isA<ArgumentError>()),
          reason: 'rejects ${forged.keys.first}',
        );
      }
    });

    test('an update bumps the revision and re-stamps the clock', () async {
      final partyId = await runner.run(
        actor,
        (tx) => tx.insert('parties', {
          'name': 'Bilal General Store',
          'name_search': 'bilal general store',
          'party_type': 'customer',
        }),
      );

      clock.advance(const Duration(minutes: 40));
      final later = firm.actorAt(clock.nowUtc());
      await runner.run(
        later,
        (tx) => tx.update('parties', partyId, {
          'credit_limit_paisa': 5000000,
        }),
      );

      final row = await db
          .customSelect(
            'SELECT * FROM parties WHERE id = ?',
            variables: [Variable<String>(partyId)],
          )
          .getSingle();
      expect(row.read<int>('rev'), 2);
      expect(row.read<int>('credit_limit_paisa'), 5000000);
      expect(row.read<int>('updated_at_utc'), later.epochMillis);
      expect(row.read<int>('created_at_utc'), actor.epochMillis,
          reason: 'creation time is history and does not move');
    });

    test('a soft delete leaves the row where it was', () async {
      // Six-year retention under s.24 STA is a legal obligation, and a
      // shopkeeper who deletes a bill by accident wants it back tomorrow.
      final partyId = await runner.run(
        actor,
        (tx) => tx.insert('parties', {
          'name': 'Closed Account',
          'name_search': 'closed account',
          'party_type': 'customer',
        }),
      );
      await runner.run(actor, (tx) => tx.softDelete('parties', partyId));

      final row = await db
          .customSelect(
            'SELECT * FROM parties WHERE id = ?',
            variables: [Variable<String>(partyId)],
          )
          .getSingle();
      expect(row.readNullable<int>('deleted_at_utc'), isNotNull);
      expect(row.read<String>('name'), 'Closed Account');
    });

    test('a write cannot land on another firm\'s row', () async {
      final partyId = await runner.run(
        actor,
        (tx) => tx.insert('parties', {
          'name': 'Ours',
          'name_search': 'ours',
          'party_type': 'customer',
        }),
      );

      final intruder = ActorContext(
        firmId: 'SOME-OTHER-FIRM',
        userId: firm.ownerUserId,
        deviceId: firm.deviceId,
        startedAtUtc: clock.nowUtc(),
      );
      await expectLater(
        runner.run(
          intruder,
          (tx) => tx.update('parties', partyId, {'city': 'Karachi'}),
        ),
        throwsA(isA<StateError>()),
      );

      final row = await db
          .customSelect(
            'SELECT * FROM parties WHERE id = ?',
            variables: [Variable<String>(partyId)],
          )
          .getSingle();
      expect(row.readNullable<String>('city'), isNull);
    });
  });

  group('the outbox', () {
    test('records every mutation, in order, with no gaps', () async {
      // The transport lands in M13. The format lands now, because data created
      // before an outbox exists can never be synced afterwards.
      final before = await _seqs(db);

      await runner.run(actor, (tx) async {
        await tx.insert('parties', {
          'name': 'A',
          'name_search': 'a',
          'party_type': 'customer',
        });
        await tx.insert('parties', {
          'name': 'B',
          'name_search': 'b',
          'party_type': 'customer',
        });
      });

      final after = await _seqs(db);
      expect(after.length, before.length + 2);
      // Strictly increasing, one at a time, from 1.
      expect(after, equals(List.generate(after.length, (i) => i + 1)));

      final device = await db
          .customSelect(
            'SELECT change_seq FROM devices WHERE id = ?',
            variables: [Variable<String>(firm.deviceId)],
          )
          .getSingle();
      expect(device.read<int>('change_seq'), after.last,
          reason: 'the device counter must survive to the next transaction');
    });

    test('carries a payload a peer can apply', () async {
      final partyId = await runner.run(
        actor,
        (tx) => tx.insert('parties', {
          'name': 'Bilal General Store',
          'name_search': 'bilal general store',
          'party_type': 'customer',
        }),
      );

      final row = await db
          .customSelect(
            "SELECT * FROM change_log WHERE entity_id = ? AND op = 'insert'",
            variables: [Variable<String>(partyId)],
          )
          .getSingle();
      final payload =
          jsonDecode(row.read<String>('payload_json')) as Map<String, Object?>;

      expect(row.read<String>('entity_table'), 'parties');
      expect(row.read<int>('entity_rev'), 1);
      expect(payload['name'], 'Bilal General Store');
      expect(payload['firm_id'], firm.firmId);
      expect(payload['created_by'], firm.ownerUserId);
      expect(row.read<String>('sync_state'), 'pending');
    });

    test('an update payload carries only what changed', () async {
      final partyId = await runner.run(
        actor,
        (tx) => tx.insert('parties', {
          'name': 'Bilal',
          'name_search': 'bilal',
          'party_type': 'customer',
        }),
      );
      await runner.run(
        actor,
        (tx) => tx.update('parties', partyId, {'city': 'Multan'}),
      );

      final row = await db
          .customSelect(
            "SELECT * FROM change_log WHERE entity_id = ? AND op = 'update'",
            variables: [Variable<String>(partyId)],
          )
          .getSingle();
      final payload =
          jsonDecode(row.read<String>('payload_json')) as Map<String, Object?>;
      expect(payload.keys, unorderedEquals(['id', 'city']));
      expect(row.read<int>('entity_rev'), 2);
    });
  });

  group('the audit trail', () {
    test('is written on commit, attributed to the actor', () async {
      await runner.run(actor, (tx) async {
        final id = await tx.insert('parties', {
          'name': 'Bilal General Store',
          'name_search': 'bilal general store',
          'party_type': 'customer',
        });
        tx.audit(
          action: 'PARTY_CREATED',
          entityTable: 'parties',
          entityId: id,
          summary: 'Bilal General Store added to the khata',
        );
      });

      final row = await db
          .customSelect(
            "SELECT * FROM audit_log WHERE action_code = 'PARTY_CREATED'",
          )
          .getSingle();
      expect(row.read<String>('created_by'), firm.ownerUserId);
      expect(row.read<String>('origin_device_id'), firm.deviceId);
      expect(row.read<String>('summary'), contains('Bilal'));
    });

    test('never survives a rolled-back action', () async {
      await expectLater(
        runner.run(actor, (tx) async {
          await tx.insert('parties', {
            'name': 'Ghost',
            'name_search': 'ghost',
            'party_type': 'customer',
          });
          tx.audit(
            action: 'PARTY_CREATED',
            entityTable: 'parties',
            entityId: 'whatever',
            summary: 'this never happened',
          );
          throw const _InjectedFault();
        }),
        throwsA(isA<_InjectedFault>()),
      );

      final audits = await db
          .customSelect(
            "SELECT * FROM audit_log WHERE action_code = 'PARTY_CREATED'",
          )
          .get();
      expect(audits, isEmpty);
    });
  });

  group('atomicity', () {
    test('a fault mid-transaction leaves nothing behind, anywhere', () async {
      // The M0 acceptance step in full: throw after the document insert and
      // assert every table it would have touched is empty. The previous build
      // could not fail this test because it never wrote anything to begin
      // with, and told the user it had.
      final baseline = await _rowCounts(db);

      await expectLater(
        runner.run(actor, (tx) async {
          await tx.insert('documents', {
            'doc_type': 'sale_invoice',
            'doc_no': 'INV-2627-0001',
            'doc_series': 'INV',
            'doc_seq': 1,
            'fiscal_year': 2627,
            'doc_date_utc': actor.epochMillis,
            'doc_date_local': actor.businessDate.value,
            'status': 'posted',
            'posted_at_utc': actor.epochMillis,
            'total_paisa': 552500,
          });
          throw const _InjectedFault();
        }),
        throwsA(isA<_InjectedFault>()),
      );

      expect(await _rowCounts(db), equals(baseline));
    });

    test('the device sequence does not advance on a rollback', () async {
      // Otherwise a peer would ask for change 12 and find it never existed,
      // and the sync would stall on a gap that can never be filled.
      final before = await db
          .customSelect(
            'SELECT change_seq FROM devices WHERE id = ?',
            variables: [Variable<String>(firm.deviceId)],
          )
          .getSingle();

      await expectLater(
        runner.run(actor, (tx) async {
          await tx.insert('parties', {
            'name': 'Ghost',
            'name_search': 'ghost',
            'party_type': 'customer',
          });
          throw const _InjectedFault();
        }),
        throwsA(isA<_InjectedFault>()),
      );

      final after = await db
          .customSelect(
            'SELECT change_seq FROM devices WHERE id = ?',
            variables: [Variable<String>(firm.deviceId)],
          )
          .getSingle();
      expect(after.read<int>('change_seq'), before.read<int>('change_seq'));
    });

    test('refuses to write for an unregistered device', () async {
      final stranger = ActorContext(
        firmId: firm.firmId,
        userId: firm.ownerUserId,
        deviceId: 'A-DEVICE-THAT-DOES-NOT-EXIST',
        startedAtUtc: clock.nowUtc(),
      );
      expect(
        runner.run(
          stranger,
          (tx) => tx.insert('parties', {
            'name': 'X',
            'name_search': 'x',
            'party_type': 'customer',
          }),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('assertBooksBalance', () {
    Future<String> account(String systemKey) async {
      final row = await db
          .customSelect(
            'SELECT id FROM accounts WHERE system_key = ?',
            variables: [Variable<String>(systemKey)],
          )
          .getSingle();
      return row.read<String>('id');
    }

    test('lets a balanced entry through', () async {
      final cash = await account('cash_in_hand');
      final sales = await account('sales');

      await runner.run(actor, (tx) async {
        final entryId = await tx.insert('journal_entries', {
          'entry_no': 'JV-00001',
          'entry_date_utc': actor.epochMillis,
          'entry_date_local': actor.businessDate.value,
          'fiscal_year': 2627,
          'source_type': 'sale',
          'total_debit_paisa': 552500,
          'total_credit_paisa': 552500,
        });
        await tx.insert('journal_lines', {
          'journal_entry_id': entryId,
          'line_no': 1,
          'account_id': cash,
          'debit_paisa': 552500,
          'credit_paisa': 0,
        });
        await tx.insert('journal_lines', {
          'journal_entry_id': entryId,
          'line_no': 2,
          'account_id': sales,
          'debit_paisa': 0,
          'credit_paisa': 552500,
        });
      });

      expect(await db.findLedgerImbalances(), isEmpty);
    });

    test('refuses to commit an entry whose lines do not balance', () async {
      // One paisa. Not "within tolerance" — the previous build's ledger check
      // had a hardcoded `> 0.01` threshold that existed only to hide the drift
      // its REAL columns accumulated.
      final cash = await account('cash_in_hand');
      final sales = await account('sales');

      await expectLater(
        runner.run(actor, (tx) async {
          final entryId = await tx.insert('journal_entries', {
            'entry_no': 'JV-00002',
            'entry_date_utc': actor.epochMillis,
            'entry_date_local': actor.businessDate.value,
            'fiscal_year': 2627,
            'source_type': 'sale',
            'total_debit_paisa': 552500,
            'total_credit_paisa': 552500,
          });
          await tx.insert('journal_lines', {
            'journal_entry_id': entryId,
            'line_no': 1,
            'account_id': cash,
            'debit_paisa': 552500,
            'credit_paisa': 0,
          });
          await tx.insert('journal_lines', {
            'journal_entry_id': entryId,
            'line_no': 2,
            'account_id': sales,
            'debit_paisa': 0,
            'credit_paisa': 552499,
          });
        }),
        throwsA(
          isA<BooksDoNotBalance>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('JV-00002'), contains('Nothing was saved')),
          ),
        ),
      );

      final entries =
          await db.customSelect('SELECT * FROM journal_entries').get();
      expect(entries, isEmpty);
    });

    test('refuses an entry whose declared total contradicts its lines',
        () async {
      final cash = await account('cash_in_hand');
      final sales = await account('sales');

      await expectLater(
        runner.run(actor, (tx) async {
          final entryId = await tx.insert('journal_entries', {
            'entry_no': 'JV-00003',
            'entry_date_utc': actor.epochMillis,
            'entry_date_local': actor.businessDate.value,
            'fiscal_year': 2627,
            'source_type': 'sale',
            'total_debit_paisa': 999900,
            'total_credit_paisa': 999900,
          });
          await tx.insert('journal_lines', {
            'journal_entry_id': entryId,
            'line_no': 1,
            'account_id': cash,
            'debit_paisa': 552500,
            'credit_paisa': 0,
          });
          await tx.insert('journal_lines', {
            'journal_entry_id': entryId,
            'line_no': 2,
            'account_id': sales,
            'debit_paisa': 0,
            'credit_paisa': 552500,
          });
        }),
        throwsA(isA<BooksDoNotBalance>()),
      );
    });
  });

  group('HLC recovery', () {
    test('resumes past the highest timestamp this device ever wrote', () async {
      await runner.run(
        actor,
        (tx) => tx.insert('parties', {
          'name': 'A',
          'name_search': 'a',
          'party_type': 'customer',
        }),
      );

      final highest = await db
          .customSelect(
            'SELECT MAX(hlc) AS h FROM change_log WHERE origin_device_id = ?',
            variables: [Variable<String>(firm.deviceId)],
          )
          .getSingle();
      final last = Hlc(highest.read<String>('h'));

      // Simulate a cold start with a handset whose clock has slipped back.
      final coldClock = FixedClock(DateTime.utc(2026, 8, 23, 8));
      final resumed = await resumeHlcClock(
        db,
        deviceId: firm.deviceId,
        clock: coldClock,
      );
      expect(resumed.next() > last, isTrue);
    });
  });
}

Future<List<int>> _seqs(AppDatabase db) async {
  final rows =
      await db.customSelect('SELECT seq FROM change_log ORDER BY seq').get();
  return [for (final r in rows) r.read<int>('seq')];
}

Future<Map<String, int>> _rowCounts(AppDatabase db) async {
  const tables = [
    'documents',
    'document_lines',
    'document_line_taxes',
    'doc_links',
    'payments',
    'payment_allocations',
    'stock_ledger',
    'journal_entries',
    'journal_lines',
  ];
  final counts = <String, int>{};
  for (final t in tables) {
    final row =
        await db.customSelect('SELECT COUNT(*) AS n FROM $t').getSingle();
    counts[t] = row.read<int>('n');
  }
  return counts;
}

class _InjectedFault implements Exception {
  const _InjectedFault();
  @override
  String toString() => 'injected fault';
}
