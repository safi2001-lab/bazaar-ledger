import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../billing/controllers/fbr_sync_controller.dart';

class FbrSettingsScreen extends ConsumerStatefulWidget {
  const FbrSettingsScreen({super.key});

  @override
  ConsumerState<FbrSettingsScreen> createState() => _FbrSettingsScreenState();
}

class _FbrSettingsScreenState extends ConsumerState<FbrSettingsScreen> {
  late TextEditingController _posIdController;
  late TextEditingController _tokenController;
  bool _isProduction = false;

  @override
  void initState() {
    super.initState();
    final fbrConfig = ref.read(fbrSyncControllerProvider);
    _posIdController = TextEditingController(text: fbrConfig.posId);
    _tokenController = TextEditingController(text: fbrConfig.bearerToken);
    _isProduction = fbrConfig.isProduction;
  }

  @override
  void dispose() {
    _posIdController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fbrState = ref.watch(fbrSyncControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FBR Digital Invoicing (DI)'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Compliance Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified, color: AppTheme.primaryEmerald, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Compliant with FBR SRO 28(I)/2024 & Digital Invoicing API v1.12. Invoices generate official FBR IRNs & QR verification codes.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          SwitchListTile(
            title: const Text('Enable FBR Integration', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('Generates FBR IRN & QR codes on every printed receipt'),
            value: fbrState.isFbrEnabled,
            onChanged: (val) {
              ref.read(fbrSyncControllerProvider.notifier).toggleFbr(val);
            },
          ),
          const Divider(),

          if (fbrState.isFbrEnabled) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _posIdController,
              decoration: const InputDecoration(
                labelText: 'FBR POS ID *',
                hintText: 'e.g. 100245',
                prefixIcon: Icon(Icons.badge),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'FBR API Bearer Token *',
                prefixIcon: Icon(Icons.key),
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Production Mode (Live Gateway)'),
              subtitle: Text(
                _isProduction
                    ? 'Transmitting live fiscal data to https://ims.fbr.gov.pk'
                    : 'Using FBR Sandbox testing gateway',
              ),
              value: _isProduction,
              onChanged: (val) {
                setState(() => _isProduction = val);
                ref.read(fbrSyncControllerProvider.notifier).updateCredentials(
                      posId: _posIdController.text.trim(),
                      bearerToken: _tokenController.text.trim(),
                      isProduction: val,
                    );
              },
            ),
            const SizedBox(height: 20),

            // 72-Hour Offline Queue Section
            Card(
              elevation: 0,
              color: Colors.amber.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.amber.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.cloud_sync, color: Colors.amber, size: 24),
                        SizedBox(width: 8),
                        Text(
                          '72-Hour Offline Sync Queue',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'If internet drops, receipts are saved locally with provisional IRNs. When online, flush the queue to submit to FBR.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: fbrState.isSyncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.upload),
                        label: const Text('Flush & Sync Pending Invoices'),
                        onPressed: fbrState.isSyncing
                            ? null
                            : () {
                                ref.read(fbrSyncControllerProvider.notifier).flushOfflineQueue();
                              },
                      ),
                    ),
                    if (fbrState.lastSyncStatus != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        fbrState.lastSyncStatus!,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
