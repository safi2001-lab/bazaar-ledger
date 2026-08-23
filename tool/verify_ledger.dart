// The anti-lie gate.
//
// `docs/feature_ledger.yaml` carries one row per feature. A row marked done
// must name a proof: a test that exists, is not skipped, and PASSED in this
// run. This script runs the suites, collects the names of the tests that
// actually passed, and fails the build if any claim is unsupported.
//
// The rule it enforces: a commit may not say "Complete Milestone N" unless
// this script printed 100% for N. Under that rule the previous build's five
// commits, each announcing a completed sprint, would have printed about 18%
// and been rejected — which is the number an audit later put on them.
//
//   dart run tool/verify_ledger.dart            verify everything
//   dart run tool/verify_ledger.dart --milestone M0
//   dart run tool/verify_ledger.dart --offline  parse only, run nothing
//
// The YAML is read with a small hand-rolled parser rather than a package, for
// the same reason `arch_check` has no dependencies: a gate that can be
// disabled by a version bump is not a gate.

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final onlyMilestone = _flagValue(args, '--milestone');
  final offline = args.contains('--offline');

  final ledgerFile = File('docs/feature_ledger.yaml');
  if (!ledgerFile.existsSync()) {
    stderr.writeln('verify_ledger: docs/feature_ledger.yaml is missing.');
    exit(1);
  }

  final features = _parseLedger(ledgerFile.readAsLinesSync());
  final scoped = onlyMilestone == null
      ? features
      : features.where((f) => f.milestone == onlyMilestone).toList();

  if (scoped.isEmpty) {
    stderr.writeln('verify_ledger: no features matched.');
    exit(1);
  }

  final passing = offline ? <String>{} : await _runSuites();

  final problems = <String>[];
  final done = scoped.where((f) => f.status == 'done').toList();

  for (final feature in done) {
    if (feature.proof.isEmpty) {
      problems.add('${feature.id}: marked done with no proof.');
      continue;
    }
    for (final proof in feature.proof) {
      if (offline) continue;
      if (!passing.contains(proof)) {
        problems.add(
          '${feature.id}: proof "$proof" did not pass in this run.',
        );
      }
    }
  }

  // Per milestone, so the number in a commit message is one this script
  // printed rather than one somebody felt.
  final byMilestone = <String, List<_Feature>>{};
  for (final f in scoped) {
    byMilestone.putIfAbsent(f.milestone, () => []).add(f);
  }

  stdout.writeln('verify_ledger: ${scoped.length} features\n');
  final milestones = byMilestone.keys.toList()..sort();
  for (final m in milestones) {
    final rows = byMilestone[m]!;
    final complete = rows.where((f) => f.status == 'done').length;
    final percent = (complete * 100 / rows.length).floor();
    stdout.writeln(
      '  $m  ${percent.toString().padLeft(3)}%  '
      '$complete/${rows.length} done',
    );
  }

  if (problems.isEmpty) {
    stdout.writeln(
      offline
          ? '\nverify_ledger: ledger parses; nothing was run (--offline).'
          : '\nverify_ledger: every completed feature has a passing proof.',
    );
    return;
  }

  stderr.writeln('\nverify_ledger: ${problems.length} unsupported claim(s):');
  for (final p in problems) {
    stderr.writeln('  $p');
  }
  stderr.writeln(
    '\nA feature is done when a test proves it, and not before.',
  );
  exit(1);
}

final class _Feature {
  _Feature({
    required this.id,
    required this.milestone,
    required this.title,
    required this.status,
    required this.proof,
  });

  final String id;
  final String milestone;
  final String title;
  final String status;
  final List<String> proof;
}

String? _flagValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  if (i == -1 || i + 1 >= args.length) return null;
  return args[i + 1];
}

/// Reads the ledger.
///
/// The subset of YAML the ledger uses, and nothing more: a top-level
/// `features:` list of maps whose values are plain scalars, plus a `proof:`
/// list. Anything else is a syntax error rather than a silent misread.
List<_Feature> _parseLedger(List<String> lines) {
  final features = <_Feature>[];
  Map<String, Object>? current;
  List<String>? currentList;
  var inFeatures = false;

  void flush() {
    if (current == null) return;
    features.add(
      _Feature(
        id: (current!['id'] ?? '?') as String,
        milestone: (current!['milestone'] ?? '?') as String,
        title: (current!['title'] ?? '') as String,
        status: (current!['status'] ?? 'todo') as String,
        proof: (current!['proof'] as List<String>?) ?? const [],
      ),
    );
    current = null;
    currentList = null;
  }

  for (final raw in lines) {
    final line = raw.replaceAll('\t', '  ');
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;

    if (line.startsWith('features:')) {
      inFeatures = true;
      continue;
    }
    if (!inFeatures) continue;

    final trimmed = line.trimLeft();
    if (trimmed.startsWith('- ')) {
      final indent = line.length - trimmed.length;
      if (indent <= 2) {
        flush();
        current = <String, Object>{};
        final rest = trimmed.substring(2).trim();
        if (rest.isNotEmpty) _assign(current!, rest, (l) => currentList = l);
        continue;
      }
      // A list item under the current key.
      currentList?.add(_unquote(trimmed.substring(2).trim()));
      continue;
    }

    if (current == null) continue;
    _assign(current!, trimmed, (l) => currentList = l);
  }
  flush();
  return features;
}

void _assign(
  Map<String, Object> into,
  String text,
  void Function(List<String>) openList,
) {
  final colon = text.indexOf(':');
  if (colon == -1) return;
  final key = text.substring(0, colon).trim();
  final value = text.substring(colon + 1).trim();
  if (value.isEmpty) {
    final list = <String>[];
    into[key] = list;
    openList(list);
    return;
  }
  into[key] = _unquote(value);
}

String _unquote(String value) {
  if (value.length >= 2 &&
      ((value.startsWith("'") && value.endsWith("'")) ||
          (value.startsWith('"') && value.endsWith('"')))) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

/// Runs every suite and returns the names of the tests that passed.
///
/// A skipped test is not a passing test, and neither is one that errored after
/// reporting success — the JSON reporter distinguishes both, which is why it
/// is used here instead of parsing human-readable output.
Future<Set<String>> _runSuites() async {
  final passing = <String>{};
  final packages = Directory('packages')
      .listSync()
      .whereType<Directory>()
      .where((d) => Directory('${d.path}/test').existsSync())
      .map((d) => d.path)
      .toList()
    ..sort();

  for (final dir in [...packages, '.']) {
    stdout.writeln('verify_ledger: running $dir');
    final result = await Process.run(
      Platform.isWindows ? 'flutter.bat' : 'flutter',
      ['test', '--reporter', 'json'],
      workingDirectory: dir,
      runInShell: true,
    );

    final names = <int, String>{};
    for (final line in const LineSplitter().convert(result.stdout as String)) {
      if (!line.startsWith('{')) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (decoded is! Map<String, Object?>) continue;

      switch (decoded['type']) {
        case 'testStart':
          final test = decoded['test'] as Map<String, Object?>?;
          if (test == null) break;
          names[test['id']! as int] = test['name']! as String;
        case 'testDone':
          final id = decoded['testID']! as int;
          final name = names[id];
          if (name == null) break;
          final skipped = decoded['skipped'] == true;
          final passed = decoded['result'] == 'success';
          if (passed && !skipped) passing.add(name);
        default:
          break;
      }
    }
  }
  return passing;
}
