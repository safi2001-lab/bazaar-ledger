import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/backup_sync_controller.dart';

class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBackingUp = ref.watch(backupSyncControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud & Local Backup'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.cloud_done, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            const Text(
              'Your data stays on your device.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'To prevent data loss if your phone is broken or stolen, you can create a secure encrypted backup (.pkbak file) and save it to your Google Drive or share it via WhatsApp.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 40),
            if (isBackingUp)
              const Center(child: CircularProgressIndicator())
            else ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.save_alt),
                label: const Text('Create Local Backup (.pkbak)'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                onPressed: () async {
                  final file = await ref.read(backupSyncControllerProvider.notifier).createBackup();
                  if (file != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Backup saved locally: ${file.path}')),
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.share),
                label: const Text('Share Backup to Google Drive'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
                onPressed: () {
                  ref.read(backupSyncControllerProvider.notifier).shareBackup();
                },
              ),
            ]
          ],
        ),
      ),
    );
  }
}
