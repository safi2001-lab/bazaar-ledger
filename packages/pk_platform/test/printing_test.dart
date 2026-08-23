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
        reason: 'the printer was handed different bytes than it was given, '
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
        const TcpPrinter(connectTimeout: Duration(milliseconds: 300))
            .send(unreachable, [1, 2, 3]),
        throwsA(
          isA<PrinterException>()
              .having((e) => e.isSafeToRetry, 'isSafeToRetry', isTrue)
              .having((e) => e.bytesWritten, 'bytesWritten', 0),
        ),
      );
    });
  });

  group('the queue, and the rule it exists for', () {
    test('one job, printed once, however many times it is asked for',
        () async {
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
        reason: 'the customer was handed ${printer.sends} receipts for one '
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

    test('a transport that throws something unexpected is treated as partial',
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
    });

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

    test('a reprint is a deliberate act and goes through a different door',
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
    });
  });
}

/// Lets the loopback server finish reading before the test asserts.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));

final class _CountingPrinter implements PrinterTransport {
  _CountingPrinter({this.delay = Duration.zero});

  final Duration delay;
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
