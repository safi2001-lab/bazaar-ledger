import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/subscription_controller.dart';
import '../services/subscription_service.dart';

class PaywallScreen extends ConsumerWidget {
  const PaywallScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subState = ref.watch(subscriptionControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription Plans'),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Purchases restored from Google Play account.')),
              );
            },
            child: const Text('Restore'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Upgrade Your Business',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choose the plan that fits your shop\'s size. Subscriptions are billed securely through Google Play.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),

          // Plan Cards
          ...SubscriptionService.availablePlans.map((plan) {
            final isCurrent = subState.currentTier == plan.tier;
            final isPopular = plan.tier == SubscriptionTier.gold;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Card(
                  margin: const EdgeInsets.only(bottom: 20),
                  elevation: isPopular ? 4 : 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: isCurrent
                          ? AppTheme.primaryEmerald
                          : (isPopular ? Colors.amber.shade400 : Colors.grey.shade300),
                      width: isCurrent || isPopular ? 2 : 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              plan.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (isCurrent)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryEmerald.withAlpha(30),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'ACTIVE PLAN',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryEmerald,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          plan.pricePkr,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryEmerald,
                          ),
                        ),
                        const Divider(height: 24),
                        ...plan.features.map(
                          (f) => Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: AppTheme.primaryEmerald, size: 18),
                                const SizedBox(width: 8),
                                Expanded(child: Text(f, style: const TextStyle(fontSize: 13))),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isCurrent ? Colors.grey.shade400 : (isPopular ? Colors.amber.shade800 : null),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: isCurrent
                                ? null
                                : () {
                                    ref.read(subscriptionControllerProvider.notifier).activateTier(plan.tier);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: AppTheme.successGreen,
                                        content: Text('Successfully subscribed to ${plan.title}!'),
                                      ),
                                    );
                                  },
                            child: Text(isCurrent ? 'Current Plan' : 'Subscribe via Google Play'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isPopular)
                  Positioned(
                    top: -10,
                    right: 24,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'MOST POPULAR',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
