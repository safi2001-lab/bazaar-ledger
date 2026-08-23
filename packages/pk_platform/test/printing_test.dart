import 'dart:async';
import 'dart:io';

import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:test/test.dart';

/// Getting a receipt onto paper, and never twice.
///
/// The TCP tests run against a real `ServerSocket` on loopback rather than a
/// mock, because what is being tested IS the socket handling — the chunking,
/// the flush, the close — and a mock of a socket would only assert that the
/// code calls the methods it calls.
///
/// The queue tests are about one rule, and it is the rule the obvious
/// implementation gets wrong: a print that failed part way through must never
/// be retried on its own. A thermal printer has no memory and no job
/// identity. Asked twice it prints twice, so a queue that retries on any
/// failure quietly hands out two of every long bill on a flaky shop network.
void main() {
  group('a printer on the shop wi-fi', () {
    late ServerSocket server;
    late List<int> received;
    late PrinterTarget target;

    setUp(() async {
      received = [];
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      target = PrinterTarget(
        kind: 'tcp',
        address: '127.0.0.1:${server.port}',
        name: 'Test printer',
      );
      server.listen((socket) {
        socket.listen(received.addAll, onDone: socket.destroy);
      });
    });

    tearDown(() async => server.close());

    test('takes every byte of the receipt, in order', () async {
      // A real receipt's worth: longer than the 1024-byte chunk, so the
      // chunking is genuinely exercised rather than skipped.
      final bytes = [for (var i = 0; i < 5000; i++) i % 251];

      await const TcpPrinter().send(target, bytes);
      await _settle();

      expect(received, hasLength(bytes.length));
      expect(
        received,
        bytes,
        reason:
            'the printer was handed different bytes than it was given, '
            'which on a real machine is a receipt with its middle missing',
      );
    });

    test('an unreachable printer is safe to try again', () async {
      // Nothing came out, so nobody can tell. This is the one case where a
      // silent retry is the right thing.
      await server.close();
      final unreachable = PrinterTarget(
        kind: 'tcp',
        address: '127.0.0.1:${server.port}',
        name: 'Gone',
      );

      await expectLater(
        const TcpPrinter(
          connectTimeout: Duration(milliseconds: 300),
        ).send(unreachable, [1, 2, 3]),
        throwsA(
          isA<PrinterException>()
              .having((e) => e.isSafeToRetry, 'isSafeToRetry', isTrue)
              .having((e) => e.bytesWritten, 'bytesWritten', 0),
        ),
      );
    });
  });

  group('the queue, and the rule it exists for', () {
    test('one job, printed once, however many times it is asked for', () async {
      final printer = _CountingPrinter();
      final queue = PrintQueue(transport: printer);
      const target = PrinterTarget(kind: 'x', address: 'a', name: 'A');

      // A double-tapped Print button, and a rebuilt widget asking again.
      final results = await Future.wait([
        queue.submit(jobId: 'INV-0001', target: target, bytes: [1]),
        queue.submit(jobId: 'INV-0001', target: target, bytes: [1]),
        queue.submit(jobId: 'INV-0001', target: target, bytes: [1]),
      ]);

      expect(results.every((r) => r.ok), isTrue);
      expect(
        printer.sends,
        1,
        reason:
            'the customer was handed ${printer.sends} receipts for one '
            'sale, and the shop has ${printer.sends} records of it',
      );
    });

    test('a print that failed part way is never retried on its own', () async {
      // The whole point. Paper has already moved; a silent retry produces two
      // half-receipts and the shopkeeper cannot tell which is which.
      final printer = _FailingPrinter(
        const PrinterException('cable pulled', bytesWritten: 512),
      );
      final queue = PrintQueue(transport: printer, maxAttempts: 3);

      final result = await queue.submit(
        jobId: 'INV-0002',
        target: const PrinterTarget(kind: 'x', address: 'a', name: 'A'),
        bytes: [1],
      );

      expect(result.outcome, PrintOutcome.partial);
      expect(result.mayRetryAutomatically, isFalse);
      expect(
        printer.sends,
        1,
        reason: 'it tried again after paper had already come out',
      );
    });

    test('a print that never started is retried, and then gives up', () async {
      final printer = _FailingPrinter(const PrinterException('no route'));
      final queue = PrintQueue(
        transport: printer,
        maxAttempts: 3,
        retryDelay: Duration.zero,
      );

      final result = await queue.submit(
        jobId: 'INV-0003',
        target: const PrinterTarget(kind: 'x', address: 'a', name: 'A'),
        bytes: [1],
      );

      expect(result.outcome, PrintOutcome.notSent);
      expect(printer.sends, 3);
      expect(
        result.mayRetryAutomatically,
        isTrue,
        reason: 'nothing came out, so the counter may offer to try again',
      );
    });

    test(
      'a transport that throws something unexpected is treated as partial',
      () async {
        // A transport that threw something other than PrinterException has not
        // told us whether paper moved. Assuming the safe case here is how a bug
        // in a transport becomes a double-printed bill.
        final printer = _FailingPrinter(StateError('bug in the transport'));
        final queue = PrintQueue(transport: printer, retryDelay: Duration.zero);

        final result = await queue.submit(
          jobId: 'INV-0004',
          target: const PrinterTarget(kind: 'x', address: 'a', name: 'A'),
          bytes: [1],
        );

        expect(result.outcome, PrintOutcome.partial);
        expect(printer.sends, 1);
      },
    );

    test('jobs go out one at a time', () async {
      // Two receipts sent at once to a printer with a small buffer come out
      // interleaved, which is worse than either coming out late.
      final printer = _CountingPrinter(delay: const Duration(milliseconds: 20));
      final queue = PrintQueue(transport: printer);
      const target = PrinterTarget(kind: 'x', address: 'a', name: 'A');

      await Future.wait([
        for (var i = 0; i < 4; i++)
          queue.submit(jobId: 'INV-$i', target: target, bytes: [i]),
      ]);

      expect(printer.sends, 4);
      expect(
        printer.maxConcurrent,
        1,
        reason: 'two receipts were on the wire at once',
      );
    });

    test(
      'a reprint is a deliberate act and goes through a different door',
      () async {
        final printer = _CountingPrinter();
        final queue = PrintQueue(transport: printer);
        const target = PrinterTarget(kind: 'x', address: 'a', name: 'A');

        await queue.submit(jobId: 'INV-0005', target: target, bytes: [1]);
        expect(queue.hasPrinted('INV-0005'), isTrue);

        // The shopkeeper can see whether the first one came out, and asks for
        // another. That is not the queue retrying; it is a person deciding.
        queue.forget('INV-0005');
        await queue.submit(jobId: 'INV-0005', target: target, bytes: [1]);

        expect(printer.sends, 2);
      },
    );
  });
  group('the record that outlives the process', () {
    test(
      'a half-printed job is not sent again when it is asked for twice',
      () async {
        // The defect this group was written for. `submit` short-circuited only
        // on `printed`, so a job that ended `partial` was stored and then
        // RE-SENT on the next ask — from a rebuilt widget, or a shopkeeper
        // tapping again after seeing a failure. Paper had already moved once.
        final printer = _FailingPrinter(
          const PrinterException('cable pulled', bytesWritten: 512),
        );
        final queue = PrintQueue(transport: printer, retryDelay: Duration.zero);
        const target = PrinterTarget(kind: 'x', address: 'a', name: 'A');

        final first = await queue.submit(
          jobId: 'INV-0100',
          target: target,
          bytes: [1],
        );
        final second = await queue.submit(
          jobId: 'INV-0100',
          target: target,
          bytes: [1],
        );

        expect(first.outcome, PrintOutcome.partial);
        expect(second.outcome, PrintOutcome.partial);
        expect(
          printer.sends,
          1,
          reason:
              'the customer was handed a second half-receipt for a bill '
              'that had already partly printed',
        );
      },
    );

    test('a job that never started may still be asked for again', () async {
      // The other side of the same rule. Nothing came out, so a shopkeeper
      // pressing Print again must reach the printer rather than be told about
      // a failure that left no paper.
      final printer = _EventuallyWorkingPrinter(failuresBeforeSuccess: 1);
      final queue = PrintQueue(
        transport: printer,
        maxAttempts: 1,
        retryDelay: Duration.zero,
      );
      const target = PrinterTarget(kind: 'x', address: 'a', name: 'A');

      final first = await queue.submit(
        jobId: 'INV-0101',
        target: target,
        bytes: [1],
      );
      expect(first.outcome, PrintOutcome.notSent);

      final second = await queue.submit(
        jobId: 'INV-0101',
        target: target,
        bytes: [1],
      );
      expect(second.outcome, PrintOutcome.printed);
      expect(printer.sends, 2);
    });

    test(
      'a job the log says already printed never reaches the printer',
      () async {
        // The kill-survival case, and the whole reason the record is in a
        // database. The in-memory maps are empty here because this queue is a
        // fresh object — exactly as it would be after Android reclaimed the app.
        final printer = _CountingPrinter();
        final log = _FakeLog()
          ..records['INV-0102'] = const PrintJobRecord(
            jobKey: 'INV-0102',
            status: PrintJobStatus.printed,
            bytesWritten: 900,
            byteCount: 900,
            copyIndex: 1,
          );
        final queue = PrintQueue(transport: printer, log: log);

        final result = await queue.submit(
          jobId: 'INV-0102',
          target: const PrinterTarget(kind: 'x', address: 'a', name: 'A'),
          bytes: [1],
          actor: _actor,
        );

        expect(result.outcome, PrintOutcome.printed);
        expect(
          printer.sends,
          0,
          reason:
              'a receipt that was printed before the app was killed came '
              'out a second time',
        );
      },
    );

    test(
      'a job left mid-flight by a process death reports unknown, not lost',
      () async {
        // A row still saying `sending` means the app died holding the job. Paper
        // may have moved. The only honest answer is that nobody knows, and the
        // only safe action is to ask a person.
        final printer = _CountingPrinter();
        final log = _FakeLog()
          ..records['INV-0103'] = const PrintJobRecord(
            jobKey: 'INV-0103',
            status: PrintJobStatus.sending,
            bytesWritten: 0,
            byteCount: 900,
            copyIndex: 1,
          );
        final queue = PrintQueue(transport: printer, log: log);

        final result = await queue.submit(
          jobId: 'INV-0103',
          target: const PrinterTarget(kind: 'x', address: 'a', name: 'A'),
          bytes: [1],
          actor: _actor,
        );

        expect(result.outcome, PrintOutcome.unknown);
        expect(result.mayRetryAutomatically, isFalse);
        expect(printer.sends, 0);
      },
    );

    test('a job the log says failed outright is sent again', () async {
      final printer = _CountingPrinter();
      final log = _FakeLog()
        ..records['INV-0104'] = const PrintJobRecord(
          jobKey: 'INV-0104',
          status: PrintJobStatus.failed,
          bytesWritten: 0,
          byteCount: 900,
          copyIndex: 1,
        );
      final queue = PrintQueue(transport: printer, log: log);

      final result = await queue.submit(
        jobId: 'INV-0104',
        target: const PrinterTarget(kind: 'x', address: 'a', name: 'A'),
        bytes: [1],
        actor: _actor,
      );

      expect(result.outcome, PrintOutcome.printed);
      expect(printer.sends, 1);
    });

    test(
      'the job is recorded before a byte is sent, and settled after',
      () async {
        // The ordering IS the mechanism. If begin() landed after the send, a
        // process death mid-print would leave no row at all and the next attempt
        // would print a second copy believing it was the first.
        final log = _FakeLog();
        final printer = _CountingPrinter(journal: log.calls);
        final queue = PrintQueue(transport: printer, log: log);

        await queue.submit(
          jobId: 'INV-0105',
          target: const PrinterTarget(kind: 'x', address: 'a', name: 'A'),
          bytes: [1, 2, 3],
          actor: _actor,
          documentId: 'DOC-1',
          columnsUsed: 42,
        );

        expect(log.calls, [
          'begin:INV-0105',
          'send',
          'finish:INV-0105:printed',
        ]);
        expect(log.begunColumns['INV-0105'], 42);
        expect(log.begunDocuments['INV-0105'], 'DOC-1');
      },
    );

    test(
      'the recorded digest distinguishes two widths of the same bill',
      () async {
        // A reprint at 32 columns is a different piece of paper from the same
        // bill at 48, and the record should say so rather than looking like the
        // same job asked for twice.
        final log = _FakeLog();
        final queue = PrintQueue(transport: _CountingPrinter(), log: log);
        const target = PrinterTarget(kind: 'x', address: 'a', name: 'A');

        await queue.submit(
          jobId: 'INV-0106#48',
          target: target,
          bytes: [1, 2, 3],
          actor: _actor,
        );
        await queue.submit(
          jobId: 'INV-0106#32',
          target: target,
          bytes: [9, 9, 9],
          actor: _actor,
        );

        expect(
          log.begunDigests['INV-0106#48'],
          isNot(log.begunDigests['INV-0106#32']),
        );
      },
    );

    test(
      'without an actor the queue is in-memory only, and says nothing',
      () async {
        // The queue's own rules stay testable without a database. What must not
        // happen is a half-configured queue silently skipping the record while
        // looking configured.
        final log = _FakeLog();
        final queue = PrintQueue(transport: _CountingPrinter(), log: log);

        await queue.submit(
          jobId: 'INV-0107',
          target: const PrinterTarget(kind: 'x', address: 'a', name: 'A'),
          bytes: [1],
        );

        expect(log.calls, isEmpty);
      },
    );
  });
}

/// Lets the loopback server finish reading before the test asserts.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

final class _CountingPrinter implements PrinterTransport {
  _CountingPrinter({this.delay = Duration.zero, this.journal});

  final Duration delay;

  /// Shared with a _FakeLog so the ORDER of begin, send and finish can be
  /// asserted. That ordering is the mechanism: if begin landed after the send,
  /// a process death mid-print would leave no row at all, and the next attempt
  /// would print a second copy believing it was the first.
  final List<String>? journal;

  int sends = 0;
  int _inFlight = 0;
  int maxConcurrent = 0;

  @override
  String get kind => 'counting';

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<List<PrinterTarget>> discover({Duration? timeout}) async => const [];

  @override
  Future<void> send(PrinterTarget target, List<int> bytes) async {
    journal?.add('send');
    sends++;
    _inFlight++;
    maxConcurrent = _inFlight > maxConcurrent ? _inFlight : maxConcurrent;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    _inFlight--;
  }
}

final class _FailingPrinter implements PrinterTransport {
  _FailingPrinter(this.error);

  final Object error;
  int sends = 0;

  @override
  String get kind => 'failing';

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<List<PrinterTarget>> discover({Duration? timeout}) async => const [];

  @override
  Future<void> send(PrinterTarget target, List<int> bytes) async {
    sends++;
    throw error;
  }
}

/// A stand-in actor. The queue only reads `firmId` from it.
final _actor = ActorContext(
  firmId: 'FIRM01',
  userId: 'USER01',
  deviceId: 'DEV01',
  startedAtUtc: DateTime.utc(2026, 8, 23, 9, 15),
);

/// Records what the queue asked of the log, in order.
final class _FakeLog implements PrintJobLog {
  final records = <String, PrintJobRecord>{};
  final calls = <String>[];
  final begunColumns = <String, int>{};
  final begunDocuments = <String, String?>{};
  final begunDigests = <String, String>{};

  @override
  Future<PrintJobRecord?> byKey(String firmId, String jobKey) async =>
      records[jobKey];

  @override
  Future<void> begin(
    ActorContext actor, {
    required String jobKey,
    required String transportKind,
    required String targetAddress,
    required int columnsUsed,
    required int copyIndex,
    required int byteCount,
    required String payloadSha256,
    String? documentId,
  }) async {
    calls.add('begin:$jobKey');
    begunColumns[jobKey] = columnsUsed;
    begunDocuments[jobKey] = documentId;
    begunDigests[jobKey] = payloadSha256;
    records[jobKey] = PrintJobRecord(
      jobKey: jobKey,
      status: PrintJobStatus.sending,
      bytesWritten: 0,
      byteCount: byteCount,
      copyIndex: copyIndex,
      documentId: documentId,
    );
  }

  @override
  Future<void> finish(
    ActorContext actor, {
    required String jobKey,
    required PrintJobStatus status,
    required int bytesWritten,
    String? failureReason,
  }) async {
    calls.add('finish:$jobKey:${status.name}');
    final previous = records[jobKey];
    records[jobKey] = PrintJobRecord(
      jobKey: jobKey,
      status: status,
      bytesWritten: bytesWritten,
      byteCount: previous?.byteCount ?? 0,
      copyIndex: previous?.copyIndex ?? 1,
      documentId: previous?.documentId,
      failureReason: failureReason,
    );
  }

  @override
  Future<List<PrintJobRecord>> forDocument(
    String firmId,
    String documentId,
  ) async => [
    for (final r in records.values)
      if (r.documentId == documentId) r,
  ];
}

/// Fails a set number of times, then works. For the "nothing came out, so it
/// may be asked for again" rule.
final class _EventuallyWorkingPrinter implements PrinterTransport {
  _EventuallyWorkingPrinter({required this.failuresBeforeSuccess});

  final int failuresBeforeSuccess;
  int sends = 0;

  @override
  String get kind => 'eventual';

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<List<PrinterTarget>> discover({Duration? timeout}) async => const [];

  @override
  Future<void> send(PrinterTarget target, List<int> bytes) async {
    sends++;
    if (sends <= failuresBeforeSuccess) {
      throw const PrinterException('no route');
    }
  }
}
