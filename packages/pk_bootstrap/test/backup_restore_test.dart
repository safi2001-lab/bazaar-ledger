import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// Making a backup of real books on disk, and bringing them back on a phone
/// that has never seen them.
///
/// Files, not memory: a restore is a file being swapped under a database, and
/// an in-memory test could not see the WAL left behind, the plain copy that
/// outlived its backup, or the old books deleted instead of kept.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const passphrase = 'chishti-1987';
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pkbak_test');
    // drift_flutter asks the platform for a temp directory before it opens a
    // file. Answered with this test's own, and nothing else is stubbed.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => root.path,
        );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  String phone(String name) {
    final dir = Directory(p.join(root.path, name))..createSync();
    return p.join(dir.path, 'bazaar_ledger.sqlite');
  }

  Future<AppServices> openShop(String path, {String? shopName}) async {
    final services = await AppServices.open(databasePath: path);
    if (shopName != null) {
      await services.setUpShop(
        shopName: shopName,
        ownerName: 'Malik Sahib',
        deviceLabel: 'Counter 1',
        city: 'Lahore',
      );
    }
    return services;
  }

  Future<File> backUp(AppServices services) async {
    final made = await services.backups.create(
      services.actorNow(),
      passphrase: passphrase,
      into: Directory(p.join(root.path, 'out')),
    );
    return made.file;
  }

  Directory scratch() => Directory(p.join(root.path, 'scratch'));

  Matcher refusedFor(BackupProblem problem) => throwsA(
    isA<BackupRefused>().having((e) => e.problem, 'problem', problem),
  );

  test('the books come back on a phone that has never seen them', () async {
    final oldPhone = phone('old');
    final shop = await openShop(oldPhone, shopName: 'Chishti Kiryana Store');
    await shop.catalogue.addParty(
      shop.actorNow(),
      const PartyDraft(
        name: 'Rashid Traders',
        openingBalance: Money.rupees(4500),
      ),
    );
    final file = await backUp(shop);
    await shop.close();

    final candidate = await Restore.inspect(
      await file.readAsBytes(),
      passphrase: passphrase,
      scratch: scratch(),
    );
    expect(candidate.shopName, 'Chishti Kiryana Store');
    expect(candidate.parties, 1);

    final newPhone = phone('new');
    await Restore.stage(candidate, databasePath: newPhone);
    final restored = await openShop(newPhone);
    addTearDown(restored.close);

    expect(restored.isSetUp, isTrue);
    final firm = (await restored.queries.currentFirm())!;
    expect(firm.name, 'Chishti Kiryana Store');
    final rashid = await restored.queries.searchParties(
      firm.id,
      query: 'rashid',
    );
    expect(rashid.single.balance, const Money.rupees(4500));
  });

  test(
    'a restore is written into the audit trail of the books it restored',
    () async {
      final shop = await openShop(
        phone('old'),
        shopName: 'Chishti Kiryana Store',
      );
      final file = await backUp(shop);
      await shop.close();

      final target = phone('new');
      await Restore.stage(
        await Restore.inspect(
          await file.readAsBytes(),
          passphrase: passphrase,
          scratch: scratch(),
        ),
        databasePath: target,
      );
      final restored = await openShop(target);
      addTearDown(restored.close);

      final rows = await restored.database
          .customSelect(
            'SELECT action_code FROM audit_log '
            "WHERE action_code IN ('BACKUP_MADE', 'BACKUP_RESTORED') "
            'ORDER BY at_utc',
          )
          .get();
      expect(rows.map((r) => r.read<String>('action_code')), [
        'BACKUP_RESTORED',
      ]);
    },
  );

  test('the books being replaced are kept, not deleted', () async {
    final source = await openShop(
      phone('old'),
      shopName: 'Chishti Kiryana Store',
    );
    final file = await backUp(source);
    await source.close();

    // This phone already has a shop of its own, which the restore replaces.
    final target = phone('new');
    final other = await openShop(target, shopName: 'Madina General Store');
    await other.close();

    await Restore.stage(
      await Restore.inspect(
        await file.readAsBytes(),
        passphrase: passphrase,
        scratch: scratch(),
      ),
      databasePath: target,
    );
    final restored = await openShop(target);
    addTearDown(restored.close);

    expect(
      (await restored.queries.currentFirm())!.name,
      'Chishti Kiryana Store',
    );

    final kept = raw.sqlite3.open('$target${Restore.keptSuffix}');
    addTearDown(kept.dispose);
    expect(
      kept.select('SELECT name FROM firms').first['name'],
      'Madina General Store',
    );
  });

  test('the plain copy never outlives the backup', () async {
    final shop = await openShop(
      phone('old'),
      shopName: 'Chishti Kiryana Store',
    );
    addTearDown(shop.close);

    final file = await backUp(shop);

    final left = Directory(p.join(root.path, 'out')).listSync();
    expect(left.map((e) => p.basename(e.path)), [p.basename(file.path)]);
    expect(p.basename(file.path), isNot(contains('Chishti')));
  });

  test('the shop knows when it last made a backup', () async {
    final shop = await openShop(
      phone('old'),
      shopName: 'Chishti Kiryana Store',
    );
    addTearDown(shop.close);

    expect(await shop.lastBackupAt(), isNull);
    await backUp(shop);
    expect(await shop.lastBackupAt(), isNotNull);
  });

  test('a wrong passphrase stages nothing', () async {
    final shop = await openShop(
      phone('old'),
      shopName: 'Chishti Kiryana Store',
    );
    final file = await backUp(shop);
    await shop.close();

    expect(
      Restore.inspect(
        await file.readAsBytes(),
        passphrase: 'chishti-1988',
        scratch: scratch(),
      ),
      refusedFor(BackupProblem.wrongPassphraseOrDamaged),
    );
    expect(Restore.isPending(phone('new')), isFalse);
  });

  test(
    'books from a newer build are refused before anything is replaced',
    () async {
      final shop = await openShop(
        phone('old'),
        shopName: 'Chishti Kiryana Store',
      );
      final file = await backUp(shop);
      await shop.close();

      // The same books, as a later schema would have left them.
      final opened = await const BackupArchive().open(
        await file.readAsBytes(),
        passphrase: passphrase,
      );
      final future = File(p.join(root.path, 'future.db'))
        ..writeAsBytesSync(opened.database);
      raw.sqlite3.open(future.path)
        ..execute('PRAGMA user_version = 99')
        ..dispose();

      expect(
        Restore.inspect(
          await _seal(future.readAsBytesSync(), passphrase),
          passphrase: passphrase,
          scratch: scratch(),
        ),
        refusedFor(BackupProblem.newerFormat),
      );
    },
  );

  test('a sealed file that is not a database is refused', () async {
    expect(
      Restore.inspect(
        await _seal(
          Uint8List.fromList(List.generate(8192, (i) => i % 256)),
          passphrase,
        ),
        passphrase: passphrase,
        scratch: scratch(),
      ),
      refusedFor(BackupProblem.damaged),
    );
  });

  test('a database that is not a shop is refused', () async {
    final stranger = File(p.join(root.path, 'stranger.db'));
    raw.sqlite3.open(stranger.path)
      ..execute('CREATE TABLE notes (body TEXT)')
      ..dispose();

    expect(
      Restore.inspect(
        await _seal(stranger.readAsBytesSync(), passphrase),
        passphrase: passphrase,
        scratch: scratch(),
      ),
      refusedFor(BackupProblem.notABackup),
    );
  });
}

Future<Uint8List> _seal(Uint8List database, String passphrase) =>
    const BackupArchive().seal(
      database: database,
      passphrase: passphrase,
      schemaVersion: 2,
      appVersion: 'test',
      createdAtUtc: DateTime.utc(2026, 9, 26),
    );
