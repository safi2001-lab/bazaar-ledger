import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';

/// What one customer paid for one item on their last few bills (M37).
///
/// Keyed by the pair, so every line on a named customer's bill asks once and
/// is answered from the cache while it stays on screen. A fresh sale bumps
/// the refresh tick, so the next bill for the same customer already shows the
/// price they were just charged.
final lastSoldProvider = FutureProvider.autoDispose
    .family<List<PastDeal>, ({String partyId, String itemId})>((
      ref,
      key,
    ) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return const [];
      return services.queries.lastSoldTo(
        firm.id,
        partyId: key.partyId,
        itemId: key.itemId,
      );
    });

/// The last deliveries of one item: from one supplier, or the latest from
/// anybody when [supplierId] is null (M37).
///
/// What the shop paid is a cost, and a role that may not see costs (M9's
/// `seeCosts`: a cashier) is not shown it. Refused here, before the query,
/// rather than by each screen remembering to hide it: a list that is never
/// read cannot be drawn by a widget somebody adds next year.
final lastBoughtProvider = FutureProvider.autoDispose
    .family<List<PastDeal>, ({String? supplierId, String itemId, int limit})>((
      ref,
      key,
    ) async {
      ref.watch(refreshTickProvider);
      final services = ref.watch(appServicesProvider);
      if (!services.can(Permission.seeCosts)) return const [];
      final firm = await ref.watch(firmProvider.future);
      if (firm == null) return const [];
      return services.queries.lastBought(
        firm.id,
        itemId: key.itemId,
        supplierId: key.supplierId,
        limit: key.limit,
      );
    });

/// A price as the counter shows it beside a line: per the line's own unit
/// when the old price carries across exactly, and per its own unit when it
/// does not — "5,000/bori" on a line in kilos says what it is, where a bare
/// "5,000" would be read as the price of a kilo.
String dealPrice(
  PastDeal deal, {
  required String toUnitId,
  required String itemId,
  UnitConverter? units,
}) {
  final carried = deal.rateIn(toUnitId, itemId: itemId, units: units);
  if (carried != null) return carried.amountOnly;
  return deal.unitCode.isEmpty
      ? deal.rate.amountOnly
      : '${deal.rate.amountOnly}/${deal.unitCode}';
}

/// A percentage off as a shopkeeper writes it: 5%, 2.5%, 12.75%.
String percentOff(int bp) {
  final whole = bp ~/ 100;
  final part = bp % 100;
  if (part == 0) return '$whole%';
  final digits = part.toString().padLeft(2, '0');
  return '$whole.${digits.endsWith('0') ? digits[0] : digits}%';
}

/// The last few deals, each a tap from being this line's price (M37).
///
/// Every row says when, on which bill, how many, at what, and what came off
/// it — the five things a wholesaler is asked when a customer says "same as
/// last time". The price on the right is carried into the unit the line is
/// in now; a deal in a unit that does not convert exactly is shown in its
/// own unit and, tapped, says why it cannot be used rather than putting a
/// price per bori on a line in kilos.
class PastDealsList extends StatefulWidget {
  const PastDealsList({
    super.key,
    required this.title,
    required this.deals,
    required this.toUnitId,
    required this.itemId,
    required this.onPick,
    this.units,
  });

  final String title;
  final List<PastDeal> deals;

  /// The unit the line is in now, which a picked price is carried into.
  final String toUnitId;
  final String itemId;
  final UnitConverter? units;

  /// Called with the price per [toUnitId] of the deal tapped.
  final ValueChanged<Rate> onPick;

  @override
  State<PastDealsList> createState() => _PastDealsListState();
}

class _PastDealsListState extends State<PastDealsList> {
  /// Why the last tap did nothing, while it is worth saying.
  String? _problem;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    if (widget.deals.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.history, size: 18, color: t.accent),
            const SizedBox(width: BlTokens.space2),
            Expanded(
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: t.ink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: BlTokens.space1),
        Text(s.dealsTapHint, style: TextStyle(fontSize: 12, color: t.inkMuted)),
        const SizedBox(height: BlTokens.space2),
        for (final deal in widget.deals) _row(context, deal),
        if (_problem != null) ...[
          const SizedBox(height: BlTokens.space1),
          Text(_problem!, style: TextStyle(fontSize: 13, color: t.warning)),
        ],
      ],
    );
  }

  Widget _row(BuildContext context, PastDeal deal) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final carried = deal.rateIn(
      widget.toUnitId,
      itemId: widget.itemId,
      units: widget.units,
    );
    final price = dealPrice(
      deal,
      toUnitId: widget.toUnitId,
      itemId: widget.itemId,
      units: widget.units,
    );
    final off = deal.discount.isPositive
        ? ' · ${s.posDiscount} ${deal.discount.amountOnly}'
              '${deal.discountBp > 0 ? ' (${percentOff(deal.discountBp)})' : ''}'
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: Semantics(
        button: true,
        label: s.dealUse(price),
        excludeSemantics: true,
        child: Material(
          color: t.surface,
          borderRadius: BorderRadius.circular(BlTokens.radiusMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(BlTokens.radiusMd),
            onTap: () {
              if (carried == null) {
                setState(() => _problem = s.dealOtherUnit(deal.unitCode));
                return;
              }
              widget.onPick(carried);
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: BlTokens.touchMin),
              padding: const EdgeInsets.symmetric(
                horizontal: BlTokens.space3,
                vertical: BlTokens.space2,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: carried == null ? t.line : t.accent),
                borderRadius: BorderRadius.circular(BlTokens.radiusMd),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            deal.dateLocal,
                            deal.docNo,
                            ?deal.partyName,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: t.inkMuted),
                        ),
                        Text(
                          '${deal.qty.display} ${deal.unitCode} × '
                          '${deal.rate.amountOnly}$off',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: t.ink),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: BlTokens.space2),
                  // Flexible and scaled, like every price on the counter: a
                  // six-figure rate at 200% must not push the bill number
                  // off the left of the row.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        price,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: carried == null ? t.inkMuted : t.accent,
                          fontFeatures: BlTokens.tabular,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
