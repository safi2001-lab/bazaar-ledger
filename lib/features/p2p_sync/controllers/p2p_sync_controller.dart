import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../services/p2p_sync_service.dart';
import '../../../shared/providers/database_provider.dart';

part 'p2p_sync_controller.g.dart';

enum CounterRole { master, subCounter }

class P2pSyncState {
  final CounterRole role;
  final String nodeId;
  final String pairingPin;
  final bool isServerRunning;
  final int serverPort;
  final String? masterIp;
  final bool isSyncing;
  final String? lastSyncMessage;
  final DateTime? lastSyncTime;

  const P2pSyncState({
    this.role = CounterRole.master,
    required this.nodeId,
    this.pairingPin = '1234',
    this.isServerRunning = false,
    this.serverPort = 8088,
    this.masterIp,
    this.isSyncing = false,
    this.lastSyncMessage,
    this.lastSyncTime,
  });

  P2pSyncState copyWith({
    CounterRole? role,
    String? nodeId,
    String? pairingPin,
    bool? isServerRunning,
    int? serverPort,
    String? masterIp,
    bool? isSyncing,
    String? lastSyncMessage,
    DateTime? lastSyncTime,
  }) {
    return P2pSyncState(
      role: role ?? this.role,
      nodeId: nodeId ?? this.nodeId,
      pairingPin: pairingPin ?? this.pairingPin,
      isServerRunning: isServerRunning ?? this.isServerRunning,
      serverPort: serverPort ?? this.serverPort,
      masterIp: masterIp ?? this.masterIp,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncMessage: lastSyncMessage ?? this.lastSyncMessage,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}

@riverpod
class P2pSyncController extends _$P2pSyncController {
  P2pSyncService? _service;

  @override
  P2pSyncState build() {
    final db = ref.watch(appDatabaseProvider);
    final nodeId = 'COUNTER-${DateTime.now().millisecondsSinceEpoch % 10000}';
    _service = P2pSyncService(
      db: db,
      nodeId: nodeId,
      pairingPin: '1234',
    );
    return P2pSyncState(nodeId: nodeId);
  }

  void setRole(CounterRole role) {
    state = state.copyWith(role: role);
  }

  void setPairingPin(String pin) {
    state = state.copyWith(pairingPin: pin);
  }

  void setMasterIp(String ip) {
    state = state.copyWith(masterIp: ip);
  }

  Future<void> toggleMasterServer() async {
    if (_service == null) return;
    if (state.isServerRunning) {
      await _service!.stopMasterServer();
      state = state.copyWith(isServerRunning: false);
    } else {
      final port = await _service!.startMasterServer(port: state.serverPort);
      state = state.copyWith(isServerRunning: true, serverPort: port);
    }
  }

  Future<void> syncWithMaster() async {
    if (_service == null || state.masterIp == null || state.masterIp!.isEmpty) {
      state = state.copyWith(lastSyncMessage: 'Error: Master IP not set.');
      return;
    }

    state = state.copyWith(isSyncing: true, lastSyncMessage: null);
    try {
      final mergedCount = await _service!.syncSubCounterWithMaster(
        masterIp: state.masterIp!,
        port: state.serverPort,
        pin: state.pairingPin,
      );
      state = state.copyWith(
        isSyncing: false,
        lastSyncMessage: 'Synced $mergedCount records successfully.',
        lastSyncTime: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        lastSyncMessage: 'Sync failed: $e',
      );
    }
  }
}
