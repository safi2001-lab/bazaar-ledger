import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    show ReplacementMode;
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';

/// A plan as Google Play sells it: its own price string, in the buyer's
/// currency, once Play has answered.
final class PlanOffer {
  const PlanOffer(this.plan, this.price, this.details);

  final Plan plan;
  final String price;
  final ProductDetails details;
}

/// Google Play Billing, for the three paid plans (M21).
///
/// Nothing here decides the plan: every purchase Play reports goes to
/// [PlanServices], which keeps it only if Google's signature checks out
/// against the key built into the app.
abstract interface class Billing {
  /// What Play sells, or empty when it cannot be reached.
  Future<List<PlanOffer>> offers();

  /// Opens Play's own purchase sheet for [offer]. The result arrives through
  /// [watch], not here.
  Future<void> buy(PlanOffer offer);

  /// Asks Play what this phone's Google account holds now, and hands it to
  /// [PlanServices]. Quietly does nothing when Play cannot be reached.
  Future<void> refresh();

  /// Starts listening for purchases; [changed] runs when the plan may have
  /// moved.
  void watch(PlanServices plans, void Function() changed);

  void dispose();
}

/// The real one, over the in_app_purchase plugin.
final class PlayBilling implements Billing {
  PlayBilling();

  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  PlanServices? _plans;
  final _held = <String, GooglePlayPurchaseDetails>{};

  static final _ids = {for (final p in Plan.values) ?p.productId};

  @override
  void watch(PlanServices plans, void Function() changed) {
    _plans = plans;
    _sub ??= _iap.purchaseStream.listen((purchases) async {
      for (final p in purchases) {
        if (p is GooglePlayPurchaseDetails) _held[p.productID] = p;
        if (p.status == PurchaseStatus.purchased ||
            p.status == PurchaseStatus.restored) {
          final signed = _signed(p);
          if (signed != null) await plans.bought(signed.json, signed.signature);
        }
        // Acknowledged only after it is kept: Play refunds a purchase not
        // acknowledged within three days, which is the right outcome for
        // one this phone could not verify.
        if (p.pendingCompletePurchase &&
            p.status != PurchaseStatus.pending &&
            plans.purchased != Plan.free) {
          await _iap.completePurchase(p);
        }
      }
      changed();
    }, onError: (_) {});
  }

  static ({String json, String signature})? _signed(PurchaseDetails p) {
    if (p is! GooglePlayPurchaseDetails) return null;
    return (
      json: p.billingClientPurchase.originalJson,
      signature: p.billingClientPurchase.signature,
    );
  }

  @override
  Future<List<PlanOffer>> offers() async {
    if (!await _iap.isAvailable()) return const [];
    final response = await _iap.queryProductDetails(_ids);
    final out = <PlanOffer>[];
    for (final d in response.productDetails) {
      final plan = Plan.forProduct(d.id);
      // One entry per offer; the first is the base plan.
      if (plan == null || out.any((o) => o.plan == plan)) continue;
      out.add(PlanOffer(plan, d.price, d));
    }
    return out..sort((a, b) => a.plan.index.compareTo(b.plan.index));
  }

  @override
  Future<void> buy(PlanOffer offer) async {
    // The plugin takes the offer token from the product details itself.
    final details = offer.details;
    // Moving from one plan to another replaces the subscription rather than
    // adding a second one beside it.
    final current = _held.values
        .where((p) => Plan.forProduct(p.productID) != null)
        .firstOrNull;
    await _iap.buyNonConsumable(
      purchaseParam: GooglePlayPurchaseParam(
        productDetails: details,
        changeSubscriptionParam:
            current == null || current.productID == details.id
            ? null
            : ChangeSubscriptionParam(
                oldPurchaseDetails: current,
                replacementMode: ReplacementMode.withTimeProration,
              ),
      ),
    );
  }

  @override
  Future<void> refresh() async {
    final plans = _plans;
    if (plans == null || !await _iap.isAvailable()) return;
    final addition = _iap
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final response = await addition.queryPastPurchases();
    // An error is not an answer: the plan stays as last confirmed.
    if (response.error != null) return;
    _held
      ..clear()
      ..addEntries(response.pastPurchases.map((p) => MapEntry(p.productID, p)));
    await plans.confirm([for (final p in response.pastPurchases) ?_signed(p)]);
    for (final p in response.pastPurchases) {
      if (p.pendingCompletePurchase && plans.purchased != Plan.free) {
        await _iap.completePurchase(p);
      }
    }
  }

  @override
  void dispose() => unawaited(_sub?.cancel());
}

/// Play Billing, or null on a build with no licensing key, where nothing
/// can be bought and the plans screen says so. A test stands one in.
final billingProvider = Provider<Billing?>((ref) {
  if (!AppConfig.hasPlayBilling) return null;
  final billing = PlayBilling();
  ref.onDispose(billing.dispose);
  return billing;
});

/// The plan in force, re-read on every refresh.
final planProvider = Provider<Plan>((ref) {
  ref.watch(refreshTickProvider);
  return ref.watch(appServicesProvider).plans.plan;
});

/// Listens for purchases from the moment the shop opens, and asks Play
/// again whenever the app comes to the front, so a renewal, an upgrade on
/// another phone or a cancellation is seen without anybody looking for it.
class BillingKeeper extends ConsumerStatefulWidget {
  const BillingKeeper({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<BillingKeeper> createState() => _BillingKeeperState();
}

class _BillingKeeperState extends ConsumerState<BillingKeeper>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final billing = ref.read(billingProvider);
    if (billing == null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    billing.watch(ref.read(appServicesProvider).plans, container.bumpRefresh);
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final billing = ref.read(billingProvider);
    if (billing == null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    final plans = ref.read(appServicesProvider).plans;
    final before = plans.plan;
    try {
      await billing.refresh();
      // Only when it moved: a refresh rebuilds the screens above this.
      if (plans.plan != before) container.bumpRefresh();
    } on Object {
      // Play out of reach: the plan stays as last confirmed.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
