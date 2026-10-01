import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import 'play_billing.dart';

/// The plans, what each adds, and Google Play's own purchase sheet (M21).
///
/// Prices come from Play once it answers, in the buyer's currency; until
/// then the plan document's rupee prices are shown. On a test build there
/// is a switch to try any plan without paying; a release build has none.
class PlansScreen extends ConsumerStatefulWidget {
  const PlansScreen({this.needed, super.key});

  /// The plan the shopkeeper was sent here for, shown first.
  final Plan? needed;

  @override
  ConsumerState<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends ConsumerState<PlansScreen> {
  List<PlanOffer> _offers = const [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadOffers());
  }

  Future<void> _loadOffers() async {
    final billing = ref.read(billingProvider);
    if (billing == null) return;
    try {
      final offers = await billing.offers();
      if (mounted) setState(() => _offers = offers);
    } on Object {
      // Prices from the plan document are shown instead.
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await action();
      container.bumpRefresh();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final plan = ref.watch(planProvider);
    final plans = ref.watch(appServicesProvider).plans;
    final billing = ref.watch(billingProvider);
    final needed = widget.needed;

    return Scaffold(
      backgroundColor: t.paper,
      appBar: AppBar(title: Text(s.planTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(BlTokens.space4),
          children: [
            BlChip(
              s.planCurrent(planName(plan)),
              tone: plan == Plan.free ? BlChipTone.neutral : BlChipTone.good,
              icon: Icons.workspace_premium_outlined,
            ),
            if (plans.testPlan case final test?) ...[
              const SizedBox(height: BlTokens.space2),
              BlChip(
                s.planTestActive(planName(test)),
                tone: BlChipTone.warn,
                icon: Icons.science_outlined,
              ),
            ],
            if (needed != null && !plan.covers(needed)) ...[
              const SizedBox(height: BlTokens.space3),
              Text(
                s.planNeeded(planName(needed)),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: t.ink,
                ),
              ),
            ],
            const SizedBox(height: BlTokens.space3),
            Text(
              s.planFreeIncludes,
              style: TextStyle(fontSize: 14, color: t.inkMuted),
            ),
            for (final p in Plan.values.skip(1)) ...[
              const SizedBox(height: BlTokens.space4),
              _PlanCard(
                plan: p,
                current: plan == p,
                highlighted: p == needed,
                price:
                    _offers.where((o) => o.plan == p).firstOrNull?.price ??
                    'Rs ${_grouped(p.rupeesPerYear)}',
                onBuy: billing == null || plan.covers(p) || _busy
                    ? null
                    : () {
                        final offer = _offers
                            .where((o) => o.plan == p)
                            .firstOrNull;
                        if (offer == null) {
                          setState(() => _error = s.planNoBilling);
                          return;
                        }
                        unawaited(_run(() => billing.buy(offer)));
                      },
              ),
            ],
            const SizedBox(height: BlTokens.space4),
            if (billing == null)
              Text(s.planNoBilling, style: TextStyle(color: t.inkMuted))
            else
              BlButton(
                label: s.planRestore,
                icon: Icons.restore,
                kind: BlButtonKind.ghost,
                busy: _busy,
                onPressed: _busy
                    ? null
                    : () => unawaited(_run(billing.refresh)),
              ),
            if (_error != null) ...[
              const SizedBox(height: BlTokens.space3),
              Text(_error!, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
            if (plans.allowTestPlans) ...[
              const SizedBox(height: BlTokens.space6),
              BlSectionHeader(s.planTestTitle),
              Text(
                s.planTestNote,
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
              const SizedBox(height: BlTokens.space2),
              Wrap(
                spacing: BlTokens.space2,
                runSpacing: BlTokens.space2,
                children: [
                  ChoiceChip(
                    label: Text(s.planTestReal),
                    selected: plans.testPlan == null,
                    onSelected: (_) =>
                        unawaited(_run(() => plans.setTestPlan(null))),
                  ),
                  for (final p in Plan.values)
                    ChoiceChip(
                      label: Text(planName(p)),
                      selected: plans.testPlan == p,
                      onSelected: (_) =>
                          unawaited(_run(() => plans.setTestPlan(p))),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.current,
    required this.highlighted,
    required this.price,
    required this.onBuy,
  });

  final Plan plan;
  final bool current;
  final bool highlighted;
  final String price;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final below = Plan.values[plan.index - 1];
    final adds = [
      for (final f in PlanFeature.values)
        if (f.plan == plan) featureLabel(s, f),
      if (plan.firms != below.firms)
        plan.firms == null ? s.planFirmsUnlimited : s.planFirms(plan.firms!),
      if (plan.users != below.users)
        plan.users == null ? s.planUsersUnlimited : s.planUsers(plan.users!),
    ];
    return BlCard(
      accent: highlighted || current,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  planName(plan),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: t.ink,
                  ),
                ),
              ),
              Text(
                s.planPerYear(price),
                style: TextStyle(fontSize: 15, color: t.ink),
              ),
            ],
          ),
          if (plan != Plan.silver)
            Padding(
              padding: const EdgeInsets.only(top: BlTokens.space1),
              child: Text(
                '+ ${planName(below)}',
                style: TextStyle(fontSize: 13, color: t.inkMuted),
              ),
            ),
          const SizedBox(height: BlTokens.space2),
          for (final line in adds)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check, size: 18, color: t.money),
                  const SizedBox(width: BlTokens.space2),
                  Expanded(
                    child: Text(line, style: TextStyle(color: t.ink)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: BlTokens.space3),
          if (current)
            BlChip(s.planIsYours, tone: BlChipTone.good, icon: Icons.check)
          else if (onBuy != null)
            BlButton(
              key: Key('plan-buy-${plan.name}'),
              label: s.planBuy,
              icon: Icons.shopping_cart_checkout,
              onPressed: onBuy,
            ),
        ],
      ),
    );
  }
}

String _grouped(int n) => n.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+$)'),
  (m) => '${m[1]},',
);

/// A plan's name; the same in both languages.
String planName(Plan p) => '${p.name[0].toUpperCase()}${p.name.substring(1)}';

String featureLabel(AppStrings s, PlanFeature f) => switch (f) {
  PlanFeature.noWatermark => s.planFeatNoWatermark,
  PlanFeature.autoDriveBackup => s.planFeatAutoDriveBackup,
  PlanFeature.cheques => s.planFeatCheques,
  PlanFeature.priceLists => s.planFeatPriceLists,
  PlanFeature.accountingReports => s.planFeatAccountingReports,
  PlanFeature.tracking => s.planFeatTracking,
  PlanFeature.scaleLabels => s.planFeatScaleLabels,
  PlanFeature.godowns => s.planFeatGodowns,
  PlanFeature.lanSync => s.planFeatLanSync,
  PlanFeature.fbr => s.planFeatFbr,
  PlanFeature.manufacturing => s.planFeatManufacturing,
  PlanFeature.vans => s.planFeatVans,
};

/// Whether the shop's plan has [feature]; if not, shows the plans with the
/// one that has it first, and answers again once the shopkeeper is back.
Future<bool> ensurePlan(
  BuildContext context,
  WidgetRef ref,
  PlanFeature feature,
) async {
  final plans = ref.read(appServicesProvider).plans;
  if (plans.has(feature)) return true;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PlansScreen(needed: feature.plan)),
  );
  return plans.has(feature);
}

/// Shows the plans for a refusal the service made.
Future<void> offerPlan(BuildContext context, PlanRequired refused) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlansScreen(needed: refused.needed),
      ),
    );

/// A small lock beside something the plan does not include.
class PlanLock extends ConsumerWidget {
  const PlanLock(this.feature, {super.key});

  final PlanFeature feature;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(planProvider);
    if (ref.read(appServicesProvider).plans.has(feature)) {
      return const SizedBox.shrink();
    }
    return Icon(
      Icons.lock_outline,
      size: 16,
      color: context.bl.inkMuted,
      semanticLabel: planName(feature.plan),
    );
  }
}

/// Opens [screen] if the plan has [feature], or the plans if it does not.
Future<void> openWithPlan(
  BuildContext context,
  WidgetRef ref,
  PlanFeature feature,
  Widget Function() screen,
) async {
  // Taken before the plans are shown: getting a plan refreshes the screens
  // behind them, and the one that asked may not be the one there after.
  final navigator = Navigator.of(context);
  if (!await ensurePlan(context, ref, feature) || !navigator.mounted) return;
  await navigator.push(MaterialPageRoute<void>(builder: (_) => screen()));
}
