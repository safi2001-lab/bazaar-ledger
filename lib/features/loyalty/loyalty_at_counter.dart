import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../pos/cart.dart';
import '../pos/pos_screen.dart' show cartPreviewByProvider;
import '../pos/scheme_book.dart';
import 'loyalty_providers.dart';

/// M66 at the counter: the customer's points on the payment sheet, their own
/// price on the line, and the profit on the bill for whoever may see it.
///
/// Nothing here decides anything. What points are worth, how many may be
/// used and what a line is priced at are the domain's (loyalty.dart,
/// party_prices.dart), and the sale path checks the points again in the
/// bill's own commit; these widgets say it and let the cashier choose.

// ---------------------------------------------------------------------------
// Points on the payment sheet
// ---------------------------------------------------------------------------

/// Under what is due on the payment sheet, for a named customer of a shop
/// that gives points: what they hold, a way to use some on this bill, and
/// what this bill will earn.
///
/// Using points is a discount the owner's rate and share decide, so any
/// cashier may (loyalty_services.dart); the most offered is the smaller of
/// what the customer holds and the shop's share of this bill.
class LoyaltyRow extends ConsumerStatefulWidget {
  const LoyaltyRow({super.key, required this.onUdhaar});

  /// Whether the bill goes on the khata, so it earns only when paid.
  final bool onUdhaar;

  @override
  ConsumerState<LoyaltyRow> createState() => _LoyaltyRowState();
}

class _LoyaltyRowState extends ConsumerState<LoyaltyRow> {
  final _points = TextEditingController();
  bool _asking = false;
  String? _problem;

  @override
  void dispose() {
    _points.dispose();
    super.dispose();
  }

  /// What the bill's goods come to after every discount but the points:
  /// the figure the shop's share of a bill is of, as the sale path reads it.
  Money _goods(Cart cart) {
    final books = cart.forBooks(
      ref.read(unitConverterProvider).valueOrNull,
      schemesFor(ref),
      points: false,
    );
    return SchemeBook.billValueOf(books.lines) - books.billDiscount;
  }

  void _apply(LoyaltyRule rule, String partyId, int most) {
    final s = AppStrings.of(context);
    final wanted = int.tryParse(_points.text.trim().replaceAll(',', ''));
    if (wanted == null || wanted <= 0) {
      setState(() => _problem = s.loyaltyProblemFigures);
      return;
    }
    if (wanted > most) {
      setState(() => _problem = s.loyaltyAtMost(pointsText(most)));
      return;
    }
    ref
        .read(cartProvider.notifier)
        .setLoyalty(
          LoyaltyRedemption(
            partyId: partyId,
            points: wanted,
            value: rule.valueOf(wanted),
          ),
        );
    setState(() {
      _asking = false;
      _problem = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final partyId = cart.partyId;
    if (partyId == null) return const SizedBox.shrink();
    final rules = ref.watch(loyaltyRulesProvider).valueOrNull;
    final rule = rules?.current;
    if (rules == null || rule == null) return const SizedBox.shrink();
    final standing = ref.watch(loyaltyStandingProvider(partyId)).valueOrNull;
    if (standing == null) return const SizedBox.shrink();

    final s = AppStrings.of(context);
    final t = context.bl;
    final held = standing.outstanding < 0 ? 0 : standing.outstanding;
    final used = cart.pointsOff.isPositive ? cart.loyalty : null;
    final most = rule.maxPointsOn(_goods(cart), held);
    final preview = ref.watch(cartPreviewByProvider(null));
    final earns = preview == null ? 0 : rule.pointsFor(preview.total);
    final notifier = ref.read(cartProvider.notifier);

    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.stars_outlined, size: 18, color: t.accent),
          const SizedBox(width: BlTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.loyaltyHeld(
                    pointsText(held),
                    rule.valueOf(held).amountOnly,
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.ink,
                  ),
                ),
                if (used != null)
                  Wrap(
                    spacing: BlTokens.space3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        s.loyaltyApplied(
                          pointsText(used.points),
                          used.value.amountOnly,
                        ),
                        style: TextStyle(fontSize: 13, color: t.money),
                      ),
                      TextButton(
                        onPressed: () => notifier.setLoyalty(null),
                        child: Text(s.loyaltyTakeOff),
                      ),
                    ],
                  )
                else if (rule.isOn && most > 0 && !_asking)
                  TextButton(
                    onPressed: () => setState(() {
                      _asking = true;
                      _points.text = '$most';
                    }),
                    child: Text(s.loyaltyUse),
                  )
                else if (_asking) ...[
                  const SizedBox(height: BlTokens.space2),
                  BlField(
                    controller: _points,
                    label: s.loyaltyHowMany,
                    hint: s.loyaltyAtMost(pointsText(most)),
                    numeric: true,
                    decimals: 0,
                    onChanged: (_) => setState(() => _problem = null),
                  ),
                  const SizedBox(height: BlTokens.space2),
                  BlButton(
                    label: s.loyaltyApply,
                    kind: BlButtonKind.secondary,
                    onPressed: () => _apply(rule, partyId, most),
                  ),
                ],
                if (_problem != null)
                  Text(
                    _problem!,
                    style: TextStyle(fontSize: 13, color: t.danger),
                  ),
                if (rule.isOn && earns > 0)
                  Text(
                    widget.onUdhaar
                        ? s.loyaltyWillEarnWhenPaid(pointsText(earns))
                        : s.loyaltyWillEarn(pointsText(earns)),
                    style: TextStyle(fontSize: 12, color: t.inkMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The customer's own price, on the line
// ---------------------------------------------------------------------------

/// Under a line on the counter: "Haji Sahib ka rate" when it is at the
/// customer's own price, and — for whoever may see costs — "Qeemat se kam"
/// in red when it sells below what it cost.
class LineNotes extends ConsumerWidget {
  const LineNotes({super.key, required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final units = ref.watch(unitConverterProvider).valueOrNull;
    final own = cart.partyName != null && cart.atOwnRate(line, units);
    // Read only once the profit is shown at all: a cashier's counter never
    // watches a cost.
    final shown = ref.watch(marginShownProvider).valueOrNull ?? false;
    final below =
        shown &&
        (ref
                .watch(counterMarginProvider(null))
                ?.forKey(line.item.id)
                ?.belowCost ??
            false);
    if (!own && !below) return const SizedBox.shrink();

    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(
        left: BlTokens.space3,
        bottom: BlTokens.space1,
      ),
      child: Wrap(
        spacing: BlTokens.space3,
        children: [
          if (own)
            Text(
              s.lineOwnRate(cart.partyName!),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.accent,
              ),
            ),
          if (below)
            Text(
              s.marginBelowCost,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: t.danger,
              ),
            ),
        ],
      ),
    );
  }
}

/// In a line's editor: keeps the price typed as the customer's own, for
/// whoever may set a customer's prices. [rate] is what the price field says
/// now; [onKept] applies the editor and closes it.
class KeepRateButton extends ConsumerStatefulWidget {
  const KeepRateButton({
    super.key,
    required this.line,
    required this.rate,
    required this.onKept,
  });

  final CartLine line;
  final Rate? Function() rate;
  final VoidCallback onKept;

  @override
  ConsumerState<KeepRateButton> createState() => _KeepRateButtonState();
}

class _KeepRateButtonState extends ConsumerState<KeepRateButton> {
  bool _busy = false;
  String? _problem;

  Future<void> _keep() async {
    final s = AppStrings.of(context);
    final services = ref.read(appServicesProvider);
    final cart = ref.read(cartProvider);
    final partyId = cart.partyId;
    final rate = widget.rate() ?? widget.line.rate;
    if (partyId == null || rate.inMilliPaisa <= 0) return;
    final line = widget.line;
    final units = ref.read(unitConverterProvider).valueOrNull;
    // Kept per the item's own unit, as its prices are; carried there from
    // the line's unit exactly, or not at all.
    Rate perBase;
    try {
      perBase = !line.isConverted
          ? rate
          : units!.convertRate(
              rate,
              fromUnitId: line.sellingUnitId,
              toUnitId: line.item.unitId,
              itemId: line.item.id,
            );
    } on Object {
      setState(() => _problem = s.lineRateNotCarried);
      return;
    }
    setState(() {
      _busy = true;
      _problem = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(cartProvider.notifier);
    try {
      final prices = await services.loyalty.setPartyPrice(
        partyId,
        line.item.id,
        perBase,
      );
      if (!mounted) return;
      // The line takes the price as typed, and is then at the customer's
      // own price; nothing else on the bill moves.
      notifier.setRate(line.item.id, rate);
      notifier.ownPricesChanged(prices, units: units);
      messenger.showSnackBar(
        SnackBar(content: Text(s.lineRateKept(cart.partyName ?? ''))),
      );
      widget.onKept();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _problem = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final partyId = ref.watch(cartProvider.select((c) => c.partyId));
    final services = ref.watch(appServicesProvider);
    if (partyId == null ||
        widget.line.isLoose ||
        !services.loyalty.maySetPrices) {
      return const SizedBox.shrink();
    }
    final s = AppStrings.of(context);
    final t = context.bl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: BlTokens.space2),
        BlButton(
          label: s.lineKeepRate,
          icon: Icons.push_pin_outlined,
          kind: BlButtonKind.secondary,
          busy: _busy,
          onPressed: _busy ? null : () => unawaited(_keep()),
        ),
        if (_problem != null)
          Text(_problem!, style: TextStyle(fontSize: 13, color: t.danger)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The profit on the bill
// ---------------------------------------------------------------------------

/// "Munafa Rs 1,240 (12.5%)" for the bill, discreet, for whoever may see
/// costs while the owner leaves it on; red when the bill, or a line of it,
/// sells below cost. Nothing at all for anybody else — not even a widget
/// that was handed the figure and hid it.
class MarginLine extends ConsumerWidget {
  const MarginLine({super.key, this.mode});

  /// How the bill is being paid, for its provincial tax (M59); null is cash.
  final String? mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(marginShownProvider).valueOrNull ?? false;
    if (!shown) return const SizedBox.shrink();
    final margin = ref.watch(counterMarginProvider(mode));
    if (margin == null || (margin.sale.isZero && margin.cost.isZero)) {
      return const SizedBox.shrink();
    }
    final s = AppStrings.of(context);
    final t = context.bl;
    final red = margin.profit.isNegative || margin.anyBelowCost;
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space1),
      child: Wrap(
        spacing: BlTokens.space2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.trending_up, size: 14, color: red ? t.danger : t.inkMuted),
          Text(
            s.marginBill(
              margin.profit.amountOnly,
              marginLabel(margin.marginBp),
            ),
            style: TextStyle(fontSize: 12, color: red ? t.danger : t.inkMuted),
          ),
          if (margin.anyBelowCost)
            Text(
              s.marginBelowCost,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: t.danger,
              ),
            ),
        ],
      ),
    );
  }
}

/// In a line's editor: the profit on this item of the bill, or what it loses
/// below cost, for whoever may see it.
class LineMarginNote extends ConsumerWidget {
  const LineMarginNote({super.key, required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = ref.watch(marginShownProvider).valueOrNull ?? false;
    if (!shown || line.isLoose) return const SizedBox.shrink();
    final mine = ref.watch(counterMarginProvider(null))?.forKey(line.item.id);
    if (mine == null) return const SizedBox.shrink();
    final s = AppStrings.of(context);
    final t = context.bl;
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space2),
      child: Text(
        mine.belowCost
            ? s.marginLineLoss((-mine.profit).amountOnly)
            : s.marginLine(mine.profit.amountOnly, marginLabel(mine.marginBp)),
        style: TextStyle(
          fontSize: 13,
          fontWeight: mine.belowCost ? FontWeight.w700 : FontWeight.w400,
          color: mine.belowCost ? t.danger : t.inkMuted,
        ),
      ),
    );
  }
}
