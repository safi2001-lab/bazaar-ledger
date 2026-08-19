import 'dart:io';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../services/backup_service.dart';

part 'backup_sync_controller.g.dart';

@riverpod
class BackupSyncController extends _$BackupSyncController {
  @override
  bool build() {
    return false; // represents isLoading state
  }

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
