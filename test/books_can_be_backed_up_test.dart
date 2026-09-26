import 'dart:io';
import 'dart:typed_data';

import 'package:bazaar_ledger/features/backup/backup_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/harness.dart';

/// Making a backup and bringing one back, from the app.
///
/// The startup-failure screen has carried a "restore from backup" button
/// since M0 that said "arrives in M5". These drive the real screens: the
/// backup goes to the share sheet sealed, and a backup picked on a new phone
/// is opened, shown, and staged for the swap.
void main() {
  final shareSheet = _FakeShareSheet();
  SharePlatform.instance = shareSheet;

  const passphrase = 'chishti-1987';

  setUp(shareSheet.paths.clear);

  testWidgets('a backup can be reached from Settings', (tester) async {
    await Harness.startWithShop(tester);
    await _openBackup(tester);

    expect(find.text('Abhi tak koi backup nahi banaya'), findsOneWidget);
  });

  testWidgets('a short password is refused in words', (tester) async {
    final app = await Harness.startWithShop(tester);
    await _openBackup(tester);

    await typeInto(tester, 'Backup ka password', '1234');
    await typeInto(tester, 'Password dobara likhein', '1234');
    await tapButton(tester, 'Backup banayein');

    expect(find.text('Password kam az kam 8 huroof ka ho'), findsOneWidget);
    expect(shareSheet.paths, isEmpty);
    expect(await app.services.lastBackupAt(), isNull);
  });

  testWidgets('two passwords that differ are refused in words', (tester) async {
    await Harness.startWithShop(tester);
    await _openBackup(tester);

    await typeInto(tester, 'Backup ka password', passphrase);
    await typeInto(tester, 'Password dobara likhein', 'chishti-1978');
    await tapButton(tester, 'Backup banayein');

    expect(find.text('Dono password ek jaise nahi'), findsOneWidget);
    expect(shareSheet.paths, isEmpty);
  });

  testWidgets('a backup reaches the share sheet sealed, and opens again', (
    tester,
  ) async {
    final app = await Harness.startWithShop(tester);
    await app.seedParty(name: 'Rashid Traders', owedRupees: 4500);
    await _openBackup(tester);

    await typeInto(tester, 'Backup ka password', passphrase);
    await typeInto(tester, 'Password dobara likhein', passphrase);
    await tester.tap(find.text('Backup banayein'));
    await settleReal(tester, until: find.textContaining('Aakhri backup'));

    expect(shareSheet.paths, hasLength(1));
    final shared = File(shareSheet.paths.single);
    expect(shared.path, endsWith('.pkbak'));

    final bytes = (await tester.runAsync(shared.readAsBytes))!;
    expect(
      String.fromCharCodes(bytes.take(7)),
      'PKBAK01',
      reason: 'what reached the share sheet is not a sealed backup',
    );
    final candidate = (await tester.runAsync(
      () => Restore.inspect(
        bytes,
        passphrase: passphrase,
        scratch: Directory('${Directory.systemTemp.path}/bl_backup_test'),
      ),
    ))!;
    expect(candidate.shopName, 'Chishti Kiryana Store');
    expect(candidate.parties, 1);
  });

  testWidgets('a new phone brings the books back from the setup screen', (
    tester,
  ) async {
    // The books of a phone that is gone, as a file.
    final backup = (await tester.runAsync(_backupOfAnotherShop))!;

    var restarted = 0;
    await Harness.start(
      tester,
      overrides: [
        pickBackupFileProvider.overrideWithValue(() async => backup),
        restartAppProvider.overrideWithValue(() async => restarted++),
      ],
    );

    await tapText(tester, 'Pehle se hisaab hai? Backup se wapas layein');
    await tapButton(tester, 'Backup file chunein');
    await settleReal(tester, until: find.textContaining('ko bana tha'));

    await typeInto(tester, 'Backup ka password', passphrase);
    await tester.tap(find.text('Backup kholein'));
    await settleReal(tester, until: find.text('Madina General Store'));

    expect(find.text('Madina General Store'), findsOneWidget);
    // Not tapButton: the button stays busy on purpose, because in the app
    // the next thing that happens is the whole tree being rebuilt.
    final confirm = find.text('Haan, wapas layein');
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await settleReal(tester, done: () => restarted > 0);

    expect(restarted, 1);
    final booksPath = (await tester.runAsync(AppServices.defaultDatabasePath))!;
    addTearDown(() => File('$booksPath${Restore.pendingSuffix}').deleteSync());
    expect(Restore.isPending(booksPath), isTrue);
  });

  testWidgets('the wrong password is refused and nothing is staged', (
    tester,
  ) async {
    final backup = (await tester.runAsync(_backupOfAnotherShop))!;
    var restarted = 0;
    await Harness.start(
      tester,
      overrides: [
        pickBackupFileProvider.overrideWithValue(() async => backup),
        restartAppProvider.overrideWithValue(() async => restarted++),
      ],
    );

    await tapText(tester, 'Pehle se hisaab hai? Backup se wapas layein');
    await tapButton(tester, 'Backup file chunein');
    await settleReal(tester, until: find.textContaining('ko bana tha'));
    await typeInto(tester, 'Backup ka password', 'chishti-1988');
    await tester.tap(find.text('Backup kholein'));
    await settleReal(tester, until: find.textContaining('passphrase'));

    expect(find.textContaining('does not open this backup'), findsOneWidget);
    expect(restarted, 0);
    final booksPath = (await tester.runAsync(AppServices.defaultDatabasePath))!;
    expect(Restore.isPending(booksPath), isFalse);
  });
}

Future<void> _openBackup(WidgetTester tester) async {
  await openSettings(tester);
  // Below the fold at the default test size, and a lazy list builds nothing
  // it has not scrolled to.
  await tester.scrollUntilVisible(find.text('Backup'), 200);
  await tapText(tester, 'Backup');
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

/// Stands in for the system share sheet and records what it was handed.
final class _FakeShareSheet extends SharePlatform {
  final paths = <String>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    paths.addAll((params.files ?? const []).map((f) => f.path));
    return const ShareResult('ok', ShareResultStatus.success);
  }
}
