import 'dart:io';

import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

/// Where the key the books are encrypted with comes from.
///
/// On Android it is a random 256-bit key, generated once on the phone and
/// kept sealed by a key in the Android Keystore that never leaves the
/// phone's secure hardware. It is not derived from anything the shopkeeper
/// types, and it is never in a backup: a backup carries the books in the
/// clear inside its own passphrase-sealed envelope, so it opens on a new
/// phone whose keystore has never seen this one.
abstract interface class BooksKeySource {
  /// The key as 64 hex digits, or null when this phone cannot keep one.
  Future<String?> key();
}

/// The Android Keystore, through the app's own channel.
final class AndroidBooksKey implements BooksKeySource {
  const AndroidBooksKey();

  static const _channel = MethodChannel('pk.bazaarledger/books_key');

  @override
  Future<String?> key() async {
    if (!Platform.isAndroid) return null;
    try {
      final key = await _channel.invokeMethod<String>('databaseKey');
      return key != null && BooksFile.isKey(key) ? key : null;
    } on Object {
      return null;
    }
  }
}

/// The books on disk, encrypted with SQLite3 Multiple Ciphers when there is
/// a key for them.
abstract final class BooksFile {
  static final _hex = RegExp(r'^[0-9a-f]{64}$');

  static bool isKey(String key) => _hex.hasMatch(key);

  static const _plainHeader = 'SQLite format 3';

  /// Whether [path] is an ordinary SQLite file anybody could read: the
  /// header an encrypted file does not have. A missing or empty file is not
  /// plain; it is nothing yet, and is created encrypted.
  static bool isPlain(String path) {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() < 16) return false;
    final handle = file.openSync();
    try {
      return String.fromCharCodes(handle.readSync(15)) == _plainHeader;
    } finally {
      handle.closeSync();
    }
  }

  /// Encrypts the plain books at [path] in place, under [key].
  ///
  /// Written for the two ways plain books reach a phone that has a key: a
  /// shop set up before M14, and a backup just restored. The write-ahead log
  /// is folded in first, because encrypting a file whose last sales are
  /// still in its log would leave them in the clear beside it.
  static void encryptInPlace(String path, String key) {
    _requireKey(key);
    final db = raw.sqlite3.open(path);
    try {
      db
        ..execute('PRAGMA journal_mode = DELETE')
        ..execute("PRAGMA hexrekey = '$key'");
    } finally {
      db.close();
    }
  }

  /// Takes the encryption off the copy at [path], so a backup made from it
  /// opens on another phone.
  static void decryptInPlace(String path, String key) {
    _requireKey(key);
    final db = raw.sqlite3.open(path);
    try {
      db
        ..execute("PRAGMA hexkey = '$key'")
        ..execute('PRAGMA journal_mode = DELETE')
        ..execute("PRAGMA rekey = ''");
    } finally {
      db.close();
    }
  }

  /// Opens the books at [path], under [key] when there is one.
  ///
  /// The key is set before anything else touches the file, and read back at
  /// once, so a wrong key fails here in words rather than on the first
  /// query the counter runs.
  static QueryExecutor open(String path, {String? key}) {
    if (key != null) _requireKey(key);
    return NativeDatabase.createInBackground(
      File(path),
      setup: (db) {
        if (key != null) db.execute("PRAGMA hexkey = '$key'");
        db.select('SELECT count(*) FROM sqlite_master');
      },
    );
  }

  /// Whether the books at [path] are encrypted and can be read with [key].
  static bool opensWith(String path, String key) {
    _requireKey(key);
    final db = raw.sqlite3.open(path);
    try {
      db
        ..execute("PRAGMA hexkey = '$key'")
        ..select('SELECT count(*) FROM sqlite_master');
      return true;
    } on raw.SqliteException {
      return false;
    } finally {
      db.close();
    }
  }

  static void _requireKey(String key) {
    // Checked, not escaped: it is spliced into a pragma, and a key is only
    // ever 64 hex digits.
    if (!isKey(key)) throw ArgumentError.value('…', 'key', 'not a books key');
  }
}

/// Thrown when the books on this phone are encrypted and the key for them
/// is gone — the keystore was wiped, or the file came from another phone.
final class BooksLocked implements Exception {
  const BooksLocked();

  @override
  String toString() =>
      'The books on this phone are locked with a key this phone no longer '
      'has. Restore them from a backup.';
}
