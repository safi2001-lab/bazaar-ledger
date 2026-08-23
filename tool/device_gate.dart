// Is there a device to run the acceptance suite on, and if not, say so out loud.
//
//   dart run tool/device_gate.dart
//
// `integration_test/` is the only thing in this project that genuinely needs a
// device — see docs/verification_tiers.md, which lists what each tier proves
// and, more usefully, what it does not.
//
// The reason this exists rather than "just run the tests and see" is that the
// interesting case is the failure: no emulator on the machine. The tempting
// response is to shrug and carry on, and the result is a ledger row that says
// `done` on the strength of a test nobody has ever run. So when there is no
// device this prints the exact YAML to paste into the row, with a date on it,
// and `verify_ledger` treats a deferred row as not-done until somebody either
// runs it or admits it is unproven.

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final devices = _attachedDevices();

  if (devices.isNotEmpty) {
    stdout.writeln('device_gate: ${devices.length} device(s) attached.\n');
    for (final d in devices) {
      stdout.writeln('  $d');
    }
    stdout.writeln(
      '\nRun the acceptance suite:\n'
      '  melos run device\n',
    );
    return;
  }

  final proof = _flagValue(args, '--proof') ?? '<name the proof test>';
  final reason =
      _flagValue(args, '--reason') ?? 'no emulator or handset on this machine';
  final who =
      _flagValue(args, '--by') ??
      Platform.environment['GIT_AUTHOR_EMAIL'] ??
      _gitEmail() ??
      '<your email>';

  // Deliberately UTC and deliberately short. Two weeks is long enough to get
  // a handset and short enough that a deferral cannot quietly become the
  // permanent state of a milestone.
  final today = DateTime.now().toUtc();
  final expires = today.add(const Duration(days: 14));

  stderr.writeln(
    'device_gate: no device or emulator.\n\n'
    'The acceptance suite in integration_test/ cannot run. Nine of the twelve\n'
    'Android gates do not need one — run `melos run android` for those.\n\n'
    'For the two that do, paste this into the ledger row rather than leaving\n'
    'it claiming a proof nobody has run:\n',
  );

  stdout.writeln('    deferred:');
  stdout.writeln('      proof: $proof');
  stdout.writeln('      reason: $reason');
  stdout.writeln('      recorded: ${_date(today)}');
  stdout.writeln('      recorded_by: $who');
  stdout.writeln('      expires: ${_date(expires)}');
  stdout.writeln('');

  stderr.writeln(
    'The row drops out of `done` the moment that lands, so the milestone\n'
    'percentage falls on its own. It expires on ${_date(expires)}, and CI\n'
    'never passes --allow-deferred.',
  );
  exit(1);
}

/// Everything `adb` can see, minus the header line and the offline ones.
List<String> _attachedDevices() {
  final ProcessResult result;
  try {
    result = Process.runSync(
      'adb',
      const ['devices', '-l'],
      runInShell: true,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  } on ProcessException {
    // No adb at all. Reported as "no device" rather than as an error: the
    // answer to the question being asked is the same.
    return const [];
  }
  if (result.exitCode != 0) return const [];

  return const LineSplitter()
      .convert(result.stdout as String)
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .where((l) => !l.startsWith('List of devices'))
      .where((l) => !l.contains('offline'))
      .where((l) => !l.contains('unauthorized'))
      .toList();
}

String? _gitEmail() {
  try {
    final result = Process.runSync(
      'git',
      const ['config', 'user.email'],
      runInShell: true,
      stdoutEncoding: utf8,
    );
    if (result.exitCode != 0) return null;
    final email = (result.stdout as String).trim();
    return email.isEmpty ? null : email;
  } on ProcessException {
    return null;
  }
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String? _flagValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  if (i == -1 || i + 1 >= args.length) return null;
  return args[i + 1];
}
