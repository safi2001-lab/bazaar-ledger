import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The CI workflow and `melos.yaml` must name the same gates.
///
/// They used to be two hand-maintained lists of the same thing, and one of them
/// was wrong: `melos run ci` invoked a `lint:custom` step that matched zero
/// packages and exited 0, while the workflow never invoked it at all. Two files
/// disagreeing about what gets checked, and both reporting success.
///
/// A workflow that has quietly stopped running a gate looks exactly like one
/// that runs it. So the lists are compared here rather than trusted, and
/// removing a gate from one file fails in the other.
void main() {
  final melos = File('melos.yaml').readAsStringSync();
  final workflow = File('.github/workflows/ci.yaml').readAsStringSync();

  /// Script names declared under `scripts:` in melos.yaml.
  Set<String> declaredScripts() {
    final scripts = melos.substring(melos.indexOf('scripts:'));
    return RegExp(
      r'^  ([a-z0-9:_]+):$',
      multiLine: true,
    ).allMatches(scripts).map((m) => m.group(1)!).toSet();
  }

  /// Every `melos run X` the workflow invokes.
  Set<String> invokedByWorkflow() => RegExp(
    r'melos run ([a-z0-9:_]+)',
  ).allMatches(workflow).map((m) => m.group(1)!).toSet();

  test('every gate the workflow invokes exists in melos.yaml', () {
    final missing = invokedByWorkflow().difference(declaredScripts());
    expect(
      missing,
      isEmpty,
      reason:
          'the workflow runs ${missing.join(', ')}, which melos.yaml does '
          'not define — so the step fails, or worse, silently does nothing',
    );
  });

  test('the ci script chains every host gate', () {
    // These are the Tier A gates. A gate dropped from this chain still has its
    // own melos script and still looks present in the file, which is exactly
    // how a check stops running without anybody noticing.
    final ci = RegExp(
      r'^  ci:\n(?:.*\n)*?    run: (.*)$',
      multiLine: true,
    ).firstMatch(melos)?.group(1);
    expect(ci, isNotNull, reason: 'melos.yaml has no `ci` script');

    for (final gate in const [
      'l10n:check',
      'analyze',
      'arch',
      'ledger',
      'test',
      'verify',
    ]) {
      expect(
        ci,
        contains('melos run $gate'),
        reason: 'the ci chain does not run $gate',
      );
    }
  });

  test('no melos script matches zero packages and passes', () {
    // `lint:custom` was `melos exec --depends-on="custom_lint"`, and no package
    // in the repository depended on custom_lint. It matched nothing, exited 0,
    // and was reported as a passing step in `melos run ci` for weeks.
    final dependsOn = RegExp(r'--depends-on="([^"]+)"').allMatches(melos);
    for (final match in dependsOn) {
      final package = match.group(1)!;
      final dependants = Directory('packages')
          .listSync()
          .whereType<Directory>()
          .map((d) => File('${d.path}/pubspec.yaml'))
          .where((f) => f.existsSync())
          .where((f) => f.readAsStringSync().contains('$package:'))
          .length;
      final rootDependsOnIt = File(
        'pubspec.yaml',
      ).readAsStringSync().contains('$package:');
      expect(
        dependants + (rootDependsOnIt ? 1 : 0),
        greaterThan(0),
        reason:
            'a melos step selects packages depending on "$package" and no '
            'package does, so it runs nothing and reports success',
      );
    }
  });

  test('the workflow runs all three verification tiers', () {
    for (final job in const ['gates:', 'android:', 'device:']) {
      expect(
        workflow,
        contains(job),
        reason:
            'the $job job is gone. docs/verification_tiers.md says what '
            'each tier proves; dropping one silently narrows what "CI is '
            'green" means',
      );
    }
  });

  test('the acceptance suite is actually run somewhere', () {
    // integration_test/ existed for the life of this project and had never run
    // in CI. `flutter test` in the root defaults to test/ and skips it, so the
    // directory has to be named explicitly.
    expect(
      workflow,
      contains('flutter test integration_test'),
      reason:
          'nothing in CI runs integration_test/, which is the acceptance '
          'gate and the only place the fault-injection run happens',
    );
  });

  test('the ledger checkout is deep enough for its own rules', () {
    // verify_ledger's R4 and R5 read the commit range. A shallow clone makes
    // them silently pass, which is a rule that cannot fire.
    expect(
      workflow,
      contains('fetch-depth: 0'),
      reason:
          'a shallow checkout degrades the ledger ownership and '
          'commit-claim rules into checks that always pass',
    );
  });

  test('a missing signing key is recorded as skipped, never as passed', () {
    expect(
      workflow,
      contains('SKIPPED'),
      reason:
          'a fork PR without the keystore secret must say the artefact '
          'gates did not run, rather than showing green',
    );
  });
}
