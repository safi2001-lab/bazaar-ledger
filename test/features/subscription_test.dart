import 'package:flutter_test/flutter_test.dart';
import 'package:pakistan_sme_billing/features/subscription/controllers/subscription_controller.dart';
import 'package:pakistan_sme_billing/features/subscription/services/subscription_service.dart';

void main() {
  test('SubscriptionState gates features strictly across Free, Silver, Gold, Platinum tiers', () {
    // Free Tier
    const freeState = SubscriptionState(currentTier: SubscriptionTier.free);
    expect(freeState.canUseThermalPrint, isFalse);
    expect(freeState.canUseMultiCounter, isFalse);
    expect(freeState.canUseFbr, isFalse);

    // Silver Tier (Solo Pro)
    const silverState = SubscriptionState(currentTier: SubscriptionTier.silver);
    expect(silverState.canUseThermalPrint, isTrue);
    expect(silverState.canUseWhatsAppShare, isTrue);
    expect(silverState.canUseMultiCounter, isFalse);
    expect(silverState.canUseFbr, isFalse);

    // Gold Tier (Retail Master)
    const goldState = SubscriptionState(currentTier: SubscriptionTier.gold);
    expect(goldState.canUseThermalPrint, isTrue);
    expect(goldState.canUseMultiCounter, isTrue);
    expect(goldState.canUseKhata, isTrue);
    expect(goldState.canUsePdc, isTrue);
    expect(goldState.canUseFbr, isFalse);

    // Platinum Tier (Enterprise)
    const platState = SubscriptionState(currentTier: SubscriptionTier.platinum);
    expect(platState.canUseThermalPrint, isTrue);
    expect(platState.canUseMultiCounter, isTrue);
    expect(platState.canUseFbr, isTrue);
    expect(platState.canUseTajirDost, isTrue);
    expect(platState.canUseCloudBackup, isTrue);
  });
}
