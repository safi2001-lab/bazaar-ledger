import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'backup_providers.dart';
import 'drive_access.dart';
import 'restore_screen.dart';

/// Making a backup, and the way back to one.
///
/// A backup made here goes to the share sheet. This app has no server;
/// where the file goes — WhatsApp to themselves, Google Drive, a nephew's
/// laptop — is the shopkeeper's decision, made in the system's own sheet.
/// The one exception is the daily Drive backup (M20), which the owner turns
/// on here and which sends only the sealed file, to their own Drive.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  final _passphrase = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passphrase.dispose();
    _again.dispose();
    super.dispose();
  }

  /// Whether the passphrase typed twice will do, saying why not.
  bool _passphraseOk() {
    final s = AppStrings.of(context);
    if (_passphrase.text.length < BackupArchive.minimumPassphraseLength) {
      setState(() => _error = s.backupPassphraseShort);
      return false;
    }
    if (_passphrase.text != _again.text) {
      // Typed twice because a typo here is not discovered until the day the
      // backup is needed, and then it is a backup nobody can open.
      setState(() => _error = s.backupPassphraseMismatch);
      return false;
    }
    return true;
  }

  /// Runs one Drive action with the screen busy, showing what went wrong.
  Future<void> _drive(
    Future<void> Function(AppServices services) action,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await action(services);
      container.bumpRefresh();
    } on BackupRefused catch (refused) {
      if (mounted) setState(() => _error = refused.reason);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _driveOn(CloudBackupStore store) async {
    if (_busy || !_passphraseOk()) return;
    final passphrase = _passphrase.text;
    final connect = ref.read(connectDriveProvider);
    await _drive((services) async {
      await connect();
      await services.drive.turnOn(passphrase);
      _passphrase.clear();
      _again.clear();
      await services.drive.runIfDue(
        store,
        scratch: await driveScratch(),
        force: true,
      );
    });
  }

  Future<void> _make() async {
    // First statement: two taps in one frame would otherwise seal the books
    // twice and open two share sheets.
    if (_busy) return;
    final s = AppStrings.of(context);
    if (!_passphraseOk()) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final made = await services.backups.create(
        services.actorNow(),
        passphrase: _passphrase.text,
        into: Directory(
          '${(await getTemporaryDirectory()).path}'
          '${Platform.pathSeparator}backups',
        ),
      );
      container.bumpRefresh();
      _passphrase.clear();
      _again.clear();
      messenger.showSnackBar(SnackBar(content: Text(s.backupMade)));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(made.file.path, mimeType: 'application/octet-stream')],
          subject: s.backupTitle,
        ),
      );
    } on BackupRefused catch (refused) {
      if (mounted) setState(() => _error = refused.reason);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _driveSection(BuildContext context, CloudBackupStore store) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final drive = ref.watch(driveSettingsProvider).valueOrNull;
    String day(DateTime utc) => utc
        .add(const Duration(hours: 5))
        .toIso8601String()
        .substring(0, 16)
        .replaceFirst('T', ' ');
    return [
      const SizedBox(height: BlTokens.space6),
      Text(
        s.driveTitle,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: t.ink,
        ),
      ),
      const SizedBox(height: BlTokens.space2),
      Text(s.driveExplain, style: TextStyle(fontSize: 14, color: t.inkMuted)),
      const SizedBox(height: BlTokens.space3),
      if (drive?.enabled ?? false) ...[
        BlChip(
          drive!.lastUtc == null ? s.driveOn : s.driveLast(day(drive.lastUtc!)),
          tone: BlChipTone.good,
          icon: Icons.cloud_done_outlined,
        ),
        if (drive.lastError case final reason?) ...[
          const SizedBox(height: BlTokens.space2),
          Text(
            s.driveFailed(reason),
            style: TextStyle(color: t.danger, fontSize: 14),
          ),
        ],
        const SizedBox(height: BlTokens.space3),
        BlButton(
          label: s.driveNow,
          icon: Icons.cloud_upload_outlined,
          kind: BlButtonKind.secondary,
          onPressed: _busy
              ? null
              : () => unawaited(
                  _drive(
                    (services) async => services.drive.runIfDue(
                      store,
                      scratch: await driveScratch(),
                      force: true,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: BlTokens.space2),
        BlButton(
          label: s.driveTurnOff,
          icon: Icons.cloud_off_outlined,
          kind: BlButtonKind.ghost,
          onPressed: _busy
              ? null
              : () => unawaited(_drive((services) => services.drive.turnOff())),
        ),
      ] else
        BlButton(
          label: s.driveTurnOn,
          icon: Icons.cloud_upload_outlined,
          kind: BlButtonKind.secondary,
          onPressed: _busy ? null : () => unawaited(_driveOn(store)),
        ),
      const SizedBox(height: BlTokens.space2),
      BlButton(
        label: s.driveRestore,
        icon: Icons.cloud_download_outlined,
        kind: BlButtonKind.ghost,
        onPressed: () => openDriveRestore(context, ref, store),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final last = ref.watch(lastBackupProvider).valueOrNull;
    final store = ref.watch(driveStoreProvider);

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.backupTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            Text(s.backupExplain, style: TextStyle(fontSize: 14, color: t.ink)),
            const SizedBox(height: BlTokens.space3),
            BlChip(
              last == null
                  ? s.backupNever
                  : s.backupLast(
                      last
                          .add(const Duration(hours: 5))
                          .toIso8601String()
                          .substring(0, 10),
                    ),
              tone: last == null ? BlChipTone.warn : BlChipTone.good,
              icon: last == null ? Icons.warning_amber_outlined : Icons.check,
            ),
            const SizedBox(height: BlTokens.space4),
            BlField(
              controller: _passphrase,
              label: s.backupPassphrase,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: BlTokens.space2),
            BlField(
              controller: _again,
              label: s.backupPassphraseAgain,
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: BlTokens.space2),
            Text(
              s.backupPassphraseHint,
              style: TextStyle(fontSize: 13, color: t.inkMuted),
            ),
            if (_error != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(_error!, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.backupMake,
              icon: Icons.backup_outlined,
              big: true,
              busy: _busy,
              onPressed: _busy ? null : () => unawaited(_make()),
            ),
            if (store != null) ..._driveSection(context, store),
            const SizedBox(height: BlTokens.space6),
            BlButton(
              label: s.backupRestore,
              icon: Icons.settings_backup_restore,
              kind: BlButtonKind.secondary,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => restoreRoute(ref)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Restoring a backup kept on the shop's Drive: the same restore screen,
/// with the list of Drive backups in place of the file picker.
void openDriveRestore(
  BuildContext context,
  WidgetRef ref,
  CloudBackupStore store,
) {
  final connect = ref.read(connectDriveProvider);
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (route) => restoreRoute(
          ref,
          pickFile: () => pickFromDrive(route, store, connect),
        ),
      ),
    ),
  );
}

/// The restore screen, wired to this app's picker, books and restart.
/// [pickFile] replaces the system picker, for a backup kept on Drive.
Widget restoreRoute(WidgetRef ref, {Future<Uint8List?> Function()? pickFile}) {
  final services = ref.read(appServicesProvider);
  return RestoreScreen(
    pickFile: pickFile ?? ref.read(pickBackupFileProvider),
    databasePath: () async =>
        services.databasePath ?? await AppServices.defaultDatabasePath(),
    onRestored: ref.read(restartAppProvider),
  );
}
