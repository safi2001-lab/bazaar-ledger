import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';

enum SubscriptionTier {
  free,
  silver, // Solo Pro (Rs 1,500/mo)
  gold,   // Retail Master (Rs 3,000/mo)
  platinum, // Enterprise (Rs 5,000/mo)
}

class SubscriptionPlanInfo {
  final String id;
  final String title;
  final String pricePkr;
  final SubscriptionTier tier;
  final List<String> features;

  const SubscriptionPlanInfo({
    required this.id,
    required this.title,
    required this.pricePkr,
    required this.tier,
    required this.features,
  });
}

class SubscriptionService {
  static const silverMonthlyId = 'pk_billing_silver_monthly';
  static const goldMonthlyId = 'pk_billing_gold_monthly';
  static const platinumMonthlyId = 'pk_billing_platinum_monthly';

  static const List<SubscriptionPlanInfo> availablePlans = [
    SubscriptionPlanInfo(
      id: silverMonthlyId,
      title: 'Silver (Solo Pro)',
      pricePkr: 'Rs. 1,500 / month',
      tier: SubscriptionTier.silver,
      features: [
        'Unlimited Invoices & Receipts',
        'Bluetooth ESC/POS Thermal Printing',
        'Direct WhatsApp OS Share Sheet',
        'Single Device Counter',
      ],
    ),
    SubscriptionPlanInfo(
      id: goldMonthlyId,
      title: 'Gold (Retail Master)',
      pricePkr: 'Rs. 3,000 / month',
      tier: SubscriptionTier.gold,
      features: [
        'All Silver Features',
        'Local Wi-Fi Multi-Counter Sync (2-4 Devices)',
        'Udhaar Khata & Customer Ledgers',
        'PDC Cheque Lifecycle Tracker',
        'Pharmacy Batch & Mobile IMEI Support',
      ],
    ),
    SubscriptionPlanInfo(
      id: platinumMonthlyId,
      title: 'Platinum (Enterprise)',
      pricePkr: 'Rs. 5,000 / month',
      tier: SubscriptionTier.platinum,
      features: [
        'All Gold Features',
        'FBR Digital Invoicing (DI API v1.12)',
        'Tajir Dost 1% Turnover Tax Ledger',
        'Google Drive Automated Cloud Backup',
        'Priority Phone / WhatsApp Support',
      ],
    ),
  ];

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  Future<bool> isAvailable() async {
    return _iap.isAvailable();
  }

  Future<List<ProductDetails>> loadProducts() async {
    final ids = {silverMonthlyId, goldMonthlyId, platinumMonthlyId};
    final response = await _iap.queryProductDetails(ids);
    return response.productDetails;
  }

  void listenToPurchases(Function(PurchaseDetails purchase) onPurchaseCompleted) {
    _subscription = _iap.purchaseStream.listen((purchases) {
      for (var purchase in purchases) {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          onPurchaseCompleted(purchase);
        }
        if (purchase.pendingCompletePurchase) {
          _iap.completePurchase(purchase);
        }
      }
    });
  }

  Future<void> buyPlan(ProductDetails product) async {
    final purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  void dispose() {
    _subscription?.cancel();
  }
}
