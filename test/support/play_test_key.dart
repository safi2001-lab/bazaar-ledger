import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// A Play licensing key made for tests only (openssl genrsa 2048), and a
/// signer with its private half, so a test can be Google Play.
const testPlayPublicKey =
    'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvM2W60F65q9T3BTfFErg'
    '4GvwMeKYhw7jG62/xb2XJuirZ6CpiMu1Iz1vIfsClOr5TYdTEguxa3JFk/WL2+yB'
    'fC1NaM4h+Cyg15f1l0thmnwIPKUGZCB3NlorxIZgJEEPAoooKfWNqYkVWUiSz0Zd'
    'pP3N0KM42WBSXGUipBaHmzibeHG79yY4B5kHoj0H/g/XLwomok4EQ2+x0l0cgd7D'
    '1GYtYrgIpCyUOIBO28rE6gYUCo/2T/iPA5496BI/MecOs7Dq2vkDHVgM3ZKkkVKE'
    'OYWX2+bRHDb0747OAD8EisRz2rh8/56dFLgujMS/zcRng6IPuC0IbVaK5fistLF+'
    '0QIDAQAB';

final _n = BigInt.parse(
  'bccd96eb417ae6af53dc14df144ae0e06bf031e298870ee31badbfc5bd9726e8'
  'ab67a0a988cbb5233d6f21fb0294eaf94d8753120bb16b724593f58bdbec817c'
  '2d4d68ce21f82ca0d797f5974b619a7c083ca506642077365a2bc4866024410f'
  '028a2829f58da98915594892cf465da4fdcdd0a338d960525c6522a416879b38'
  '9b7871bbf72638079907a23d07fe0fd72f0a26a24e04436fb1d25d1c81dec3d4'
  '662d62b808a42c9438804edbcac4ea06140a8ff64ff88f039e3de8123f31e70e'
  'b3b0eadaf9031d580cdd92a4915284398597dbe6d11c36f4ef8ece003f048ac4'
  '73dab87cff9e9d14b82e8cc4bfcdc46783a20fb82d086d568ae5f8acb4b17ed1',
  radix: 16,
);
final _d = BigInt.parse(
  '552592ce7e35631be701f617b51b1fd7965638e92c489c9a27bd702349a18556'
  'a116970a5e3b2071c81efa802d65e3a29328587a66f398b56c53920585256030'
  '146e38b9ddf00290772a7d03c2673e3879ae7fee25f1ce51a0d0e44c85c753df'
  'e5115193babe2c9b3a198df547ad40464c80297bb303b5c0ef125d510b281503'
  'e7480a89c68d48ee3cb2f1cd3ef9a5d56183ee699d1c0ee0ca50edc64a5a473e'
  'cd55c899a92b00694ce36ffb37e85111a4d6d0f196f8d1775cabfba5b143971e'
  'ba088f182aa44011ddf4a59505eb43928ca8a21cb7aaa6cbde7a8a83b158781c'
  '5f2c386a48b3bfca8e44c1697c878c08b58275cf66aa79f68bac6d4da9cc701',
  radix: 16,
);

/// Signs as Play would, with the test key's private half.
String signLikePlay(String data) {
  final digest = sha1.convert(utf8.encode(data)).bytes;
  const prefix = [
    0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, //
    0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14,
  ];
  const k = 256;
  final t = [...prefix, ...digest];
  final em = Uint8List(k)
    ..[1] = 1
    ..fillRange(2, k - t.length - 1, 0xff)
    ..setRange(k - t.length, k, t);
  var m = BigInt.zero;
  for (final b in em) {
    m = (m << 8) | BigInt.from(b);
  }
  var s = m.modPow(_d, _n);
  final out = Uint8List(k);
  for (var i = k - 1; i >= 0; i--) {
    out[i] = (s & BigInt.from(0xff)).toInt();
    s >>= 8;
  }
  return base64.encode(out);
}
