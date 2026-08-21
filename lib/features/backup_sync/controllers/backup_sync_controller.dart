import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/backup_service.dart';

class BackupSyncNotifier extends StateNotifier<bool> {
  BackupSyncNotifier() : super(false); // false = not loading

  Future<File?> createBackup() async {
    state = true;
    try {
      final file = await BackupService.createLocalBackup();
      state = false;
      return file;
    } catch (e) {
      state = false;
      return null;
    }
  }

  Future<void> shareBackup() async {
    state = true;
    try {
      await BackupService.shareBackupToDrive();
    } finally {
      state = false;
    }
  }
}

final backupSyncControllerProvider =
    StateNotifierProvider<BackupSyncNotifier, bool>((ref) {
  return BackupSyncNotifier();
});
