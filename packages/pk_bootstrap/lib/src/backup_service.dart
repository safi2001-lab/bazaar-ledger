import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// A backup that was written, ready to be handed to the share sheet.
final class MadeBackup {
  const MadeBackup({
    required this.file,
    required this.bytes,
    required this.createdAtUtc,
  });

  final File file;
  final int bytes;
  final DateTime createdAtUtc;
}

/// A backup that opened, checked out, and is waiting for the shopkeeper to
/// say yes.
///
/// Everything on it was read from the database inside the file, not from the
/// header, so "Chishti Kiryana Store, 3,412 bills" is what a restore will
/// actually bring back.
final class RestoreCandidate {
  const RestoreCandidate({
    required this.shopName,
    required this.createdAtUtc,
    required this.schemaVersion,
    required this.bills,
    required this.parties,
    required this.items,
    required this.lastEntryDateLocal,
    required this.verifiedPath,
  });

  final String shopName;
  final DateTime createdAtUtc;
  final int schemaVersion;
  final int bills;
  final int parties;
  final int items;
  final String? lastEntryDateLocal;

  /// The decrypted, checked database, in scratch space.
  final String verifiedPath;
}

/// Making a backup of the live books.
///
/// Lives beside [AppServices] because it needs the one open database and the
/// write path for its audit row — and nothing else. Restoring is [Restore],
/// which needs neither, because the screen that most needs it is the one
/// shown when the database would not open at all.
final class BackupService {
  BackupService({
    required this._database,
    required this._runner,
    required this._clock,
    required this._appVersion,
  });

  final AppDatabase _database;
  final TxRunner Function() _runner;
  final Clock _clock;
  final String _appVersion;

  /// Seals the whole database with [passphrase] into a `.pkbak` in [into].
  ///
  /// The plain copy SQLite writes on the way is deleted before this returns,
  /// whatever happens. It is the whole shop, unencrypted, and it must not
  /// outlive the seconds it takes to read it.
  Future<MadeBackup> create(
    ActorContext actor, {
    required String passphrase,
    required Directory into,
  }) async {
    if (passphrase.length < BackupArchive.minimumPassphraseLength) {
      // Checked before the snapshot, so a short passphrase costs nothing.
      throw const BackupRefused(
        BackupProblem.weakPassphrase,
        'A backup passphrase needs at least '
        '${BackupArchive.minimumPassphraseLength} characters.',
      );
    }

    final createdAt = _clock.nowUtc();
    await into.create(recursive: true);
    final snapshot = File(
      p.join(into.path, '.snapshot-${createdAt.microsecondsSinceEpoch}.db'),
    );

    final Uint8List sealed;
    try {
      await _database.snapshotTo(snapshot.path);
      final plain = await snapshot.readAsBytes();
      final appVersion = _appVersion;
      // Off the UI isolate. Argon2id and AES over a few megabytes is seconds
      // on an Android Go handset, and a frozen counter is a cashier who
      // assumes the app has crashed and kills it halfway through.
      sealed = await Isolate.run(
        () => const BackupArchive().seal(
          database: plain,
          passphrase: passphrase,
          schemaVersion: AppDatabase.currentSchemaVersion,
          appVersion: appVersion,
          createdAtUtc: createdAt,
        ),
      );
    } finally {
      if (snapshot.existsSync()) snapshot.deleteSync();
    }

    // Dated, and nothing else. The file name is visible wherever it is
    // shared to, and the shop's name in it would say whose books these are.
    final stamp = createdAt.toIso8601String().substring(0, 16);
    final file = File(
      p.join(
        into.path,
        'bazaar-ledger-${stamp.replaceAll(':', '').replaceAll('T', '-')}.pkbak',
      ),
    );
    await file.writeAsBytes(sealed, flush: true);

    // After the file exists, never before: a trail that says a backup was
    // made when the write then failed is a shopkeeper who stops making them.
    await _runner().run(actor, (tx) async {
      tx.audit(
        action: 'BACKUP_MADE',
        entityTable: 'firms',
        entityId: actor.firmId,
        summary: 'Backup made, ${sealed.length} bytes',
      );
    });

    return MadeBackup(
      file: file,
      bytes: sealed.length,
      createdAtUtc: createdAt,
    );
  }
}

/// Bringing a backup back.
///
/// Three steps, and the live books are untouched until the last:
///
///  1. [inspect] decrypts into scratch space and checks what came out is a
///     whole, readable Bazaar Ledger database this build can open.
///  2. [stage] puts it beside the live file, under a name nothing opens.
///  3. [applyPending] swaps it in — only ever at open, before the database
///     is in use, so there is no moment at which a half-replaced file is
///     being written to.
///
/// The books being replaced are kept, not deleted, as `.before-restore`. A
/// shopkeeper who restored last month's backup over this month's work has
/// one way back, and it should not depend on them having made a backup of
/// the thing they did not know they were about to lose.
abstract final class Restore {
  static const pendingSuffix = '.restore';
  static const keptSuffix = '.before-restore';

  static Future<RestoreCandidate> inspect(
    Uint8List file, {
    required String passphrase,
    required Directory scratch,
  }) async {
    final opened = await Isolate.run(
      () => const BackupArchive().open(file, passphrase: passphrase),
    );

    await scratch.create(recursive: true);
    final path = p.join(
      scratch.path,
      'restore-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    await File(path).writeAsBytes(opened.database, flush: true);

    try {
      return _check(path, opened.header);
    } on Object {
      _deleteWithSidecars(path);
      rethrow;
    }
  }

  static RestoreCandidate _check(String path, BackupHeader header) {
    final raw.Database db;
    try {
      db = raw.sqlite3.open(path);
    } on Object {
      throw const BackupRefused(
        BackupProblem.damaged,
        'The backup opened, but what is inside is not a database.',
      );
    }
    try {
      final String check;
      try {
        check = db.select('PRAGMA quick_check').first.values.first.toString();
      } on Object {
        throw const BackupRefused(
          BackupProblem.damaged,
          'The backup opened, but what is inside is not a database.',
        );
      }
      if (check != 'ok') {
        throw BackupRefused(
          BackupProblem.damaged,
          'The books inside this backup are damaged ($check). Nothing has '
          'been restored.',
        );
      }

      final version =
          db.select('PRAGMA user_version').first.values.first as int;
      if (version > AppDatabase.currentSchemaVersion) {
        throw const BackupRefused(
          BackupProblem.newerFormat,
          'This backup was made by a newer version of the app. Update the '
          'app, then restore it.',
        );
      }

      final raw.Row row;
      try {
        row = db.select('''
          SELECT
            (SELECT name FROM firms WHERE deleted_at_utc IS NULL
               ORDER BY created_at_utc LIMIT 1) AS shop,
            (SELECT COUNT(*) FROM documents
               WHERE doc_type = 'sale_invoice' AND status = 'posted'
                 AND deleted_at_utc IS NULL) AS bills,
            (SELECT COUNT(*) FROM parties
               WHERE deleted_at_utc IS NULL) AS parties,
            (SELECT COUNT(*) FROM items
               WHERE deleted_at_utc IS NULL) AS items,
            (SELECT MAX(doc_date_local) FROM documents
               WHERE deleted_at_utc IS NULL) AS last_date
        ''').first;
      } on raw.SqliteException {
        throw const BackupRefused(
          BackupProblem.notABackup,
          'The file inside this backup is a database, but not a shop\'s '
          'books.',
        );
      }

      final shop = row['shop'] as String?;
      if (shop == null) {
        throw const BackupRefused(
          BackupProblem.notABackup,
          'This backup holds no shop. It was made before setup finished, and '
          'restoring it would bring back nothing.',
        );
      }

      return RestoreCandidate(
        shopName: shop,
        createdAtUtc: header.createdAtUtc,
        schemaVersion: version,
        bills: row['bills'] as int,
        parties: row['parties'] as int,
        items: row['items'] as int,
        lastEntryDateLocal: row['last_date'] as String?,
        verifiedPath: path,
      );
    } finally {
      db.dispose();
    }
  }

  /// Puts a checked backup beside the live books, to be swapped in when the
  /// database is next opened.
  static Future<void> stage(
    RestoreCandidate candidate, {
    required String databasePath,
  }) async {
    final pending = '$databasePath$pendingSuffix';
    final partial = '$pending.partial';
    // Copied to a name nothing reads, then renamed: a rename within one
    // directory is atomic, so a phone that dies mid-copy leaves a `.partial`
    // that is ignored rather than a `.restore` that is half a database.
    await File(candidate.verifiedPath).copy(partial);
    await File(partial).rename(pending);
    _deleteWithSidecars(candidate.verifiedPath);
  }

  /// Whether a restore is waiting for the next open.
  static bool isPending(String databasePath) =>
      File('$databasePath$pendingSuffix').existsSync();

  /// Swaps a staged restore in. Called at open, before anything reads the
  /// database, and returns whether it did.
  ///
  /// The WAL and its index move with the file they belong to. Leaving the old
  /// `-wal` beside the new database would have SQLite replay the previous
  /// shop's last transactions into the restored one.
  static bool applyPending(String databasePath) {
    final pending = File('$databasePath$pendingSuffix');
    if (!pending.existsSync()) return false;

    for (final sidecar in const ['', '-wal', '-shm']) {
      final kept = File('$databasePath$keptSuffix$sidecar');
      if (kept.existsSync()) kept.deleteSync();
    }
    for (final sidecar in const ['', '-wal', '-shm']) {
      final live = File('$databasePath$sidecar');
      if (live.existsSync()) {
        live.renameSync('$databasePath$keptSuffix$sidecar');
      }
    }
    pending.renameSync(databasePath);
    return true;
  }

  static void _deleteWithSidecars(String path) {
    for (final sidecar in const ['', '-wal', '-shm']) {
      final f = File('$path$sidecar');
      if (f.existsSync()) f.deleteSync();
    }
  }
}
