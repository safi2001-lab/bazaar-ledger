import 'dart:convert';

import 'package:bazaar_ledger/features/subscription/play_billing.dart';
import 'package:bazaar_ledger/features/vans/vans_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import 'support/harness.dart';
import 'support/play_test_key.dart';

/// Google Play as a stand-in: sells the three plans, and on a purchase
/// reports it signed with the test key, exactly as Play's stream does.
final class _FakePlay implements Billing {
  PlanServices? _plans;
  void Function()? _changed;
  final bought = <Plan>[];

  @override
  Future<List<PlanOffer>> offers() async => [
    for (final p in Plan.values.skip(1))
      PlanOffer(
        p,
        'Rs ${p.rupeesPerYear}.00',
        ProductDetails(
          id: p.productId!,
          title: p.name,
          description: '',
          price: 'Rs ${p.rupeesPerYear}.00',
          rawPrice: p.rupeesPerYear.toDouble(),
          currencyCode: 'PKR',
        ),
      ),
  ];

  @override
  Future<void> buy(PlanOffer offer) async {
    bought.add(offer.plan);
    final json = jsonEncode({
      'orderId': 'GPA.1111-2222',
      'packageName': 'pk.bazaarledger',
      'productId': offer.plan.productId,
      'purchaseTime': 1790000000000,
      'purchaseState': 0,
      'purchaseToken': 'token',
      'autoRenewing': true,
    });
    await _plans!.bought(json, signLikePlay(json));
    _changed!();
  }

  @override
  Future<void> refresh() async {}

  @override
  void watch(PlanServices plans, void Function() changed) {
    _plans = plans;
    _changed = changed;
  }

  @override
  void dispose() {}
}

/// The plans, from the app (M21).
void main() {
  testWidgets('a free shop reaching for a paid feature meets the plans, and '
      'a test build can try one without paying', (tester) async {
    final app = await Harness.startWithShop(tester);
    app.services.plans
      ..pinForTests(null)
      ..allowTestPlans = true;
    await tester.pumpAndSettle();

    await tapText(tester, 'Gaariyan (van)');
    expect(find.text('Iske liye Platinum plan chahiye'), findsOneWidget);
    expect(find.text('Aap ka plan: Free'), findsOneWidget);

    final chip = find.widgetWithText(ChoiceChip, 'Platinum');
    await tester.scrollUntilVisible(
      chip,
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(app.services.plans.plan, Plan.platinum);
    expect(app.services.plans.purchased, Plan.free);
    await tester.scrollUntilVisible(
      find.text('Test plan chal raha hai: Platinum'),
      -300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Back from the plans with the plan in hand: the vans open.
    await settleReal(tester, until: find.byType(VansScreen));
    expect(find.byType(VansScreen), findsOneWidget);
  });

  testWidgets('a plan bought through Play unlocks it, and only a signed '
      'purchase does', (tester) async {
    final play = _FakePlay();
    final app = await Harness.startWithShop(
      tester,
      overrides: [billingProvider.overrideWithValue(play)],
    );
    app.services.plans
      ..pinForTests(null)
      ..allowTestPlans = false
      ..publicKey = testPlayPublicKey;
    await tester.pumpAndSettle();

    await openSettings(tester);
    await tapText(tester, 'Aap ka plan: Free');
    expect(find.text('Rs 3499.00 / saal'), findsOneWidget);
    expect(find.text('Sirf test ke liye: plan chunein'), findsNothing);

    final buy = find.byKey(const Key('plan-buy-gold'));
    await tester.ensureVisible(buy);
    await tester.pumpAndSettle();
    await tester.tap(buy);
    await settleReal(tester, until: find.text('Aap ka plan: Gold'));

    expect(play.bought, [Plan.gold]);
    expect(app.services.plans.plan, Plan.gold);
    expect(find.text('Yeh aap ka plan hai'), findsOneWidget);
  });
}
