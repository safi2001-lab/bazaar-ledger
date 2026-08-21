import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/subscription_service.dart';

class SubscriptionState {
  final SubscriptionTier currentTier;
  final bool isLoading;
  final String? errorMessage;

  const SubscriptionState({
    this.currentTier = SubscriptionTier.free,
    this.isLoading = false,
    this.errorMessage,
  });

  // Feature Gate Accessors
  bool get canUseThermalPrint => currentTier != SubscriptionTier.free;
  bool get canUseWhatsAppShare => currentTier != SubscriptionTier.free;
  bool get canUseMultiCounter =>
      currentTier == SubscriptionTier.gold || currentTier == SubscriptionTier.platinum;
  bool get canUseKhata =>
      currentTier == SubscriptionTier.gold || currentTier == SubscriptionTier.platinum;
  bool get canUsePdc =>
      currentTier == SubscriptionTier.gold || currentTier == SubscriptionTier.platinum;
  bool get canUseFbr => currentTier == SubscriptionTier.platinum;
  bool get canUseTajirDost => currentTier == SubscriptionTier.platinum;
  bool get canUseCloudBackup => currentTier == SubscriptionTier.platinum;

  SubscriptionState copyWith({
    SubscriptionTier? currentTier,
    bool? isLoading,
    String? errorMessage,
  }) {
    return SubscriptionState(
      currentTier: currentTier ?? this.currentTier,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  SubscriptionNotifier() : super(const SubscriptionState());

  void activateTier(SubscriptionTier tier) {
    state = state.copyWith(currentTier: tier);
  }

  void setTierFromProductId(String productId) {
    if (productId.contains('platinum')) {
      state = state.copyWith(currentTier: SubscriptionTier.platinum);
    } else if (productId.contains('gold')) {
      state = state.copyWith(currentTier: SubscriptionTier.gold);
    } else if (productId.contains('silver')) {
      state = state.copyWith(currentTier: SubscriptionTier.silver);
    } else {
      state = state.copyWith(currentTier: SubscriptionTier.free);
    }
  }
}

final subscriptionControllerProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
  return SubscriptionNotifier();
});
