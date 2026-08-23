import '../identity/actor_context.dart';
import 'receipt.dart';

/// Which printer this counter uses, and how to talk to it.
///
/// Stored per device rather than per firm. The counter has the USB printer and
/// the back office has the LAN one, and when M13's sync carries the settings
/// table between them an unnamespaced key would let two tills overwrite each
/// other's choice forever.
final class PrinterSettings {
  const PrinterSettings({
    required this.transportKind,
    required this.address,
    required this.name,
    this.columns = 48,
    this.leftMarginColumns = 0,
    this.copies = 1,
    this.openDrawerOnCash = false,
    this.chunkSize = 256,
    this.chunkDelayMs = 20,
    this.settleMs = 400,
  });

  /// `tcp`, `bluetooth` or `usb` — matching [PrinterTransport.kind].
  final String transportKind;

  /// How the transport reaches it. Opaque above the transport.
  final String address;

  /// What the shopkeeper chose it as. A MAC address is not a name.
  final String name;

  /// 32, 42 or 48.
  ///
  /// This is the setting shopkeepers get wrong most often, and getting it
  /// wrong is not subtle: at 48 on a 42-column printer every total wraps onto
  /// the next line and the receipt becomes unreadable. It cannot be detected —
  /// ESC/POS has no query for it, and 80mm printers ship in both widths
  /// depending on whether the ROM font is A or B. So the setup screen prints a
  /// ruler and the shopkeeper looks at the paper.
  final int columns;

  /// Shifts everything right, for a printer whose head is off-centre in its
  /// housing. Small integers, and usually zero.
  final int leftMarginColumns;

  /// How many identical receipts to print. One for the customer, sometimes a
  /// second for the shop's own spike.
  final int copies;

  /// Whether a cash sale kicks the drawer.
  ///
  /// Off by default: most shops in this bracket have no drawer, and a printer
  /// that clicks on every sale for no reason is a printer somebody unplugs.
  final bool openDrawerOnCash;

  /// How much goes over the link at a time, and how long to wait between.
  ///
  /// The module between the link and the print head feeds the controller over
  /// an internal UART with no flow control, so bytes arrive faster than the
  /// printer drains. Nothing reports an error when it overflows: the receipt
  /// comes out garbled, and only the long ones — which is exactly why it
  /// survives testing and fails in the shop. A printer that still garbles
  /// wants a smaller chunk and a longer delay, which is why these are settings
  /// and not constants.
  final int chunkSize;
  final int chunkDelayMs;

  /// How long to hold the link open after the last byte.
  ///
  /// Closing immediately truncates the tail, and the tail is the cut command,
  /// so the symptom is a receipt that prints perfectly and never cuts.
  final int settleMs;

  static const allowedColumns = <int>[32, 42, 48];

  /// The paper this width corresponds to.
  ///
  /// Three widths, two roll sizes: an 80 mm printer takes either 42 or 48
  /// columns depending on its ROM font and margins, and ESC/POS has no query
  /// for which. That is why the width is a setting a shopkeeper confirms
  /// against a printed ruler rather than something the app works out.
  ReceiptPaper get paper => switch (columns) {
    32 => ReceiptPaper.mm58,
    42 => ReceiptPaper.mm80Narrow,
    _ => ReceiptPaper.mm80,
  };

  PrinterSettings copyWith({
    String? transportKind,
    String? address,
    String? name,
    int? columns,
    int? leftMarginColumns,
    int? copies,
    bool? openDrawerOnCash,
    int? chunkSize,
    int? chunkDelayMs,
    int? settleMs,
  }) => PrinterSettings(
    transportKind: transportKind ?? this.transportKind,
    address: address ?? this.address,
    name: name ?? this.name,
    columns: columns ?? this.columns,
    leftMarginColumns: leftMarginColumns ?? this.leftMarginColumns,
    copies: copies ?? this.copies,
    openDrawerOnCash: openDrawerOnCash ?? this.openDrawerOnCash,
    chunkSize: chunkSize ?? this.chunkSize,
    chunkDelayMs: chunkDelayMs ?? this.chunkDelayMs,
    settleMs: settleMs ?? this.settleMs,
  );

  Map<String, Object?> toJson() => {
    'transportKind': transportKind,
    'address': address,
    'name': name,
    'columns': columns,
    'leftMarginColumns': leftMarginColumns,
    'copies': copies,
    'openDrawerOnCash': openDrawerOnCash,
    'chunkSize': chunkSize,
    'chunkDelayMs': chunkDelayMs,
    'settleMs': settleMs,
  };

  /// Reads settings written by this or any earlier build.
  ///
  /// Every field falls back to its default rather than throwing. A settings
  /// row that gained a field in a later version must not stop a shopkeeper
  /// printing — losing a margin nudge is a nuisance, and refusing to print is
  /// a shop that cannot hand over a receipt.
  static PrinterSettings? fromJson(Map<String, Object?> json) {
    final kind = json['transportKind'];
    final address = json['address'];
    if (kind is! String || address is! String) return null;
    if (kind.isEmpty || address.isEmpty) return null;

    int intOr(String key, int fallback) {
      final value = json[key];
      return value is int ? value : fallback;
    }

    final columns = intOr('columns', 48);
    return PrinterSettings(
      transportKind: kind,
      address: address,
      name: json['name'] is String ? json['name']! as String : address,
      columns: allowedColumns.contains(columns) ? columns : 48,
      leftMarginColumns: intOr('leftMarginColumns', 0),
      copies: intOr('copies', 1).clamp(1, 5),
      openDrawerOnCash: json['openDrawerOnCash'] == true,
      chunkSize: intOr('chunkSize', 256),
      chunkDelayMs: intOr('chunkDelayMs', 20),
      settleMs: intOr('settleMs', 400),
    );
  }

  @override
  String toString() => 'PrinterSettings($transportKind, $name, ${columns}col)';
}

/// Where the chosen printer is remembered.
abstract interface class PrinterSettingsStore {
  /// What this device prints on, or null if nobody has chosen yet.
  Future<PrinterSettings?> forDevice(String firmId, String deviceId);

  /// Records the choice, through the one write path, so it is audited and
  /// reaches the outbox like every other decision about the shop.
  Future<void> save(ActorContext actor, PrinterSettings settings);

  /// Forgets it, for a printer that has been sold or thrown away.
  Future<void> clear(ActorContext actor);
}

/// What happened to one print, as far as anybody knows.
enum PrintJobStatus {
  /// In flight — or the process died holding it.
  ///
  /// NOT the same as "did not print", and the difference is the entire reason
  /// this is written to a database. Android Go ROMs kill this app aggressively;
  /// the cart is persisted on every mutation for exactly that reason. If the
  /// app is reclaimed after 400 of 900 bytes reached a Bluetooth printer, paper
  /// has already moved. Treating that as un-printed and retrying hands the
  /// customer two half-receipts.
  sending,

  /// Every byte acknowledged.
  printed,

  /// Paper moved and then something went wrong. Never retried automatically.
  partial,

  /// Nothing came out. Safe for the counter to offer again.
  failed,
}

/// One attempt to put a document on paper.
final class PrintJobRecord {
  const PrintJobRecord({
    required this.jobKey,
    required this.status,
    required this.bytesWritten,
    required this.byteCount,
    required this.copyIndex,
    this.documentId,
    this.failureReason,
  });

  /// Deterministic: `<documentId>#<revision>#<columns>#<copyIndex>`.
  ///
  /// Never a fresh ULID. A random key would not match after a restart, which
  /// would make the record useless at the one moment it exists for.
  final String jobKey;

  final PrintJobStatus status;
  final int bytesWritten;
  final int byteCount;
  final int copyIndex;
  final String? documentId;
  final String? failureReason;

  /// Whether the counter may send this again without asking a person.
  ///
  /// Only when nothing came out. Anything else — including [sending], which
  /// means nobody knows — is a question for the shopkeeper, who can look at
  /// the paper.
  bool get mayRetryAutomatically => status == PrintJobStatus.failed;
}

/// The record of what has been printed, in the database rather than in memory.
abstract interface class PrintJobLog {
  /// What happened last time this exact job was sent, if it ever was.
  Future<PrintJobRecord?> byKey(String firmId, String jobKey);

  /// Records that a job is about to go out.
  ///
  /// Committed BEFORE the first byte. That ordering is the mechanism: a row
  /// still saying [PrintJobStatus.sending] at next launch is how the app knows
  /// it does not know.
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
  });

  /// Records how it ended.
  Future<void> finish(
    ActorContext actor, {
    required String jobKey,
    required PrintJobStatus status,
    required int bytesWritten,
    String? failureReason,
  });

  /// Every print attempted for one document, newest first.
  Future<List<PrintJobRecord>> forDocument(String firmId, String documentId);
}
