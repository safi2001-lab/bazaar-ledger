import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:sqlite3/open.dart';

/// Everything the app can do, wired once.
///
/// This is the only object in the process that knows both drift and Flutter.
/// The UI package does not list `pk_data` in its pubspec at all, so a widget
/// that reaches for a table is a resolution error rather than a review
/// comment, and `depend_on_referenced_packages: error` closes the transitive
/// loophole.
final class AppServices {
  // `prefer_initializing_formals` cannot be satisfied here: Dart has no
  // private named parameter, and making these fields public would hand
  // anything holding an AppServices a second write path straight to the
  // database. The lint loses to the boundary.
  // ignore_for_file: prefer_initializing_formals
  AppServices._({
    required this.database,
    required this.queries,
    required this.receipts,
    required this.clock,
    required this.ids,
    required this.drafts,
    required this.restoredCartDraft,
    required TxRunner runner,
  }) : _runner = runner;

  /// Rebuilt, not merged, once first run has registered this device.
  ///
  /// `HlcClock.deviceId` is final and every timestamp it renders carries it,
  /// so merging a resumed clock into one built before the device existed
  /// catches up the millisecond and leaves the node id as the placeholder.
  /// Every row written for the rest of that session then reads
  /// `...-unregistered`, two freshly set-up tills mint byte-identical
  /// timestamps on a tie — exactly what the HLC exists to break — and 'u'
  /// sorts above every hex digit, so those rows win every conflict forever.
  void _adoptDevice(HlcClock resumed) {
    _runner = TxRunner(database: database, ids: ids, hlc: resumed);
  }

  final AppDatabase database;
  final AppQueries queries;
  final ReceiptRenderer receipts;
  final Clock clock;
  final IdGenerator ids;

  /// Where a half-finished bill waits out a process kill.
  ///
  /// Not the books. A draft has no invoice number, no journal entry, no audit
  /// row and no place in the sync outbox, and it is kept behind its own port
  /// and in its own file so that stays structural rather than a rule someone
  /// has to remember.
  final DraftStore drafts;

  /// The draft that was on disk when the app opened, if there was one.
  ///
  /// Read here rather than by the counter, because the counter must be able to
  /// restore it synchronously. A cart that arrives one frame late shows the
  /// cashier an empty bill first, and an empty bill is a bill they start
  /// ringing again.
  final String? restoredCartDraft;

  TxRunner _runner;

  /// Who is signed in. Null until first run has produced a firm and an owner.
  ActorIdentity? _identity;

  ActorIdentity? get identity => _identity;

  /// Built from the current runner every time, so a writer handed out before
  /// first run cannot keep writing through the clock that predates the device.
  CatalogueWriter get catalogue => DriftCatalogueWriter(_runner);

  PostSaleUseCase get postSale =>
      PostSaleUseCase(writer: DriftSaleWriter(runner: _runner));

  bool get isSetUp => _identity != null;

  /// Opens the database and works out whether this device has a shop yet.
  ///
  /// [databasePath] is for tests; production picks the application support
  /// directory, which Android excludes from the media scanner and from
  /// automatic cloud backup, so a shop's books do not end up in someone's
  /// photo gallery.
  static Future<AppServices> open({
    String? databasePath,
    Clock clock = const SystemClock(),
    String appVersion = '0.1.0',
  }) async {
    final path = databasePath ?? await _defaultDatabasePath();
    final database = AppDatabase(
      driftDatabase(
        name: p.basenameWithoutExtension(path),
        native: DriftNativeOptions(
          databaseDirectory: () async => Directory(p.dirname(path)),
        ),
      ),
    );
    return _wire(
      database,
      clock,
      appVersion,
      FileDraftStore(Directory(p.dirname(path))),
    );
  }

  /// Opens against an executor the caller already has. Used by tests.
  static Future<AppServices> openWith(
    QueryExecutor executor, {
    Clock clock = const SystemClock(),
    String appVersion = '0.1.0-test',
    DraftStore? drafts,
  }) =>
      _wire(
        AppDatabase(executor),
        clock,
        appVersion,
        drafts ?? InMemoryDraftStore(),
      );

  static Future<AppServices> _wire(
    AppDatabase database,
    Clock clock,
    String appVersion,
    DraftStore drafts,
  ) async {
    final ids = UlidGenerator();
    final queries = DriftAppQueries(database);

    // Which device is this? Resolved before anything can be written, because
    // ActorContext is a required parameter of every mutation and a write can
    // never be attributed to a device that is not registered.
    final device = await database
        .customSelect(
          'SELECT id FROM devices WHERE is_this_device = 1 '
          'AND deleted_at_utc IS NULL LIMIT 1',
        )
        .getSingleOrNull();
    final deviceId = device?.read<String>('id');

    // The highest HLC this device ever issued is already in the outbox, which
    // the single write path guarantees is complete — so there is no separate
    // counter to persist, keep in step, or lose in a power cut.
    final hlc = deviceId == null
        ? HlcClock(deviceId: 'unregistered', clock: clock)
        : await resumeHlcClock(database, deviceId: deviceId, clock: clock);

    final runner = TxRunner(database: database, ids: ids, hlc: hlc);

    final services = AppServices._(
      database: database,
      queries: queries,
      receipts: const ThermalReceiptRenderer(),
      clock: clock,
      ids: ids,
      drafts: drafts,
      // One small file read, before the first frame. The counter has to be
      // able to restore the cart synchronously: a bill that arrives a frame
      // late shows the cashier an empty one first, and an empty one is a bill
      // they start ringing again.
      restoredCartDraft: await drafts.read(cartDraftSlot),
      runner: runner,
    );

    final firm = await queries.currentFirm();
    if (firm != null && deviceId != null) {
      final owner = await database
          .customSelect(
            "SELECT id FROM users WHERE firm_id = ? AND role = 'owner' "
            'AND deleted_at_utc IS NULL LIMIT 1',
            variables: [Variable<String>(firm.id)],
          )
          .getSingleOrNull();
      if (owner != null) {
        services._identity = ActorIdentity(
          firmId: firm.id,
          userId: owner.read<String>('id'),
          deviceId: deviceId,
        );
      }
    }

    return services;
  }

  /// Runs the first-run wizard's write.
  ///
  /// Reopens the clocks afterwards, because until this moment there was no
  /// device row for the HLC to belong to.
  Future<FirmProfile> setUpShop({
    required String shopName,
    required String ownerName,
    required String deviceLabel,
    String city = '',
    String province = 'punjab',
    String businessKind = 'general',
  }) async {
    final result = await FirstRunSeeder(
      database: database,
      ids: ids,
      clock: clock,
    ).seed(
      shopName: shopName,
      ownerName: ownerName,
      deviceLabel: deviceLabel,
      platform: _platformName(),
      city: city,
      province: province,
      businessKind: businessKind,
    );

    _identity = ActorIdentity(
      firmId: result.firmId,
      userId: result.ownerUserId,
      deviceId: result.deviceId,
    );

    // The HLC now has a device to belong to. It is replaced rather than
    // merged: the node id is part of every timestamp and cannot be changed
    // after construction.
    _adoptDevice(
      await resumeHlcClock(
        database,
        deviceId: result.deviceId,
        clock: clock,
      ),
    );

    final firm = await queries.currentFirm();
    return firm!;
  }

  /// A context stamped with the current instant.
  ///
  /// Every row a single operation writes shares this timestamp, so an invoice
  /// never appears to predate its own lines just because the write took eleven
  /// milliseconds.
  ActorContext actorNow() {
    final id = _identity;
    if (id == null) {
      throw StateError(
        'This device has no shop yet. Run the setup wizard before writing '
        'anything — there is no actor for the envelope to name.',
      );
    }
    return ActorContext(
      firmId: id.firmId,
      userId: id.userId,
      deviceId: id.deviceId,
      startedAtUtc: clock.nowUtc(),
    );
  }

  /// Updates the shop's own details from the settings screen.
  Future<void> updateFirm(Map<String, Object?> columns) async {
    final actor = actorNow();
    await _runner.run(actor, (tx) async {
      await tx.update('firms', actor.firmId, columns);
      tx.audit(
        action: 'FIRM_UPDATED',
        entityTable: 'firms',
        entityId: actor.firmId,
        summary: 'Shop details edited',
      );
    });
  }

  Future<DatabaseHealth> checkHealth() => database.checkHealth();

  Future<void> close() => database.close();

  static Future<String> _defaultDatabasePath() async =>
      p.join((await booksDirectory()).path, 'bazaar_ledger.sqlite');

  /// Where the books live: the one directory Android will not copy off the
  /// phone.
  ///
  /// `android:allowBackup="false"` already stops Auto Backup uploading the
  /// database to a Google account the shopkeeper never asked for — the first
  /// screen of this app promises, in Roman Urdu, that their hisaab stays on
  /// this phone with no account and no server, and a silent nightly upload
  /// would make that a lie.
  ///
  /// But the manifest flag is not the whole story. Android's own
  /// documentation says that for apps targeting 12 or higher, "on devices
  /// from some device manufacturers, you can't disable device-to-device
  /// migration of your app's files" — and the manufacturers this ships to are
  /// exactly the ones that phrase is about: Transsion is roughly 44% of the
  /// Pakistani market at the bottom end.
  ///
  /// `getNoBackupFilesDir()` is excluded from backup and from transfer by the
  /// platform itself, whatever the manifest says and whatever the OEM has
  /// done to it. `path_provider` does not expose it, but it is a documented,
  /// stable part of the app data layout: `files` and `no_backup` are siblings
  /// under the app's data directory.
  ///
  /// If it cannot be created for any reason, the support directory is used
  /// instead. A shopkeeper who cannot open their books at all is worse off
  /// than one whose books might survive a phone-to-phone transfer.
  static Future<Directory> booksDirectory() async {
    final support = await getApplicationSupportDirectory();
    if (!Platform.isAndroid) return support;
    try {
      final noBackup = Directory(p.join(p.dirname(support.path), 'no_backup'));
      if (!noBackup.existsSync()) noBackup.createSync(recursive: true);
      return noBackup;
    } on Object {
      return support;
    }
  }

  static String _platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return 'test';
  }
}

/// Who is using this device.
final class ActorIdentity {
  const ActorIdentity({
    required this.firmId,
    required this.userId,
    required this.deviceId,
  });

  final String firmId;
  final String userId;
  final String deviceId;
}

/// Opens a throwaway database in memory, for tests and demos.
///
/// Deliberately part of the shipped API rather than a test helper copied into
/// every suite. Widget and integration tests must drive the real write path
/// against a real SQLite file — mock databases are banned in integration tests
/// by lint, because the previous build's suite passed while the app wrote
/// nothing at all. What varies between production and a test is where the
/// bytes live, and nothing else.
Future<AppServices> openInMemoryServices({
  Clock clock = const SystemClock(),
  String appVersion = '0.1.0-test',
}) async {
  _resolveSqliteForHost();
  return AppServices.openWith(
    NativeDatabase.memory(),
    clock: clock,
    appVersion: appVersion,
  );
}

var _sqliteResolved = false;

/// Points `sqlite3` at a native library on desktop hosts that do not ship one
/// on the default search path.
///
/// Android and iOS get theirs from `sqlite3_flutter_libs`, and Linux CI finds
/// `libsqlite3.so` the usual way. Windows 10 1803 and later carry
/// `winsqlite3.dll` in System32 — a current SQLite, 3.51 on the development
/// machine — so the suite runs with no vendored binary and no download step.
void _resolveSqliteForHost() {
  if (_sqliteResolved) return;
  _sqliteResolved = true;
  if (Platform.isWindows) {
    open.overrideFor(
      OperatingSystem.windows,
      () => DynamicLibrary.open('winsqlite3.dll'),
    );
  }
}
