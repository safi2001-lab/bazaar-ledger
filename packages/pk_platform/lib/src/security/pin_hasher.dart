import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// A PIN as the users table keeps it: an Argon2id hash and its salt, never
/// the digits.
///
/// Honest about what this is for. A four-digit PIN keeps the counter boy out
/// of the owner's screens; it does not keep the books safe from somebody
/// holding the database file, who can try all ten thousand PINs at leisure.
/// That is what the sealed backup and, in M14, encryption at rest are for.
final class PinHasher {
  const PinHasher({this.memoryKiB = 8192, this.iterations = 2});

  /// Cheap enough for a test suite; never used by the app.
  const PinHasher.forTestsOnly() : memoryKiB = 64, iterations = 1;

  final int memoryKiB;
  final int iterations;

  /// Four to six digits, and nothing else.
  static bool isValidPin(String pin) => RegExp(r'^\d{4,6}$').hasMatch(pin);

  /// A fresh salt and the hash of [pin] under it, both base64.
  Future<({String hash, String salt})> hash(
    String pin, {
    Random? random,
  }) async {
    if (!isValidPin(pin)) {
      throw ArgumentError.value('****', 'pin', 'must be 4 to 6 digits');
    }
    final rng = random ?? Random.secure();
    final salt = [for (var i = 0; i < 16; i++) rng.nextInt(256)];
    return (hash: await _derive(pin, salt), salt: base64Encode(salt));
  }

  /// Whether [pin] is the one hashed as [hash] under [salt].
  Future<bool> verify(
    String pin, {
    required String hash,
    required String salt,
  }) async {
    if (!isValidPin(pin)) return false;
    final List<int> saltBytes;
    try {
      saltBytes = base64Decode(salt);
    } on FormatException {
      return false;
    }
    final candidate = await _derive(pin, saltBytes);
    // Compared in full whatever the first mismatch, so the time taken says
    // nothing about how many characters were right.
    if (candidate.length != hash.length) return false;
    var diff = 0;
    for (var i = 0; i < candidate.length; i++) {
      diff |= candidate.codeUnitAt(i) ^ hash.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<String> _derive(String pin, List<int> salt) async {
    final key = await DartArgon2id(
      memory: memoryKiB,
      iterations: iterations,
      parallelism: 1,
      hashLength: 32,
    ).deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt);
    return base64Encode(await key.extractBytes());
  }
}
