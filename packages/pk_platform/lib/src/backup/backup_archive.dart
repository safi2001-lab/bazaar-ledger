/// The `.pkbak` file: a shop's whole database, sealed with a passphrase only
/// the shopkeeper knows.
///
/// ## Why a backup exists at all
///
/// The books live in one SQLite file on one phone. A phone that is dropped,
/// stolen or reset takes three years of udhaar with it, and nothing in this
/// product can bring it back — there is no server, by design. A backup is the
/// only answer to "my phone is gone", and until this existed the app had no
/// answer. The startup-failure screen had a "restore from backup" button that
/// said "arrives in M5".
///
/// ## Why it is encrypted, and with what
///
/// The file leaves the phone — that is its whole job — and where it goes is
/// the shopkeeper's choice: WhatsApp to themselves, Google Drive, a USB
/// stick, a nephew's laptop. Every one of those is somewhere a customer list
/// with phone numbers and balances should not be readable. So the file is
/// useless without the passphrase, and nothing in it identifies the shop.
///
///  * **Argon2id** turns the passphrase into a key: 19 MiB, two passes, one
///    lane — the OWASP minimum. It is deliberately slow and memory-hard, so
///    guessing passphrases against a stolen file costs real hardware per
///    guess. About 160 ms on a server; a second or two on an Android Go
///    handset, run off the UI thread.
///  * **AES-256-GCM** seals the data. GCM is authenticated: a flipped byte, a
///    truncated download or the wrong passphrase all fail the tag, and a
///    restore never proceeds on data that is not exactly what was written.
///  * **The header is authenticated too**, as associated data. It is readable
///    without the passphrase — so a restore screen can say "made on 3 Sept"
///    before asking for it — but it cannot be edited: change the date, the
///    KDF cost or the schema version and the tag fails.
///
/// The pure-Dart implementations are used on purpose. The whole seal runs in
/// a background isolate, where a platform channel to a native implementation
/// is not available, and a backup that took four seconds and kept the counter
/// responsive beats one that took one second and froze it.
///
/// ## Layout
///
/// ```text
/// 0      8 bytes   magic "PKBAK01\0"
/// 8      4 bytes   header length, big-endian
/// 12     n bytes   header, UTF-8 JSON (format, KDF, salt, nonce, dates)
/// 12+n   ...       AES-256-GCM ciphertext of gzip(database), then 16-byte tag
/// ```
library;

import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Why a backup could not be written or read.
enum BackupProblem {
  /// The passphrase is too short to protect a file that will leave the phone.
  weakPassphrase,

  /// The file is not a `.pkbak` at all — a photo, a PDF, the wrong download.
  notABackup,

  /// Made by a later version of this app, in a format this one cannot read.
  newerFormat,

  /// Cut short or damaged before the sealed part could even be found.
  damaged,

  /// The tag did not verify. Either the passphrase is wrong or the file was
  /// changed after it was written, and GCM cannot say which — so neither can
  /// this, and the message says both.
  wrongPassphraseOrDamaged,
}

/// A refusal, with the reason in words.
final class BackupRefused implements Exception {
  const BackupRefused(this.problem, this.reason);

  final BackupProblem problem;
  final String reason;

  @override
  String toString() => reason;
}

/// How expensive turning the passphrase into a key is.
///
/// Recorded in every file's header, so the cost can be raised later without
/// making an old backup unreadable.
final class BackupKdf {
  const BackupKdf({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  /// OWASP's minimum recommendation for Argon2id.
  static const standard = BackupKdf(
    memoryKiB: 19456,
    iterations: 2,
    parallelism: 1,
  );

  /// Cheap enough for a test suite to seal and open dozens of files. Never
  /// used by the app: nothing outside tests can reach it except by name.
  static const forTestsOnly = BackupKdf(
    memoryKiB: 64,
    iterations: 1,
    parallelism: 1,
  );

  final int memoryKiB;
  final int iterations;
  final int parallelism;
}

/// What can be read from a backup without its passphrase.
final class BackupHeader {
  const BackupHeader({
    required this.format,
    required this.createdAtUtc,
    required this.schemaVersion,
    required this.appVersion,
  });

  final int format;
  final DateTime createdAtUtc;

  /// The database schema the file holds. A restore refuses one newer than
  /// the running app can migrate.
  final int schemaVersion;
  final String appVersion;
}

/// A backup, opened: its header and the database it carried.
final class OpenedBackup {
  const OpenedBackup({required this.header, required this.database});

  final BackupHeader header;

  /// The SQLite file, byte for byte as it was when the backup was made.
  final Uint8List database;
}

/// Seals and opens `.pkbak` files.
final class BackupArchive {
  const BackupArchive();

  /// The first eight bytes of every backup.
  static final magic = Uint8List.fromList([...ascii.encode('PKBAK01'), 0]);

  /// The only format this build writes, and the newest it can read.
  static const currentFormat = 1;

  /// Shorter than this is refused. The file is meant to leave the phone, and
  /// a four-digit PIN is ten thousand guesses away from every customer's
  /// name, number and balance.
  static const minimumPassphraseLength = 8;

  static const _nonceLength = 12;
  static const _saltLength = 16;
  static const _tagLength = 16;

  Future<Uint8List> seal({
    required Uint8List database,
    required String passphrase,
    required int schemaVersion,
    required String appVersion,
    required DateTime createdAtUtc,
    BackupKdf kdf = BackupKdf.standard,
    Random? random,
  }) async {
    if (passphrase.length < minimumPassphraseLength) {
      throw const BackupRefused(
        BackupProblem.weakPassphrase,
        'A backup passphrase needs at least $minimumPassphraseLength '
        'characters. The file will leave this phone, and a short one can be '
        'guessed.',
      );
    }

    final rng = random ?? Random.secure();
    final salt = _randomBytes(rng, _saltLength);
    final nonce = _randomBytes(rng, _nonceLength);

    final header = utf8.encode(
      jsonEncode({
        'format': currentFormat,
        'kdf': {
          'alg': 'argon2id',
          'memoryKiB': kdf.memoryKiB,
          'iterations': kdf.iterations,
          'parallelism': kdf.parallelism,
          'salt': base64Encode(salt),
        },
        'cipher': 'aes-256-gcm',
        'nonce': base64Encode(nonce),
        'compression': 'gzip',
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
        'schemaVersion': schemaVersion,
        'appVersion': appVersion,
      }),
    );

    final prefix = BytesBuilder(copy: false)
      ..add(magic)
      ..add(_uint32(header.length))
      ..add(header);
    final aad = prefix.toBytes();

    final key = await _deriveKey(passphrase, salt, kdf);
    final box = await DartAesGcm.with256bits(
      nonceLength: _nonceLength,
    ).encrypt(gzip.encode(database), secretKey: key, nonce: nonce, aad: aad);

    return (BytesBuilder(copy: false)
          ..add(aad)
          ..add(box.cipherText)
          ..add(box.mac.bytes))
        .toBytes();
  }

  /// What the file says about itself, without the passphrase.
  ///
  /// Not proof of anything: the header is only verified when [open] checks
  /// the tag. It is for showing a shopkeeper which backup they picked.
  BackupHeader readHeader(Uint8List file) => _parse(file).header;

  Future<OpenedBackup> open(
    Uint8List file, {
    required String passphrase,
  }) async {
    final parsed = _parse(file);

    final key = await _deriveKey(passphrase, parsed.salt, parsed.kdf);
    final List<int> compressed;
    try {
      compressed = await DartAesGcm.with256bits(nonceLength: _nonceLength)
          .decrypt(
            SecretBox(
              parsed.cipherText,
              nonce: parsed.nonce,
              mac: Mac(parsed.tag),
            ),
            secretKey: key,
            aad: parsed.aad,
          );
    } on SecretBoxAuthenticationError {
      throw const BackupRefused(
        BackupProblem.wrongPassphraseOrDamaged,
        'That passphrase does not open this backup, or the file was changed '
        'after it was made. Nothing has been restored.',
      );
    }

    final Uint8List database;
    try {
      database = Uint8List.fromList(gzip.decode(compressed));
    } on FormatException {
      // Past the tag, so the bytes are exactly what was sealed. A file that
      // authenticates and will not decompress was written wrong, not
      // damaged in transit.
      throw const BackupRefused(
        BackupProblem.damaged,
        'This backup opened but its contents are not readable.',
      );
    }
    return OpenedBackup(header: parsed.header, database: database);
  }

  _Parsed _parse(Uint8List file) {
    if (file.length < magic.length + 4 ||
        !_startsWith(file, magic.sublist(0, 6))) {
      throw const BackupRefused(
        BackupProblem.notABackup,
        'This file is not a Bazaar Ledger backup.',
      );
    }
    if (!_startsWith(file, magic)) {
      // "PKBAK" and a version this build has never heard of.
      throw const BackupRefused(
        BackupProblem.newerFormat,
        'This backup was made by a newer version of the app. Update the app, '
        'then restore it.',
      );
    }

    final headerLength = ByteData.sublistView(file, 8, 12).getUint32(0);
    final headerEnd = 12 + headerLength;
    if (headerLength == 0 || headerEnd + _tagLength > file.length) {
      throw const BackupRefused(
        BackupProblem.damaged,
        'This backup is cut short. It may not have finished downloading.',
      );
    }

    final Map<String, Object?> json;
    try {
      json =
          jsonDecode(utf8.decode(file.sublist(12, headerEnd)))
              as Map<String, Object?>;
    } on Object {
      throw const BackupRefused(
        BackupProblem.damaged,
        'This backup is damaged and cannot be read.',
      );
    }

    final format = json['format'];
    if (format is! int) {
      throw const BackupRefused(
        BackupProblem.damaged,
        'This backup is damaged and cannot be read.',
      );
    }
    if (format > currentFormat) {
      throw const BackupRefused(
        BackupProblem.newerFormat,
        'This backup was made by a newer version of the app. Update the app, '
        'then restore it.',
      );
    }

    try {
      final kdf = json['kdf']! as Map<String, Object?>;
      if (kdf['alg'] != 'argon2id' || json['cipher'] != 'aes-256-gcm') {
        throw const FormatException('unknown algorithm');
      }
      return _Parsed(
        header: BackupHeader(
          format: format,
          createdAtUtc: DateTime.parse(json['createdAtUtc']! as String),
          schemaVersion: json['schemaVersion']! as int,
          appVersion: json['appVersion']! as String,
        ),
        kdf: BackupKdf(
          memoryKiB: kdf['memoryKiB']! as int,
          iterations: kdf['iterations']! as int,
          parallelism: kdf['parallelism']! as int,
        ),
        salt: base64Decode(kdf['salt']! as String),
        nonce: base64Decode(json['nonce']! as String),
        aad: Uint8List.sublistView(file, 0, headerEnd),
        cipherText: Uint8List.sublistView(
          file,
          headerEnd,
          file.length - _tagLength,
        ),
        tag: Uint8List.sublistView(file, file.length - _tagLength),
      );
    } on Object {
      throw const BackupRefused(
        BackupProblem.damaged,
        'This backup is damaged and cannot be read.',
      );
    }
  }

  static Future<SecretKey> _deriveKey(
    String passphrase,
    List<int> salt,
    BackupKdf kdf,
  ) => DartArgon2id(
    memory: kdf.memoryKiB,
    iterations: kdf.iterations,
    parallelism: kdf.parallelism,
    hashLength: 32,
  ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);

  static Uint8List _randomBytes(Random rng, int n) =>
      Uint8List.fromList([for (var i = 0; i < n; i++) rng.nextInt(256)]);

  static Uint8List _uint32(int value) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, value);

  static bool _startsWith(Uint8List data, List<int> prefix) {
    if (data.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (data[i] != prefix[i]) return false;
    }
    return true;
  }
}

final class _Parsed {
  const _Parsed({
    required this.header,
    required this.kdf,
    required this.salt,
    required this.nonce,
    required this.aad,
    required this.cipherText,
    required this.tag,
  });

  final BackupHeader header;
  final BackupKdf kdf;
  final List<int> salt;
  final List<int> nonce;
  final Uint8List aad;
  final Uint8List cipherText;
  final Uint8List tag;
}
