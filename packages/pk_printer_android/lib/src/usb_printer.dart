import 'package:flutter/services.dart';
import 'package:pk_domain/pk_domain.dart';

/// The printer already cabled to the counter.
///
/// The default shape of a Pakistani shop counter: an 80mm thermal unit on a
/// USB lead, six to twelve thousand rupees. The battery Bluetooth printer is
/// what a delivery man carries and the LAN one is how a counter and a back
/// office share a machine, but this is the one most shops already own — and a
/// product that cannot drive it is asking a shopkeeper to buy a second
/// printer in order to use it.
///
/// Two things about USB printers that cost time to learn:
///
/// They enumerate as USB **printer class (0x07)**, not as CDC serial. Every
/// `usb_serial` package looks for 0x02/0x0A, finds nothing, and reports no
/// device attached against a printer that is plainly plugged in and lit up.
///
/// And there is no manifest permission for them. Access is granted per device,
/// by the system, at the moment of use — so this transport adds nothing to the
/// Play listing, which is a genuinely better privacy story than the Bluetooth
/// one.
final class UsbPrinter implements PrinterTransport {
  const UsbPrinter({
    this.chunkDelay = const Duration(milliseconds: 8),
    this.settle = const Duration(milliseconds: 250),
  });

  /// How long to wait between chunks.
  ///
  /// Shorter than the Bluetooth default. USB has flow control that RFCOMM does
  /// not, and the endpoint reports back how much it actually took, so the
  /// pacing here is a courtesy to the print controller rather than the only
  /// thing standing between a long receipt and a garbled one.
  final Duration chunkDelay;

  /// How long to hold the connection after the last byte.
  ///
  /// Closing immediately truncates the tail, and the tail is the cut command,
  /// so the symptom is a receipt that prints perfectly and never cuts.
  final Duration settle;

  static const _channel = MethodChannel('pk.bazaarledger/printer');

  @override
  String get kind => 'usb';

  @override
  Future<bool> get isAvailable async {
    try {
      return await _channel.invokeMethod<bool>('usbIsAvailable') ?? false;
    } on Object {
      // No OTG support, or not Android. Not an error — this transport is
      // simply not one the setup screen should offer here.
      return false;
    }
  }

  /// Printers currently plugged in.
  ///
  /// Filtered on interface class rather than on a vendor list. A vendor list
  /// is a list of the printers somebody remembered, and the machines this
  /// exists for are unbranded units from a dozen importers.
  @override
  Future<List<PrinterTarget>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final raw = await _channel.invokeListMethod<Object?>('usbDevices');
    if (raw == null) return const [];
    return [
      for (final entry in raw)
        if (entry is Map)
          PrinterTarget(
            kind: kind,
            address: '${entry['address']}',
            name: '${entry['name']}',
            // Whether the shopkeeper has already said yes to this device. The
            // setup screen shows it so that "nothing happened" is explained
            // before it happens rather than after.
            details: entry['hasPermission'] == true ? 'Ready' : 'Needs a tap',
          ),
    ];
  }

  @override
  Future<void> send(PrinterTarget target, List<int> bytes) async {
    try {
      await _channel.invokeMethod<void>('usbSend', {
        'address': target.address,
        'bytes': Uint8List.fromList(bytes),
        'chunkDelayMs': chunkDelay.inMilliseconds,
        'settleMs': settle.inMilliseconds,
      });
    } on PlatformException catch (error) {
      // `details` carries how many bytes the printer took, and that number
      // decides whether the queue may send this again on its own.
      //
      // Absent is NOT zero. Zero means the platform said, explicitly, that
      // nothing came out — which is the only case safe to retry. A missing
      // count means nobody knows, and nobody-knows is a question for the
      // person holding the paper. The Bluetooth transport had this inverted
      // for a while and it took a test to notice.
      final details = error.details;
      throw PrinterException(
        error.message ?? 'The printer stopped taking the receipt.',
        bytesWritten: details is int ? details : 1,
        target: target,
      );
    } on Object catch (error) {
      throw PrinterException('$error', bytesWritten: 1, target: target);
    }
  }
}
