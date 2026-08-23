import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_printer_android/pk_printer_android.dart';

/// The Dart half of the USB transport.
///
/// `UsbBulkWriterTest` covers the byte counting on the Kotlin side — short
/// transfers, stalls, and how much paper moved before a failure. This covers
/// the seam: what crosses the channel, and what this class decides a platform
/// error means.
///
/// The rule it protects is the same one the Bluetooth transport got wrong for
/// a while. An error carrying no byte count has not told us that nothing came
/// out; it has told us nothing. Absent is not zero, and zero is the only value
/// that earns an automatic retry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('pk.bazaarledger/printer');
  const printer = UsbPrinter();
  const target = PrinterTarget(
    kind: 'usb',
    address: '/dev/bus/usb/001/002',
    name: 'Counter printer',
  );

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  List<MethodCall> intercept(Future<Object?>? Function(MethodCall) handler) {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return handler(call);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return calls;
  }

  test('it is its own transport kind, not the Bluetooth one', () {
    // Both live on one channel. If they reported the same kind, a shop that
    // configured USB would get its jobs queued behind the Bluetooth printer's
    // and the settings row would resolve to the wrong transport.
    expect(printer.kind, 'usb');
    expect(printer.kind, isNot(const BluetoothPrinter().kind));
  });

  test(
    'a phone without OTG says so instead of failing at print time',
    () async {
      intercept((_) async => false);
      expect(await printer.isAvailable, isFalse);
    },
  );

  test('a platform that does not answer is unavailable, not a crash', () async {
    intercept((_) => throw MissingPluginException());
    expect(await printer.isAvailable, isFalse);
  });

  test('a plugged-in printer is offered, with whether it is ready', () async {
    // "Needs a tap" is worth saying before the shopkeeper prints, not after.
    // Android grants USB access per device at the moment of use, so the first
    // print of the day shows a dialog and every one after it does not.
    intercept(
      (_) async => [
        {
          'address': '/dev/bus/usb/001/002',
          'name': 'POS-80',
          'vendorId': 1155,
          'productId': 22304,
          'hasPermission': true,
        },
        {
          'address': '/dev/bus/usb/001/003',
          'name': 'Other printer',
          'hasPermission': false,
        },
      ],
    );

    final found = await printer.discover();
    expect(found, hasLength(2));
    expect(found.first.kind, 'usb');
    expect(found.first.name, 'POS-80');
    expect(found.first.details, 'Ready');
    expect(found.last.details, isNot('Ready'));
  });

  test('nothing plugged in is an empty list, not an error', () async {
    intercept((_) async => <Object?>[]);
    expect(await printer.discover(), isEmpty);
  });

  test('the bytes and the pacing reach the platform', () async {
    const paced = UsbPrinter(
      chunkDelay: Duration(milliseconds: 3),
      settle: Duration(milliseconds: 120),
    );
    final calls = intercept((_) async => null);

    await paced.send(target, [1, 2, 3]);

    expect(calls.single.method, 'usbSend');
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['address'], '/dev/bus/usb/001/002');
    expect((args['bytes']! as List<int>), [1, 2, 3]);
    expect(args['chunkDelayMs'], 3);
    expect(args['settleMs'], 120);
  });

  test('it does not answer the Bluetooth methods', () async {
    // Shared channel, separate methods. A `send` that switched on a string
    // would make the bytes-written contract depend on which branch a caller
    // happened to take.
    final calls = intercept((_) async => null);
    await printer.send(target, [1]);
    expect(calls.map((c) => c.method), everyElement(startsWith('usb')));
  });

  test('how much paper moved survives the trip back', () async {
    intercept(
      (_) => throw PlatformException(
        code: 'send',
        message: 'the printer stopped accepting data after 384 bytes',
        details: 384,
      ),
    );

    await expectLater(
      printer.send(target, [1, 2, 3]),
      throwsA(
        isA<PrinterException>()
            .having((e) => e.bytesWritten, 'bytesWritten', 384)
            .having((e) => e.isSafeToRetry, 'isSafeToRetry', isFalse),
      ),
    );
  });

  test('nothing written is safe to try again', () async {
    intercept(
      (_) => throw PlatformException(
        code: 'send',
        message: 'No printer at that address. Is the cable in?',
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
    'an error with no byte count is treated as though paper moved',
    () async {
      // Absent is not zero. The Bluetooth transport had this inverted, and a
      // platform error carrying no count read as "nothing came out, retry
      // freely" — which on a flaky link is two of every long bill.
      intercept(
        (_) =>
            throw PlatformException(code: 'send', message: 'unknown failure'),
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

  test(
    'a refused permission is reported in words a shopkeeper can act on',
    () async {
      intercept(
        (_) => throw PlatformException(
          code: 'send',
          message: 'Permission to use the printer was not granted.',
          details: 0,
        ),
      );

      await expectLater(
        printer.send(target, [1, 2, 3]),
        throwsA(
          isA<PrinterException>().having(
            (e) => e.message,
            'message',
            contains('Permission'),
          ),
        ),
      );
    },
  );
}
