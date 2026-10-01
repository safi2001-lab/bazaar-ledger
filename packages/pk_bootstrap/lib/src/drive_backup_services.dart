part of 'app_services.dart';

/// How this shop backs up to its Google Drive (M20).
final class DriveBackupSettings {
  const DriveBackupSettings({
    this.enabled = false,
    this.passphrase = '',
    this.lastUtc,
    this.lastError,
  });

  final bool enabled;

  /// What every Drive backup is sealed with. Needed, with the Google
  /// account, to bring the books back on a new phone.
  final String passphrase;
  final DateTime? lastUtc;

  /// Why the last try did not reach Drive; null once one has.
  final String? lastError;
}

/// What one pass did.
enum DriveBackupRun { off, notDue, uploaded, failed }

/// A backup to the shop's own Google Drive once a day, with nobody
/// remembering to (M20).
///
/// There is no background job: a shop opens the app every day, so when it
/// opens, or comes back to the front, and the last Drive backup is a day
/// old, a new one is sealed and sent. The newest [keep] are kept. What goes
/// is the same sealed `.pkbak` the share sheet sends, locked with the
/// shop's backup passphrase before it leaves the phone.
final class DriveBackupServices {
  DriveBackupServices._(this._app);

  final AppServices _app;

  static const keep = 7;
  static const every = Duration(hours: 24);

  static const _keys = (
    enabled: 'drive.enabled',
    passphrase: 'drive.passphrase',
    last: 'drive.last_utc',
    error: 'drive.last_error',
  );

  /// Whether a backup is due, given when the last one reached Drive.
  static bool isDue(DateTime? lastUtc, DateTime nowUtc) =>
      lastUtc == null || nowUtc.difference(lastUtc) >= every;

  /// The backups past the newest [keep], to be deleted.
  static List<CloudBackupFile> toPrune(
    List<CloudBackupFile> files, {
    int keep = DriveBackupServices.keep,
  }) {
    final newest = [...files]
      ..sort((a, b) => b.createdUtc.compareTo(a.createdUtc));
    return newest.length <= keep ? const [] : newest.sublist(keep);
  }

  Future<DriveBackupSettings> settings() async {
    final id = _app._identity;
    if (id == null) return const DriveBackupSettings();
    final rows = await _app.database
        .customSelect(
          'SELECT setting_key, setting_value FROM settings WHERE firm_id = ? '
          "AND setting_key LIKE 'drive.%' AND deleted_at_utc IS NULL",
          variables: [Variable<String>(id.firmId)],
        )
        .get();
    final v = {
      for (final r in rows)
        r.read<String>('setting_key'): r.read<String>('setting_value'),
    };
    final last = int.tryParse(v[_keys.last] ?? '');
    final error = v[_keys.error] ?? '';
    return DriveBackupSettings(
      enabled: v[_keys.enabled] == '1',
      passphrase: v[_keys.passphrase] ?? '',
      lastUtc: last == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(last, isUtc: true),
      lastError: error.isEmpty ? null : error,
    );
  }

  Future<void> _put(
    Map<String, String> values, {
    String? audit,
    ActorContext? actor,
  }) async {
    final who = actor ?? _app.actorNow();
    await _app._runner.run(who, (tx) async {
      for (final MapEntry(:key, :value) in values.entries) {
        final held = await tx.selectOne(
          'SELECT id, setting_value FROM settings WHERE firm_id = ? '
          'AND setting_key = ? AND deleted_at_utc IS NULL',
          [who.firmId, key],
        );
        if (held == null) {
          await tx.insert('settings', {
            'setting_key': key,
            'setting_value': value,
          });
        } else if (held.read<String>('setting_value') != value) {
          await tx.update('settings', held.read<String>('id'), {
            'setting_value': value,
          });
        }
      }
      if (audit != null) {
        tx.audit(
          action: 'DRIVE_BACKUP_SETTINGS',
          entityTable: 'firms',
          entityId: who.firmId,
          summary: audit,
        );
      }
    });
  }

  /// Turns daily Drive backups on, sealed with [passphrase]. Owner or
  /// manager, as any backup is.
  Future<void> turnOn(String passphrase) async {
    _app.require(Permission.backups);
    _app.plans.require(PlanFeature.autoDriveBackup);
    if (passphrase.length < BackupArchive.minimumPassphraseLength) {
      throw const BackupRefused(
        BackupProblem.weakPassphrase,
        'A backup passphrase needs at least '
        '${BackupArchive.minimumPassphraseLength} characters.',
      );
    }
    await _put({
      _keys.enabled: '1',
      _keys.passphrase: passphrase,
    }, audit: 'Daily Google Drive backup on');
  }

  Future<void> turnOff() async {
    _app.require(Permission.backups);
    await _put({_keys.enabled: '0'}, audit: 'Daily Google Drive backup off');
  }

  /// Seals the books and sends them to [store] if a backup is due, or
  /// whenever [force] is set; then keeps the newest [keep]. Never throws:
  /// what went wrong is kept for the Backup screen to show.
  ///
  /// Runs as the shop's owner, so a cashier's phone opening in the morning
  /// backs up too; the setting that allows it was turned on by the owner.
  Future<DriveBackupRun> runIfDue(
    CloudBackupStore store, {
    required Directory scratch,
    bool force = false,
  }) async {
    final id = _app._identity;
    if (id == null) return DriveBackupRun.off;
    final s = await settings();
    if (!s.enabled || s.passphrase.isEmpty) return DriveBackupRun.off;
    if (!_app.plans.has(PlanFeature.autoDriveBackup)) return DriveBackupRun.off;
    final now = _app.clock.nowUtc();
    if (!force && !isDue(s.lastUtc, now)) return DriveBackupRun.notDue;

    final actor = ActorContext(
      firmId: id.firmId,
      userId: id.userId,
      deviceId: id.deviceId,
      startedAtUtc: now,
    );
    File? made;
    try {
      final backup = await BackupService(
        database: _app.database,
        runner: () => _app._runner,
        clock: _app.clock,
        appVersion: _app._appVersion,
        booksKey: _app._booksKey,
      ).create(actor, passphrase: s.passphrase, into: scratch);
      made = backup.file;
      await store.upload(
        p.basename(backup.file.path),
        await backup.file.readAsBytes(),
      );
      for (final old in toPrune(await store.list())) {
        await store.delete(old.id);
      }
      await _put({
        _keys.last: '${backup.createdAtUtc.millisecondsSinceEpoch}',
        _keys.error: '',
      }, actor: actor);
      return DriveBackupRun.uploaded;
    } on Object catch (error) {
      try {
        await _put({_keys.error: '$error'}, actor: actor);
      } on Object {
        // The books themselves would not take a write; nothing to add.
      }
      return DriveBackupRun.failed;
    } finally {
      if (made != null && made.existsSync()) made.deleteSync();
    }
  }
}
