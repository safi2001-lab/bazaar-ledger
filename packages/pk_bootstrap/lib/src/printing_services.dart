import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';

/// Everything the app needs to put a receipt on paper.
///
/// This type exists because the pieces were all built and none of them were
/// joined up. `TcpPrinter`, `BluetoothPrinter`, `PrintQueue`, `EscPos` and the
/// 48- and 32-column layouts were written, tested, and reachable from nothing:
/// `pk_bootstrap` deliberately withheld them from the app, `AppServices` had no
/// printer field, and the receipt screen rendered a crossed-out printer under a
/// string reading "Printing arrives in M2." Two commits said the milestone had
/// landed. Both described packages rather than the product.
final class PrintingServices {
  // `prefer_initializing_formals` cannot be satisfied here: Dart has no
  // private named parameter, and a public `store` field would hand anything
  // holding a PrintingServices a second write path to the database. The lint
  // loses to the boundary, exactly as it does in AppServices.
  // ignore_for_file: prefer_initializing_formals
  PrintingServices({
    required DriftPrinterSettings store,
    required List<PrinterTransport> transports,
  }) : _store = store,
       _transports = {for (final t in transports) t.kind: t};

  final DriftPrinterSettings _store;
  final Map<String, PrinterTransport> _transports;

  /// One queue per transport kind, built on first use.
  ///
  /// Per transport rather than one shared queue, because the serialisation a
  /// queue provides is about one printer's buffer. A LAN printer and a
  /// Bluetooth printer have no reason to wait for each other.
  final _queues = <String, PrintQueue>{};

  /// The transports this build carries, whether or not they work here.
  ///
  /// The setup screen asks each one whether it is available, so a shopkeeper is
  /// told "this phone has no Bluetooth" rather than being offered a choice that
  /// fails at the moment they try to print.
  List<PrinterTransport> get transports => _transports.values.toList();

  /// What this counter prints on, or null if nobody has chosen yet.
  Future<PrinterSettings?> settings(String firmId, String deviceId) =>
      _store.forDevice(firmId, deviceId);

  Future<void> saveSettings(ActorContext actor, PrinterSettings settings) =>
      _store.save(actor, settings);

  Future<void> forgetPrinter(ActorContext actor) => _store.clear(actor);

  /// Every print attempted for one bill, newest first.
  Future<List<PrintJobRecord>> historyFor(String firmId, String documentId) =>
      _store.forDocument(firmId, documentId);

  /// Whether a given transport can be used on this device right now.
  Future<bool> isAvailable(String kind) async =>
      await _transports[kind]?.isAvailable ?? false;

  /// Printers a transport can see. Empty is a normal answer, not an error.
  Future<List<PrinterTarget>> discover(
    String kind, {
    Duration timeout = const Duration(seconds: 4),
  }) async => await _transports[kind]?.discover(timeout: timeout) ?? const [];

  /// Sends [bytes] to the configured printer, once.
  ///
  /// [jobKey] must be deterministic — `<documentId>#<revision>#<columns>#<copy>`
  /// — and never a fresh id. A random key would not match after a restart,
  /// which would defeat the record at the one moment it exists for.
  Future<PrintResult> print({
    required ActorContext actor,
    required PrinterSettings settings,
    required String jobKey,
    required List<int> bytes,
    String? documentId,
    int copyIndex = 1,
  }) async {
    final transport = _transports[settings.transportKind];
    if (transport == null) {
      // The saved printer uses a transport this build does not carry — an
      // older settings row, or a shop moving between devices. Reported as a
      // job that never started rather than thrown, because the counter's
      // answer is the same either way: nothing came out, and it is safe to
      // offer again once a printer is chosen.
      return PrintResult(
        outcome: PrintOutcome.notSent,
        jobId: jobKey,
        error: StateError(
          'No ${settings.transportKind} transport on this device.',
        ),
      );
    }

    final queue = _queues.putIfAbsent(
      settings.transportKind,
      () => PrintQueue(transport: transport, log: _store),
    );

    return queue.submit(
      jobId: jobKey,
      target: PrinterTarget(
        kind: settings.transportKind,
        address: settings.address,
        name: settings.name,
      ),
      bytes: bytes,
      actor: actor,
      documentId: documentId,
      columnsUsed: settings.columns,
      copyIndex: copyIndex,
    );
  }
}

/// The job key for one printing of one revision of one bill, at one width.
///
/// Deterministic on purpose, and every part of it earns its place: a reprint at
/// a different column width is a different piece of paper, a revised invoice is
/// a different document, and a second copy is a deliberate act by a person.
String printJobKey({
  required String documentId,
  required int revision,
  required int columns,
  int copyIndex = 1,
}) => '$documentId#$revision#$columns#$copyIndex';
