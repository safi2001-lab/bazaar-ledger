import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../controllers/p2p_sync_controller.dart';

class P2pSyncScreen extends ConsumerStatefulWidget {
  const P2pSyncScreen({super.key});

  @override
  ConsumerState<P2pSyncScreen> createState() => _P2pSyncScreenState();
}

class _P2pSyncScreenState extends ConsumerState<P2pSyncScreen> {
  final _ipController = TextEditingController();
  final _pinController = TextEditingController(text: '1234');

  @override
  void dispose() {
    _ipController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(p2pSyncControllerProvider);
    final isMaster = syncState.role == CounterRole.master;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Wi-Fi Multi-Counter Sync'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Banner explanation
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.wifi, size: 32, color: Colors.green.shade800),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Operate 2–4 counter devices simultaneously over your shop\'s Wi-Fi router. 100% offline with zero cloud server cost.',
                    style: TextStyle(fontSize: 13, color: Colors.green.shade900),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Role Selector
          SegmentedButton<CounterRole>(
            segments: const [
              ButtonSegment(
                value: CounterRole.master,
                label: Text('Master Counter (Host)'),
                icon: Icon(Icons.dns),
              ),
              ButtonSegment(
                value: CounterRole.subCounter,
                label: Text('Sub-Counter (Client)'),
                icon: Icon(Icons.point_of_sale),
              ),
            ],
            selected: {syncState.role},
            onSelectionChanged: (set) {
              ref.read(p2pSyncControllerProvider.notifier).setRole(set.first);
            },
          ),
          const SizedBox(height: 20),

          if (isMaster) ...[
            // Master Host Card
            Card(
              elevation: 0,
              color: Colors.grey.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Local Server Status',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: syncState.isServerRunning
                                ? Colors.green.shade100
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            syncState.isServerRunning ? 'RUNNING' : 'STOPPED',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: syncState.isServerRunning
                                  ? Colors.green.shade800
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Node ID: ${syncState.nodeId}'),
                    Text('Port: ${syncState.serverPort}'),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: const InputDecoration(
                        labelText: '4-Digit Pairing PIN',
                        hintText: 'e.g. 1234',
                      ),
                      onChanged: (val) {
                        ref.read(p2pSyncControllerProvider.notifier).setPairingPin(val);
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: Icon(syncState.isServerRunning ? Icons.stop : Icons.play_arrow),
                        label: Text(
                          syncState.isServerRunning
                              ? 'Stop Local Server'
                              : 'Start Master Sync Server',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              syncState.isServerRunning ? Colors.red.shade700 : null,
                          foregroundColor:
                              syncState.isServerRunning ? Colors.white : null,
                        ),
                        onPressed: () {
                          ref.read(p2pSyncControllerProvider.notifier).toggleMasterServer();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // Sub-Counter Client Card
            Card(
              elevation: 0,
              color: Colors.grey.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Connect to Master Counter',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _ipController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Master Device IP Address',
                        hintText: 'e.g. 192.168.1.100',
                        prefixIcon: Icon(Icons.computer),
                      ),
                      onChanged: (val) {
                        ref.read(p2pSyncControllerProvider.notifier).setMasterIp(val.trim());
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: const InputDecoration(
                        labelText: '4-Digit Pairing PIN',
                        hintText: 'e.g. 1234',
                        prefixIcon: Icon(Icons.lock),
                      ),
                      onChanged: (val) {
                        ref.read(p2pSyncControllerProvider.notifier).setPairingPin(val);
                      },
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: syncState.isSyncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.sync),
                        label: const Text('Sync Now with Master Counter'),
                        onPressed: syncState.isSyncing
                            ? null
                            : () {
                                ref.read(p2pSyncControllerProvider.notifier).syncWithMaster();
                              },
                      ),
                    ),
                    if (syncState.lastSyncMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: syncState.lastSyncMessage!.startsWith('Error') ||
                                  syncState.lastSyncMessage!.startsWith('Sync failed')
                              ? Colors.red.shade50
                              : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          syncState.lastSyncMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: syncState.lastSyncMessage!.startsWith('Error') ||
                                    syncState.lastSyncMessage!.startsWith('Sync failed')
                                ? Colors.red.shade800
                                : Colors.green.shade800,
                          ),
                        ),
                      ),
                    ],
                    if (syncState.lastSyncTime != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Last Sync: ${DateFormat('hh:mm:ss a, dd MMM').format(syncState.lastSyncTime!)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
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
