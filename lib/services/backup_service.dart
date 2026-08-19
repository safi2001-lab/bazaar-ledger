import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

class BackupService {
  /// Create a local zip backup of the SQLite database
  static Future<File> createLocalBackup() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final dbFile = File(p.join(dbFolder.path, 'pakistan_sme_billing.sqlite'));
    
    if (!await dbFile.exists()) {
      throw Exception('Database file not found. Nothing to backup.');
    }

    final backupDir = await getExternalStorageDirectory() ?? await getApplicationSupportDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
    final backupFileName = 'pakistan_billing_$timestamp.pkbak';
    final backupFile = File(p.join(backupDir.path, backupFileName));

    // Create a zip archive containing the db file
    final encoder = ZipFileEncoder();
    encoder.create(backupFile.path);
    encoder.addFile(dbFile);
    encoder.close();

    return backupFile;
  }

  /// Share the local backup file to Google Drive or other apps (via OS Share intent)
  static Future<void> shareBackupToDrive() async {
    final backupFile = await createLocalBackup();
    final xFile = XFile(backupFile.path);
    await Share.shareXFiles(
      [xFile],
      text: 'Save this .pkbak file to your Google Drive or local storage.',
      subject: 'Pakistan SME Billing Backup',
    );
  }
}
