import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pk_bootstrap/pk_bootstrap.dart';

import '../../app/counting.dart'; // M45
import '../../app/providers.dart';
import '../../design/add_offer.dart';
import '../../design/components.dart';
import '../../design/counted_qty_field.dart'; // M45
import '../../design/tokens.dart';
import '../../l10n/app_strings.dart';
import '../items/pack_choice.dart';
import '../items/quick_item_sheet.dart';
import '../mobile/mobile_providers.dart'; // M50
import '../mobile/phone_lines.dart'; // M50
import '../pos/past_deals.dart';
import 'counted_purchase.dart'; // M45

/// Adding one line to a delivery: which item, how much, what it cost.
///
/// Cost, never price. The sale rate is not asked for and not touched — a
/// delivery arriving is not an instruction to reprice the shelf, and a screen
/// that changed both at once would make it impossible to tell which decision
/// the shopkeeper actually made.
///
/// [supplierId] is who the delivery is from, once chosen: the item's last
/// prices from them are shown under it, each a tap from being this line's
/// cost (M37).
Future<PurchaseLineDraft?> showPurchaseItemPicker(
  BuildContext context, {
  String? supplierId,
}) => showModalBottomSheet<PurchaseLineDraft>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _PurchaseItemPicker(supplierId: supplierId),
);

class _PurchaseItemPicker extends ConsumerStatefulWidget {
  const _PurchaseItemPicker({this.supplierId});

  final String? supplierId;

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

  /// M43: what the supplier sent free on this line ("10+1"), in the same
  /// unit as the quantity. Blank is none.
  final _free = TextEditingController();

  /// M49: the retail price printed on the batch, per the item's own unit.
  final _mrp = TextEditingController();
  String? _problem;

  Timer? _debounce;
  String _query = '';
  ItemSummary? _chosen;

  /// Whether the shopkeeper has typed the cost themselves. Until they do,
  /// the cost prefilled from the item's purchase rate follows the quantity.
  bool _costTyped = false;

  /// The price per unit the cost follows until it is typed: the item's
  /// purchase rate, or an earlier delivery's price picked from the list
  /// (M37).
  Rate? _followRate;

  /// M53: the pack this line is counted in, or null for the item's own
  /// unit (pack_choice.dart). The cost still follows per base unit.
  ItemPack? _pack;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _qty.dispose();
    _cost.dispose();
    _batch.dispose();
    _expiry.dispose();
    _serials.dispose();
    _free.dispose(); // M43
    _mrp.dispose(); // M49
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
      _followRate = item.purchaseRate;
      _pack = null; // M53
      // M49: the batch's printed price starts at the item's own.
      _mrp.text = item.mrp?.amountOnly ?? '';
    });
  }

  /// An earlier delivery's price, tapped (M37): the cost becomes it times
  /// the quantity, and follows the quantity from there, as the purchase
  /// rate's prefill does.
  void _usePrice(Rate rate) {
    final base = _count(_qty.text)?.base; // M45
    setState(() {
      _followRate = rate;
      _costTyped = false;
      _cost.text = rate
          .amountFor(
            // M53: a carton of 24 costs 24 pieces' worth.
            base != null && base.isPositive
                ? base
                : PackChoice.inBase(Qty.one, _pack) ?? Qty.one,
          )
          .amountOnly;
    });
  }

  // M45: the quantity box read in the item's own units, "10 ctn 5" as well
  // as "10" (counted_purchase.dart).
  PurchaseCount? _count(String typed) {
    final item = _chosen;
    if (item == null) return null;
    final counting = ref
        .read(countingBookProvider)
        .entryLadder(
          itemId: item.id,
          baseUnitId: item.unitId,
          baseUnitCode: item.unitCode,
          baseDecimals: item.unitDecimals,
        );
    return purchaseCount(typed, counting, _pack);
  }

  /// [freeQty] counted in the chip's unit, said in the unit the paid line
  /// was written in ([linePack], or the item's own unit when null); null
  /// when it is no whole number of that unit (M43 with M45).
  Qty? _freeInLineUnit(Qty freeQty, Qty freeBase, ItemPack? linePack) {
    if (linePack?.unitId == _pack?.unitId) return freeQty;
    if (linePack == null) return freeBase;
    final scaled = freeBase.inThousandths * 1000;
    final size = linePack.size.inThousandths;
    if (size <= 0 || scaled % size != 0) return null;
    return Qty.raw(scaled ~/ size);
  }

  /// The cost field is what the whole line cost, and the prefill is the
  /// price of one. So until the shopkeeper types a cost of their own, it is
  /// kept at the purchase rate times the quantity: ten sacks at Rs 950 is Rs
  /// 9,500, not Rs 950 — which the line would otherwise have read as Rs 95 a
  /// sack, and moved the item's average cost to it. An item made on this
  /// sheet (M32) comes here with its buying price as that rate, which is
  /// when this mattered most.
  void _onQty(String value) {
    final rate = _followRate;
    setState(() {
      // M53: in the base unit, so a carton follows at 24 pieces' worth.
      final base = _count(value)?.base; // M45
      if (!_costTyped && rate != null && base != null && base.isPositive) {
        _cost.text = rate.amountFor(base).amountOnly;
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
    // M50: in a mobile shop each line is a phone, "IMEI 1 / IMEI 2" for a
    // dual-SIM one, its check digit checked (mobile/phone_lines.dart).
    final phones = ref.read(isMobileShopProvider)
        ? phonesFromLines(serials)
        : const <PhoneUnitDraft>[];
    if (phonesProblem(s, phones) case final problem?) {
      setState(() => _problem = problem);
      return;
    }
    // M45: "10 ctn 5" is 245 pieces, billed by the piece; "10" with the
    // carton chip on is ten cartons, as before.
    final count = item.tracksSerial ? null : _count(_qty.text);
    final pack = count?.pack;
    final qty = item.tracksSerial ? Qty.units(serials.length) : count?.qty;
    final cost = Money.tryParse(_cost.text);
    // M53: what the shelf receives, a carton being 24 pieces.
    final base = item.tracksSerial ? qty : count?.base;
    if (qty == null ||
        base == null ||
        !qty.isPositive ||
        cost == null ||
        !cost.isPositive) {
      setState(
        () => _problem = item.tracksSerial ? s.purchaseSerialsNeeded : null,
      );
      return;
    }
    // M43: the supplier's bonus, counted as the paid goods are. It goes on
    // the shelf with them and shares their cost (purchase_builder.dart).
    final freeText = item.tracksSerial ? '' : _free.text.trim();
    final freeQty = freeText.isEmpty ? Qty.zero : Qty.tryParse(freeText);
    final freeBase = freeQty == null ? null : PackChoice.inBase(freeQty, _pack);
    // M43 with M45: the free box counts in the chip's unit, but "10 ctn 5"
    // moves the paid line to pieces, and the free row is written in the
    // line's own unit. So it is said again in that unit: a free carton on
    // a line of pieces is 24 pieces. A free piece on a line of cartons is
    // no whole number of cartons, and is refused rather than rounded.
    final freeInLine = freeQty == null || freeBase == null
        ? null
        : _freeInLineUnit(freeQty, freeBase, count?.pack);
    if (freeQty == null ||
        freeQty.isNegative ||
        freeBase == null ||
        freeInLine == null) {
      setState(() => _problem = s.purchaseFreeWrong);
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
        // The item's own unit, or one of its packs (M53): ten cartons of 24
        // are billed as ten cartons and put 240 pieces on the shelf, the
        // size coming from the item's own conversion, exactly.
        baseQty: base,
        unitId: item.tracksSerial ? item.unitId : pack?.unitId ?? item.unitId,
        unitCode: item.tracksSerial
            ? item.unitCode
            : pack?.unitCode ?? item.unitCode,
        rate: Rate.fromPack(cost, qty),
        batchNo: item.tracksBatch ? _batch.text.trim() : null,
        expiry: item.tracksBatch ? expiry : null,
        serials: phones.isEmpty ? serials : const [],
        phones: phones, // M50
        freeQty: freeInLine, // M43, in the line's own unit
        freeBaseQty: freeBase,
        // M49: kept on the batch, which DRAP prices batch by batch.
        mrp: item.tracksBatch ? Money.tryParse(_mrp.text) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final t = context.bl;
    final results = ref.watch(itemSearchProvider(_query));
    final chosen = _chosen;

    // Scrollable since M37: the supplier's last prices can stand between the
    // item and the quantity, and on a small phone at 200% the sheet would
    // otherwise run past the bottom with the Add button under it.
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
            // What this supplier charged for it before (M37), so a rate
            // that has crept up is seen before it is typed in.
            if (widget.supplierId case final supplier?)
              Padding(
                padding: const EdgeInsets.only(top: BlTokens.space3),
                child: PastDealsList(
                  title: s.dealsBoughtTitle,
                  deals:
                      ref
                          .watch(
                            lastBoughtProvider((
                              supplierId: supplier,
                              itemId: chosen.id,
                              limit: 5,
                            )),
                          )
                          .valueOrNull ??
                      const [],
                  toUnitId: chosen.unitId,
                  itemId: chosen.id,
                  units: ref.watch(unitConverterProvider).valueOrNull,
                  onPick: _usePrice,
                ),
              ),
            // M53: by the piece, or by the carton (pack_choice.dart).
            if (!chosen.tracksSerial)
              PackChoice(
                item: chosen,
                selected: _pack,
                onChanged: (pack) {
                  setState(() => _pack = pack);
                  _onQty(_qty.text);
                },
              ),
            const SizedBox(height: BlTokens.space3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  // M45: "10 ctn 5" as well as "10", with a carton stepper.
                  child: CountedQtyField(
                    controller: _qty,
                    label:
                        '${s.posQty} (${_pack?.unitCode ?? chosen.unitCode})',
                    counting: ref
                        .watch(countingBookProvider)
                        .entryLadder(
                          itemId: chosen.id,
                          baseUnitId: chosen.unitId,
                          baseUnitCode: chosen.unitCode,
                          baseDecimals: chosen.unitDecimals,
                        ),
                    unitSize: _pack?.size ?? Qty.one,
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
            // M43: "10+1" — what came free with the line.
            if (!chosen.tracksSerial) ...[
              const SizedBox(height: BlTokens.space3),
              BlField(
                controller: _free,
                label: s.purchaseFree(_pack?.unitCode ?? chosen.unitCode),
                numeric: true,
                decimals: 3,
                onChanged: (_) => setState(() => _problem = null),
              ),
            ],
            // M45: the carton calculator — what the line cost, per piece
            // and per carton.
            PackPriceHint(
              counting: countingOf(ref, chosen),
              rate: switch (Money.tryParse(_cost.text)) {
                final cost? => Rate.perUnit(cost),
                null => null,
              },
              per: _count(_qty.text)?.base,
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
              // M49: the price printed on this batch.
              const SizedBox(height: BlTokens.space3),
              BlField(
                controller: _mrp,
                label: s.pharmacyBatchMrp(chosen.unitCode),
                numeric: true,
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
