import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../pos/past_deals.dart';

/// One line of an order: which item, how many, in what, at what rate (M41).
///
/// In the unit the supplier or the customer counts in — two cartons, a
/// bori, a dozen — where the shop has said what that unit is of this item.
/// The rate starts at what it was last bought for from this supplier, or
/// at the item's purchase rate on a purchase order, and at the price the
/// customer is sold at on a sale order; either way it is the shopkeeper's
/// to change, and it is the figure the delivery or the bill is held to.
Future<OrderLineDraft?> showOrderItemSheet(
  BuildContext context, {
  required OrderKind kind,
  String? partyId,
  PriceTier tier = PriceTier.retail,
}) => showModalBottomSheet<OrderLineDraft>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _OrderItemSheet(kind: kind, partyId: partyId, tier: tier),
);

class _OrderItemSheet extends ConsumerStatefulWidget {
  const _OrderItemSheet({
    required this.kind,
    required this.partyId,
    required this.tier,
  });

  final OrderKind kind;
  final String? partyId;
  final PriceTier tier;

  @override
  ConsumerState<_OrderItemSheet> createState() => _OrderItemSheetState();
}

class _OrderItemSheetState extends ConsumerState<_OrderItemSheet> {
  final _search = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _rate = TextEditingController();
  Timer? _debounce;
  String _query = '';
  ItemSummary? _chosen;
  String? _unitId;
  String? _unitCode;
  String? _problem;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _qty.dispose();
    _rate.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Rate? _startingRate(ItemSummary item) => widget.kind == OrderKind.purchase
      ? item.purchaseRate
      : priceFor(item, widget.tier);

  void _choose(ItemSummary item) {
    setState(() {
      _chosen = item;
      _unitId = item.unitId;
      _unitCode = item.unitCode;
      _rate.text = _startingRate(item)?.amountOnly ?? '';
      _problem = null;
    });
  }

  /// Orders this line in [unitId], carrying the rate across with it: a
  /// hundred rupees a piece is twelve hundred a dozen.
  void _setUnit(UnitConverter units, String unitId, String unitCode) {
    final item = _chosen!;
    final rate = Rate.tryParse(_rate.text.trim());
    setState(() {
      if (rate != null) {
        try {
          _rate.text = units
              .convertRate(
                rate,
                fromUnitId: _unitId ?? item.unitId,
                toUnitId: unitId,
                itemId: item.id,
              )
              .amountOnly;
        } on Object {
          // Left as typed when it cannot carry across exactly.
        }
      }
      _unitId = unitId;
      _unitCode = unitCode;
    });
  }

  void _add() {
    final s = AppStrings.of(context);
    final item = _chosen;
    if (item == null) return;
    final qty = Qty.tryParse(_qty.text.trim());
    final rate = Rate.tryParse(_rate.text.trim()) ?? Rate.zero;
    if (qty == null || !qty.isPositive || rate.inMilliPaisa < 0) {
      setState(() => _problem = s.orderItemNeeds);
      return;
    }
    final unitId = _unitId ?? item.unitId;
    Qty base = qty;
    if (unitId != item.unitId) {
      final units = ref.read(unitConverterProvider).valueOrNull;
      try {
        base = units!.convert(
          qty,
          fromUnitId: unitId,
          toUnitId: item.unitId,
          itemId: item.id,
        );
      } on Object {
        setState(() => _problem = s.orderItemUnitInexact);
        return;
      }
    }
    Navigator.of(context).pop(
      OrderLineDraft(
        itemId: item.id,
        itemName: item.name,
        qty: qty,
        baseQty: base,
        unitId: unitId,
        unitCode: _unitCode ?? item.unitCode,
        rate: rate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final chosen = _chosen;

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: BlTokens.space4,
        right: BlTokens.space4,
        top: BlTokens.space4,
        bottom:
            MediaQuery.viewInsetsOf(context).bottom +
            MediaQuery.viewPaddingOf(context).bottom +
            BlTokens.space4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.purchaseAddItem,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: t.ink,
            ),
          ),
          const SizedBox(height: BlTokens.space3),
          if (chosen == null) ...[
            BlField(
              controller: _search,
              label: s.actionSearch,
              autofocus: true,
              onChanged: _onSearch,
              prefix: const Icon(Icons.search, size: 20),
            ),
            const SizedBox(height: BlTokens.space2),
            SizedBox(
              height: 260,
              child: ref
                  .watch(itemSearchProvider(_query))
                  .when(
                    loading: () => const BlSkeletonList(),
                    error: (error, _) => BlError(
                      title: s.commonSomethingWentWrong,
                      message: '$error',
                    ),
                    data: (rows) => rows.isEmpty
                        ? BlEmpty(
                            icon: Icons.search_off,
                            title: s.emptyNoResults,
                            message: s.emptyNoResultsHint,
                          )
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (context, i) => ListTile(
                              title: Text(rows[i].name),
                              subtitle: Text(
                                '${rows[i].stockOnHand.display} '
                                '${rows[i].unitCode}',
                              ),
                              onTap: () => _choose(rows[i]),
                            ),
                          ),
                  ),
            ),
          ] else ...[
            Text(
              chosen.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: t.ink,
              ),
            ),
            _Units(
              item: chosen,
              unitId: _unitId ?? chosen.unitId,
              onPick: _setUnit,
            ),
            // What this supplier charged for it before (M37), so the rate
            // on the order is the one the last bill was at.
            if (widget.kind == OrderKind.purchase && widget.partyId != null)
              Padding(
                padding: const EdgeInsets.only(top: BlTokens.space3),
                child: PastDealsList(
                  title: s.dealsBoughtTitle,
                  deals:
                      ref
                          .watch(
                            lastBoughtProvider((
                              supplierId: widget.partyId,
                              itemId: chosen.id,
                              limit: 5,
                            )),
                          )
                          .valueOrNull ??
                      const [],
                  toUnitId: _unitId ?? chosen.unitId,
                  itemId: chosen.id,
                  units: ref.watch(unitConverterProvider).valueOrNull,
                  onPick: (rate) =>
                      setState(() => _rate.text = rate.amountOnly),
                ),
              ),
            const SizedBox(height: BlTokens.space3),
            Row(
              children: [
                Expanded(
                  child: BlField(
                    controller: _qty,
                    label: '${s.posQty} (${_unitCode ?? chosen.unitCode})',
                    numeric: true,
                    decimals: 3,
                    autofocus: true,
                    onChanged: (_) => setState(() => _problem = null),
                  ),
                ),
                const SizedBox(width: BlTokens.space2),
                Expanded(
                  child: BlField(
                    controller: _rate,
                    label: widget.kind == OrderKind.purchase
                        ? s.orderSupplierRate
                        : s.orderRate,
                    numeric: true,
                    onChanged: (_) => setState(() => _problem = null),
                  ),
                ),
              ],
            ),
            if (_problem != null) ...[
              const SizedBox(height: BlTokens.space2),
              Text(_problem!, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.orderItemAdd,
              icon: Icons.add,
              big: true,
              onPressed: _add,
            ),
          ],
        ],
      ),
    );
  }
}

/// The units this item can be ordered in, when there is more than its own.
class _Units extends ConsumerWidget {
  const _Units({
    required this.item,
    required this.unitId,
    required this.onPick,
  });

  final ItemSummary item;
  final String unitId;
  final void Function(UnitConverter units, String unitId, String unitCode)
  onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(unitConverterProvider).valueOrNull;
    final all = ref.watch(unitsProvider).valueOrNull;
    if (units == null || all == null) return const SizedBox.shrink();
    final reachable = units.reachableFrom(item.unitId, itemId: item.id);
    final offered = [
      for (final u in all)
        if (u.id == item.unitId ||
            (reachable.contains(u.id) &&
                units.canConvert(
                  Qty.one,
                  fromUnitId: u.id,
                  toUnitId: item.unitId,
                  itemId: item.id,
                )))
          u,
    ];
    if (offered.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: BlTokens.space2),
      child: Wrap(
        spacing: BlTokens.space2,
        runSpacing: BlTokens.space2,
        children: [
          for (final u in offered)
            ChoiceChip(
              label: Text(u.code),
              selected: u.id == unitId,
              onSelected: (_) {
                if (u.id != unitId) onPick(units, u.id, u.code);
              },
            ),
        ],
      ),
    );
  }
}
