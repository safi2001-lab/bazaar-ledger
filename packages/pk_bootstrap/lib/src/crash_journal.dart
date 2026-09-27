import 'dart:convert';
import 'dart:io';

import 'package:pk_domain/pk_domain.dart';

/// One error the app did not handle.
final class CrashEntry {
  const CrashEntry({
    required this.at,
    required this.error,
    required this.stack,
  });

  final DateTime at;
  final String error;

  /// The first frames only: enough to find the line, small enough to keep.
  final String stack;
}

/// Errors the app did not handle, kept on this phone and nowhere else.
///
/// There is no crash reporter: sending one would mean a server, and this app
/// has none. So what went wrong is written here, beside the books, where
/// Data Health shows it and the shopkeeper can read it out to whoever is
/// helping them. The last [keep] are kept; older ones fall off.
final class CrashJournal {
  CrashJournal(this.file, {this.keep = 50, this.clock = const SystemClock()});

  final File file;
  final int keep;
  final Clock clock;

  /// Records [error]. Never throws: it runs inside the error handler, and an
  /// error there is an error nobody hears about.
  void record(Object error, StackTrace? stack) {
    try {
      final all = [
        ...entries(),
        CrashEntry(
          at: clock.nowUtc(),
          error: _clip('$error', 500),
          stack: (stack?.toString() ?? '').split('\n').take(12).join('\n'),
        ),
      ];
      final kept = all.length > keep ? all.sublist(all.length - keep) : all;
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('${kept.map(_encode).join('\n')}\n', flush: true);
    } on Object {
      // Nothing to be done from inside the error handler.
    }
  }

  /// What was recorded, oldest first.
  List<CrashEntry> entries() {
    try {
      if (!file.existsSync()) return const [];
      return [for (final line in file.readAsLinesSync()) ?_decode(line)];
    } on Object {
      return const [];
    }
  }

  void clear() {
    try {
      if (file.existsSync()) file.deleteSync();
    } on Object {
      // Left for next time.
    }
  }

  static String _clip(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  static String _encode(CrashEntry e) => jsonEncode({
    'at': e.at.toUtc().millisecondsSinceEpoch,
    'error': e.error,
    'stack': e.stack,
  });

  static CrashEntry? _decode(String line) {
    try {
      final json = jsonDecode(line);
      if (json is! Map<String, Object?>) return null;
      return CrashEntry(
        at: DateTime.fromMillisecondsSinceEpoch(
          json['at']! as int,
          isUtc: true,
        ),
        error: json['error']! as String,
        stack: json['stack']! as String,
      );
    } on Object {
      // A line half-written when the phone died is skipped, not fatal.
      return null;
    }
  }
}
