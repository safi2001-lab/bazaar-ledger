import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Checks that Google Play signed a purchase (M21).
///
/// Play signs each purchase's JSON with the app's licensing key, RSA
/// PKCS#1 v1.5 over SHA-1. The matching public key ships in the build
/// (`PLAY_BILLING_PUBLIC_KEY`); it can check a signature and cannot make
/// one, so a phone that edits its stored purchase gains nothing. Written
/// out by hand on `BigInt` — a few dozen lines — rather than taking a
/// cryptography package for one verify.
abstract final class PlaySignature {
  /// Whether [signatureBase64] is Play's signature of [signedData] under
  /// [publicKeyBase64] (X.509 SubjectPublicKeyInfo, base64, as Play Console
  /// shows it). False for anything malformed; never throws.
  static bool verify({
    required String publicKeyBase64,
    required String signedData,
    required String signatureBase64,
  }) {
    try {
      final key = _readKey(base64.decode(_clean(publicKeyBase64)));
      if (key == null) return false;
      final (n, e) = key;
      final sig = base64.decode(_clean(signatureBase64));
      final k = (n.bitLength + 7) ~/ 8;
      if (sig.length != k) return false;
      final s = _toBig(sig);
      if (s >= n) return false;
      final em = _fromBig(s.modPow(e, n), k);
      final expected = _encode(sha1.convert(utf8.encode(signedData)).bytes, k);
      if (expected == null) return false;
      var diff = 0;
      for (var i = 0; i < k; i++) {
        diff |= em[i] ^ expected[i];
      }
      return diff == 0;
    } on Object {
      return false;
    }
  }

  static String _clean(String s) => s.replaceAll(RegExp(r'\s'), '');

  /// DigestInfo for SHA-1, before the 20-byte hash.
  static const _sha1Prefix = [
    0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, //
    0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14,
  ];

  /// EMSA-PKCS1-v1_5: 00 01 FF..FF 00 DigestInfo.
  static Uint8List? _encode(List<int> hash, int k) {
    final t = [..._sha1Prefix, ...hash];
    if (k < t.length + 11) return null;
    return Uint8List(k)
      ..[1] = 0x01
      ..fillRange(2, k - t.length - 1, 0xff)
      ..setRange(k - t.length, k, t);
  }

  static BigInt _toBig(List<int> bytes) {
    var r = BigInt.zero;
    for (final b in bytes) {
      r = (r << 8) | BigInt.from(b);
    }
    return r;
  }

  static Uint8List _fromBig(BigInt v, int k) {
    final out = Uint8List(k);
    var x = v;
    for (var i = k - 1; i >= 0; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x >>= 8;
    }
    return out;
  }

  /// (modulus, exponent) from a SubjectPublicKeyInfo, or a bare RSA key.
  static (BigInt, BigInt)? _readKey(Uint8List der) {
    final outer = _Der(der).next(0x30);
    if (outer == null) return null;
    final body = _Der(outer);
    final first = body.peekTag();
    if (first == 0x02) {
      // RSAPublicKey: SEQUENCE { n, e }.
      final n = body.next(0x02), e = body.next(0x02);
      return n == null || e == null ? null : (_toBig(n), _toBig(e));
    }
    if (body.next(0x30) == null) return null; // AlgorithmIdentifier
    final bits = body.next(0x03);
    if (bits == null || bits.isEmpty || bits[0] != 0) return null;
    final rsa = _Der(Uint8List.sublistView(bits, 1)).next(0x30);
    if (rsa == null) return null;
    final inner = _Der(rsa);
    final n = inner.next(0x02), e = inner.next(0x02);
    return n == null || e == null ? null : (_toBig(n), _toBig(e));
  }
}

/// Just enough DER to walk a public key.
final class _Der {
  _Der(this._b);

  final Uint8List _b;
  var _i = 0;

  int? peekTag() => _i < _b.length ? _b[_i] : null;

  Uint8List? next(int tag) {
    if (_i + 2 > _b.length || _b[_i] != tag) return null;
    _i++;
    var len = _b[_i++];
    if (len & 0x80 != 0) {
      final count = len & 0x7f;
      if (count == 0 || count > 4 || _i + count > _b.length) return null;
      len = 0;
      for (var j = 0; j < count; j++) {
        len = (len << 8) | _b[_i++];
      }
    }
    if (_i + len > _b.length) return null;
    final out = Uint8List.sublistView(_b, _i, _i + len);
    _i += len;
    return out;
  }
}
