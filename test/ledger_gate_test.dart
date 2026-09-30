import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The gate that guards the gate.
///
/// `tool/verify_ledger.dart` is the rule that decides whether a commit may
/// claim a milestone. For several weeks it reported success on every run while
/// being structurally unable to say anything about M1 or M2 — every one of its
/// fifty rows named M0, and a milestone with no rows has no denominator, so it
/// was never printed and could never fail.
///
/// That is the same failure `tool/arch_check.dart` was written to eliminate in
/// the architecture rules: six of its twelve rules were silently inert, passing
/// because they could not fire rather than because nothing was wrong. So each
/// rule here is shown a ledger it MUST reject and a ledger it MUST accept. A
/// rule that cannot fail is not a rule, and this file is what stops one from
/// quietly becoming decoration again.
void main() {
  late Directory work;

  setUp(() => work = Directory.systemTemp.createTempSync('ledger_gate'));
  tearDown(() => work.deleteSync(recursive: true));

  /// Runs the real gate against a ledger written for this test.
  ///
  /// The git range defaults to an empty one so R4 and R5 do not read this
  /// repository's history unless a test means them to.
  ({int exitCode, String output}) check(
    String yaml, {
    bool strict = true,
    String range = 'HEAD..HEAD',
    List<String> extra = const [],
  }) {
    final file = File('${work.path}/ledger.yaml')..writeAsStringSync(yaml);
    final result = Process.runSync(Platform.isWindows ? 'dart.bat' : 'dart', [
      'run',
      'tool/verify_ledger.dart',
      '--ledger',
      file.path,
      '--offline',
      if (strict) '--strict',
      '--range',
      range,
      ...extra,
    ], runInShell: true);
    return (
      exitCode: result.exitCode,
      output: '${result.stdout}${result.stderr}',
    );
  }

  const goodMilestones = '''
milestones:
  - id: M0
    title: The walking skeleton
    state: sealed
    owns:
      - packages/**
      - lib/**
  - id: M1
    title: The catalogue
    state: open
    owns:
      - lib/features/items/**
''';

  const goodFeatures = '''
features:
  - id: M0-A-01
    milestone: M0
    title: Something proved
    status: done
    proof:
      - a test that exists
  - id: M1-A-01
    milestone: M1
    title: Something not yet built
    status: todo
    proof: []
''';

  test('a ledger that holds together passes', () {
    final result = check('$goodMilestones\n$goodFeatures');
    expect(result.exitCode, 0, reason: result.output);
    expect(result.output, contains('M1'));
  });

  test('R1 — a row may not name a milestone nobody declared', () {
    final result = check('''
$goodMilestones
features:
  - id: M7-A-01
    milestone: M7
    title: Written before the milestone existed
    status: todo
    proof: []
''');
    expect(result.exitCode, 1);
    expect(result.output, contains('M7'));
    expect(result.output, contains('does not'));
  });

  test('R2 — an open milestone with no rows fails, and is the whole point', () {
    // The exact shape the real ledger was in: M1 announced by six commits, and
    // not one row measuring it.
    final result = check('''
$goodMilestones
features:
  - id: M0-A-01
    milestone: M0
    title: Something proved
    status: done
    proof:
      - a test that exists
''');
    expect(result.exitCode, 1);
    expect(
      result.output,
      contains('no feature rows'),
      reason:
          'the gate did not notice a milestone it cannot measure, which '
          'is the failure this whole rewrite exists for',
    );
  });

  test('R2 — a planned milestone with no rows is fine', () {
    final result = check('''
milestones:
  - id: M0
    title: The walking skeleton
    state: sealed
    owns:
      - lib/**
  - id: M9
    title: Not started
    state: planned
    owns:
      - lib/features/users/**
features:
  - id: M0-A-01
    milestone: M0
    title: Something proved
    status: done
    proof:
      - a test that exists
''');
    expect(result.exitCode, 0, reason: result.output);
  });

  test('R3 — done with no proof is refused', () {
    // R3 runs in the offline pass but not the strict-only one, because strict
    // is the fast shape check CI runs first.
    final result = check('''
$goodMilestones
features:
  - id: M0-A-01
    milestone: M0
    title: Claimed without evidence
    status: done
    proof: []
  - id: M1-A-01
    milestone: M1
    title: Honest
    status: todo
    proof: []
''', strict: false);
    expect(result.exitCode, 1);
    expect(result.output, contains('no proof'));
  });

  test('R4 — a change under a milestone that has not opened is refused', () {
    // A range from this repository's own history that certainly touched lib/.
    // Discovered rather than hardcoded, so a rebase cannot turn this test into
    // one that passes because it found nothing to check.
    final head = Process.runSync('git', const [
      'log',
      '--format=%H',
      '-n',
      '1',
      '--',
      'lib/',
    ], runInShell: true).stdout.toString().trim();
    expect(
      head,
      isNotEmpty,
      reason:
          'no commit in this repository touched lib/, which cannot be '
          'true — R4 would be untested',
    );
    final range = '$head~1..$head';

    final touched =
        Process.runSync('git', ['diff', '--name-only', range], runInShell: true)
            .stdout
            .toString()
            .split('\n')
            .where(
              (l) => l.trim().startsWith('lib/') && l.trim().endsWith('.dart'),
            );
    expect(
      touched,
      isNotEmpty,
      reason:
          'the chosen range changed no Dart file under lib/, so R4 would '
          'be asked nothing and would pass for the wrong reason',
    );

    // Every milestone the real commit subjects might name has to be declared,
    // or R5 fires and this test reports an R4 failure that is nothing of the
    // kind. It cost a confusing run to notice: the commit under test began
    // "M2:", the fixture declared only M0 and M1, and the output said "commit
    // claims M2, which the ledger does not declare" while the test insisted
    // R4 was broken.
    String spare({required String ownsLib, required String libState}) {
      final buffer = StringBuffer('milestones:\n');
      buffer.writeln('  - id: M0');
      buffer.writeln('    title: The walking skeleton');
      buffer.writeln('    state: sealed');
      buffer.writeln('    owns:');
      buffer.writeln('      - packages/**');
      buffer.writeln('  - id: M1');
      buffer.writeln('    title: The one under test');
      buffer.writeln('    state: $libState');
      buffer.writeln('    owns:');
      buffer.writeln('      - $ownsLib');
      for (var i = 2; i <= _lastMilestone; i++) {
        buffer.writeln('  - id: M$i');
        buffer.writeln('    title: Declared so R5 has nothing to say');
        buffer.writeln('    state: open');
        buffer.writeln('    owns:');
        buffer.writeln('      - never/matches/anything/m$i/**');
      }

      // Every declared milestone is `open`, has a row, and that row is `done`.
      //
      // All three are needed and each closes a different rule. `open` so R5
      // does not object to a real commit subject naming the milestone. A row
      // so R2 does not object to a milestone nobody is measuring. And `done`
      // so R5 does not object when a real commit subject says a milestone is
      // COMPLETE — which is exactly what happened the first time M1 reached
      // 20/20 and the commit said so: this test failed against a fixture that
      // deliberately held M1 at zero, while the real ledger was perfectly
      // fine.
      //
      // Every one of those was the rule working. The fixture simply has to be
      // a ledger that holds together in every respect except the one under
      // test.
      buffer.writeln('features:');
      for (var i = 0; i <= _lastMilestone; i++) {
        buffer.writeln('  - id: M$i-A-01');
        buffer.writeln('    milestone: M$i');
        buffer.writeln('    title: A row so the milestone is measurable');
        buffer.writeln('    status: done');
        buffer.writeln('    proof:');
        buffer.writeln('      - a test that exists');
      }
      return buffer.toString();
    }

    // M1 owns lib/** and is planned, so every changed file under lib/ is a
    // violation.
    final refused = check(
      spare(ownsLib: 'lib/**', libState: 'planned'),
      range: range,
    );
    expect(refused.exitCode, 1, reason: refused.output);
    expect(refused.output, contains('still `planned`'));

    // The same range against a ledger where the same milestone is OPEN must
    // pass — otherwise this test proves only that the gate dislikes something.
    final allowed = check(
      spare(ownsLib: 'lib/**', libState: 'open'),
      range: range,
    );
    expect(allowed.exitCode, 0, reason: allowed.output);
  });

  test('R6 — two milestones may not own the same pattern', () {
    final result = check('''
milestones:
  - id: M0
    title: The walking skeleton
    state: sealed
    owns:
      - lib/features/items/**
  - id: M1
    title: The catalogue
    state: open
    owns:
      - lib/features/items/**
$goodFeatures''');
    expect(result.exitCode, 1);
    expect(result.output, contains('claimed by both'));
  });

  test('an unknown state is refused rather than treated as planned', () {
    final result = check('''
milestones:
  - id: M0
    title: The walking skeleton
    state: nearly
    owns:
      - lib/**
features:
  - id: M0-A-01
    milestone: M0
    title: Something
    status: todo
    proof: []
''');
    expect(result.exitCode, 1);
    expect(result.output, contains('not one of'));
  });

  test(
    'a deferred proof drops the row out of done, and fails without the flag',
    () {
      const yaml = '''
milestones:
  - id: M0
    title: The walking skeleton
    state: sealed
    owns:
      - lib/**
features:
  - id: M0-A-01
    milestone: M0
    title: Proved only on a handset
    status: done
    proof:
      - a test that exists
    deferred:
      proof: a test that exists
      reason: no emulator on this machine
      recorded: 2026-08-23
      recorded_by: someone
      expires: 2099-01-01
''';
      final refused = check(yaml);
      expect(refused.exitCode, 1);
      expect(refused.output, contains('DEFERRED'));

      final allowed = check(yaml, extra: const ['--allow-deferred']);
      expect(allowed.exitCode, 0, reason: allowed.output);
      expect(
        allowed.output,
        contains('0/1 done'),
        reason:
            'a deferred row still counted as done, so the milestone '
            'percentage did not fall and nobody reading it would notice',
      );
    },
  );

  test('an expired deferral fails even with the flag', () {
    final result = check(
      '''
milestones:
  - id: M0
    title: The walking skeleton
    state: sealed
    owns:
      - lib/**
features:
  - id: M0-A-01
    milestone: M0
    title: Proved only on a handset
    status: done
    proof:
      - a test that exists
    deferred:
      proof: a test that exists
      reason: no emulator that afternoon
      recorded: 2020-01-01
      recorded_by: someone
      expires: 2020-01-15
''',
      extra: const ['--allow-deferred'],
    );
    expect(result.exitCode, 1);
    expect(result.output, contains('expired'));
  });

  test('a ledger with no milestones block is refused outright', () {
    final result = check(goodFeatures);
    expect(result.exitCode, 1);
    expect(result.output, contains('declares no milestones'));
  });

  test('the real ledger declares every milestone from M0 to M14', () {
    final text = File('docs/feature_ledger.yaml').readAsStringSync();
    for (var i = 0; i <= 14; i++) {
      expect(
        text,
        contains('- id: M$i\n'),
        reason: 'M$i is not declared, so nothing measures it',
      );
    }
  });

  test('the phantom gate is gone and stays gone', () {
    // `packages/pk_lints/` was two empty directories. `tx_runner.dart` and
    // `tokens.dart` both cited its rules as build-time guarantees, and
    // `melos run lint:custom` matched zero packages and exited 0 — a green
    // tick for a check that was never running.
    expect(
      Directory('packages/pk_lints').existsSync(),
      isFalse,
      reason: 'pk_lints is back; either it is real now or it is a lie again',
    );
    expect(
      File('melos.yaml').readAsStringSync(),
      isNot(contains('custom_lint')),
      reason: 'melos still runs a step that matches no package and passes',
    );
    for (final path in const [
      'packages/pk_data/lib/src/write/tx_runner.dart',
      'lib/design/tokens.dart',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('pk_lints')),
        reason: '$path credits an enforcement mechanism that does not exist',
      );
    }
  });
}

/// Every milestone a real commit subject in this repository might name. The
/// fixture declares them all, so R5 has nothing to say about a commit that
/// is really being used to test R4; raise it when milestones outgrow it.
const _lastMilestone = 40;
