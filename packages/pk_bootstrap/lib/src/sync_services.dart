part of 'app_services.dart';

/// Where a counter remembers the master it joined: `{firm, host, port}`.
const syncMasterSlot = 'sync_master';

/// The firm this phone hosts sync for, when it does. Read at start so a
/// master that was hosting before a restart goes on hosting after it.
const syncHostingSlot = 'sync_hosting';

/// A device of the shop, as the sync screen lists it.
final class SyncDevice {
  const SyncDevice({
    required this.id,
    required this.label,
    required this.role,
    required this.prefix,
    required this.isThisDevice,
    this.lastSyncedAt,
  });

  final String id;
  final String label;

  /// `master` or `counter`.
  final String role;

  /// The letter in the bill numbers this device prints.
  final String prefix;
  final bool isThisDevice;

  /// When this phone last took in something the device wrote.
  final DateTime? lastSyncedAt;
}

/// Counters on the shop's wi-fi: the master lets them join and serves them,
/// and a counter joins once and then syncs with it.
///
/// Nothing leaves the shop. The master listens on the local network only
/// while the owner has sync turned on, a counter joins with the six-digit
/// code the master shows, and every request after that carries the shop's
/// sync key. The traffic itself is not encrypted: it stays on the shop's
/// own wi-fi, which is why joining needs the code shown on the master.
final class SyncServices {
  SyncServices._(this._app);

  final AppServices _app;
  SyncHost? _host;
  StreamSubscription<ApplyResult>? _hostEvents;
  String? _key;
  final _received = StreamController<ApplyResult>.broadcast();

  /// Fires when a counter's changes have been taken in on this master.
  Stream<ApplyResult> get received => _received.stream;

  bool get isHosting => _host?.isRunning ?? false;

  int? get port => _host?.port;

  /// The code to show while a counter may join.
  String? get pairingCode => _host?.pairingCode;

  DriftSyncStore _store(String firmId) => DriftSyncStore(
    _app.database,
    firmId: firmId,
    mergeClock: (remote) => _app._runner.hlc.merge(remote),
    now: _app.clock.nowUtc,
  );

  ActorIdentity get _id {
    final id = _app._identity;
    if (id == null) {
      throw const SyncRefused('Set up the shop on this phone first.');
    }
    return id;
  }

  /// An actor for writes the master makes on a counter's behalf, which must
  /// work while the master's own screen is locked.
  ActorContext _hostActor() => ActorContext(
    firmId: _id.firmId,
    userId: _id.userId,
    deviceId: _id.deviceId,
    startedAtUtc: _app.clock.nowUtc(),
  );

  // -------------------------------------------------------------------------
  // The master
  // -------------------------------------------------------------------------

  /// Starts serving the counters. Owner or manager, on a plan with more
  /// than one counter; the counters that join need no plan of their own.
  Future<int> startHosting({
    int port = defaultSyncPort,
    InternetAddress? address,
  }) async {
    _app.require(Permission.settings);
    _app.plans.require(PlanFeature.lanSync);
    return _start(port: port, address: address);
  }

  Future<int> _start({required int port, InternetAddress? address}) async {
    if (await isCounter()) {
      throw const SyncRefused(
        'This phone is a counter. Counters sync with the master; only the '
        'master lets others join.',
      );
    }
    final firmId = _id.firmId;
    _key = await _app._runner.run(_hostActor(), ensureSyncKey);
    final host = _host ??= SyncHost(
      peer: _store(firmId),
      syncKey: () => _key ?? '',
      admit: _admit,
    );
    _hostEvents ??= host.changed.listen(_received.add);
    final bound = await host.start(port: port, address: address);
    await _app.drafts.write(syncHostingSlot, firmId);
    // Says where it is on the wi-fi, so a counter can find it (M23). A
    // network that will not carry a broadcast still has the typed address.
    try {
      await (_beacon ??= SyncBeacon()).start(
        port: bound,
        shopName: (await _app.queries.currentFirm())?.name ?? '',
      );
    } on Object {
      _beacon = null;
    }
    return bound;
  }

  SyncBeacon? _beacon;

  /// Masters heard on this wi-fi in the next few seconds.
  Future<List<FoundMaster>> findMasters() => pk_sync.findMasters();

  Future<JoinGrant> _admit({
    required String label,
    required String platform,
  }) async {
    final deviceId = await _app._runner.run(
      _hostActor(),
      (tx) => admitCounter(tx, label: label, platform: platform),
    );
    final firm = await _app.queries.currentFirm();
    return JoinGrant(
      firmId: _id.firmId,
      deviceId: deviceId,
      syncKey: _key ?? '',
      shopName: firm?.name ?? '',
    );
  }

  /// Lets one counter join, and returns the code it must type.
  String openJoining() {
    _app.require(Permission.settings);
    final host = _host;
    if (host == null || !host.isRunning) {
      throw const SyncRefused('Turn sync on first.');
    }
    return host.openForJoining();
  }

  void closeJoining() => _host?.closeJoining();

  /// Stops serving. [forget] also stops it coming back at the next start.
  Future<void> stopHosting({bool forget = true}) async {
    final host = _host;
    _host = null;
    _beacon?.stop();
    _beacon = null;
    await _hostEvents?.cancel();
    _hostEvents = null;
    await host?.dispose();
    if (forget) await _app.drafts.clear(syncHostingSlot);
  }

  Future<void> _close() async {
    await stopHosting(forget: false);
    await _received.close();
  }

  /// Picks sync back up after the app opens: a master that was hosting
  /// hosts again. Never throws; a port another app holds is not a reason
  /// for the shop not to open.
  Future<void> resume() async {
    final id = _app._identity;
    if (id == null || isHosting) return;
    if (!_app.plans.has(PlanFeature.lanSync)) return;
    if (await _app.drafts.read(syncHostingSlot) != id.firmId) return;
    try {
      await _start(port: defaultSyncPort);
    } on Object {
      // Shown as off on the sync screen, where it can be turned on again.
    }
  }

  /// This phone's addresses on the local network, for the counter to type.
  static Future<List<String>> addresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      return [
        for (final i in interfaces)
          for (final a in i.addresses)
            if (!a.isLoopback) a.address,
      ];
    } on Object {
      return const [];
    }
  }

  // -------------------------------------------------------------------------
  // A counter
  // -------------------------------------------------------------------------

  /// Whether this phone joined another as a counter.
  Future<bool> isCounter() async {
    final id = _app._identity;
    if (id == null) return false;
    final row = await _app.database
        .customSelect(
          'SELECT device_role FROM devices WHERE id = ?',
          variables: [Variable<String>(id.deviceId)],
        )
        .getSingleOrNull();
    return row?.read<String>('device_role') == 'counter';
  }

  /// The master this counter syncs with, if it joined one.
  Future<({String host, int port})?> master() async {
    final id = _app._identity;
    final raw = await _app.drafts.read(syncMasterSlot);
    if (id == null || raw == null) return null;
    final json = jsonDecode(raw);
    if (json is! Map<String, Object?> || json['firm'] != id.firmId) {
      return null;
    }
    return (host: json['host']! as String, port: json['port']! as int);
  }

  /// Joins the master at [host] with the [code] it shows, takes in the
  /// whole of the shop's books, and opens them on this phone as a counter.
  ///
  /// On a phone that already keeps a shop of its own, the joined one is
  /// kept beside it, as a second firm is.
  Future<FirmProfile> join({
    required String host,
    required String code,
    required String label,
    int port = defaultSyncPort,
  }) async {
    if (_app.isSetUp) _app.require(Permission.manageUsers);
    final grant = await RemotePeer.join(
      host: host,
      port: port,
      code: code,
      label: label,
      platform: AppServices._platformName(),
    );
    final remote = RemotePeer(host: host, port: port, syncKey: grant.syncKey);
    final store = DriftSyncStore(
      _app.database,
      firmId: grant.firmId,
      now: _app.clock.nowUtc,
    );
    await store.apply(await remote.changesSince(const {}));
    await store.adoptThisDevice(grant.deviceId);

    final owner = await _app.database
        .customSelect(
          "SELECT id FROM users WHERE firm_id = ? AND role = 'owner' "
          'AND deleted_at_utc IS NULL LIMIT 1',
          variables: [Variable<String>(grant.firmId)],
        )
        .getSingleOrNull();
    if (owner == null) {
      throw const SyncRefused('The master sent a shop with no owner.');
    }
    _app._identity = ActorIdentity(
      firmId: grant.firmId,
      userId: owner.read<String>('id'),
      deviceId: grant.deviceId,
    );
    final clock = await resumeHlcClock(
      _app.database,
      deviceId: grant.deviceId,
      clock: _app.clock,
    );
    final newest = await _app.database
        .customSelect(
          'SELECT MAX(entity_hlc) AS h FROM change_log WHERE firm_id = ?',
          variables: [Variable<String>(grant.firmId)],
        )
        .getSingle();
    final h = newest.readNullable<String>('h');
    if (h != null) clock.merge(Hlc(h));
    _app._adoptDevice(clock);

    await _app.drafts.write(activeFirmSlot, grant.firmId);
    await _app.drafts.write(
      syncMasterSlot,
      jsonEncode({'firm': grant.firmId, 'host': host, 'port': port}),
    );
    await _app.drafts.clear(cartDraftSlot);
    await _app._resumeSession();
    return (await _app.queries.currentFirm())!;
  }

  /// Hands the master what this counter wrote and takes back what the
  /// master has, the other counters' included.
  Future<SyncReport> syncNow() async {
    final firmId = _id.firmId;
    final master = await this.master();
    if (master == null) {
      throw const SyncRefused('This phone has not joined a master.');
    }
    final key = await _app.database
        .customSelect(
          'SELECT setting_value FROM settings WHERE firm_id = ? '
          'AND setting_key = ? AND deleted_at_utc IS NULL',
          variables: [
            Variable<String>(firmId),
            Variable<String>(syncKeySetting),
          ],
        )
        .getSingleOrNull();
    if (key == null) {
      throw const SyncRefused('Join the master again from the sync screen.');
    }
    return exchange(
      _store(firmId),
      RemotePeer(
        host: master.host,
        port: master.port,
        syncKey: key.read<String>('setting_value'),
      ),
    );
  }

  /// Changes that clashed with a row this phone had under the same code or
  /// number, kept under a marked name.
  Future<int> conflicts() => _store(_id.firmId).conflictCount();

  /// The clashes still to be looked at, by name (M29).
  Future<List<({String changeId, String table, String label})>> clashes() =>
      _store(_id.firmId).clashes();

  /// Marks a clash as put right. Owner or manager.
  Future<void> resolveClash(String changeId) {
    _app.require(Permission.settings);
    return _store(_id.firmId).resolveClash(changeId);
  }

  /// Every device of the shop this phone knows of.
  Future<List<SyncDevice>> devices() async {
    final rows = await _app.database
        .customSelect(
          '''
          SELECT d.id, d.label, d.device_role, d.doc_prefix, d.is_this_device,
                 (SELECT MAX(c.synced_at_utc) FROM change_log c
                   WHERE c.origin_device_id = d.id) AS synced
          FROM devices d
          WHERE d.firm_id = ? AND d.deleted_at_utc IS NULL
          ORDER BY d.created_at_utc
          ''',
          variables: [Variable<String>(_id.firmId)],
        )
        .get();
    return [
      for (final r in rows)
        SyncDevice(
          id: r.read<String>('id'),
          label: r.read<String>('label'),
          role: r.read<String>('device_role'),
          prefix: r.read<String>('doc_prefix'),
          isThisDevice: r.read<int>('is_this_device') == 1,
          lastSyncedAt: switch (r.readNullable<int>('synced')) {
            final ms? => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
            null => null,
          },
        ),
    ];
  }
}
