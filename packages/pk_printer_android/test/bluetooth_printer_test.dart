import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_printer_android/pk_printer_android.dart';

/// The Dart half of the Bluetooth transport.
///
/// The Kotlin half is covered by `PacedWriterTest` — chunking, pacing, and the
/// bytes-written contract, all in a JVM test that needed a JUnit engine added
/// before it ran a single case. This covers the seam between the two, which no
/// Kotlin test can reach: what the platform channel returns, and what this
/// class decides that means.
///
/// One decision matters more than the rest. `PrinterException.bytesWritten` is
/// what the print queue consults to decide whether a failed job may be sent
/// again on its own. Lose that number and every failure looks safe to retry,
/// which on a flaky link hands the customer two of every long bill. The
/// platform sends it back in `PlatformException.details`, and it has to survive
/// the trip.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('pk.bazaarledger/printer');
  const printer = BluetoothPrinter();
  const target = PrinterTarget(
    kind: 'bluetooth',
    address: 'AA:BB:CC:DD:EE:FF',
    name: 'Delivery printer',
  );

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Answers the channel with [handler], and records what was asked.
  List<MethodCall> intercept(Future<Object?>? Function(MethodCall) handler) {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return calls;
  }

  group('what the platform says it can do', () {
    test('no radio and no permission both read as unavailable', () async {
      intercept((_) async => false);
      expect(await printer.isAvailable, isFalse);
    });

    test('a platform that throws is unavailable, not a crash', () async {
      // A desktop, or an Android build without the plugin registered. The
      // setup screen should offer the other transports rather than fail.
      intercept((_) => throw MissingPluginException());
      expect(await printer.isAvailable, isFalse);
      expect(await printer.hasPermission, isFalse);
    });

    test('permission is asked about separately from the radio', () async {
      // "This phone has no Bluetooth" and "you have not said yes yet" are
      // different problems with different answers, and a shopkeeper told the
      // wrong one goes looking in the wrong place.
      final calls = intercept((call) async => call.method == 'hasPermission');
      expect(await printer.hasPermission, isTrue);
      expect(calls.single.method, 'hasPermission');
    });
  });

  group('finding a printer', () {
    test('everything paired is offered, whatever it calls itself', () async {
      // Not filtered by Bluetooth device class. Cheap thermal printers report
      // themselves as uncategorised or even as audio devices, so filtering by
      // class hides the very machines this exists for.
      intercept(
        (_) async => [
          {
            'address': 'AA:BB:CC:DD:EE:FF',
            'name': 'BlueTooth Printer',
            'deviceClass': 0,
          },
          {
            'address': '11:22:33:44:55:66',
            'name': 'Speaker',
            'deviceClass': 1024,
          },
        ],
      );

      final found = await printer.discover();
      expect(found, hasLength(2));
      expect(found.first.name, 'BlueTooth Printer');
      expect(found.first.kind, 'bluetooth');
    });

    test('nothing paired is an empty list, not an error', () async {
      intercept((_) async => <Object?>[]);
      expect(await printer.discover(), isEmpty);
    });

    test('a device with no name is offered by its address', () async {
      // A MAC address is a poor label, and no label at all is worse.
      intercept(
        (_) async => [
          {'address': 'AA:BB:CC:DD:EE:FF', 'name': null},
        ],
      );
      final found = await printer.discover();
      expect(found.single.name, isNotEmpty);
    });
  });

  group('sending a receipt', () {
    test('the pacing settings reach the platform', () async {
      // These are settings rather than constants because a printer that still
      // garbles wants a smaller chunk and a longer delay. If they do not cross
      // the channel, changing them in the setup screen does nothing.
      const paced = BluetoothPrinter(
        chunkSize: 64,
        chunkDelay: Duration(milliseconds: 40),
        settle: Duration(milliseconds: 900),
      );
      final calls = intercept((_) async => null);

      await paced.send(target, [1, 2, 3]);

      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['address'], 'AA:BB:CC:DD:EE:FF');
      expect(args['chunkSize'], 64);
      expect(args['chunkDelayMs'], 40);
      expect(args['settleMs'], 900);
      expect((args['bytes']! as List<int>), [1, 2, 3]);
    });

    test('how much paper moved survives the trip back', () async {
      // The number the whole no-double-print design rests on.
      intercept(
        (_) => throw PlatformException(
          code: 'send',
          message: 'the link went away',
          details: 512,
        ),
      );

      await expectLater(
        printer.send(target, [1, 2, 3]),
        throwsA(
          isA<PrinterException>()
              .having((e) => e.bytesWritten, 'bytesWritten', 512)
              .having((e) => e.isSafeToRetry, 'isSafeToRetry', isFalse),
        ),
      );
    });

    test('nothing written is safe to try again', () async {
      intercept(
        (_) => throw PlatformException(
          code: 'send',
          message: 'could not connect',
          details: 0,
        ),
      );

      await expectLater(
        printer.send(target, [1, 2, 3]),
        throwsA(
          isA<PrinterException>()
              .having((e) => e.bytesWritten, 'bytesWritten', 0)
              .having((e) => e.isSafeToRetry, 'isSafeToRetry', isTrue),
        ),
      );
    });

    test(
      'a failure that says nothing about paper is treated as though it moved',
      () async {
        // A platform error with no byte count has not told us whether anything
        // came out. Assuming the safe case here is how a bug on the Kotlin side
        // becomes a double-printed bill.
        intercept(
          (_) => throw PlatformException(code: 'send', message: 'unknown'),
        );

        await expectLater(
          printer.send(target, [1, 2, 3]),
          throwsA(
            isA<PrinterException>().having(
              (e) => e.isSafeToRetry,
              'isSafeToRetry',
              isFalse,
            ),
          ),
        );
      },
    );

    test('a missing plugin is also treated as though paper moved', () async {
      // Same reasoning: nothing told us it did not.
      intercept((_) => throw MissingPluginException());

      await expectLater(
        printer.send(target, [1, 2, 3]),
        throwsA(
          isA<PrinterException>().having(
            (e) => e.isSafeToRetry,
            'isSafeToRetry',
            isFalse,
          ),
        ),
      );
    });

    test(
      'a permission refusal names the permission, not a stack trace',
      () async {
        intercept(
          (_) => throw PlatformException(
            code: 'permission',
            message: 'Bluetooth permission has not been granted.',
            details: 0,
          ),
        );

        await expectLater(
          printer.send(target, [1, 2, 3]),
          throwsA(
            isA<PrinterException>().having(
              (e) => e.message,
              'message',
              contains('permission'),
            ),
          ),
        );
      },
    );
  });
}
