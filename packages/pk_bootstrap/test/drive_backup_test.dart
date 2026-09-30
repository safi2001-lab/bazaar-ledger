import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pk_bootstrap/pk_bootstrap.dart';

/// Google Drive as a stand-in: keeps what it is given, in memory.
final class _FakeDrive implements CloudBackupStore {
  final files = <String, (CloudBackupFile, Uint8List)>{};
  Object? failWith;
  var _next = 0;
  DateTime Function() now = DateTime.now;

  @override
  Future<CloudBackupFile> upload(String name, Uint8List bytes) async {
    if (failWith case final e?) throw e;
    final f = CloudBackupFile(
      id: 'd${_next++}',
      name: name,
      createdUtc: now().toUtc(),
      bytes: bytes.length,
    );
    files[f.id] = (f, bytes);
    return f;
  }

  @override
  Future<List<CloudBackupFile>> list() async =>
      [for (final e in files.values) e.$1]
        ..sort((a, b) => b.createdUtc.compareTo(a.createdUtc));

  @override
  Future<Uint8List> download(String id) async => files[id]!.$2;

  @override
  Future<void> delete(String id) async => files.remove(id);
}

void main() {
  const passphrase = 'chishti-kiryana-1990';
  late Directory root;
  late FixedClock clock;
  late AppServices shop;
  late _FakeDrive drive;

  Directory scratch() => Directory(p.join(root.path, 'scratch'));

  setUp(() async {
    root = Directory.systemTemp.createTempSync('drive_test');
    clock = FixedClock(DateTime.utc(2026, 9, 1, 4));
    shop = await openInMemoryServices(clock: clock);
    await shop.setUpShop(
      shopName: 'Chishti Kiryana Store',
      ownerName: 'Malik Sahib',
      deviceLabel: 'Counter 1',
    );
    drive = _FakeDrive()..now = clock.nowUtc;
  });

  tearDown(() async {
    await shop.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('drive backup', () {
    test('a backup is due after a day, and not before', () {
      final t = DateTime.utc(2026, 9, 1, 4);
      expect(DriveBackupServices.isDue(null, t), isTrue);
      expect(
        DriveBackupServices.isDue(t, t.add(const Duration(hours: 23))),
        isFalse,
      );
      expect(
        DriveBackupServices.isDue(t, t.add(const Duration(hours: 24))),
        isTrue,
      );
    });

    test('the newest seven are kept', () {
      final files = [
        for (var d = 1; d <= 10; d++)
          CloudBackupFile(
            id: 'f$d',
            name: 'day $d',
            createdUtc: DateTime.utc(2026, 9, d),
            bytes: 1,
          ),
      ]..shuffle();
      expect(
        [for (final f in DriveBackupServices.toPrune(files)) f.id],
        ['f3', 'f2', 'f1'],
      );
      expect(DriveBackupServices.toPrune(files.sublist(0, 7)), isEmpty);
    });

    test('off until turned on, and a short passphrase is refused', () async {
      expect(
        await shop.drive.runIfDue(drive, scratch: scratch()),
        DriveBackupRun.off,
      );
      await expectLater(
        shop.drive.turnOn('short'),
        throwsA(isA<BackupRefused>()),
      );
      expect(drive.files, isEmpty);
    });

    test('once a day it goes to Drive, the newest seven stay, and one comes '
        'back', () async {
      await shop.drive.turnOn(passphrase);

      expect(
        await shop.drive.runIfDue(drive, scratch: scratch()),
        DriveBackupRun.uploaded,
      );
      // Opened again the same morning: nothing to do.
      clock.advance(const Duration(hours: 3));
      expect(
        await shop.drive.runIfDue(drive, scratch: scratch()),
        DriveBackupRun.notDue,
      );
      expect(drive.files, hasLength(1));

      for (var day = 0; day < 9; day++) {
        clock.advance(const Duration(hours: 24));
        expect(
          await shop.drive.runIfDue(drive, scratch: scratch()),
          DriveBackupRun.uploaded,
        );
      }
      expect(drive.files, hasLength(DriveBackupServices.keep));
      final settings = await shop.drive.settings();
      expect(settings.lastUtc, clock.nowUtc());
      expect(settings.lastError, isNull);
      // Nothing sealed is left behind on the phone.
      expect(scratch().listSync(), isEmpty);

      final newest = (await drive.list()).first;
      final candidate = await Restore.inspect(
        await drive.download(newest.id),
        passphrase: passphrase,
        scratch: Directory(p.join(root.path, 'restore')),
      );
      expect(candidate.shopName, 'Chishti Kiryana Store');
    });

    test('a failure is kept in words and tried again next time', () async {
      await shop.drive.turnOn(passphrase);
      drive.failWith = const CloudBackupFailed(
        'No connection to Google Drive.',
      );
      expect(
        await shop.drive.runIfDue(drive, scratch: scratch()),
        DriveBackupRun.failed,
      );
      final failed = await shop.drive.settings();
      expect(failed.lastError, 'No connection to Google Drive.');
      expect(failed.lastUtc, isNull);

      drive.failWith = null;
      expect(
        await shop.drive.runIfDue(drive, scratch: scratch()),
        DriveBackupRun.uploaded,
      );
      expect((await shop.drive.settings()).lastError, isNull);
    });

    test('turned off, nothing is sent', () async {
      await shop.drive.turnOn(passphrase);
      await shop.drive.turnOff();
      expect(
        await shop.drive.runIfDue(drive, scratch: scratch(), force: true),
        DriveBackupRun.off,
      );
      expect(drive.files, isEmpty);
    });
  });
}
