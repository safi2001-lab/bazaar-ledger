/// How a receipt reaches paper.
///
/// The bytes are already someone else's problem — `ReceiptRenderer` produces
/// a finished ESC/POS stream, and this only has to carry it. Keeping the two
/// apart is what lets the byte stream be asserted command by command in a
/// headless test while the transport is swapped for a socket, a Bluetooth
/// serial link, or a file.
///
/// Three transports, because a Pakistani counter has three shapes. The
/// printer plugged into the till by USB. The one on the shop's own Wi-Fi,
/// which is how a counter and a back office share one machine. And the
/// battery one a delivery man carries, which is Bluetooth. A shop that can
/// only use one of the three is a shop that has to buy a different printer.
abstract interface class PrinterTransport {
  /// A stable name for this transport, for settings and for diagnostics.
  String get kind;

  /// Whether this transport can be used on this device at all.
  ///
  /// False on a desktop with no Bluetooth radio, or where the platform
  /// permission was refused. The printer setup screen offers what is
  /// available and says why the rest is not, rather than offering everything
  /// and failing at the moment someone tries to print.
  Future<bool> get isAvailable;

  /// Printers this transport can see right now.
  ///
  /// Empty is a normal answer, not an error: nothing is plugged in, nothing
  /// is paired, nothing answered on the network.
  Future<List<PrinterTarget>> discover({Duration timeout});

  /// Sends [bytes] to [target], start to finish.
  ///
  /// Returns when the printer has taken every byte. Throws
  /// [PrinterException] otherwise, and the distinction that matters is in
  /// [PrinterException.bytesWritten]: a job that failed before writing
  /// anything is safe to retry automatically, and one that failed halfway is
  /// not, because half a receipt has already come out of the machine.
  Future<void> send(PrinterTarget target, List<int> bytes);
}

/// One printer, as a transport found it.
final class PrinterTarget {
  const PrinterTarget({
    required this.kind,
    required this.address,
    required this.name,
    this.details,
  });

  /// Which transport this belongs to.
  final String kind;

  /// How the transport reaches it: an IP and port, a MAC address, a USB
  /// device id. Opaque to everything above.
  final String address;

  /// What to show a shopkeeper. A MAC address is not a name.
  final String name;

  /// Anything worth showing in setup — the model string a printer reported,
  /// the interface it was found on.
  final String? details;

  /// Stable across sessions, so a chosen printer can be remembered.
  String get id => '$kind:$address';

  @override
  bool operator ==(Object other) => other is PrinterTarget && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => '$name ($id)';
}

/// A print that did not happen, or did not entirely happen.
final class PrinterException implements Exception {
  const PrinterException(this.message, {this.bytesWritten = 0, this.target});

  final String message;

  /// How much of the job the printer took before it went wrong.
  ///
  /// Zero means nothing came out and the job can be sent again without
  /// asking. Anything else means paper has already moved, and a silent retry
  /// would hand the customer two half-receipts — so the shopkeeper is asked
  /// instead. This is the whole reason the number is on the exception rather
  /// than a bare failure.
  final int bytesWritten;

  final PrinterTarget? target;

  /// Whether the queue may send this again on its own.
  bool get isSafeToRetry => bytesWritten == 0;

  @override
  String toString() =>
      'PrinterException: $message'
      '${target == null ? '' : ' (${target!.name})'}'
      '${bytesWritten == 0 ? '' : ', $bytesWritten bytes already printed'}';
}
