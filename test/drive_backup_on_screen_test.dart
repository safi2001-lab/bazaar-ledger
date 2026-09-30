import 'dart:io';
import 'dart:typed_data';

import 'package:bazaar_ledger/features/backup/backup_providers.dart';
import 'package:bazaar_ledger/features/backup/drive_access.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';

/// Google Drive as a stand-in, holding whatever it is given.
final class _FakeDrive implements CloudBackupStore {
  final files = <String, (CloudBackupFile, Uint8List)>{};
  var _next = 0;

  @override
  Future<CloudBackupFile> upload(String name, Uint8List bytes) async {
    final f = CloudBackupFile(
      id: 'd${_next++}',
      name: name,
      createdUtc: DateTime.utc(2026, 9, 1).add(Duration(days: _next)),
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

/// The daily Drive backup, from the app (M20).
void main() {
  const passphrase = 'chishti-1987';

  testWidgets('turning Drive backup on sends the first one straight away', (
    tester,
  ) async {
    final drive = _FakeDrive();
    var connected = 0;
    final app = await Harness.startWithShop(
      tester,
      overrides: [
        driveStoreProvider.overrideWithValue(drive),
        connectDriveProvider.overrideWithValue(() async => connected++),
      ],
    );
    await openSettings(tester);
    await tester.scrollUntilVisible(find.text('Backup'), 200);
    await tapText(tester, 'Backup');

    await typeInto(tester, 'Backup ka password', passphrase);
    await typeInto(tester, 'Password dobara likhein', passphrase);
    // Not tapText: the screen stays busy while the backup is sealed.
    final turnOn = find.text('Drive backup chalu karein');
    await tester.ensureVisible(turnOn);
    await tester.pumpAndSettle();
    await tester.tap(turnOn);
    await settleReal(tester, until: find.textContaining('Drive par aakhri'));

    expect(connected, 1);
    expect(drive.files, hasLength(1));
    final settings = (await tester.runAsync(app.services.drive.settings))!;
    expect(settings.enabled, isTrue);
    expect(find.text('Drive backup band karein'), findsOneWidget);
  });

  testWidgets('a backup that is due goes when the app comes back to the '
      'front', (tester) async {
    final drive = _FakeDrive();
    final app = await Harness.startWithShop(
      tester,
      overrides: [driveStoreProvider.overrideWithValue(drive)],
    );
    // Turned on on another day; nothing has reached Drive since.
    await tester.runAsync(() => app.services.drive.turnOn(passphrase));
    expect(drive.files, isEmpty);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settleReal(tester, done: () => drive.files.isNotEmpty);

    expect(drive.files, hasLength(1));
    final sealed = drive.files.values.single.$2;
    final candidate = (await tester.runAsync(
      () => Restore.inspect(
        sealed,
        passphrase: passphrase,
        scratch: Directory('${Directory.systemTemp.path}/bl_drive_test'),
      ),
    ))!;
    expect(candidate.shopName, 'Chishti Kiryana Store');
  });

  testWidgets('a new phone brings the books back from Drive', (tester) async {
    final drive = _FakeDrive();
    final backup = (await tester.runAsync(_backupOfAnotherShop))!;
    await tester.runAsync(() => drive.upload('old.pkbak', backup));

    var restarted = 0;
    await Harness.start(
      tester,
      overrides: [
        driveStoreProvider.overrideWithValue(drive),
        connectDriveProvider.overrideWithValue(() async {}),
        restartAppProvider.overrideWithValue(() async => restarted++),
      ],
    );

    await tapText(tester, 'Google Drive se wapas layein');
    // Not tapButton: the button spins until a backup is chosen.
    await tester.tap(find.text('Backup file chunein'));
    await settleReal(tester, until: find.text('Kaunsi backup wapas layein?'));
    await tester.tap(find.textContaining('KB'));
    await settleReal(tester, until: find.textContaining('ko bana tha'));

    await typeInto(tester, 'Backup ka password', passphrase);
    await tester.tap(find.text('Backup kholein'));
    await settleReal(tester, until: find.text('Madina General Store'));

    final confirm = find.text('Haan, wapas layein');
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await settleReal(tester, done: () => restarted > 0);

    final booksPath = (await tester.runAsync(AppServices.defaultDatabasePath))!;
    addTearDown(() => File('$booksPath${Restore.pendingSuffix}').deleteSync());
    expect(Restore.isPending(booksPath), isTrue);
  });
}

/// A sealed backup of a shop that is not the one on screen.
Future<Uint8List> _backupOfAnotherShop() async {
  final other = await openInMemoryServices();
  try {
    await other.setUpShop(
      shopName: 'Madina General Store',
      ownerName: 'Haji Sahib',
      deviceLabel: 'Counter 1',
    );
    final made = await other.backups.create(
      other.actorNow(),
      passphrase: 'chishti-1987',
      into: Directory.systemTemp.createTempSync('other_shop'),
    );
    return made.file.readAsBytes();
  } finally {
    await other.close();
  }
}
