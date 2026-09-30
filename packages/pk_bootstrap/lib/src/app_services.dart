import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pk_application/pk_application.dart';
import 'package:pk_data/pk_data.dart';
import 'package:pk_domain/pk_domain.dart';
import 'package:pk_import/pk_import.dart';
import 'package:pk_platform/pk_platform.dart';
import 'package:pk_reports/pk_reports.dart';
import 'package:pk_sync/pk_sync.dart';
import 'backup_service.dart';
import 'encrypted_database.dart';
import 'printing_services.dart';

part 'import_services.dart';
part 'sync_services.dart';

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
    required this.printing,
    required this.pictures,
    required this.databasePath,
    required String appVersion,
    required TxRunner runner,
  }) : _runner = runner,
       _appVersion = appVersion;

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

  /// Getting a receipt onto paper.
  ///
  /// This field is the whole of what two commits announcing "a receipt can
  /// reach paper" actually delivered. The transports, the layouts, the
  /// ESC/POS encoder and the idempotent queue were all real, all tested, and
  /// reachable from nothing: `pk_bootstrap` deliberately did not export them,
  /// AppServices had no printer, and the receipt screen rendered a crossed-out
  /// printer icon under a string reading "Printing arrives in M2." A library
  /// nothing links to is not a feature.
  final PrintingServices printing;

  /// Item photographs, cheque images, the bank QR a shopkeeper imported.
  ///
  /// Stored inline in the database rather than as files beside it, which the
  /// schema chose deliberately: a backup is then one file, and a restore
  /// cannot come back with every picture missing because the phone they were
  /// taken on is gone.
  final PictureServices pictures;

  TxRunner _runner;
  final String _appVersion;

  /// Where the books are on disk, or null for a database held in memory.
  ///
  /// A restore is staged beside this file and swapped in at the next open,
  /// so a build with no file has nothing to restore into.
  final String? databasePath;

  /// Sealing the books into a `.pkbak` the shopkeeper can keep somewhere
  /// else. Built per call, like the writers, so it writes its audit row
  /// through whichever runner is current.
  BackupService get backups {
    require(Permission.backups);
    return BackupService(
      database: database,
      runner: () => _runner,
      clock: clock,
      appVersion: _appVersion,
      booksKey: _booksKey,
    );
  }

  /// The key the books on this phone are encrypted with, or null when they
  /// are not: a phone whose keystore could not keep one, or a test.
  String? _booksKey;

  /// Whether the books on this phone are encrypted at rest.
  bool get booksEncrypted => _booksKey != null;

  /// When this shop last made a backup, or null if it never has.
  Future<DateTime?> lastBackupAt() async {
    final id = _identity;
    if (id == null) return null;
    final row = await database
        .customSelect(
          'SELECT MAX(at_utc) AS at FROM audit_log '
          "WHERE firm_id = ? AND action_code = 'BACKUP_MADE'",
          variables: [Variable<String>(id.firmId)],
        )
        .getSingle();
    final at = row.readNullable<int>('at');
    return at == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(at, isUtc: true);
  }

  /// Who is signed in. Null until first run has produced a firm and an owner.
  ActorIdentity? _identity;

  ActorIdentity? get identity => _identity;

  /// Built from the current runner every time, so a writer handed out before
  /// first run cannot keep writing through the clock that predates the device.
  CatalogueWriter get catalogue => DriftCatalogueWriter(_runner);

  /// The one calculator every bill, quotation and challan is priced by, and
  /// the counter's own preview with it: the Pakistan tax pack, which charges
  /// nothing at all for a shop that is not registered for sales tax.
  static const taxCalculator = SaleCalculator(taxEngine: PakistanTaxEngine());

  PostSaleUseCase get postSale {
    require(Permission.sell);
    return PostSaleUseCase(
      writer: DriftSaleWriter(runner: _runner),
      calculator: taxCalculator,
    );
  }

  RecordReceiptUseCase get recordReceipt {
    require(Permission.takePayments);
    return RecordReceiptUseCase(writer: DriftPaymentWriter(runner: _runner));
  }

  SaveQuotationUseCase get saveQuotation {
    require(Permission.sell);
    return SaveQuotationUseCase(
      writer: DriftQuotationWriter(runner: _runner),
      calculator: taxCalculator,
    );
  }

  IssueChallanUseCase get issueChallan {
    require(Permission.sell);
    return IssueChallanUseCase(
      writer: DriftChallanWriter(runner: _runner),
      calculator: taxCalculator,
    );
  }

  /// The report pack, read from the books as they stand.
  ReportEngine get reports {
    require(Permission.reports);
    return ReportEngine(DriftReportSource(database));
  }

  RecordDebitNoteUseCase get chargeParty {
    require(Permission.takePayments);
    return RecordDebitNoteUseCase(
      writer: DriftDebitNoteWriter(runner: _runner),
    );
  }

  MoveChequeUseCase get cheques {
    require(Permission.cheques);
    return MoveChequeUseCase(writer: DriftChequeWriter(runner: _runner));
  }

  PaySupplierUseCase get paySupplier {
    require(Permission.purchases);
    return PaySupplierUseCase(writer: DriftPaymentWriter(runner: _runner));
  }

  /// Recipes and production runs (M17). Stock-moving, so it takes the
  /// purchases permission, as receiving goods does.
  ManufacturingWriter get manufacturing {
    require(Permission.purchases);
    return DriftManufacturingWriter(runner: _runner);
  }

  RecordPurchaseUseCase get recordPurchase {
    require(Permission.purchases);
    return RecordPurchaseUseCase(writer: DriftPurchaseWriter(runner: _runner));
  }

  VoidDocumentUseCase get voidDocument {
    require(Permission.voidDocuments);
    return VoidDocumentUseCase(writer: DriftVoidWriter(runner: _runner));
  }

  RecordPurchaseReturnUseCase get recordPurchaseReturn {
    require(Permission.purchases);
    return RecordPurchaseReturnUseCase(
      writer: DriftPurchaseReturnWriter(runner: _runner),
    );
  }

  RecordReturnUseCase get recordReturn {
    require(Permission.takeReturns);
    return RecordReturnUseCase(writer: DriftReturnWriter(runner: _runner));
  }

  PostJournalVoucherUseCase get postJournal {
    require(Permission.journal);
    return PostJournalVoucherUseCase(
      writer: DriftJournalWriter(runner: _runner),
    );
  }

  CloseDayUseCase get closeDay {
    require(Permission.closeDay);
    return CloseDayUseCase(writer: DriftDayCloseWriter(runner: _runner));
  }

  RecordExpenseUseCase get recordExpense {
    require(Permission.expenses);
    return RecordExpenseUseCase(writer: DriftExpenseWriter(runner: _runner));
  }

  bool get isSetUp => _identity != null;

  /// Counters on the shop's wi-fi.
  late final SyncServices sync = SyncServices._(this);

  /// Items and parties from a spreadsheet.
  late final ImportServices import = ImportServices._(this);

  // ---------------------------------------------------------------------
  // Who is at the phone
  // ---------------------------------------------------------------------

  /// How PINs are hashed. Cheap in tests, Argon2id at full cost otherwise.
  PinHasher pinHasher = const PinHasher();

  /// Staff, and the PINs that let them in.
  StaffStore get staffStore => DriftStaffStore(database, () => _runner);

  StaffMember? _signedIn;
  bool _locked = false;
  int _failedPins = 0;
  DateTime? _pinsBlockedUntil;

  /// Who is using the app now; null while it is locked.
  StaffMember? get currentUser => _locked ? null : _signedIn;

  /// Whether somebody has to sign in before anything can be done.
  bool get isLocked => _locked;

  /// Whether [permission] is allowed to whoever is signed in.
  ///
  /// A shop set up before M9 has one user, the owner, with no PIN; they are
  /// signed in from the moment the app opens, as they always were.
  bool can(Permission permission) {
    if (_locked) return false;
    return (_signedIn?.role ?? Role.owner).can(permission);
  }

  /// Throws [PermissionDenied] unless [can] allows [permission].
  void require(Permission permission) {
    if (_locked) {
      throw PermissionDenied(permission, 'Sign in first.');
    }
    if (!can(permission)) {
      throw PermissionDenied(
        permission,
        'Only the owner or a manager can do this. '
        '${_signedIn?.name ?? 'This user'} is signed in as '
        '${_signedIn?.role.name ?? 'staff'}.',
      );
    }
  }

  /// Reads who is signed in when the app opens: the owner, locked if
  /// anybody in the shop has a PIN.
  Future<void> _resumeSession() async {
    final id = _identity;
    if (id == null) return;
    final everyone = await staffStore.staff(id.firmId);
    _signedIn = everyone.where((m) => m.id == id.userId).firstOrNull;
    _locked = everyone.any((m) => m.isActive && m.hasPin);
  }

  /// Puts into the books any opening stock or opening balance entered before
  /// M10 posted them, once, as the owner who entered them.
  Future<void> _postMissingOpenings() async {
    final id = _identity;
    if (id == null) return;
    await _runner.run(
      ActorContext(
        firmId: id.firmId,
        userId: id.userId,
        deviceId: id.deviceId,
        startedAtUtc: clock.nowUtc(),
      ),
      postMissingOpenings,
    );
  }

  // ---------------------------------------------------------------------
  // More than one firm
  // ---------------------------------------------------------------------

  /// Starts the books of another firm on this phone: its own chart, its own
  /// numbering, its own khatas and its own staff, in the same database and
  /// sealed into the same backup. Owner only. Returns the new firm's id; the
  /// phone stays on the firm it had open until [switchFirm].
  Future<String> addFirm({
    required String shopName,
    required String ownerName,
    String city = '',
    String province = 'punjab',
  }) async {
    require(Permission.manageUsers);
    final name = shopName.trim();
    if (name.isEmpty) {
      throw const PermissionDenied(
        Permission.manageUsers,
        'A firm needs a name.',
      );
    }
    final label =
        (await database
                .customSelect(
                  'SELECT label FROM devices WHERE id = ?',
                  variables: [Variable<String>(_identity!.deviceId)],
                )
                .getSingleOrNull())
            ?.read<String>('label');
    final result =
        await FirstRunSeeder(database: database, ids: ids, clock: clock).seed(
          shopName: name,
          ownerName: ownerName.trim().isEmpty ? 'Owner' : ownerName.trim(),
          deviceLabel: label ?? 'This phone',
          platform: _platformName(),
          city: city,
          province: province,
          allowSecondFirm: true,
        );
    return result.firmId;
  }

  /// Opens the books of [firmId] on this phone. The owner of the firm open
  /// now may switch; the other firm then opens as its owner, or on its own
  /// sign-in screen when anybody there has a PIN.
  Future<void> switchFirm(String firmId) async {
    require(Permission.manageUsers);
    final device = await database
        .customSelect(
          'SELECT id FROM devices WHERE is_this_device = 1 AND firm_id = ? '
          'AND deleted_at_utc IS NULL LIMIT 1',
          variables: [Variable<String>(firmId)],
        )
        .getSingleOrNull();
    final owner = await database
        .customSelect(
          "SELECT id FROM users WHERE firm_id = ? AND role = 'owner' "
          'AND deleted_at_utc IS NULL LIMIT 1',
          variables: [Variable<String>(firmId)],
        )
        .getSingleOrNull();
    if (device == null || owner == null) {
      throw StateError('That firm is not kept on this phone.');
    }
    final deviceId = device.read<String>('id');
    _identity = ActorIdentity(
      firmId: firmId,
      userId: owner.read<String>('id'),
      deviceId: deviceId,
    );
    // The host serves one firm's books; it does not follow the switch.
    await sync.stopHosting(forget: false);
    _adoptDevice(
      await resumeHlcClock(database, deviceId: deviceId, clock: clock),
    );
    await drafts.write(activeFirmSlot, firmId);
    // A bill half-rung in one firm must not be finished in another.
    await drafts.clear(cartDraftSlot);
    _failedPins = 0;
    _pinsBlockedUntil = null;
    await _resumeSession();
    await _postMissingOpenings();
  }

  /// Locks the app until somebody signs in. Does nothing in a shop where
  /// nobody has a PIN, since nobody could then get back in but the owner by
  /// default anyway.
  Future<void> lock() async {
    final id = _identity;
    if (id == null) return;
    final everyone = await staffStore.staff(id.firmId);
    if (everyone.any((m) => m.isActive && m.hasPin)) _locked = true;
  }

  /// Signs [userId] in with [pin]. Returns whether it was right.
  ///
  /// Five wrong PINs in a row block every sign-in for thirty seconds, so a
  /// four-digit PIN cannot be walked through at the counter.
  Future<bool> signIn(String userId, String pin) async {
    final id = _identity;
    if (id == null) return false;
    final blocked = _pinsBlockedUntil;
    if (blocked != null && clock.nowUtc().isBefore(blocked)) {
      throw PermissionDenied(
        Permission.sell,
        'Too many wrong PINs. Wait ${blocked.difference(clock.nowUtc()).inSeconds + 1} seconds.',
      );
    }
    final member = await staffStore.member(id.firmId, userId);
    final stored = await staffStore.pinOf(id.firmId, userId);
    final ok =
        member != null &&
        member.isActive &&
        stored != null &&
        await pinHasher.verify(pin, hash: stored.hash, salt: stored.salt);
    if (!ok) {
      _failedPins++;
      if (_failedPins >= 5) {
        _failedPins = 0;
        _pinsBlockedUntil = clock.nowUtc().add(const Duration(seconds: 30));
      }
      return false;
    }
    _failedPins = 0;
    _pinsBlockedUntil = null;
    _identity = ActorIdentity(
      firmId: id.firmId,
      userId: userId,
      deviceId: id.deviceId,
    );
    _signedIn = member;
    _locked = false;
    await staffStore.recordSignIn(actorNow());
    return true;
  }

  /// Adds a member of staff with their own PIN. Owner only, and only once
  /// the owner has a PIN: staff with PINs and an owner without one would
  /// leave the owner's screens open to anybody who taps the owner's name.
  Future<String> addStaff({
    required String name,
    required Role role,
    required String pin,
  }) async {
    require(Permission.manageUsers);
    final owner = _signedIn;
    if (owner == null || !owner.hasPin) {
      throw const PermissionDenied(
        Permission.manageUsers,
        'Set your own PIN first, so staff cannot open your screens.',
      );
    }
    return staffStore.add(
      actorNow(),
      name: name,
      role: role,
      pin: await pinHasher.hash(pin),
    );
  }

  /// Sets [userId]'s PIN: the owner for anybody, anybody for themselves.
  Future<void> setPin(String userId, String pin) async {
    if (userId != _signedIn?.id) require(Permission.manageUsers);
    if (_locked) require(Permission.manageUsers);
    await staffStore.setPin(actorNow(), userId, await pinHasher.hash(pin));
    if (userId == _signedIn?.id) {
      _signedIn = await staffStore.member(_identity!.firmId, userId);
    }
  }

  Future<void> setStaffRole(String userId, Role role) async {
    require(Permission.manageUsers);
    await staffStore.setRole(actorNow(), userId, role);
  }

  Future<void> setStaffActive(String userId, {required bool active}) async {
    require(Permission.manageUsers);
    await staffStore.setActive(actorNow(), userId, active: active);
  }

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
    List<PrinterTransport>? transports,
    BooksKeySource keys = const AndroidBooksKey(),
  }) async {
    final path = databasePath ?? await defaultDatabasePath();

    // Before anything opens the file. A restore is only ever swapped in here,
    // when nothing can be holding the database, so there is no moment at
    // which a half-replaced file is being written to.
    final restored = Restore.applyPending(path);

    // Encrypted at rest when this phone can keep a key (M14). Books kept in
    // the clear — a shop set up before, or a backup just restored — are
    // encrypted in place on the way in. A phone whose keystore cannot keep
    // a key goes on with plain books rather than not opening at all; Data
    // Health says which it is.
    final key = await keys.key();
    if (key != null && BooksFile.isPlain(path)) {
      BooksFile.encryptInPlace(path, key);
    }
    if (File(path).existsSync() &&
        File(path).lengthSync() > 0 &&
        !BooksFile.isPlain(path) &&
        (key == null || !BooksFile.opensWith(path, key))) {
      throw const BooksLocked();
    }

    final database = AppDatabase(BooksFile.open(path, key: key));
    final services = await _wire(
      database,
      clock,
      appVersion,
      FileDraftStore(Directory(p.dirname(path))),
      transports,
      databasePath: path,
    );
    services._booksKey = key;
    if (restored && services._identity != null) {
      // The first row the restored books hold that the backup did not: when
      // they came back, and on which device.
      final actor = services.actorNow();
      await services._runner.run(actor, (tx) async {
        tx.audit(
          action: 'BACKUP_RESTORED',
          entityTable: 'firms',
          entityId: actor.firmId,
          summary: 'Books restored from a backup',
        );
      });
    }
    return services;
  }

  /// Opens against an executor the caller already has. Used by tests.
  static Future<AppServices> openWith(
    QueryExecutor executor, {
    Clock clock = const SystemClock(),
    String appVersion = '0.1.0-test',
    DraftStore? drafts,
    List<PrinterTransport>? transports,
  }) => _wire(
    AppDatabase(executor),
    clock,
    appVersion,
    drafts ?? InMemoryDraftStore(),
    // A test that does not name its transports gets none, so nothing in a
    // suite can accidentally reach for a real socket or a real radio.
    transports ?? const [],
  );

  static Future<AppServices> _wire(
    AppDatabase database,
    Clock clock,
    String appVersion,
    DraftStore drafts,
    List<PrinterTransport>? transports, {
    String? databasePath,
  }) async {
    final ids = UlidGenerator();
    // Declared before `services` so the store can close over it, and reads the
    // runner through a supplier rather than holding one: the bootstrap rebuilds
    // its runner once first run registers this device, and anything caching the
    // old one would keep stamping rows with the `unregistered` node id.
    late final AppServices services;
    // The firm the phone has open, read through the identity so a switch of
    // firm is seen by every query at once.
    final queries = DriftAppQueries(
      database,
      activeFirmId: () => services._identity?.firmId,
    );

    // Which device is this? Resolved before anything can be written, because
    // ActorContext is a required parameter of every mutation and a write can
    // never be attributed to a device that is not registered.
    //
    // A phone that keeps the books of more than one firm is registered once
    // in each, and opens on the one it last had open.
    final lastFirm = await drafts.read(activeFirmSlot);
    final devices = await database
        .customSelect(
          'SELECT id, firm_id FROM devices WHERE is_this_device = 1 '
          'AND deleted_at_utc IS NULL ORDER BY created_at_utc',
        )
        .get();
    final device =
        devices
            .where((d) => d.read<String>('firm_id') == lastFirm)
            .firstOrNull ??
        devices.firstOrNull;
    final deviceId = device?.read<String>('id');
    final deviceFirmId = device?.read<String>('firm_id');

    // The highest HLC this device ever issued is already in the outbox, which
    // the single write path guarantees is complete — so there is no separate
    // counter to persist, keep in step, or lose in a power cut.
    final hlc = deviceId == null
        ? HlcClock(deviceId: 'unregistered', clock: clock)
        : await resumeHlcClock(database, deviceId: deviceId, clock: clock);

    final runner = TxRunner(database: database, ids: ids, hlc: hlc);

    final printing = PrintingServices(
      store: DriftPrinterSettings(database, () => services._runner),
      transports: transports ?? const [],
    );

    services = AppServices._(
      database: database,
      queries: queries,
      receipts: const ThermalReceiptRenderer(),
      clock: clock,
      ids: ids,
      drafts: drafts,
      printing: printing,
      pictures: PictureServices._(
        store: DriftAttachments(database, () => services._runner),
      ),
      // One small file read, before the first frame. The counter has to be
      // able to restore the cart synchronously: a bill that arrives a frame
      // late shows the cashier an empty one first, and an empty one is a bill
      // they start ringing again.
      restoredCartDraft: await drafts.read(cartDraftSlot),
      databasePath: databasePath,
      appVersion: appVersion,
      runner: runner,
    );

    if (deviceFirmId != null && deviceId != null) {
      final owner = await database
          .customSelect(
            "SELECT id FROM users WHERE firm_id = ? AND role = 'owner' "
            'AND deleted_at_utc IS NULL LIMIT 1',
            variables: [Variable<String>(deviceFirmId)],
          )
          .getSingleOrNull();
      if (owner != null) {
        services._identity = ActorIdentity(
          firmId: deviceFirmId,
          userId: owner.read<String>('id'),
          deviceId: deviceId,
        );
        await services._resumeSession();
        await services._postMissingOpenings();
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
    final result =
        await FirstRunSeeder(database: database, ids: ids, clock: clock).seed(
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
      await resumeHlcClock(database, deviceId: result.deviceId, clock: clock),
    );
    await _resumeSession();

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
    if (_locked) {
      throw const PermissionDenied(Permission.sell, 'Sign in first.');
    }
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

  /// How this shop's weighing scale lays out its labels (M16).
  static const scaleFormatSetting = 'scale.format';

  Future<ScaleFormat> scaleFormat() async {
    final id = _identity;
    if (id == null) return ScaleFormat.standard;
    final row = await database
        .customSelect(
          'SELECT setting_value FROM settings WHERE firm_id = ? '
          'AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(id.firmId),
            Variable<String>(scaleFormatSetting),
          ],
        )
        .getSingleOrNull();
    return ScaleFormat.fromJson(row?.read<String>('setting_value'));
  }

  Future<void> setScaleFormat(ScaleFormat format) async {
    require(Permission.settings);
    if (!format.isValid) {
      throw const PermissionDenied(
        Permission.settings,
        'A prefix can mean weight or price, not both, and each must be '
        'between 20 and 29.',
      );
    }
    final actor = actorNow();
    await _runner.run(actor, (tx) async {
      final held = await tx.selectOne(
        'SELECT id FROM settings WHERE firm_id = ? AND setting_key = ? '
        'AND deleted_at_utc IS NULL',
        [actor.firmId, scaleFormatSetting],
      );
      if (held == null) {
        await tx.insert('settings', {
          'setting_key': scaleFormatSetting,
          'setting_value': format.toJson(),
          'value_type': 'json',
        });
      } else {
        await tx.update('settings', held.read<String>('id'), {
          'setting_value': format.toJson(),
        });
      }
      tx.audit(
        action: 'SCALE_FORMAT_SET',
        entityTable: 'settings',
        entityId: actor.firmId,
        summary: 'Weighing-scale labels set up',
      );
    });
  }

  /// Updates the shop's own details from the settings screen.
  Future<void> updateFirm(Map<String, Object?> columns) async {
    require(Permission.settings);
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

  Future<void> close() async {
    await sync._close();
    await database.close();
  }

  /// Where the books live on this phone. Public so the startup-failure
  /// screen, which has no services, can stage a restore into it.
  static Future<String> defaultDatabasePath() async =>
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
  List<PrinterTransport>? transports,
}) async {
  final services = await AppServices.openWith(
    NativeDatabase.memory(),
    clock: clock,
    appVersion: appVersion,
    // None unless a test asks for one. A suite that could reach a real socket
    // or a real Bluetooth radio would pass or fail depending on what happened
    // to be plugged into the machine running it.
    transports: transports,
  );
  // A suite signs in dozens of times; Argon2id at full cost would make each
  // one a second of pure hashing.
  services.pinHasher = const PinHasher.forTestsOnly();
  return services;
}

/// Pictures the shop owns.
///
/// A thin seam over the store and the shrinker, so a screen never has to know
/// that a photograph has to be reduced before it can be kept, or what the
/// ceiling is. Handing a screen the raw store would mean every caller
/// remembering to shrink, and the one that forgot would be the one that put an
/// eight-megabyte camera original into a shop's only backup.
final class PictureServices {
  PictureServices._({required DriftAttachments store}) : _store = store;

  final DriftAttachments _store;
  final ImageShrinker _shrinker = const DartImageShrinker();

  /// Reduces [source] and stores it against one row, replacing what was there.
  ///
  /// Throws [FormatException] when the bytes are not a picture this build can
  /// read — a thing to say to a shopkeeper in words, rather than a silent
  /// failure that leaves them tapping the same button again.
  Future<void> setItemPicture(
    ActorContext actor, {
    required String itemId,
    required Uint8List source,
    required String fileName,
  }) async {
    final shrunk = await _shrinker.shrink(source, id: itemId);
    await _store.attach(
      actor,
      kind: 'item_image',
      ownerTable: 'items',
      ownerId: itemId,
      image: shrunk,
      fileName: fileName,
    );
  }

  Future<ImageAttachment?> itemPicture(String firmId, String itemId) =>
      _store.forOwner(firmId, 'items', itemId);

  Future<void> clearItemPicture(ActorContext actor, String itemId) =>
      _store.detach(actor, ownerTable: 'items', ownerId: itemId);
}
