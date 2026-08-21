import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/subscription_controller.dart';
import '../screens/paywall_screen.dart';
import '../services/subscription_service.dart';

class FeatureGate {
  /// Checks if current subscription tier permits the requested action.
  /// If permitted, runs [onAllowed]. If restricted, displays the upgrade modal.
  static void check(
    BuildContext context,
    WidgetRef ref, {
    required SubscriptionTier requiredTier,
    required String featureName,
    required VoidCallback onAllowed,
  }) {
    final currentTier = ref.read(subscriptionControllerProvider).currentTier;

    if (_isTierSufficient(currentTier, requiredTier)) {
      onAllowed();
    } else {
      _showUpgradeDialog(context, requiredTier, featureName);
    }
  }

  static bool _isTierSufficient(SubscriptionTier current, SubscriptionTier required) {
    const tierOrder = [
      SubscriptionTier.free,
      SubscriptionTier.silver,
      SubscriptionTier.gold,
      SubscriptionTier.platinum,
    ];
    return tierOrder.indexOf(current) >= tierOrder.indexOf(required);
  }

  static void _showUpgradeDialog(
    BuildContext context,
    SubscriptionTier requiredTier,
    String featureName,
  ) {
    String tierName;
    switch (requiredTier) {
      case SubscriptionTier.silver:
        tierName = 'Silver (Solo Pro)';
        break;
      case SubscriptionTier.gold:
        tierName = 'Gold (Retail Master)';
        break;
      case SubscriptionTier.platinum:
        tierName = 'Platinum (Enterprise)';
        break;
      default:
        tierName = 'Pro';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.lock, color: Colors.amber.shade700),
            const SizedBox(width: 8),
            const Text('Feature Locked'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$featureName is a premium feature available on the $tierName plan.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.star, color: Colors.amber, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Upgrade through Google Play to unlock unlimited multi-counter, thermal printing, and tax compliance.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Maybe Later'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryEmerald,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PaywallScreen()),
              );
            },
            child: const Text('View Plans'),
          ),
        ],
      ),
    );
  }
}
