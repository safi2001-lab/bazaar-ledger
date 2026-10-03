import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../pos/cart.dart';
import '../pos/past_deals.dart';
import '../pos/pos_screen.dart';
import 'goods_given.dart';

/// "Rate lagayein": goods given rate-later, priced on the day they settle
/// (M55).
///
/// Every line of every challan the customer has not been billed for, each
/// with a rate to fill: a line the counter priced keeps its price, and a
/// line given rate-later starts at what the counter would charge this
/// customer today — never a blank, because a blank forgotten on one line of
/// twelve is ten kilos of ghee given away. Beside each, what this customer
/// paid for it last time (M37), a tap from being the rate; shown, never put
/// there by itself.
///
/// The bill is made at the counter, through M25's own challan-to-bill path:
/// the challans are put on the counter at the rates written here, linked,
/// and the shopkeeper takes it as udhaar or takes the money there, where
/// tax, the customer's credit limit, FBR and every rule of the counter
/// apply. The goods are not moved again — the challan moved them — and the
/// bill must be for exactly the goods given; only the price is new.
Future<void> showPriceGoodsSheet(
  BuildContext context, {
  required PartySummary party,
  required List<GoodsGiven> goods,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _PriceGoodsSheet(party: party, goods: goods),
);

/// One line's rate being written.
final class _Rate {
  _Rate(this.challan, this.line, String start)
    : field = TextEditingController(text: start);

  final GoodsGiven challan;
  final GoodsGivenLine line;
  final TextEditingController field;

  Rate? get rate => Rate.tryParse(field.text.trim());
}

class _PriceGoodsSheet extends ConsumerStatefulWidget {
  const _PriceGoodsSheet({required this.party, required this.goods});

  final PartySummary party;
  final List<GoodsGiven> goods;

  @override
  ConsumerState<_PriceGoodsSheet> createState() => _PriceGoodsSheetState();
}

class _PriceGoodsSheetState extends ConsumerState<_PriceGoodsSheet> {
  final _rates = <_Rate>[];
  late final Set<String> _billing = {for (final g in widget.goods) g.challanId};
  final _items = <String, ItemSummary>{};
  bool _ready = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final r in _rates) {
      r.field.dispose();
    }
    super.dispose();
  }

  /// Each line's starting rate: its own if it has one; otherwise what the
  /// counter would charge this customer today, in the unit it was given in.
  Future<void> _load() async {
    final services = ref.read(appServicesProvider);
    final firm = await ref.read(firmProvider.future);
    final units = await ref.read(unitConverterProvider.future);
    if (firm == null) return;
    for (final g in widget.goods) {
      for (final line in g.lines) {
        final item =
            _items[line.itemId] ??
            await services.queries.itemById(firm.id, line.itemId);
        if (item != null) _items[line.itemId] = item;
        _rates.add(_Rate(g, line, _startingRate(line, item, units)));
      }
    }
    if (mounted) setState(() => _ready = true);
  }

  String _startingRate(
    GoodsGivenLine line,
    ItemSummary? item,
    UnitConverter units,
  ) {
    if (!line.isUnpriced) return line.rate.amountOnly;
    if (item == null) return '';
    final base = priceFor(item, widget.party.priceTier);
    final Rate inUnit;
    try {
      inUnit = line.unitId == null || line.unitId == item.unitId
          ? base
          : units.convertRate(
              base,
              fromUnitId: item.unitId,
              toUnitId: line.unitId!,
              itemId: item.id,
            );
    } on Object {
      return '';
    }
    return inUnit.isZero ? '' : inUnit.amountOnly;
  }

  Money get _total => Money.sum([
    for (final r in _rates)
      if (_billing.contains(r.challan.challanId))
        if (r.rate case final rate?)
          r.line.isFree ? Money.zero : rate.amountFor(r.line.qty),
  ]);

  /// Puts the ticked challans on the counter at the rates written, and
  /// opens it.
  Future<void> _bill() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final chosen = [
      for (final g in widget.goods)
        if (_billing.contains(g.challanId)) g,
    ];
    if (chosen.isEmpty) {
      setState(() => _error = s.priceGoodsNonePicked);
      return;
    }
    final lines = <(ItemSummary, QuotedLine)>[];
    for (final r in _rates) {
      if (!_billing.contains(r.challan.challanId)) continue;
      final rate = r.rate;
      if (!r.line.isFree && (rate == null || rate <= Rate.zero)) {
        setState(() => _error = s.priceGoodsRateMissing(r.line.itemName));
        return;
      }
      final item = _items[r.line.itemId];
      if (item == null) {
        setState(() => _error = s.quotationItemGone);
        return;
      }
      lines.add((
        item,
        QuotedLine(
          itemId: r.line.itemId,
          qty: r.line.qty,
          unitId: r.line.unitId,
          unitCode: r.line.unitCode,
          rate: rate ?? Rate.zero,
          discountBp: r.line.discountBp,
          explicitDiscount: r.line.discountBp == 0 && r.line.discount.isPositive
              ? r.line.discount
              : null,
        ),
      ));
    }
    // Never over a bill somebody is in the middle of ringing.
    if (!ref.read(cartProvider).isEmpty) {
      setState(() => _error = s.quotationCounterBusy);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    QuotationRow row(GoodsGiven g) => QuotationRow(
      id: g.challanId,
      docNo: g.docNo,
      date: BusinessDate(g.dateLocal),
      total: g.pricedValue,
      partyId: widget.party.id,
      partyName: widget.party.name,
      docType: 'delivery_challan',
    );
    ref
        .read(cartProvider.notifier)
        .loadQuotation(
          row(chosen.first),
          lines,
          party: widget.party,
          alsoFrom: [for (final g in chosen.skip(1)) row(g)],
        );
    final navigator = Navigator.of(context);
    navigator.pop();
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const PosScreen()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final units = ref.watch(unitConverterProvider).valueOrNull;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(BlTokens.space4),
        children: [
          Text(
            s.goodsGivenPrice,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          Text(
            widget.party.name,
            style: TextStyle(fontSize: 14, color: t.inkMuted),
          ),
          const SizedBox(height: BlTokens.space2),
          Text(
            s.priceGoodsHint,
            style: TextStyle(fontSize: 13, color: t.inkMuted),
          ),
          if (!_ready)
            const Padding(
              padding: EdgeInsets.only(top: BlTokens.space3),
              child: BlSkeletonList(rows: 2),
            ),
          for (final g in widget.goods) ...[
            const SizedBox(height: BlTokens.space3),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _billing.contains(g.challanId),
              onChanged: _busy
                  ? null
                  : (on) => setState(() {
                      (on ?? false)
                          ? _billing.add(g.challanId)
                          : _billing.remove(g.challanId);
                    }),
              title: Text(
                '${g.docNo} · ${shortDate(g.dateLocal)}',
                style: TextStyle(fontSize: 14, color: t.ink),
              ),
            ),
            for (final r in _rates)
              if (r.challan.challanId == g.challanId)
                _RateLine(
                  rate: r,
                  partyId: widget.party.id,
                  units: units,
                  enabled: !_busy && _billing.contains(g.challanId),
                  onChanged: () => setState(() {}),
                ),
          ],
          const SizedBox(height: BlTokens.space3),
          Row(
            children: [
              Expanded(
                child: Text(
                  s.priceGoodsTotal,
                  style: TextStyle(fontSize: 15, color: t.inkMuted),
                ),
              ),
              BlMoney(_total, size: 20, withSymbol: true),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: BlTokens.space3),
            Text(_error!, style: TextStyle(color: t.danger, fontSize: 14)),
          ],
          const SizedBox(height: BlTokens.space4),
          BlButton(
            label: s.priceGoodsBill,
            icon: Icons.point_of_sale_outlined,
            big: true,
            busy: _busy,
            onPressed: _busy || !_ready ? null : () => unawaited(_bill()),
          ),
        ],
      ),
    );
  }
}

/// One line: what was given, its rate, and what it comes to.
class _RateLine extends ConsumerWidget {
  const _RateLine({
    required this.rate,
    required this.partyId,
    required this.units,
    required this.enabled,
    required this.onChanged,
  });

  final _Rate rate;
  final String partyId;
  final UnitConverter? units;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final line = rate.line;
    final deals = ref
        .watch(lastSoldProvider((partyId: partyId, itemId: line.itemId)))
        .valueOrNull;
    final last = deals == null || deals.isEmpty ? null : deals.first;
    final lastRate = last?.rateIn(
      line.unitId ?? '',
      itemId: line.itemId,
      units: units,
    );
    final amount = rate.rate;

    return Padding(
      padding: const EdgeInsets.only(bottom: BlTokens.space2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.itemName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: t.ink),
                    ),
                    Text(
                      goodsQty(line),
                      style: TextStyle(fontSize: 12, color: t.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: BlTokens.space2),
              SizedBox(
                width: 150,
                child: line.isFree
                    ? Text(
                        s.priceGoodsFree,
                        style: TextStyle(fontSize: 13, color: t.inkMuted),
                      )
                    : BlField(
                        controller: rate.field,
                        label: s.priceGoodsRate(line.unitCode),
                        numeric: true,
                        enabled: enabled,
                        onChanged: (_) => onChanged(),
                      ),
              ),
            ],
          ),
          if (amount != null && !line.isFree)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: BlMoney(
                amount.amountFor(line.qty),
                size: 13,
                colour: t.inkMuted,
                weight: FontWeight.w400,
              ),
            ),
          // What they paid last time (M37): one tap makes it the rate.
          if (last != null && !line.isFree)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: !enabled || lastRate == null
                    ? null
                    : () {
                        rate.field.text = lastRate.amountOnly;
                        onChanged();
                      },
                icon: const Icon(Icons.history, size: 15),
                label: Text(
                  s.dealLastTime(
                    dealPrice(
                      last,
                      toUnitId: line.unitId ?? '',
                      itemId: line.itemId,
                      units: units,
                    ),
                    last.dateLocal,
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
