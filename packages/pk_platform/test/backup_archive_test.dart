import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

/// The `.pkbak` file, sealed and opened with no database and no phone.
///
/// A backup is the one thing in this product that has to work the first time
/// it is ever needed, on a day something has already gone wrong. So every way
/// a file can come back different from how it left is asserted here: the
/// wrong passphrase, a flipped byte, a truncated download, an edited header,
/// a photo picked by mistake, and a file from a newer build.
void main() {
  const archive = BackupArchive();
  const passphrase = 'chishti-1987';

  // Something that looks like the start of a real SQLite file, with a shop's
  // name and a customer's number in it, so the tests can prove neither is
  // readable in the sealed file.
  final database = Uint8List.fromList([
    ...utf8.encode('SQLite format 3\u0000'),
    ...utf8.encode('Chishti Kiryana Store 0300-1234567 ' * 200),
    ...List<int>.generate(4096, (i) => i % 251),
  ]);

  Future<Uint8List> seal({String pass = passphrase, Random? random}) =>
      archive.seal(
        database: database,
        passphrase: pass,
        schemaVersion: 2,
        appVersion: '0.1.0',
        createdAtUtc: DateTime.utc(2026, 9, 3, 14, 30),
        kdf: BackupKdf.forTestsOnly,
        random: random ?? Random(7),
      );

  Matcher refusedFor(BackupProblem problem) => throwsA(
    isA<BackupRefused>().having((e) => e.problem, 'problem', problem),
  );

  group('a backup round trip', () {
    test('what comes out is byte for byte what went in', () async {
      final opened = await archive.open(await seal(), passphrase: passphrase);

      expect(opened.database, database);
      expect(opened.header.schemaVersion, 2);
      expect(opened.header.createdAtUtc, DateTime.utc(2026, 9, 3, 14, 30));
    });

    test('the header can be read before the passphrase is asked for', () async {
      final header = archive.readHeader(await seal());

      expect(header.format, BackupArchive.currentFormat);
      expect(header.appVersion, '0.1.0');
    });

    test(
      'two backups of the same books never share a key or a nonce',
      () async {
        final a = await seal(random: Random(1));
        final b = await seal(random: Random(2));

        expect(a, isNot(b));
        expect(
          (await archive.open(b, passphrase: passphrase)).database,
          database,
        );
      },
    );

    test('it is compressed, so a big shop fits on WhatsApp', () async {
      final sealed = await seal();
      expect(sealed.length, lessThan(database.length ~/ 2));
    });
  });

  group('what the file gives away', () {
    test(
      'nothing of the database is readable without the passphrase',
      () async {
        final text = latin1.decode(await seal());

        expect(text, isNot(contains('SQLite format 3')));
        expect(text, isNot(contains('Chishti')));
        expect(text, isNot(contains('0300-1234567')));
      },
    );
  });

  group('what a backup refuses', () {
    test('a passphrase too short to protect a file that leaves the phone', () {
      expect(seal(pass: '1234'), refusedFor(BackupProblem.weakPassphrase));
    });

    test('the wrong passphrase', () async {
      expect(
        archive.open(await seal(), passphrase: 'chishti-1988'),
        refusedFor(BackupProblem.wrongPassphraseOrDamaged),
      );
    });

    test('one flipped byte in the sealed data', () async {
      final sealed = await seal();
      sealed[sealed.length - 40] ^= 0x01;

      expect(
        archive.open(sealed, passphrase: passphrase),
        refusedFor(BackupProblem.wrongPassphraseOrDamaged),
      );
    });

    test('an edited header, even though it is not secret', () async {
      // The date is readable without the passphrase, but it is authenticated:
      // a file whose header was changed must not open.
      final sealed = await seal();
      final text = latin1.decode(sealed);
      final edited = latin1.encode(
        text.replaceFirst('2026-09-03', '2026-09-04'),
      );

      expect(
        archive.open(Uint8List.fromList(edited), passphrase: passphrase),
        refusedFor(BackupProblem.wrongPassphraseOrDamaged),
      );
    });

    test('a download that was cut short', () async {
      final sealed = await seal();

      expect(
        archive.open(
          Uint8List.sublistView(sealed, 0, 60),
          passphrase: passphrase,
        ),
        refusedFor(BackupProblem.damaged),
      );
      expect(
        archive.open(
          Uint8List.sublistView(sealed, 0, sealed.length - 100),
          passphrase: passphrase,
        ),
        refusedFor(BackupProblem.wrongPassphraseOrDamaged),
      );
    });

    test('a photo picked by mistake', () {
      final jpeg = Uint8List.fromList([
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        ...List.filled(64, 0),
      ]);
      expect(
        archive.open(jpeg, passphrase: passphrase),
        refusedFor(BackupProblem.notABackup),
      );
    });

    test('a backup from a newer build', () async {
      final sealed = await seal();
      sealed[6] = 0x32; // PKBAK02

      expect(
        archive.open(sealed, passphrase: passphrase),
        refusedFor(BackupProblem.newerFormat),
      );
    });
  });
}
