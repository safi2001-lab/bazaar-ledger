import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'peer.dart';

/// Everything on the wire is sealed (M23).
///
/// Until M23 a counter's changes crossed the shop's wi-fi as plain JSON,
/// and the shop's sync key went with every request in a header, so anybody
/// on the same wi-fi could read the books going past and then join them.
/// Now:
///
///  * **Joining** is an X25519 exchange with the six-digit code mixed in:
///    the key both sides end up with is PBKDF2 of the code, salted with the
///    exchange. Someone listening learns nothing; someone in the middle has
///    to guess the code at [defaultJoinWork] PBKDF2 rounds a guess, while the
///    master closes joining after five wrong ones.
///  * **After joining**, every body both ways is AES-256-GCM under a key
///    derived from the shop's sync key, which itself never crosses the wire
///    again. A request that does not open is refused as not from this shop.
final class WireSeal {
  WireSeal._(this._key);

  final SecretKey _key;

  static final _aead = DartAesGcm.with256bits();

  /// The seal for a shop's sync key.
  static Future<WireSeal> forShop(String syncKey) async => WireSeal._(
    await DartHkdf(hmac: DartHmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(utf8.encode(syncKey)),
      info: utf8.encode('bazaar-ledger sync v2'),
      nonce: const [],
    ),
  );

  /// `{"box": ...}` holding [json], sealed.
  Future<Map<String, Object?>> seal(Object? json) async {
    final box = await _aead.encrypt(
      utf8.encode(jsonEncode(json)),
      secretKey: _key,
    );
    return {'box': base64.encode(box.concatenation())};
  }

  /// What [body] holds, or [SyncRefused] when it was not sealed with this
  /// key.
  Future<Object?> open(Object? body) async {
    final box = body is Map<String, Object?> ? body['box'] : null;
    if (box is! String) throw const SyncRefused(_notOurs);
    try {
      final bytes = base64.decode(box);
      final plain = await _aead.decrypt(
        SecretBox.fromConcatenation(
          bytes,
          nonceLength: _aead.nonceLength,
          macLength: _aead.macAlgorithm.macLength,
        ),
        secretKey: _key,
      );
      return jsonDecode(utf8.decode(plain));
    } on SecretBoxAuthenticationError {
      throw const SyncRefused(_notOurs);
    } on FormatException {
      throw const SyncRefused(_notOurs);
    } on ArgumentError {
      throw const SyncRefused(_notOurs);
    }
  }

  static const _notOurs =
      'This counter is not joined to this shop. Join it again from the '
      'master.';
}

/// PBKDF2 rounds per guess of the joining code.
const defaultJoinWork = 100000;

/// One side of a join: an X25519 key pair made for this join only.
final class JoinKeys {
  JoinKeys._(this._pair, this.publicKey);

  final SimpleKeyPair _pair;

  /// Sent to the other side, base64.
  final String publicKey;

  static final _x25519 = DartX25519();

  static Future<JoinKeys> make() async {
    final pair = await _x25519.newKeyPair();
    final public = await pair.extractPublicKey();
    return JoinKeys._(pair, base64.encode(public.bytes));
  }

  /// The seal both sides share once each has the other's key and the same
  /// [code]. [masterKey] and [counterKey] are the two public keys, so both
  /// sides salt with them in the same order.
  Future<WireSeal> sealWith({
    required String otherPublicKey,
    required String code,
    required String masterKey,
    required String counterKey,
    int work = defaultJoinWork,
  }) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: _pair,
      remotePublicKey: SimplePublicKey(
        base64.decode(otherPublicKey),
        type: KeyPairType.x25519,
      ),
    );
    final salt = await const DartSha256().hash([
      ...await shared.extractBytes(),
      ...base64.decode(masterKey),
      ...base64.decode(counterKey),
    ]);
    final key = await DartPbkdf2(
      macAlgorithm: DartHmac.sha256(),
      iterations: work,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(code)), nonce: salt.bytes);
    return WireSeal._(SecretKey(Uint8List.fromList(await key.extractBytes())));
  }
}
