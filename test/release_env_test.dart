import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The release credentials come from the environment, become the files a
/// signed build reads, and are never printed (M22).
void main() {
  late Directory work;
  final tool = File('tool/release_env.dart').absolute.path;

  setUp(() {
    work = Directory.systemTemp.createTempSync('release_env');
    Directory('${work.path}/android').createSync();
  });
  tearDown(() => work.deleteSync(recursive: true));

  ProcessResult run(Map<String, String> env, {bool release = true}) =>
      Process.runSync(
        Platform.isWindows ? 'dart.bat' : 'dart',
        ['run', tool, if (release) '--release'],
        workingDirectory: work.path,
        environment: env,
        runInShell: true,
      );

  const secrets = {
    'GOOGLE_OAUTH_CLIENT_ID': '1234-abcd.apps.googleusercontent.com',
    'PLAY_BILLING_PUBLIC_KEY': 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA',
    'UPLOAD_STORE_PASSWORD': 'store-secret-77',
    'UPLOAD_KEY_ALIAS': 'upload',
    'UPLOAD_KEY_PASSWORD': 'key-secret-88',
  };

  test('a release with every secret writes the config and the upload key, '
      'and prints none of them', () {
    final keystore = utf8.encode('not really a keystore');
    final result = run({
      ...secrets,
      'UPLOAD_KEYSTORE_BASE64': base64.encode(keystore),
    });
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');

    final config =
        jsonDecode(
              File('${work.path}/config/app_config.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    expect(config['GOOGLE_OAUTH_CLIENT_ID'], secrets['GOOGLE_OAUTH_CLIENT_ID']);
    expect(
      config['PLAY_BILLING_PUBLIC_KEY'],
      secrets['PLAY_BILLING_PUBLIC_KEY'],
    );
    expect(File('${work.path}/android/upload.jks').readAsBytesSync(), keystore);
    expect(
      File('${work.path}/android/key.properties').readAsStringSync(),
      contains('storePassword=store-secret-77'),
    );

    final printed = '${result.stdout}${result.stderr}';
    for (final value in secrets.values.where((v) => v != 'upload')) {
      expect(printed, isNot(contains(value)));
    }
  });

  test('a release missing a secret is refused and says which', () {
    final result = run({...secrets}..remove('PLAY_BILLING_PUBLIC_KEY'));
    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('PLAY_BILLING_PUBLIC_KEY'));
    expect('${result.stderr}', contains('UPLOAD_KEYSTORE_BASE64'));
  });

  test('a .env file works on a laptop, and the real environment wins', () {
    File('${work.path}/.env').writeAsStringSync(
      '# local\n'
      'GOOGLE_OAUTH_CLIENT_ID="from-file"\n'
      'export PLAY_BILLING_PUBLIC_KEY=from-file-too\n',
    );
    final result = run({
      'PLAY_BILLING_PUBLIC_KEY': 'from-environment',
    }, release: false);
    expect(result.exitCode, 0);
    final config =
        jsonDecode(
              File('${work.path}/config/app_config.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    expect(config['GOOGLE_OAUTH_CLIENT_ID'], 'from-file');
    expect(config['PLAY_BILLING_PUBLIC_KEY'], 'from-environment');
  });

  test('none of the files it writes can be committed', () {
    final ignored = Process.runSync('git', [
      'check-ignore',
      '.env',
      'config/app_config.json',
      'android/key.properties',
      'android/upload.jks',
    ], runInShell: true);
    expect(
      '${ignored.stdout}'.trim().split('\n'),
      hasLength(4),
      reason: 'a credential file is not gitignored',
    );
  });
}
