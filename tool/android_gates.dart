// The Android gates that only an artefact can prove.
//
//   dart run tool/android_gates.dart
//   dart run tool/android_gates.dart --plugin-tests-only
//
// Tier B in docs/verification_tiers.md: no emulator needed, but an Android SDK
// is. Nine of the twelve Android facts this project cares about live here, not
// on a device, which is why an emulator outage costs far less than it looks.
//
// Every check below exists because the corresponding Dart test structurally
// cannot do it:
//
//   * test/android_permissions_test.dart reads the two SOURCE manifests. The
//     failure its own doc comment describes — a dependency injecting
//     ACCESS_FINE_LOCATION — happens in the MERGER, which that test never
//     sees. This reads the merged output.
//   * No host test can tell whether an APK is signed, or by whom. The release
//     build was signed with the Android debug key for the life of this
//     project and nothing said a word.
//   * 16 KB page alignment is a property of the .so files inside the archive.
//   * Size was printed, not asserted, so it could only ever be noticed by
//     somebody reading the log.
//
// A missing tool is a FAILURE, not a skip. A skipped check that reports
// success is the exact shape of every defect this repository has found in
// itself.

import 'dart:convert';
import 'dart:io';

/// Under this, per ABI. A shopkeeper sideloading over Bluetooth or SHAREit
/// during an internet shutdown pays for every megabyte in minutes.
const _sizeCeilingBytes = 30 * 1024 * 1024;

/// Exactly what the shipped app may ask a shopkeeper's phone for.
///
/// This is the merged set — everything the app declares plus everything every
/// dependency's manifest contributes. It is the list printed on the Play
/// listing, and the only promise a shopkeeper can check without trusting
/// anybody.
const _allowedPermissions = <String>{
  // Android gates the creation of ANY socket behind this, including one to a
  // printer at 192.168.x.x on the shop's own wi-fi.
  'android.permission.INTERNET',
  // Capped at API 30 so Android 12 and above do not grant them.
  'android.permission.BLUETOOTH',
  'android.permission.BLUETOOTH_ADMIN',
  // Talking to an already-paired printer.
  'android.permission.BLUETOOTH_CONNECT',
  // Declared with neverForLocation.
  'android.permission.BLUETOOTH_SCAN',
};

Future<void> main(List<String> args) async {
  final pluginOnly = args.contains('--plugin-tests-only');
  final failures = <String>[];

  if (pluginOnly) {
    failures.addAll(await _pluginUnitTests());
    _report(failures);
    return;
  }

  final sdk = _androidSdk();
  if (sdk == null) {
    const missing =
        'no Android SDK. Set ANDROID_HOME or ANDROID_SDK_ROOT, or put sdk.dir '
        'in android/local.properties. These gates cannot run without it, and '
        'reporting success would be worse than reporting nothing.';
    _report([missing]);
    return;
  }

  final buildTools = _newestBuildTools(sdk);
  if (buildTools == null) {
    _report(['no build-tools under $sdk/build-tools.']);
    return;
  }
  stdout.writeln('android_gates: build-tools $buildTools\n');

  stdout.writeln('== building release APKs (per ABI)');
  final build = await Process.run(
    Platform.isWindows ? 'flutter.bat' : 'flutter',
    const [
      'build',
      'apk',
      '--release',
      '--split-per-abi',
      '--obfuscate',
      '--split-debug-info=build/symbols',
    ],
    runInShell: true,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (build.exitCode != 0) {
    _report(['the release build failed:\n${build.stdout}\n${build.stderr}']);
    return;
  }

  final apks = Directory('build/app/outputs/flutter-apk')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.apk'))
      .where((f) => f.path.contains('release'))
      .toList();

  if (apks.isEmpty) {
    _report(['the build reported success and produced no release APK.']);
    return;
  }

  for (final apk in apks) {
    final name = apk.uri.pathSegments.last;
    stdout.writeln('== $name');
    failures.addAll(_checkSigning(buildTools, apk, name));
    failures.addAll(_checkAlignment(buildTools, apk, name));
    failures.addAll(_checkSize(apk, name));
  }

  failures.addAll(_checkMergedPermissions(buildTools, apks.first));
  failures.addAll(await _pluginUnitTests());

  _report(failures);
}

// ---------------------------------------------------------------------------
// The gates
// ---------------------------------------------------------------------------

/// Signed at all, and not with the key every Android developer already has.
List<String> _checkSigning(String buildTools, File apk, String name) {
  final result = _run(_tool(buildTools, 'apksigner'), [
    'verify',
    '--print-certs',
    apk.path,
  ]);

  if (result == null) return ['$name: apksigner could not be run.'];
  final output = '${result.stdout}${result.stderr}';

  if (result.exitCode != 0 || output.contains('DOES NOT VERIFY')) {
    final unsigned =
        '$name: is not signed.\n'
        '    An unsigned APK reports the right size and installs nowhere. '
        'This is what `signingConfig = null` produces on its own, which is '
        'why the build now refuses outright instead.\n    $output';
    return [unsigned];
  }
  if (output.contains('CN=Android Debug')) {
    final debugKey =
        '$name: is signed with the ANDROID DEBUG KEY.\n'
        '    Every release artefact this project produced was in this state '
        'for months, behind a TODO the analyser was configured to ignore.';
    return [debugKey];
  }
  stdout.writeln('   signing   ok');
  return const [];
}

/// Every native library aligned to 16 KB, which Play requires for API 35+.
List<String> _checkAlignment(String buildTools, File apk, String name) {
  final result = _run(_tool(buildTools, 'zipalign'), [
    '-c',
    '-P',
    '16',
    '-v',
    '4',
    apk.path,
  ]);
  if (result == null) return ['$name: zipalign could not be run.'];

  if (result.exitCode != 0) {
    final bad = const LineSplitter()
        .convert('${result.stdout}')
        .where((l) => l.contains('BAD'))
        .take(10)
        .join('\n    ');
    return [
      '$name: not 16 KB aligned, so Play will reject the upload.\n    $bad',
    ];
  }
  stdout.writeln('   16 KB     ok');
  return const [];
}

List<String> _checkSize(File apk, String name) {
  final bytes = apk.lengthSync();
  final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
  if (bytes > _sizeCeilingBytes) {
    final tooBig =
        '$name: $mb MB, over the ${_sizeCeilingBytes ~/ (1024 * 1024)} MB '
        'ceiling.\n    Run `flutter build apk --analyze-size '
        '--target-platform android-arm64` to see what grew.';
    return [tooBig];
  }
  stdout.writeln('   size      ok ($mb MB)');
  return const [];
}

/// The permission set as the MERGER produced it, not as the sources declare it.
List<String> _checkMergedPermissions(String buildTools, File apk) {
  final result = _run(_tool(buildTools, 'aapt2'), [
    'dump',
    'permissions',
    apk.path,
  ]);
  if (result == null) return ['aapt2 could not be run.'];
  if (result.exitCode != 0) {
    return ['aapt2 dump permissions failed: ${result.stderr}'];
  }

  final found = const LineSplitter()
      .convert(result.stdout as String)
      .map((l) => l.trim())
      .where((l) => l.startsWith('uses-permission:'))
      .map((l) => RegExp(r"name='([^']+)'").firstMatch(l)?.group(1))
      .whereType<String>()
      .toSet();

  final unexpected = found.difference(_allowedPermissions);
  final missing = _allowedPermissions.difference(found);
  final problems = <String>[];

  if (unexpected.isNotEmpty) {
    problems.add(
      'the merged manifest asks for ${unexpected.length} permission(s) no '
      'feature needs:\n    ${unexpected.join('\n    ')}\n'
      '    A permission with no feature behind it makes the Play Data Safety '
      'form a lie. If a dependency added it, strip it with '
      'tools:node="remove"; if a feature earned it, add it to the allowlist '
      'in this file with the reason.',
    );
  }
  if (missing.isNotEmpty) {
    problems.add(
      'the merged manifest is MISSING ${missing.join(', ')}, which a feature '
      'needs. The LAN printer once shipped without INTERNET and every test '
      'passed, because tests run where Android\'s permission model does not '
      'exist.',
    );
  }
  if (found.any((p) => p.contains('LOCATION'))) {
    problems.add(
      'the merged manifest asks for LOCATION. A billing app does not need to '
      'know where the shopkeeper is standing, and it is a restricted '
      'permission with a declaration form and a review.',
    );
  }
  if (problems.isEmpty) {
    stdout.writeln('\n   merged permissions   ok (${found.length})');
    for (final p in found) {
      stdout.writeln('     $p');
    }
  }
  return problems;
}

/// The printer plugin's Kotlin tests, and proof that any of them ran.
///
/// `useJUnitPlatform()` was configured with no JUnit engine on the test runtime
/// classpath, so the task ran ZERO tests and reported success — full
/// scaffolding, verbose logging, mockito, and a green tick over nothing. The
/// exit code is not enough here; the report has to be counted.
Future<List<String>> _pluginUnitTests() async {
  final gradlew = Platform.isWindows ? 'gradlew.bat' : './gradlew';
  final result = await Process.run(
    gradlew,
    const [':pk_printer_android:testDebugUnitTest'],
    workingDirectory: 'android',
    runInShell: true,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );

  if (result.exitCode != 0) {
    final failed =
        'the printer plugin unit tests failed:\n'
        '${result.stdout}\n${result.stderr}';
    return [failed];
  }

  final reports = Directory(
    'packages/pk_printer_android/android/build/test-results',
  );
  if (!reports.existsSync()) {
    return ['the plugin test task produced no report directory at all.'];
  }

  var tests = 0;
  for (final entity in reports.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.xml')) continue;
    for (final match in RegExp(
      r'tests="(\d+)"',
    ).allMatches(entity.readAsStringSync())) {
      tests += int.parse(match.group(1)!);
    }
  }

  if (tests == 0) {
    const message =
        'the plugin test task passed having run ZERO tests. That is the state '
        'this package shipped in: useJUnitPlatform() with no engine on the '
        'classpath. Check the junit-jupiter dependency.';
    return [message];
  }
  stdout.writeln('\n   plugin tests   ok ($tests ran)');
  return const [];
}

// ---------------------------------------------------------------------------
// Plumbing
// ---------------------------------------------------------------------------

void _report(List<String> failures) {
  if (failures.isEmpty) {
    stdout.writeln('\nandroid_gates: every artefact gate passed.');
    return;
  }
  stderr.writeln('\nandroid_gates: ${failures.length} failure(s):\n');
  for (final f in failures) {
    stderr.writeln('  $f\n');
  }
  exit(1);
}

String? _androidSdk() {
  for (final key in const ['ANDROID_HOME', 'ANDROID_SDK_ROOT']) {
    final value = Platform.environment[key];
    if (value != null && Directory(value).existsSync()) return value;
  }
  final local = File('android/local.properties');
  if (!local.existsSync()) return null;
  for (final line in local.readAsLinesSync()) {
    if (!line.startsWith('sdk.dir=')) continue;
    // local.properties escapes Windows separators.
    final path = line.substring(8).trim().replaceAll(r'\\', r'\');
    if (Directory(path).existsSync()) return path;
  }
  return null;
}

String? _newestBuildTools(String sdk) {
  final dir = Directory('$sdk/build-tools');
  if (!dir.existsSync()) return null;
  final versions = dir.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return versions.isEmpty ? null : versions.last.path;
}

String _tool(String buildTools, String name) {
  for (final candidate in [
    '$buildTools/$name${Platform.isWindows ? '.bat' : ''}',
    '$buildTools/$name${Platform.isWindows ? '.exe' : ''}',
    '$buildTools/$name',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  return name;
}

ProcessResult? _run(String executable, List<String> args) {
  try {
    return Process.runSync(
      executable,
      args,
      runInShell: true,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  } on ProcessException {
    return null;
  }
}
