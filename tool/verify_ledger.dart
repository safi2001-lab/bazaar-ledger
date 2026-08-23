// The anti-lie gate.
//
// `docs/feature_ledger.yaml` carries one row per feature. A row may say
// `status: done` only if `proof` names a test that exists, is not skipped, and
// passed in the run that checked it. This script runs the suites, collects the
// names of the tests that actually passed, and fails the build if any claim is
// unsupported.
//
// The rule it enforces: a commit may not say "Complete Milestone N" unless this
// script printed 100% for N. Under that rule the previous build's five commits,
// each announcing a completed sprint, would have printed about 18% and been
// rejected — which is the number an audit later put on them.
//
// ---------------------------------------------------------------------------
// Why this file was rewritten, which is the more useful thing to know.
//
// The gate above worked exactly as designed and still failed to do its job. It
// scored each milestone that HAD rows in the ledger. Every one of the fifty
// rows said `milestone: M0`. So M1 through M14 had no denominator, could not be
// measured, and were never printed — and eight commits announcing M1 and M2
// work passed a gate that was never asked the question.
//
// The gate was not defeated. It was bypassed by not being fed. A rule that
// depends on somebody remembering to write the row is not a rule, it is a
// habit, and habits are what this project keeps proving it cannot rely on.
//
// So the ledger now declares every milestone up front, and this script checks
// six things instead of one:
//
//   R1  every row names a milestone the ledger declares
//   R2  every milestone that is `open` or `sealed` has at least one row
//   R3  every `done` row's proofs passed, unskipped, in this run   (the original)
//   R4  every changed Dart file falls under some milestone's `owns`, and none
//       falls under a milestone still `planned`
//   R5  a commit subject naming M<n> requires M<n> declared and open; a subject
//       also saying complete/done/finished requires M<n> at 100%
//   R6  no two milestones declare the same ownership pattern
//
// R2 is the one that would have caught the failure above: M1 now prints its
// real percentage from the day it is declared, rather than being absent.
//
//   dart run tool/verify_ledger.dart               verify everything
//   dart run tool/verify_ledger.dart --milestone M1
//   dart run tool/verify_ledger.dart --offline      parse only, run nothing
//   dart run tool/verify_ledger.dart --offline --strict   shape rules only, fast
//   dart run tool/verify_ledger.dart --device       also run integration_test/
//   dart run tool/verify_ledger.dart --allow-deferred     local escape, never CI
//
// The YAML is read with a small hand-rolled parser rather than a package, for
// the same reason `arch_check` has no dependencies: a gate that can be disabled
// by a version bump is not a gate.

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final onlyMilestone = _flagValue(args, '--milestone');
  final offline = args.contains('--offline');
  final strict = args.contains('--strict');
  final device = args.contains('--device');
  final allowDeferred = args.contains('--allow-deferred');
  final range = _flagValue(args, '--range');

  // Overridable so the rules can be tested against fixtures. A gate that
  // cannot be pointed at a ledger it should reject is a gate nobody has ever
  // watched fail, and `arch_check` is in this repository precisely because six
  // of its twelve rules turned out to be silently inert.
  final ledgerPath = _flagValue(args, '--ledger') ?? 'docs/feature_ledger.yaml';
  final ledgerFile = File(ledgerPath);
  if (!ledgerFile.existsSync()) {
    stderr.writeln('verify_ledger: $ledgerPath is missing.');
    exit(1);
  }

  final _Ledger ledger;
  try {
    ledger = _parseLedger(ledgerFile.readAsLinesSync());
  } on FormatException catch (error) {
    stderr.writeln('verify_ledger: ${error.message}');
    exit(1);
  }

  if (ledger.milestones.isEmpty) {
    stderr.writeln(
      'verify_ledger: the ledger declares no milestones. Without a '
      '`milestones:` block a milestone with no rows is invisible, which is '
      'the exact hole this file was rewritten to close.',
    );
    exit(1);
  }

  final scoped = onlyMilestone == null
      ? ledger.features
      : ledger.features.where((f) => f.milestone == onlyMilestone).toList();

  if (scoped.isEmpty && onlyMilestone != null) {
    stderr.writeln('verify_ledger: no features matched $onlyMilestone.');
    exit(1);
  }

  final problems = <String>[];

  // R1, R2, R6 — the shape of the ledger, checked without running anything.
  problems.addAll(_checkDeclarations(ledger));

  // R4, R5 — what this working tree and these commits actually claim.
  final changed = _changedDartFiles(range);
  if (changed == null) {
    stdout.writeln(
      'verify_ledger: no git range available; R4 (file ownership) and '
      'R5 (commit claims) were NOT checked.',
    );
  } else {
    problems.addAll(_checkOwnership(ledger, changed));
    problems.addAll(_checkCommitClaims(ledger, range));
  }

  // Deferrals, before anything is run, because a deferred row is not done and
  // its milestone's percentage must fall to say so.
  final deferrals = scoped.where((f) => f.deferred != null).toList();
  if (deferrals.isNotEmpty) {
    stdout.writeln('verify_ledger: DEFERRED (${deferrals.length})\n');
    for (final f in deferrals) {
      final d = f.deferred!;
      stdout.writeln('  ${f.id}  ${d['proof'] ?? '?'}');
      stdout.writeln('      reason:  ${d['reason'] ?? '?'}');
      stdout.writeln(
        '      recorded ${d['recorded'] ?? '?'} '
        'by ${d['recorded_by'] ?? '?'}, expires ${d['expires'] ?? '?'}',
      );
    }
    stdout.writeln('');
    problems.addAll(_checkDeferrals(deferrals, allowDeferred));
  }

  if (offline && strict) {
    _report(ledger, scoped, problems, ran: false);
    return;
  }

  final passing = offline ? <String>{} : await _runSuites(device: device);

  // R3 — the original rule, unchanged.
  for (final feature in scoped.where((f) => f.effectiveStatus == 'done')) {
    final claims = [...feature.proof, if (device) ...feature.deviceProof];
    if (claims.isEmpty) {
      problems.add('${feature.id}: marked done with no proof.');
      continue;
    }
    if (offline) continue;
    for (final proof in claims) {
      if (!passing.contains(proof)) {
        problems.add('${feature.id}: proof "$proof" did not pass in this run.');
      }
    }
  }

  // A device run must actually name device proofs somewhere, or `--device` is
  // a flag that reports success for checking nothing.
  if (device && !offline) {
    final named = ledger.features.expand((f) => f.deviceProof).length;
    if (named == 0) {
      problems.add(
        'no ledger row names a device_proof, so --device verified nothing. '
        'The integration suite is the acceptance gate; if it proves something, '
        'a row should say so.',
      );
    }
  }

  _report(ledger, scoped, problems, ran: !offline);
}

// ---------------------------------------------------------------------------
// Rules
// ---------------------------------------------------------------------------

/// R1, R2 and R6: the ledger describes a complete, unambiguous plan.
List<String> _checkDeclarations(_Ledger ledger) {
  final problems = <String>[];
  final declared = {for (final m in ledger.milestones) m.id: m};

  // R1 — a row may not name a milestone nobody declared.
  for (final f in ledger.features) {
    if (!declared.containsKey(f.milestone)) {
      problems.add(
        '${f.id}: names milestone ${f.milestone}, which the ledger does not '
        'declare. Add it to `milestones:` so it can be measured.',
      );
    }
  }

  // R2 — an open or sealed milestone with no rows is unmeasurable, and an
  // unmeasurable milestone is exactly how M1 and M2 shipped unchecked.
  final counts = <String, int>{};
  for (final f in ledger.features) {
    counts[f.milestone] = (counts[f.milestone] ?? 0) + 1;
  }
  for (final m in ledger.milestones) {
    if (m.state == 'planned') continue;
    if ((counts[m.id] ?? 0) == 0) {
      problems.add(
        '${m.id}: declared ${m.state} with no feature rows. A milestone with '
        'no rows scores nothing and is never printed, so nothing can '
        'contradict a commit that claims it.',
      );
    }
  }

  // R6 — the same pattern under two milestones makes ownership ambiguous, and
  // is nearly always a copied line somebody forgot to edit.
  final seen = <String, String>{};
  for (final m in ledger.milestones) {
    for (final pattern in m.owns) {
      final previous = seen[pattern];
      if (previous != null) {
        problems.add(
          'ownership of "$pattern" is claimed by both $previous and ${m.id}.',
        );
      }
      seen[pattern] = m.id;
    }
  }

  for (final m in ledger.milestones) {
    if (!const {'planned', 'open', 'sealed'}.contains(m.state)) {
      problems.add(
        '${m.id}: state "${m.state}" is not one of planned, open, sealed.',
      );
    }
  }

  return problems;
}

/// R4: every changed source file belongs to a milestone that has opened.
///
/// The failure this catches is writing M7 code during M2 — which is how a
/// milestone's scope quietly becomes whatever happened to get built.
List<String> _checkOwnership(_Ledger ledger, List<String> changed) {
  final problems = <String>[];
  for (final path in changed) {
    final owners = ledger.milestones
        .where((m) => m.owns.any((pattern) => _globMatches(pattern, path)))
        .toList();

    if (owners.isEmpty) {
      problems.add(
        '$path changed and no milestone declares it. Add it to a milestone\'s '
        '`owns:` so the work has somewhere to be counted.',
      );
      continue;
    }
    // Most specific wins: the longest matching pattern is the one that meant
    // it. `packages/**` and `packages/pk_platform/lib/src/printing/**` can
    // both be right, and only the second one says anything useful.
    int best(_Milestone m) => m.owns
        .where((p) => _globMatches(p, path))
        .map((p) => p.length)
        .reduce((x, y) => x > y ? x : y);
    owners.sort((a, b) => best(b).compareTo(best(a)));

    final owner = owners.first;
    if (owner.state == 'planned') {
      problems.add(
        '$path belongs to ${owner.id}, which is still `planned`. Either open '
        'the milestone and give it rows, or this change belongs elsewhere.',
      );
    }
  }
  return problems;
}

/// R5: a commit may not name a milestone it has no standing to name.
List<String> _checkCommitClaims(_Ledger ledger, String? range) {
  final problems = <String>[];
  final subjects = _commitSubjects(range);
  if (subjects.isEmpty) return problems;

  final declared = {for (final m in ledger.milestones) m.id: m};
  final counts = <String, List<_Feature>>{};
  for (final f in ledger.features) {
    counts.putIfAbsent(f.milestone, () => []).add(f);
  }

  // Both spellings. `M2:` is this project's convention; `Complete Milestone 2`
  // is what the previous build wrote across five commits, and a rule that only
  // knew the current convention would have let every one of them past.
  final claim = RegExp(
    r'\bM(\d+)\b|\bMilestone\s+(\d+)\b',
    caseSensitive: false,
  );
  final completion = RegExp(
    r'\b(complete|completes|completed|done|finish|finished)\b',
    caseSensitive: false,
  );

  for (final entry in subjects.entries) {
    final match = claim.firstMatch(entry.value);
    if (match == null) continue;
    final id = 'M${match.group(1) ?? match.group(2)}';
    final milestone = declared[id];

    if (milestone == null) {
      problems.add(
        'commit ${entry.key} claims $id, which the ledger does not declare.',
      );
      continue;
    }
    if (milestone.state == 'planned') {
      problems.add('commit ${entry.key} claims $id, which is still `planned`.');
      continue;
    }
    if (!completion.hasMatch(entry.value)) continue;

    final rows = counts[id] ?? const <_Feature>[];
    final complete = rows.where((f) => f.effectiveStatus == 'done').length;
    if (rows.isEmpty || complete != rows.length) {
      final percent = rows.isEmpty ? 0 : (complete * 100 / rows.length).floor();
      problems.add(
        'commit ${entry.key} says $id is complete; the ledger says '
        '$percent% ($complete/${rows.length}).',
      );
    }
  }
  return problems;
}

/// A deferral is a local convenience with a fuse, never a way through the gate.
List<String> _checkDeferrals(List<_Feature> deferrals, bool allowDeferred) {
  final problems = <String>[];
  final today = DateTime.now().toUtc();

  for (final f in deferrals) {
    final d = f.deferred!;
    for (final key in const ['proof', 'reason', 'recorded', 'expires']) {
      if ((d[key] ?? '').isEmpty) {
        problems.add('${f.id}: deferred without a `$key`.');
      }
    }
    final expires = DateTime.tryParse(d['expires'] ?? '');
    if (expires == null) {
      if ((d['expires'] ?? '').isNotEmpty) {
        problems.add('${f.id}: deferred `expires` is not a date.');
      }
    } else if (expires.isBefore(today)) {
      problems.add(
        '${f.id}: the deferral expired on ${d['expires']}. Run it on a device '
        'or say plainly that it is not proved.',
      );
    }
  }

  if (!allowDeferred) {
    problems.add(
      '${deferrals.length} deferred proof(s). CI never passes '
      '--allow-deferred: a deferral is for a developer without a device this '
      'afternoon, not for a release.',
    );
  }
  return problems;
}

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

void _report(
  _Ledger ledger,
  List<_Feature> scoped,
  List<String> problems, {
  required bool ran,
}) {
  final byMilestone = <String, List<_Feature>>{};
  for (final f in scoped) {
    byMilestone.putIfAbsent(f.milestone, () => []).add(f);
  }

  stdout.writeln('verify_ledger: ${scoped.length} features\n');

  // Every declared milestone is printed, including the ones with no rows yet.
  // A milestone absent from this list is a milestone nobody is measuring, and
  // that is the thing this file exists to make impossible.
  for (final m in ledger.milestones) {
    final rows = byMilestone[m.id] ?? const <_Feature>[];
    if (rows.isEmpty) {
      stdout.writeln(
        '  ${m.id.padRight(3)}     —  ${m.state.padRight(7)}  ${m.title}',
      );
      continue;
    }
    final complete = rows.where((f) => f.effectiveStatus == 'done').length;
    final percent = (complete * 100 / rows.length).floor();
    stdout.writeln(
      '  ${m.id.padRight(3)}  ${percent.toString().padLeft(3)}%  '
      '${m.state.padRight(7)}  $complete/${rows.length} done  ·  ${m.title}',
    );
  }

  if (problems.isEmpty) {
    stdout.writeln(
      ran
          ? '\nverify_ledger: every completed feature has a passing proof.'
          : '\nverify_ledger: the ledger holds together; nothing was run.',
    );
    return;
  }

  stderr.writeln('\nverify_ledger: ${problems.length} unsupported claim(s):');
  for (final p in problems) {
    stderr.writeln('  $p');
  }
  stderr.writeln('\nA feature is done when a test proves it, and not before.');
  exit(1);
}

// ---------------------------------------------------------------------------
// Git
// ---------------------------------------------------------------------------

/// The Dart files this branch changed, or null when git cannot say.
///
/// Null is reported to the user rather than treated as "nothing changed",
/// because a silent empty list would turn R4 and R5 into rules that always
/// pass — another green tick guaranteeing nothing.
List<String>? _changedDartFiles(String? range) {
  final resolved = range ?? _defaultRange();
  if (resolved == null) return null;

  final result = _git(['diff', '--name-only', resolved]);
  if (result == null) return null;

  return const LineSplitter()
      .convert(result)
      .map((l) => l.trim().replaceAll(r'\', '/'))
      .where((l) => l.endsWith('.dart'))
      .where((l) => l.startsWith('lib/') || l.startsWith('packages/'))
      .where((l) => !l.endsWith('.g.dart') && !l.endsWith('.drift.dart'))
      .where((l) => !l.contains('/test/'))
      .toList();
}

String? _defaultRange() {
  for (final base in const ['origin/main', 'origin/master', 'main', 'master']) {
    final mergeBase = _git(['merge-base', base, 'HEAD'])?.trim();
    if (mergeBase != null && mergeBase.isNotEmpty) return '$mergeBase..HEAD';
  }
  // A shallow checkout, or a repository with one commit.
  final parent = _git(['rev-parse', 'HEAD~1'])?.trim();
  if (parent != null && parent.isNotEmpty) return 'HEAD~1..HEAD';
  return null;
}

Map<String, String> _commitSubjects(String? range) {
  final resolved = range ?? _defaultRange();
  if (resolved == null) return const {};
  final log = _git(['log', '--format=%h%x09%s', resolved]);
  if (log == null) return const {};

  final subjects = <String, String>{};
  for (final line in const LineSplitter().convert(log)) {
    final tab = line.indexOf('\t');
    if (tab == -1) continue;
    subjects[line.substring(0, tab)] = line.substring(tab + 1);
  }
  return subjects;
}

String? _git(List<String> args) {
  try {
    final result = Process.runSync(
      'git',
      args,
      runInShell: true,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (result.exitCode != 0) return null;
    return result.stdout as String;
  } on ProcessException {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Globs
// ---------------------------------------------------------------------------

/// The subset of glob the ledger uses: `**` spans separators, `*` does not.
bool _globMatches(String pattern, String path) {
  final buffer = StringBuffer('^');
  var i = 0;
  while (i < pattern.length) {
    final char = pattern[i];
    if (char == '*') {
      if (i + 1 < pattern.length && pattern[i + 1] == '*') {
        buffer.write('.*');
        i += 2;
        // `a/**/b` should also match `a/b`, so swallow the separator that
        // follows a double star.
        if (i < pattern.length && pattern[i] == '/') i += 1;
        continue;
      }
      buffer.write('[^/]*');
      i += 1;
      continue;
    }
    buffer.write(RegExp.escape(char));
    i += 1;
  }
  buffer.write(r'$');
  return RegExp(buffer.toString()).hasMatch(path);
}

// ---------------------------------------------------------------------------
// The ledger
// ---------------------------------------------------------------------------

final class _Ledger {
  const _Ledger({required this.milestones, required this.features});

  final List<_Milestone> milestones;
  final List<_Feature> features;
}

final class _Milestone {
  const _Milestone({
    required this.id,
    required this.title,
    required this.state,
    required this.owns,
  });

  final String id;
  final String title;

  /// planned — declared, not started. open — being built. sealed — finished.
  final String state;

  /// Path globs this milestone is responsible for.
  final List<String> owns;
}

final class _Feature {
  const _Feature({
    required this.id,
    required this.milestone,
    required this.title,
    required this.status,
    required this.proof,
    required this.deviceProof,
    required this.deferred,
  });

  final String id;
  final String milestone;
  final String title;
  final String status;
  final List<String> proof;
  final List<String> deviceProof;
  final Map<String, String>? deferred;

  /// A deferred row is not a done row.
  ///
  /// Demoting it here rather than reporting it separately is deliberate: the
  /// milestone percentage falls the moment a proof is deferred, so the number
  /// in a status report drops on its own without anybody choosing to mention
  /// it.
  String get effectiveStatus =>
      deferred != null && status == 'done' ? 'wip' : status;
}

/// Reads the ledger.
///
/// The subset of YAML the ledger uses and nothing more: two top-level lists of
/// maps, scalar values, block lists, and one level of nested map (`deferred:`).
/// Anything else is a syntax error rather than a silent misread.
_Ledger _parseLedger(List<String> lines) {
  final milestones = <Map<String, Object>>[];
  final features = <Map<String, Object>>[];

  List<Map<String, Object>>? section;
  Map<String, Object>? current;
  List<String>? openList;
  Map<String, String>? openMap;
  var openMapIndent = -1;

  void closeNested() {
    openList = null;
    openMap = null;
    openMapIndent = -1;
  }

  for (var lineNo = 0; lineNo < lines.length; lineNo++) {
    final line = lines[lineNo].replaceAll('\t', '  ');
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;

    if (line.startsWith('milestones:')) {
      section = milestones;
      current = null;
      closeNested();
      continue;
    }
    if (line.startsWith('features:')) {
      section = features;
      current = null;
      closeNested();
      continue;
    }
    if (section == null) continue;

    final trimmed = line.trimLeft();
    final indent = line.length - trimmed.length;

    if (trimmed.startsWith('- ')) {
      if (indent <= 2) {
        current = <String, Object>{};
        section.add(current);
        closeNested();
        final rest = trimmed.substring(2).trim();
        if (rest.isNotEmpty) {
          _assign(current, rest, lineNo, (l) => openList = l);
        }
        continue;
      }
      if (openList == null) {
        throw FormatException(
          'line ${lineNo + 1}: a list item with nothing to belong to.',
        );
      }
      openList!.add(_unquote(trimmed.substring(2).trim()));
      continue;
    }

    if (current == null) {
      throw FormatException('line ${lineNo + 1}: a key outside any list entry.');
    }

    // A key indented under an open nested map belongs to it.
    if (openMap != null && indent > openMapIndent) {
      final colon = trimmed.indexOf(':');
      if (colon == -1) {
        throw FormatException('line ${lineNo + 1}: expected `key: value`.');
      }
      openMap![trimmed.substring(0, colon).trim()] = _unquote(
        trimmed.substring(colon + 1).trim(),
      );
      continue;
    }

    closeNested();
    _assign(
      current,
      trimmed,
      lineNo,
      (l) => openList = l,
      (m, i) {
        openMap = m;
        openMapIndent = i;
      },
      indent,
    );
  }

  return _Ledger(
    milestones: [
      for (final m in milestones)
        _Milestone(
          id: (m['id'] ?? '?') as String,
          title: (m['title'] ?? '') as String,
          state: (m['state'] ?? 'planned') as String,
          owns: (m['owns'] as List<String>?) ?? const [],
        ),
    ],
    features: [
      for (final f in features)
        _Feature(
          id: (f['id'] ?? '?') as String,
          milestone: (f['milestone'] ?? '?') as String,
          title: (f['title'] ?? '') as String,
          status: (f['status'] ?? 'todo') as String,
          proof: (f['proof'] as List<String>?) ?? const [],
          deviceProof: (f['device_proof'] as List<String>?) ?? const [],
          deferred: f['deferred'] as Map<String, String>?,
        ),
    ],
  );
}

void _assign(
  Map<String, Object> into,
  String text,
  int lineNo,
  void Function(List<String>) openList, [
  void Function(Map<String, String>, int)? openMap,
  int indent = 0,
]) {
  final colon = text.indexOf(':');
  if (colon == -1) {
    throw FormatException('line ${lineNo + 1}: expected `key: value`.');
  }
  final key = text.substring(0, colon).trim();
  final value = text.substring(colon + 1).trim();

  if (key == 'deferred' && value.isEmpty && openMap != null) {
    final map = <String, String>{};
    into[key] = map;
    openMap(map, indent);
    return;
  }
  if (value.isEmpty || value == '[]') {
    // `proof:` on its own opens a block list; `proof: []` is an explicit empty
    // one. Both mean the same thing here: nothing proves this yet.
    final list = <String>[];
    into[key] = list;
    openList(value.isEmpty ? list : <String>[]);
    return;
  }
  // `deferred: null` is the ordinary state of a row and carries no map.
  if (value == 'null' || value == '~') return;
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
/// reporting success — the JSON reporter distinguishes both, which is why it is
/// used here instead of parsing human-readable output.
Future<Set<String>> _runSuites({bool device = false}) async {
  final passing = <String>{};
  final packages = Directory('packages')
      .listSync()
      .whereType<Directory>()
      .where((d) => Directory('${d.path}/test').existsSync())
      .map((d) => d.path)
      .toList()
    ..sort();

  final runs = <(String, List<String>)>[
    for (final dir in packages) (dir, const ['test', '--reporter', 'json']),
    ('.', const ['test', '--reporter', 'json']),
    // `flutter test` in the root defaults to test/ and has never once run the
    // integration suite. Naming the directory is what makes --device mean
    // something.
    if (device) ('.', const ['test', 'integration_test', '--reporter', 'json']),
  ];

  for (final (dir, args) in runs) {
    stdout.writeln('verify_ledger: running $dir ${args.join(' ')}');
    final result = await Process.run(
      Platform.isWindows ? 'flutter.bat' : 'flutter',
      args,
      workingDirectory: dir,
      runInShell: true,
      // UTF-8, explicitly. The default is the system encoding, which on Windows
      // is a code page that turns every em dash in a test name into mojibake —
      // so a proof whose name contains one silently fails to match and the gate
      // reports a passing test as missing.
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
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

String? _flagValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  if (i == -1 || i + 1 >= args.length) return null;
  return args[i + 1];
}
