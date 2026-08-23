import 'package:flutter/services.dart';
import 'package:pk_domain/pk_domain.dart';

export 'src/usb_printer.dart';

/// The Bluetooth printer a delivery man carries, over Serial Port Profile.
///
/// Classic Bluetooth, not BLE — every ESC/POS printer in this price bracket is
/// SPP, and none of the BLE packages can talk to one at all.
///
/// Deliberately no discovery. A shopkeeper pairs the printer once in Android's
/// own settings, and this only ever lists what is already bonded. That keeps
/// the permission surface to `BLUETOOTH_CONNECT` alone: no `BLUETOOTH_SCAN`,
/// and above all no location permission, which several of the packages on
/// pub.dev declare in their own manifests and which would drag a billing app
/// into Play's Location policy in order to find a printer.
final class BluetoothPrinter implements PrinterTransport {
  const BluetoothPrinter({
    this.chunkSize = 256,
    this.chunkDelay = const Duration(milliseconds: 20),
    this.settle = const Duration(milliseconds: 400),
  });

  /// How much goes over the link at a time, and how long to wait between.
  ///
  /// The Bluetooth module hands data to the print controller over an internal
  /// UART with no flow control, so RFCOMM delivers faster than the printer
  /// drains. Nothing reports an error when it overflows: the receipt simply
  /// comes out garbled, and only the long ones, which is exactly why it
  /// survives testing and fails in the shop.
  ///
  /// These are a middle ground rather than a guarantee. A printer that still
  /// garbles wants a smaller chunk and a longer delay, which is why both are
  /// settings rather than constants.
  final int chunkSize;
  final Duration chunkDelay;

  /// How long to wait after the last byte before closing the link.
  ///
  /// Closing immediately truncates the tail, and the tail is the cut command —
  /// so the symptom is a receipt that prints perfectly and never cuts.
  final Duration settle;

  static const _channel = MethodChannel('pk.bazaarledger/printer');

  @override
  String get kind => 'bluetooth';

  @override
  Future<bool> get isAvailable async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on Object {
      // No radio, no permission, or not Android. Not an error — this
      // transport is simply not one the setup screen should offer.
      return false;
    }
  }

  /// Whether the runtime permission has been granted.
  ///
  /// Separate from [isAvailable] so the setup screen can tell "this phone has
  /// no Bluetooth" apart from "you have not said yes yet", which are different
  /// problems with different answers.
  Future<bool> get hasPermission async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } on Object {
      return false;
    }
  }

  /// Printers already paired in Android's settings.
  ///
  /// Everything bonded, not everything that looks like a printer: the
  /// Bluetooth device class of a cheap thermal printer is frequently reported
  /// as uncategorised or even as audio, so filtering by class hides the very
  /// machines this exists for. The shopkeeper picks theirs by name.
  @override
  Future<List<PrinterTarget>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final raw = await _channel.invokeListMethod<Object?>('bondedPrinters');
    if (raw == null) return const [];
    return [
      for (final entry in raw)
        if (entry is Map)
          PrinterTarget(
            kind: kind,
            address: '${entry['address']}',
            name: '${entry['name']}',
            details: 'Paired',
          ),
    ];
  }

  @override
  Future<void> send(PrinterTarget target, List<int> bytes) async {
    try {
      await _channel.invokeMethod<void>('send', {
        'address': target.address,
        'bytes': Uint8List.fromList(bytes),
        'chunkSize': chunkSize,
        'chunkDelayMs': chunkDelay.inMilliseconds,
        'settleMs': settle.inMilliseconds,
      });
    } on PlatformException catch (error) {
      // `details` carries how much the printer took before it went wrong, and
      // that number decides whether the queue may try again on its own.
      // Losing it here would turn every failure into "safe to retry", which
      // is how a flaky link produces two of every long bill.
      //
      // And that is exactly what this line used to do. It read
      // `error.details is int ? ... : 0`, so a platform error that carried NO
      // byte count — a Kotlin path that threw before it could count, or any
      // future one that forgets to pass it — reported zero bytes written,
      // which reads as "nothing came out, retry freely". The comment above
      // described the danger and the code below it did the thing.
      //
      // Absent is not zero. An error that said nothing about paper has not
      // told us paper did not move, so it is reported as though it did, and a
      // person decides. The only way to earn a retry is for the platform to
      // say, explicitly, that nothing was written.
      final details = error.details;
      final written = details is int ? details : 1;
      throw PrinterException(
        error.message ?? 'The printer stopped taking the receipt.',
        bytesWritten: written,
        target: target,
      );
    } on Object catch (error) {
      // Anything else has not told us whether paper moved, so it is reported
      // as though it did.
      throw PrinterException('$error', bytesWritten: 1, target: target);
    }
  }
}
