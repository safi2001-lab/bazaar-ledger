import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// Asks the system for a backup file, and returns its bytes.
///
/// No type filter. Android maps a filter to MIME types, and `.pkbak` has
/// none, so filtering on it hides every backup on the phone. The archive's
/// own magic bytes are the check, and a photo picked by mistake is refused
/// in words.
///
/// A provider so a test can hand the screen a file without a system picker.
final pickBackupFileProvider = Provider<Future<Uint8List?> Function()>(
  (ref) => pickBackupFile,
);

/// The system picker itself, for the one screen with no providers above it.
Future<Uint8List?> pickBackupFile() async {
  final file = await openFile();
  return file?.readAsBytes();
}

/// Closes the books and opens them again, which is when a staged restore is
/// swapped in. Overridden by `main`, which is the only place that can rebuild
/// everything above the app.
final restartAppProvider = Provider<Future<void> Function()>(
  (ref) =>
      () async => throw StateError(
        'Nothing can restart the app here. main() overrides this; a test that '
        'restores has to override it too.',
      ),
);

/// When this shop last made a backup.
final lastBackupProvider = FutureProvider.autoDispose<DateTime?>((ref) async {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).lastBackupAt();
});
