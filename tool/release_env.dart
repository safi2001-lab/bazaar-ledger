// Turns credentials held in the environment into the files a release build
// reads, and nothing else.
//
// Every credential lives in an environment variable — GitHub Actions
// secrets in CI, or a gitignored `.env` file on a laptop (see
// `.env.example`) — and never in the repository. This writes:
//
//   config/app_config.json   the --dart-define-from-file for the build
//   android/key.properties   where the upload key is, and its passwords
//   android/upload.jks       the upload key itself, from base64
//
// all three gitignored. It prints which values are present and never what
// they are.
//
//   dart run tool/release_env.dart            write what is there
//   dart run tool/release_env.dart --release  and fail unless everything a
//                                             Play release needs is there
//
// A release needs the upload key. A release without the billing key or the
// OAuth client still builds and is honest about it (no plans can be bought,
// no Drive backup is offered), so `--release` insists on those too: a store
// build that cannot sell its own plans is not one anybody meant to ship.
import 'dart:convert';
import 'dart:io';

const _config = {
  'GOOGLE_OAUTH_CLIENT_ID': 'Google Drive backup (M20)',
  'PLAY_BILLING_PUBLIC_KEY': 'subscription plans (M21)',
};

const _signing = [
  'UPLOAD_KEYSTORE_BASE64',
  'UPLOAD_STORE_PASSWORD',
  'UPLOAD_KEY_ALIAS',
  'UPLOAD_KEY_PASSWORD',
];

void main(List<String> args) {
  final release = args.contains('--release');
  final env = {..._dotEnv(), ...Platform.environment};
  String value(String key) => (env[key] ?? '').trim();
  final missing = <String>[];

  // The build-time identifiers.
  final config = <String, String>{};
  for (final MapEntry(:key, value: what) in _config.entries) {
    config[key] = value(key);
    stdout.writeln(
      '${config[key]!.isEmpty ? 'missing' : 'set    '}  $key  ($what)',
    );
    if (config[key]!.isEmpty) missing.add(key);
  }
  Directory('config').createSync();
  File('config/app_config.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(config)}\n',
  );

  // The upload key: from base64, or from a file already on this machine.
  final keyPath = value('UPLOAD_KEYSTORE_PATH');
  final keyB64 = value('UPLOAD_KEYSTORE_BASE64');
  var haveKey = false;
  if (keyB64.isNotEmpty) {
    File(
      'android/upload.jks',
    ).writeAsBytesSync(base64.decode(keyB64.replaceAll(RegExp(r'\s'), '')));
    haveKey = true;
  } else if (keyPath.isNotEmpty && File(keyPath).existsSync()) {
    File(keyPath).copySync('android/upload.jks');
    haveKey = true;
  }
  final passwords = [
    for (final k in _signing.skip(1))
      if (value(k).isEmpty) k,
  ];
  if (haveKey && passwords.isEmpty) {
    File('android/key.properties').writeAsStringSync(
      'storeFile=upload.jks\n'
      'storePassword=${value('UPLOAD_STORE_PASSWORD')}\n'
      'keyAlias=${value('UPLOAD_KEY_ALIAS')}\n'
      'keyPassword=${value('UPLOAD_KEY_PASSWORD')}\n',
    );
    stdout.writeln('set      upload key  (signing)');
  } else {
    stdout.writeln('missing  upload key  (signing)');
    missing.addAll([
      if (!haveKey) 'UPLOAD_KEYSTORE_BASE64 or UPLOAD_KEYSTORE_PATH',
      ...passwords,
    ]);
  }

  if (release && missing.isNotEmpty) {
    stderr.writeln(
      '\nNot a release: ${missing.join(', ')} missing. See docs/RELEASE.md.',
    );
    exitCode = 1;
  }
}

/// `KEY=value` lines from `.env`, if there is one. Quotes are stripped and
/// `#` starts a comment; the real environment wins over the file.
Map<String, String> _dotEnv() {
  final file = File('.env');
  if (!file.existsSync()) return const {};
  final out = <String, String>{};
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq <= 0) continue;
    var v = line.substring(eq + 1).trim();
    if (v.length >= 2 &&
        ((v.startsWith('"') && v.endsWith('"')) ||
            (v.startsWith("'") && v.endsWith("'")))) {
      v = v.substring(1, v.length - 1);
    }
    out[line.substring(0, eq).trim().replaceFirst('export ', '')] = v;
  }
  return out;
}
