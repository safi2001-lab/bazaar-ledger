import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../l10n/app_strings.dart';

/// Google sign-in, used for a Drive access token and nothing else (M20).
///
/// Authorization only, never authentication: the app does not learn who
/// the user is, only gets a token for the private app folder on their
/// Drive. Untested against Google from this repository — that needs the
/// app's Android OAuth client (package name and signing SHA-1) in the
/// owner's Google Cloud project.
abstract final class GoogleDrive {
  static const _scopes = [DriveBackupStore.scope];
  static Future<void>? _ready;

  static Future<void> _init() => _ready ??= GoogleSignIn.instance.initialize();

  /// A token without asking, or null when the phone has not been connected.
  static Future<String?> token() async {
    await _init();
    final held = await GoogleSignIn.instance.authorizationClient
        .authorizationForScopes(_scopes);
    return held?.accessToken;
  }

  /// Asks the shopkeeper to pick their Google account and allow the app
  /// folder. Shown by Google, not by this app.
  static Future<void> connect() async {
    await _init();
    await GoogleSignIn.instance.authorizationClient.authorizeScopes(_scopes);
  }
}

/// The shop's Drive, or null on a build with no Google client configured,
/// where the Drive section is simply not shown. A test stands one in.
final driveStoreProvider = Provider<CloudBackupStore?>(
  (ref) => AppConfig.hasDriveBackup
      ? DriveBackupStore(accessToken: GoogleDrive.token)
      : null,
);

/// Connecting the phone to Google Drive; a test replaces it.
final connectDriveProvider = Provider<Future<void> Function()>(
  (ref) => GoogleDrive.connect,
);

/// Where a Drive backup is sealed before it is sent, and deleted after.
Future<Directory> driveScratch() async => Directory(
  '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}drive',
);

/// This shop's Drive backup settings, for the Backup screen.
final driveSettingsProvider = FutureProvider.autoDispose<DriveBackupSettings>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).drive.settings();
});

/// Lets the shopkeeper pick one of the backups on their Drive, and returns
/// its bytes for the restore screen, which opens it like any other file.
Future<Uint8List?> pickFromDrive(
  BuildContext context,
  CloudBackupStore store,
  Future<void> Function() connect,
) async {
  final s = AppStrings.of(context);
  final List<CloudBackupFile> files;
  try {
    files = await store.list();
  } on CloudBackupFailed catch (failed) {
    if (!failed.signInAgain) rethrow;
    await connect();
    return context.mounted ? pickFromDrive(context, store, connect) : null;
  }
  if (!context.mounted) return null;
  if (files.isEmpty) throw StateError(s.driveNone);
  final chosen = await showDialog<CloudBackupFile>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text(s.drivePick),
      children: [
        for (final f in files)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(f),
            child: Text(
              '${f.createdUtc.add(const Duration(hours: 5)).toIso8601String().substring(0, 16).replaceFirst('T', ' ')}'
              '  ·  ${(f.bytes / 1024).ceil()} KB',
            ),
          ),
      ],
    ),
  );
  if (chosen == null) return null;
  return store.download(chosen.id);
}

/// Backs up to Drive when the app opens or comes back to the front and a
/// day has passed since the last one (M20). No background job: a shop
/// opens its till every day.
class DriveBackupKeeper extends ConsumerStatefulWidget {
  const DriveBackupKeeper({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<DriveBackupKeeper> createState() => _DriveBackupKeeperState();
}

class _DriveBackupKeeperState extends ConsumerState<DriveBackupKeeper>
    with WidgetsBindingObserver {
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_run());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_run());
  }

  Future<void> _run() async {
    final store = ref.read(driveStoreProvider);
    if (store == null || _running) return;
    _running = true;
    final services = ref.read(appServicesProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final run = await services.drive.runIfDue(
        store,
        scratch: await driveScratch(),
      );
      if (run == DriveBackupRun.uploaded || run == DriveBackupRun.failed) {
        container.bumpRefresh();
      }
    } on Object {
      // runIfDue keeps its own failures; this is only the scratch folder.
    } finally {
      _running = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
