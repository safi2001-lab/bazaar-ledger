import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// The record of what has already been printed.
///
/// A thermal printer has no memory and no job identity. Asked twice, it prints
/// twice, and the customer walks away with two receipts for one sale while the
/// shop's own books say one. So the only thing standing between a flaky link
/// and a duplicated bill is a record of whether the job already went out.
///
/// That record used to be two plain maps on a PrintQueue instance, which is
/// fine right up until Android reclaims the app — and this is a product
/// engineered around exactly that, persisting the cart to disk on every
/// mutation because Android Go ROMs kill aggressively. A printed-job record
/// that evaporates on the same kill means a shopkeeper who reopens and taps
/// Print gets a second receipt.
///
/// The subtle half is `sending`. Every reviewer's instinct is that an
/// unfinished job did not happen. On a Transsion ROM the Boost button kills
/// the process mid-write to a printer that has ALREADY taken 400 of 900 bytes.
/// Paper has moved. `sending` therefore means "nobody knows", and nobody-knows
/// is a question for a person, never an automatic retry.
void main() {
  late AppDatabase db;
  late FixedClock clock;
  late UlidGenerator ids;
  late TxRunner runner;
  late FirstRunResult firm;
  late ActorContext actor;
  late DriftPrinterSettings printing;

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
    actor = firm.actorAt(clock.nowUtc());
    final hlc = await resumeHlcClock(db, deviceId: firm.deviceId, clock: clock);
    runner = TxRunner(database: db, ids: ids, hlc: hlc);
    printing = DriftPrinterSettings(db, () => runner);
  });

  tearDown(() async => db.close());

  Future<void> begin(String jobKey, {int bytes = 900}) => printing.begin(
    actor,
    jobKey: jobKey,
    transportKind: 'tcp',
    targetAddress: '192.168.1.50:9100',
    columnsUsed: 48,
    copyIndex: 1,
    byteCount: bytes,
    payloadSha256: 'abc123',
  );

  group('the printer this counter uses', () {
    test('is remembered across a restart', () async {
      await printing.save(
        actor,
        const PrinterSettings(
          transportKind: 'tcp',
          address: '192.168.1.50:9100',
          name: 'Counter printer',
          columns: 42,
        ),
      );

      final loaded = await printing.forDevice(firm.firmId, firm.deviceId);
      expect(loaded, isNotNull);
      expect(loaded!.transportKind, 'tcp');
      expect(loaded.address, '192.168.1.50:9100');
      expect(
        loaded.columns,
        42,
        reason:
            'the column width is the setting shopkeepers get wrong most '
            'often, and losing it makes every total wrap',
      );
    });

    test('a second save replaces the first rather than colliding', () async {
      // idx_settings_key is UNIQUE per (firm, key). A blind insert on the
      // second save would throw, and a shopkeeper changing printers would be
      // told the shop is broken.
      await printing.save(
        actor,
        const PrinterSettings(
          transportKind: 'tcp',
          address: '192.168.1.50:9100',
          name: 'Old printer',
        ),
      );
      await printing.save(
        actor,
        const PrinterSettings(
          transportKind: 'bluetooth',
          address: 'AA:BB:CC:DD:EE:FF',
          name: 'New portable',
          columns: 32,
        ),
      );

      final loaded = await printing.forDevice(firm.firmId, firm.deviceId);
      expect(loaded!.name, 'New portable');
      expect(loaded.columns, 32);
    });

    test('another device on the same firm keeps its own printer', () async {
      // The counter has the USB printer, the back office has the LAN one. An
      // unnamespaced key would let them overwrite each other forever once M13
      // starts carrying the settings table between them.
      await printing.save(
        actor,
        const PrinterSettings(
          transportKind: 'tcp',
          address: '192.168.1.50:9100',
          name: 'Counter printer',
        ),
      );

      final other = await printing.forDevice(firm.firmId, 'SOME-OTHER-DEVICE');
      expect(other, isNull);
    });

    test('nothing chosen yet is not an error', () async {
      expect(await printing.forDevice(firm.firmId, firm.deviceId), isNull);
    });

    test(
      'a corrupted settings row reads as no printer, not as a crash',
      () async {
        await runner.run(actor, (tx) async {
          await tx.insert('settings', {
            'setting_key': 'printer.${firm.deviceId}',
            'setting_value': 'not json at all',
            'value_type': 'json',
          });
        });

        expect(
          await printing.forDevice(firm.firmId, firm.deviceId),
          isNull,
          reason:
              'a shopkeeper should be offered the setup screen, not an '
              'exception, because choosing a printer is the action that fixes it',
        );
      },
    );

    test(
      'the choice is audited like every other decision about the shop',
      () async {
        await printing.save(
          actor,
          const PrinterSettings(
            transportKind: 'usb',
            address: 'usb:1234',
            name: 'Counter printer',
          ),
        );

        final audit = await db
            .customSelect(
              'SELECT action_code, summary FROM audit_log '
              'WHERE action_code = ?',
              variables: [Variable<String>('PRINTER_CONFIGURED')],
            )
            .getSingle();
        expect(audit.read<String>('summary'), contains('Counter printer'));
      },
    );
  });

  group('what has already been printed', () {
    test('a job that finished is remembered as printed', () async {
      await begin('INV-0001#1#48#1');
      await printing.finish(
        actor,
        jobKey: 'INV-0001#1#48#1',
        status: PrintJobStatus.printed,
        bytesWritten: 900,
      );

      final record = await printing.byKey(firm.firmId, 'INV-0001#1#48#1');
      expect(record!.status, PrintJobStatus.printed);
      expect(record.mayRetryAutomatically, isFalse);
    });

    test(
      'a job interrupted by a process kill is UNKNOWN, not un-printed',
      () async {
        // begin() commits and nothing else happens: the app died. This is the
        // whole point of the table.
        await begin('INV-0002#1#48#1');

        final record = await printing.byKey(firm.firmId, 'INV-0002#1#48#1');
        expect(record, isNotNull, reason: 'the attempt left no trace at all');
        expect(record!.status, PrintJobStatus.sending);
        expect(
          record.mayRetryAutomatically,
          isFalse,
          reason:
              'the app is about to hand the customer a second half-receipt. '
              'Paper may already have moved and only a person can tell.',
        );
      },
    );

    test('a job that never started is safe to try again', () async {
      await begin('INV-0003#1#48#1');
      await printing.finish(
        actor,
        jobKey: 'INV-0003#1#48#1',
        status: PrintJobStatus.failed,
        bytesWritten: 0,
        failureReason: 'no route to host',
      );

      final record = await printing.byKey(firm.firmId, 'INV-0003#1#48#1');
      expect(record!.mayRetryAutomatically, isTrue);
      expect(record.failureReason, 'no route to host');
    });

    test('a job that failed part way is never safe to try again', () async {
      await begin('INV-0004#1#48#1');
      await printing.finish(
        actor,
        jobKey: 'INV-0004#1#48#1',
        status: PrintJobStatus.partial,
        bytesWritten: 512,
        failureReason: 'the link went away',
      );

      final record = await printing.byKey(firm.firmId, 'INV-0004#1#48#1');
      expect(record!.mayRetryAutomatically, isFalse);
      expect(record.bytesWritten, 512);
    });

    test('the same job key cannot be begun twice', () async {
      // The uniqueness the whole design rests on. Without it a double-tapped
      // Print button writes two rows, neither finds the other, and both print.
      await begin('INV-0005#1#48#1');
      await expectLater(begin('INV-0005#1#48#1'), throwsA(anything));
    });

    test('a deliberate reprint is a different key, and is allowed', () async {
      // The shopkeeper looked at the paper and decided. That is not the queue
      // retrying; it is a person choosing, and the copy index says so.
      await begin('INV-0006#1#48#1');
      await printing.finish(
        actor,
        jobKey: 'INV-0006#1#48#1',
        status: PrintJobStatus.printed,
        bytesWritten: 900,
      );

      await printing.begin(
        actor,
        jobKey: 'INV-0006#1#48#2',
        transportKind: 'tcp',
        targetAddress: '192.168.1.50:9100',
        columnsUsed: 48,
        copyIndex: 2,
        byteCount: 900,
        payloadSha256: 'abc123',
        documentId: null,
      );

      final second = await printing.byKey(firm.firmId, 'INV-0006#1#48#2');
      expect(second!.copyIndex, 2);
    });

    test('finishing a job nobody started is refused, and says why', () async {
      await expectLater(
        printing.finish(
          actor,
          jobKey: 'NEVER-BEGUN',
          status: PrintJobStatus.printed,
          bytesWritten: 900,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('before a byte is sent'),
          ),
        ),
      );
    });

    test(
      'a job cannot finish as `sending`, because that means nobody knows',
      () async {
        await begin('INV-0007#1#48#1');
        await expectLater(
          printing.finish(
            actor,
            jobKey: 'INV-0007#1#48#1',
            status: PrintJobStatus.sending,
            bytesWritten: 100,
          ),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test('the books still balance after all of it', () async {
      // print_jobs writes no journal entry, and this asserts that staying
      // true: a table that quietly unbalanced the ledger would be found six
      // months later by a shopkeeper, not here.
      await begin('INV-0008#1#48#1');
      await printing.finish(
        actor,
        jobKey: 'INV-0008#1#48#1',
        status: PrintJobStatus.printed,
        bytesWritten: 900,
      );

      final health = await db.checkHealth();
      expect(health.isHealthy, isTrue, reason: health.toString());
    });
  });
}
