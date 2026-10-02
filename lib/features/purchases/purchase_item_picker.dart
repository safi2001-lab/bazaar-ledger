import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/providers.dart';
import '../../design/add_offer.dart';
import '../../design/components.dart';
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../items/quick_item_sheet.dart';

/// Adding one line to a delivery: which item, how much, what it cost.
///
/// Cost, never price. The sale rate is not asked for and not touched — a
/// delivery arriving is not an instruction to reprice the shelf, and a screen
/// that changed both at once would make it impossible to tell which decision
/// the shopkeeper actually made.
Future<PurchaseLineDraft?> showPurchaseItemPicker(BuildContext context) =>
    showModalBottomSheet<PurchaseLineDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _PurchaseItemPicker(),
    );

class _PurchaseItemPicker extends ConsumerStatefulWidget {
  const _PurchaseItemPicker();

  @override
  ConsumerState<_PurchaseItemPicker> createState() => _PickerState();
}

class _PickerState extends ConsumerState<_PurchaseItemPicker> {
  final _search = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _cost = TextEditingController();
  final _batch = TextEditingController();
  final _expiry = TextEditingController();
  final _serials = TextEditingController();
  String? _problem;

  Timer? _debounce;
  String _query = '';
  ItemSummary? _chosen;

  /// Whether the shopkeeper has typed the cost themselves. Until they do,
  /// the cost prefilled from the item's purchase rate follows the quantity.
  bool _costTyped = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _qty.dispose();
    _cost.dispose();
    _batch.dispose();
    _expiry.dispose();
    _serials.dispose();
    super.dispose();
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _choose(ItemSummary item) {
    setState(() {
      _chosen = item;
      // Prefilled with the purchase rate the catalogue carries, because most
      // deliveries come in at the price the shop expects and retyping it is
      // where a wrong cost gets entered.
      //
      // Blank when there is none, never inferred from the sale rate. A cost
      // taken from a price is a margin of zero, and a margin of zero that
      // looks like a real number is worse than no number at all.
      _cost.text = item.purchaseRate?.amountOnly ?? '';
      _costTyped = false;
    });
  }

  /// The cost field is what the whole line cost, and the prefill is the
  /// price of one. So until the shopkeeper types a cost of their own, it is
  /// kept at the purchase rate times the quantity: ten sacks at Rs 950 is Rs
  /// 9,500, not Rs 950 — which the line would otherwise have read as Rs 95 a
  /// sack, and moved the item's average cost to it. An item made on this
  /// sheet (M32) comes here with its buying price as that rate, which is
  /// when this mattered most.
  void _onQty(String value) {
    final rate = _chosen?.purchaseRate;
    final qty = Qty.tryParse(value);
    setState(() {
      if (!_costTyped && rate != null && qty != null && qty.isPositive) {
        _cost.text = rate.amountFor(qty).amountOnly;
      }
    });
  }

  /// A new item, made from the delivery it first arrived on (M32): what was
  /// searched for as its name, or as its barcode when it was scanned. The
  /// buying price asked there is the rate this line starts at.
  Future<void> _addNew() async {
    final barcode = scannedBarcode(_query);
    final item = await showQuickItemSheet(
      context,
      name: barcode == null ? _query : '',
      barcode: barcode,
      forPurchase: true,
    );
    if (item != null && mounted) _choose(item);
  }

  List<String> get _serialList => [
    for (final line in _serials.text.split(RegExp(r'[\n,]')))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  /// A pack's GS1 code scanned into the batch field fills the batch and the
  /// expiry from what the pack says.
  void _onBatch(String value) {
    if (parseGs1(value) case final gs1? when gs1.batch != null) {
      _batch.text = gs1.batch!;
      if (gs1.expiry != null) _expiry.text = gs1.expiry!.value;
    }
    setState(() => _problem = null);
  }

  void _add() {
    final item = _chosen;
    if (item == null) return;
    final s = AppStrings.of(context);
    final serials = item.tracksSerial ? _serialList : const <String>[];
    final qty = item.tracksSerial
        ? Qty.units(serials.length)
        : Qty.tryParse(_qty.text);
    final cost = Money.tryParse(_cost.text);
    if (qty == null || !qty.isPositive || cost == null || !cost.isPositive) {
      setState(
        () => _problem = item.tracksSerial ? s.purchaseSerialsNeeded : null,
      );
      return;
    }
    final expiry = BusinessDate.tryParse(_expiry.text.trim());
    if (item.tracksBatch &&
        (_batch.text.trim().isEmpty ||
            (_expiry.text.trim().isNotEmpty && expiry == null))) {
      setState(() => _problem = s.purchaseBatchNeeded);
      return;
    }

    Navigator.of(context).pop(
      PurchaseLineDraft(
        itemId: item.id,
        itemName: item.name,
        qty: qty,
        // The picker deals in the item's own unit, which is already its base
        // unit here. A supplier billing in bori rather than kilos is a
        // conversion, and it belongs where every other conversion in this app
        // lives rather than being redone on a sheet.
        baseQty: qty,
        unitId: item.unitId,
        unitCode: item.unitCode,
        rate: Rate.fromPack(cost, qty),
        batchNo: item.tracksBatch ? _batch.text.trim() : null,
        expiry: item.tracksBatch ? expiry : null,
        serials: serials,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final results = ref.watch(itemSearchProvider(_query));
    final chosen = _chosen;

    return Padding(
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
              child: results.when(
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
                        action: _query.isEmpty
                            ? null
                            : BlAddOffer(
                                label: switch (scannedBarcode(_query)) {
                                  final code? => s.quickAddBarcode(code),
                                  null => s.quickAddItem(_query),
                                },
                                onTap: () => unawaited(_addNew()),
                              ),
                      )
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) => ListTile(
                          title: Text(rows[i].name),
                          subtitle: Text(rows[i].unitCode),
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
            const SizedBox(height: BlTokens.space3),
            Row(
              children: [
                Expanded(
                  child: BlField(
                    controller: _qty,
                    label: '${s.posQty} (${chosen.unitCode})',
                    numeric: true,
                    autofocus: true,
                    onChanged: _onQty,
                  ),
                ),
                const SizedBox(width: BlTokens.space2),
                Expanded(
                  child: BlField(
                    controller: _cost,
                    label: s.purchaseCost,
                    numeric: true,
                    onChanged: (_) => setState(() => _costTyped = true),
                  ),
                ),
              ],
            ),
            if (chosen.tracksBatch) ...[
              const SizedBox(height: BlTokens.space3),
              Row(
                children: [
                  Expanded(
                    child: BlField(
                      controller: _batch,
                      label: s.purchaseBatch,
                      onChanged: _onBatch,
                    ),
                  ),
                  const SizedBox(width: BlTokens.space2),
                  Expanded(
                    child: BlField(
                      controller: _expiry,
                      label: s.purchaseExpiry,
                      hint: 'YYYY-MM-DD',
                      onChanged: (_) => setState(() => _problem = null),
                    ),
                  ),
                ],
              ),
            ],
            if (chosen.tracksSerial) ...[
              const SizedBox(height: BlTokens.space3),
              BlField(
                controller: _serials,
                label: s.purchaseSerials,
                maxLines: 5,
                onChanged: (_) => setState(() => _problem = null),
              ),
              const SizedBox(height: BlTokens.space1),
              Text(
                s.purchaseSerialCount(_serialList.length),
                style: TextStyle(fontSize: 12, color: t.inkMuted),
              ),
            ],
            if (_problem != null) ...[
              const SizedBox(height: BlTokens.space2),
              Text(_problem!, style: TextStyle(color: t.danger, fontSize: 14)),
            ],
            const SizedBox(height: BlTokens.space4),
            BlButton(
              label: s.purchaseAddItem,
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
