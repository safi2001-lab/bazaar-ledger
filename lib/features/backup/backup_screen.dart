import 'dart:async';
import 'dart:io';

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
import 'restore_screen.dart';

/// Making a backup, and the way back to one.
///
/// The backup goes to the share sheet and nowhere else. This app has no
/// server and makes no network call of its own; where the file goes —
/// WhatsApp to themselves, Google Drive, a nephew's laptop — is the
/// shopkeeper's decision, made in the system's own sheet, which is the only
/// way it stays true that nothing leaves the phone unless they send it.
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

  Future<void> _make() async {
    // First statement: two taps in one frame would otherwise seal the books
    // twice and open two share sheets.
    if (_busy) return;
    final s = AppStrings.of(context);

    if (_passphrase.text.length < BackupArchive.minimumPassphraseLength) {
      setState(() => _error = s.backupPassphraseShort);
      return;
    }
    if (_passphrase.text != _again.text) {
      // Typed twice because a typo here is not discovered until the day the
      // backup is needed, and then it is a backup nobody can open.
      setState(() => _error = s.backupPassphraseMismatch);
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final last = ref.watch(lastBackupProvider).valueOrNull;

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

/// The restore screen, wired to this app's picker, books and restart.
Widget restoreRoute(WidgetRef ref) {
  final services = ref.read(appServicesProvider);
  return RestoreScreen(
    pickFile: ref.read(pickBackupFileProvider),
    databasePath: () async =>
        services.databasePath ?? await AppServices.defaultDatabasePath(),
    onRestored: ref.read(restartAppProvider),
  );
}
