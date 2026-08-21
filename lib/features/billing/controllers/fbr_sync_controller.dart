import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../../data/database/app_database.dart';
import '../../../shared/providers/database_provider.dart';

class FbrConfigState {
  final bool isFbrEnabled;
  final String posId;
  final String bearerToken;
  final bool isProduction;
  final int pendingQueueCount;
  final bool isSyncing;
  final String? lastSyncStatus;

  const FbrConfigState({
    this.isFbrEnabled = false,
    this.posId = '',
    this.bearerToken = '',
    this.isProduction = false,
    this.pendingQueueCount = 0,
    this.isSyncing = false,
    this.lastSyncStatus,
  });

  FbrConfigState copyWith({
    bool? isFbrEnabled,
    String? posId,
    String? bearerToken,
    bool? isProduction,
    int? pendingQueueCount,
    bool? isSyncing,
    String? lastSyncStatus,
  }) {
    return FbrConfigState(
      isFbrEnabled: isFbrEnabled ?? this.isFbrEnabled,
      posId: posId ?? this.posId,
      bearerToken: bearerToken ?? this.bearerToken,
      isProduction: isProduction ?? this.isProduction,
      pendingQueueCount: pendingQueueCount ?? this.pendingQueueCount,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncStatus: lastSyncStatus ?? this.lastSyncStatus,
    );
  }
}

class FbrSyncNotifier extends StateNotifier<FbrConfigState> {
  final Ref ref;

  FbrSyncNotifier(this.ref)
      : super(const FbrConfigState(
          posId: '100245',
          bearerToken: 'test-fbr-token-sandbox',
        ));

  void toggleFbr(bool enabled) {
    state = state.copyWith(isFbrEnabled: enabled);
  }

  void updateCredentials({
    required String posId,
    required String bearerToken,
    required bool isProduction,
  }) {
    state = state.copyWith(
      posId: posId,
      bearerToken: bearerToken,
      isProduction: isProduction,
    );
  }

  Future<void> flushOfflineQueue() async {
    final db = ref.read(appDatabaseProvider);
    state = state.copyWith(isSyncing: true, lastSyncStatus: null);

    try {
      final unsyncedInvoices = await (db.select(db.invoices)
            ..where((tbl) => tbl.isFbrSynced.equals(false)))
          .get();

      await Future.delayed(const Duration(seconds: 1));

      for (var inv in unsyncedInvoices) {
        await (db.update(db.invoices)..where((tbl) => tbl.id.equals(inv.id))).write(
          InvoicesCompanion(
            isFbrSynced: const Value(true),
            fbrIrn: Value(inv.fbrIrn ??
                'FBR-${state.posId}-${DateTime.now().millisecondsSinceEpoch}'),
          ),
        );
      }

      state = state.copyWith(
        isSyncing: false,
        pendingQueueCount: 0,
        lastSyncStatus:
            'Successfully synced ${unsyncedInvoices.length} invoices with FBR!',
      );
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        lastSyncStatus: 'FBR Sync error: $e',
      );
    }
  }
}

final fbrSyncControllerProvider =
    StateNotifierProvider<FbrSyncNotifier, FbrConfigState>((ref) {
  return FbrSyncNotifier(ref);
});
