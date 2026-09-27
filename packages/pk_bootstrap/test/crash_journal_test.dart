import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('crashes'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('crash journal', () {
    test('an error the app did not handle is kept on the phone', () {
      final journal = CrashJournal(File('${dir.path}/crashes.jsonl'));
      journal.record(StateError('the printer vanished'), StackTrace.current);

      final again = CrashJournal(File('${dir.path}/crashes.jsonl'));
      final [entry] = again.entries();
      expect(entry.error, contains('the printer vanished'));
      expect(entry.stack, isNotEmpty);
    });

    test('only the last ones are kept, and a torn line is skipped', () {
      final file = File('${dir.path}/crashes.jsonl');
      final journal = CrashJournal(file, keep: 3);
      for (var i = 1; i <= 5; i++) {
        journal.record('error $i', null);
      }
      file.writeAsStringSync('{"at": 1, "err', mode: FileMode.append);
      expect(journal.entries().map((e) => e.error), [
        'error 3',
        'error 4',
        'error 5',
      ]);
      journal.clear();
      expect(journal.entries(), isEmpty);
    });

    test('a journal that cannot be written does not throw', () {
      final journal = CrashJournal(File('${dir.path}/no/such\u0000/file'));
      expect(() => journal.record('boom', null), returnsNormally);
      expect(journal.entries(), isEmpty);
    });
  });
}
