import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// A key source that answers what the test says, as the keystore would.
final class _Keys implements BooksKeySource {
  const _Keys(this._key);

  final String? _key;

  @override
  Future<String?> key() async => _key;
}

const _phoneA = _Keys(
  '0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0',
);
const _phoneB = _Keys(
  'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
);
const _noKeystore = _Keys(null);

/// The books on the phone, encrypted at rest with a key the keystore keeps.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('books_at_rest'));
  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  String phone(String name) {
    final dir = Directory(p.join(root.path, name))..createSync();
    return p.join(dir.path, 'bazaar_ledger.sqlite');
  }

  Future<AppServices> open(String path, BooksKeySource keys) =>
      AppServices.open(databasePath: path, keys: keys);

  Future<void> setUpShop(AppServices services) => services.setUpShop(
    shopName: 'Chishti Kiryana Store',
    ownerName: 'Malik Sahib',
    deviceLabel: 'Counter 1',
  );

  bool readableWithoutKey(String path) {
    final db = raw.sqlite3.open(path);
    try {
      db.select('SELECT count(*) FROM firms');
      return true;
    } on raw.SqliteException {
      return false;
    } finally {
      db.close();
    }
  }

  bool fileMentions(String path, String text) {
    final bytes = [
      for (final f in [path, '$path-wal'])
        if (File(f).existsSync()) ...File(f).readAsBytesSync(),
    ];
    return String.fromCharCodes(bytes).contains(text);
  }

  group('books at rest', () {
    test("a new shop's books are encrypted on the phone", () async {
      final path = phone('a');
      final shop = await open(path, _phoneA);
      await setUpShop(shop);
      await shop.catalogue.addParty(
        shop.actorNow(),
        const PartyDraft(name: 'Rashid Traders'),
      );
      expect(shop.booksEncrypted, isTrue);
      await shop.close();

      expect(readableWithoutKey(path), isFalse);
      expect(fileMentions(path, 'Rashid Traders'), isFalse);
      expect(fileMentions(path, 'SQLite format 3'), isFalse);

      final again = await open(path, _phoneA);
      addTearDown(again.close);
      expect(
        (await again.queries.currentFirm())!.name,
        'Chishti Kiryana Store',
      );
    });

    test(
      'books kept in the clear before are encrypted at the next open',
      () async {
        final path = phone('a');
        final before = await open(path, _noKeystore);
        await setUpShop(before);
        expect(before.booksEncrypted, isFalse);
        await before.close();
        expect(readableWithoutKey(path), isTrue);

        final after = await open(path, _phoneA);
        addTearDown(after.close);
        expect(after.booksEncrypted, isTrue);
        expect(
          (await after.queries.currentFirm())!.name,
          'Chishti Kiryana Store',
        );
        expect(readableWithoutKey(path), isFalse);
        expect(fileMentions(path, 'Chishti Kiryana Store'), isFalse);
      },
    );

    test(
      'a backup of encrypted books opens on a phone with another key',
      () async {
        final shop = await open(phone('old'), _phoneA);
        await setUpShop(shop);
        final made = await shop.backups.create(
          shop.actorNow(),
          passphrase: 'chishti-1987',
          into: Directory(p.join(root.path, 'out')),
        );
        await shop.close();

        final candidate = await Restore.inspect(
          await made.file.readAsBytes(),
          passphrase: 'chishti-1987',
          scratch: Directory(p.join(root.path, 'scratch')),
        );
        expect(candidate.shopName, 'Chishti Kiryana Store');

        final newPhone = phone('new');
        await Restore.stage(candidate, databasePath: newPhone);
        final restored = await open(newPhone, _phoneB);
        addTearDown(restored.close);
        expect(
          (await restored.queries.currentFirm())!.name,
          'Chishti Kiryana Store',
        );
        expect(restored.booksEncrypted, isTrue);
        expect(readableWithoutKey(newPhone), isFalse);
      },
    );

    test('books whose key is gone do not open, and say so', () async {
      final path = phone('a');
      final shop = await open(path, _phoneA);
      await setUpShop(shop);
      await shop.close();

      await expectLater(open(path, _phoneB), throwsA(isA<BooksLocked>()));
      await expectLater(open(path, _noKeystore), throwsA(isA<BooksLocked>()));
    });
  });
}
