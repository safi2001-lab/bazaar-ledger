import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/paper.dart';

/// A parchi photographed onto an entry comes back with the books on a phone
/// that has never seen them (M60).
///
/// The reason pictures are kept inside the books rather than beside them:
/// a backup is one file, and a restore cannot come back with the entries
/// and without the paper behind them. On disk, as M5's own restore test
/// is, because a restore is a file swapped under a database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const passphrase = 'chishti-1987';
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('pkbak_photos');
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

  group('photos travel with backup', () {
    test('the bijli bill on an expense comes back with a restore, and so '
        'does one waiting in the bin', () async {
      final shop = await AppServices.open(databasePath: phone('old'));
      await shop.setUpShop(
        shopName: 'Chishti Kiryana Store',
        ownerName: 'Malik Sahib',
        deviceLabel: 'Counter 1',
        city: 'Lahore',
      );
      final firmId = (await shop.queries.currentFirm())!.id;
      final cash = (await shop.queries.paymentAccounts(
        firmId,
      )).firstWhere((a) => a.modeLabel == 'cash').id;
      final expense = await shop.recordExpense(
        shop.actorNow(),
        ExpenseDraft(
          accountSystemKey: 'utilities',
          amount: const Money.rupees(4000),
          note: 'Bijli ka bill, September',
          paymentAccountId: cash,
        ),
      );
      Future<String> photograph(int shade) => shop.photos.add(
        ownerTable: 'documents',
        ownerId: expense.documentId,
        kind: EntryPhotoKind.receipt,
        source: paper(shade),
        fileName: 'bijli-$shade.bmp',
      );
      await photograph(1);
      await shop.photos.remove(await photograph(2));
      final kept = (await shop.photos.of(
        'documents',
        expense.documentId,
      )).single.bytes;

      final made = await shop.backups.create(
        shop.actorNow(),
        passphrase: passphrase,
        into: Directory(p.join(root.path, 'out')),
      );
      await shop.close();

      final candidate = await Restore.inspect(
        await made.file.readAsBytes(),
        passphrase: passphrase,
        scratch: Directory(p.join(root.path, 'scratch')),
      );
      final newPhone = phone('new');
      await Restore.stage(candidate, databasePath: newPhone);
      final restored = await AppServices.open(databasePath: newPhone);
      addTearDown(restored.close);

      final photos = await restored.photos.of('documents', expense.documentId);
      expect(photos, hasLength(1));
      expect(photos.single.bytes, kept, reason: 'byte for byte');
      expect(photos.single.addedBy, 'Malik Sahib');
      final binned = await restored.photos.removed();
      expect(binned, hasLength(1), reason: 'the bin came back too');
      await restored.photos.restore(binned.single);
      expect(
        await restored.photos.of('documents', expense.documentId),
        hasLength(2),
      );
    });
  });
}
